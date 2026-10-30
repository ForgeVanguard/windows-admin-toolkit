#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only security posture check for a Windows workstation or server.
.DESCRIPTION
    Reports OS build and UBR, pending reboot, password and lockout policy, BitLocker,
    Microsoft Defender, firewall profiles, SMBv1, RDP and Network Level Authentication,
    local administrators and the age of the last installed update. Changes nothing.
    Run elevated for complete BitLocker and policy results.
.PARAMETER CsvPath
    Optional path to export the results as CSV.
.EXAMPLE
    .\Get-SecurityPosture.ps1
.EXAMPLE
    .\Get-SecurityPosture.ps1 -CsvPath .\posture.csv
#>
[CmdletBinding()]
param([string]$CsvPath)

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Area, [string]$Check, $Value, [ValidateSet('PASS','WARN','FAIL','INFO')][string]$Status) {
    $results.Add([pscustomobject]@{ Area = $Area; Check = $Check; Value = "$Value"; Status = $Status })
}

# OS build and UBR: verify patch level by build number, not by KB title
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Add-Result 'OS' 'Edition' $cv.ProductName 'INFO'
Add-Result 'OS' 'Build.UBR' ('{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR) 'INFO'

$lastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($lastHotfix) {
    $age = (New-TimeSpan -Start $lastHotfix.InstalledOn -End (Get-Date)).Days
    Add-Result 'Updates' 'Last update installed' ('{0} ({1} days ago)' -f $lastHotfix.HotFixID, $age) $(if ($age -le 35) { 'PASS' } else { 'WARN' })
}

$rebootKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
              'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$pending = [bool]($rebootKeys | Where-Object { Test-Path $_ })
Add-Result 'Updates' 'Reboot pending' $pending $(if ($pending) { 'WARN' } else { 'PASS' })

# Password and lockout policy (net accounts output is locale dependent; parsed by position of ':')
$net = net accounts 2>$null
function Get-NetAccountsValue([string]$Label) {
    $line = $net | Where-Object { $_ -like "$Label*" } | Select-Object -First 1
    if ($line) { ($line -split ':', 2)[1].Trim() }
}
$minLen = Get-NetAccountsValue 'Minimum password length'
$maxAge = Get-NetAccountsValue 'Maximum password age'
$lockout = Get-NetAccountsValue 'Lockout threshold'
if ($minLen) { Add-Result 'Accounts' 'Minimum password length' $minLen $(if ([int]$minLen -ge 12) { 'PASS' } else { 'FAIL' }) }
if ($maxAge) { Add-Result 'Accounts' 'Maximum password age (days)' $maxAge 'INFO' }
if ($lockout) { Add-Result 'Accounts' 'Lockout threshold' $lockout $(if ($lockout -match '^\d+$' -and [int]$lockout -gt 0 -and [int]$lockout -le 10) { 'PASS' } else { 'WARN' }) }

try {
    $admins = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
    Add-Result 'Accounts' 'Local administrators' $admins.Count $(if ($admins.Count -le 2) { 'PASS' } else { 'WARN' })
} catch { Add-Result 'Accounts' 'Local administrators' 'unavailable' 'INFO' }

$guest = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID -like '*-501' }
if ($guest) { Add-Result 'Accounts' 'Guest account enabled' $guest.Enabled $(if ($guest.Enabled) { 'FAIL' } else { 'PASS' }) }

# BitLocker
try {
    $os = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    Add-Result 'Encryption' "BitLocker $env:SystemDrive" ('{0}, {1}%' -f $os.ProtectionStatus, $os.EncryptionPercentage) $(if ($os.ProtectionStatus -eq 'On') { 'PASS' } else { 'FAIL' })
} catch { Add-Result 'Encryption' "BitLocker $env:SystemDrive" 'unavailable (run elevated)' 'INFO' }

# Defender
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Add-Result 'Defender' 'Real-time protection' $mp.RealTimeProtectionEnabled $(if ($mp.RealTimeProtectionEnabled) { 'PASS' } else { 'FAIL' })
    Add-Result 'Defender' 'Tamper protection' $mp.IsTamperProtected $(if ($mp.IsTamperProtected) { 'PASS' } else { 'WARN' })
    Add-Result 'Defender' 'Signature age (days)' $mp.AntivirusSignatureAge $(if ($mp.AntivirusSignatureAge -le 2) { 'PASS' } else { 'WARN' })
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($pref) { Add-Result 'Defender' 'Controlled folder access' $pref.EnableControlledFolderAccess 'INFO' }
} catch { Add-Result 'Defender' 'Status' 'unavailable (third-party AV?)' 'INFO' }

# Firewall
Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
    Add-Result 'Firewall' "$($_.Name) profile enabled" $_.Enabled $(if ($_.Enabled) { 'PASS' } else { 'FAIL' })
}

# SMBv1
try {
    $smb1 = (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
    Add-Result 'Network' 'SMBv1 server enabled' $smb1 $(if ($smb1) { 'FAIL' } else { 'PASS' })
} catch { Add-Result 'Network' 'SMBv1 server enabled' 'unavailable' 'INFO' }

# RDP
$ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction SilentlyContinue
$rdpOn = $ts -and $ts.fDenyTSConnections -eq 0
Add-Result 'Network' 'RDP enabled' $rdpOn 'INFO'
if ($rdpOn) {
    $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction SilentlyContinue).UserAuthentication
    Add-Result 'Network' 'RDP requires NLA' ($nla -eq 1) $(if ($nla -eq 1) { 'PASS' } else { 'FAIL' })
}

$results | Format-Table -AutoSize
$summary = $results | Group-Object Status | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }
Write-Output ('Summary: ' + ($summary -join '  '))
if ($CsvPath) { $results | Export-Csv -Path $CsvPath -NoTypeInformation; Write-Output "Saved $CsvPath" }
