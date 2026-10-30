#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Searches for, downloads and installs pending Windows software updates, then reports the build before and after.
.DESCRIPTION
    Uses the Windows Update Agent COM API, so it works without extra modules. Compliance
    should be judged by the OS build and UBR (CurrentBuildNumber.UBR) rather than by KB
    title. Use -WhatIf to list what would be installed.
.PARAMETER IncludeDrivers
    Also install driver updates (software updates only by default).
.PARAMETER Reboot
    Restart automatically if an update requires it.
.EXAMPLE
    .\Invoke-QualityUpdate.ps1 -WhatIf
.EXAMPLE
    .\Invoke-QualityUpdate.ps1 -Reboot
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$IncludeDrivers, [switch]$Reboot)

function Get-BuildUbr {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    '{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR
}

$before = Get-BuildUbr
Write-Output "Build before: $before"

$session  = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$criteria = if ($IncludeDrivers) { 'IsInstalled=0 and IsHidden=0' } else { "IsInstalled=0 and IsHidden=0 and Type='Software'" }
Write-Output "Searching ($criteria)..."
$found = $searcher.Search($criteria).Updates

if ($found.Count -eq 0) { Write-Output 'No applicable updates.'; return }

$toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($u in $found) {
    $kb = ($u.KBArticleIDs | ForEach-Object { "KB$_" }) -join ','
    if ($PSCmdlet.ShouldProcess("$($u.Title) $kb", 'Install')) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$toInstall.Add($u)
    }
}
if ($toInstall.Count -eq 0) { return }

Write-Output "Downloading $($toInstall.Count) update(s)..."
$dl = $session.CreateUpdateDownloader()
$dl.Updates = $toInstall
[void]$dl.Download()

Write-Output 'Installing...'
$inst = $session.CreateUpdateInstaller()
$inst.Updates = $toInstall
$res = $inst.Install()

$codes = @{ 0 = 'NotStarted'; 1 = 'InProgress'; 2 = 'Succeeded'; 3 = 'SucceededWithErrors'; 4 = 'Failed'; 5 = 'Aborted' }
for ($i = 0; $i -lt $toInstall.Count; $i++) {
    [pscustomobject]@{
        Update = $toInstall.Item($i).Title
        Result = $codes[[int]$res.GetUpdateResult($i).ResultCode]
    }
}
Write-Output "Overall: $($codes[[int]$res.ResultCode]); reboot required: $($res.RebootRequired)"
Write-Output "Build after (may change only after reboot): $(Get-BuildUbr)"

if ($res.RebootRequired -and $Reboot -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart')) {
    Restart-Computer -Force
}
