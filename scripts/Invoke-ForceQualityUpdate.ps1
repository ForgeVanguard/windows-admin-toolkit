<#
.SYNOPSIS
    Install every pending Windows quality update and force a restart.
    Target: CVE-2026-81963 (Windows Update Stack EoP). Compliance is the
    September 2026 build, not a single KB number.

.DESCRIPTION
    Run as SYSTEM (Intune platform script or proactive remediation, 64-bit).
    Does not wait for the logged-on user to click Check for updates.
    Download and install run in session 0. A cumulative still needs a reboot;
    -ForceRestart is what interrupts the user.

    Fixed builds for CVE-2026-81963:
      23H2  10.0.22631.7582   KB5122880
      24H2  10.0.26100.9445   KB5124008
      25H2  10.0.26200.9445   KB5124008
      26H1  10.0.28000.2954   KB5124012
    Anything newer than those builds is also compliant. Windows 10 is not
    in the MSRC affected list for this CVE.

    KB5124008 and later honor Machine Identity Isolation. On a domain that
    is not Windows Server 2025 DFL, value 1 or 2 can drop the secure channel
    after reboot. Default is to refuse the install when that value is set.
    Pass -IgnoreMachineIdentityRisk only after you have disabled it.

.PARAMETER RestartDelaySeconds
    Countdown before the forced restart. Default 300. User gets a msg.exe
    notice. shutdown /f discards unsaved work when the timer hits zero.

.PARAMETER ForceRestart
    Restart if the install or the CBS reboot flag says a restart is required.
    Without this switch the script installs and exits, leaving the CVE open
    until someone reboots.

.PARAMETER IgnoreMachineIdentityRisk
    Install even if MachineIdentityIsolation is 1 or 2.

.PARAMETER SkipIfCompliant
    Exit 0 when the current build is already at or past the CVE fix build
    and no reboot is pending. Default true.

.NOTES
    Author : Steven Drew
    License: MIT
    Logs: %ProgramData%\WindowsUpdateForce\Invoke-ForceQualityUpdate.log
    Intune: Platform script, run as system, 64-bit PowerShell host.
    Do not use CurrentUser module scope.

    The UBR table in Get-RequiredUbr is specific to one advisory. For a new advisory,
    update the table and the CVE ID in the messages; the install/restart logic is generic.
#>
[CmdletBinding()]
param(
    [int]$RestartDelaySeconds = 300,
    [switch]$ForceRestart,
    [switch]$IgnoreMachineIdentityRisk,
    [bool]$SkipIfCompliant = $true
)

$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'

$LogDir = Join-Path $env:ProgramData 'WindowsUpdateForce'
$LogFile = Join-Path $LogDir 'Invoke-ForceQualityUpdate.log'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-UpdateLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Output $line
}

function Get-OsBuild {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $ubr = 0
    if ($null -ne $cv.UBR) { $ubr = [int]$cv.UBR }
    [pscustomobject]@{
        CurrentBuild = [string]$cv.CurrentBuild
        UBR          = $ubr
        Display      = '{0}.{1}' -f $cv.CurrentBuild, $ubr
        ProductName  = [string]$cv.ProductName
        Edition      = [string]$cv.EditionID
    }
}

function Get-RequiredUbr {
    param([string]$CurrentBuild)
    switch ($CurrentBuild) {
        '22631' { return 7582 }   # 23H2  KB5122880
        '22621' { return 7582 }   # 23H2 catalog title sometimes reports 22621
        '26100' { return 9445 }   # 24H2  KB5124008
        '26200' { return 9445 }   # 25H2  KB5124008
        '28000' { return 2954 }   # 26H1  KB5124012
        default { return $null }
    }
}

function Get-MachineIdentityIsolation {
    $paths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    )
    $found = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        $item = Get-ItemProperty $p -ErrorAction SilentlyContinue
        if ($null -ne $item.MachineIdentityIsolation) {
            $found += [pscustomobject]@{
                Path  = $p
                Value = [int]$item.MachineIdentityIsolation
            }
        }
    }
    return $found
}

function Test-RebootPending {
    $cbs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $wu  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    return ((Test-Path $cbs) -or (Test-Path $wu))
}

function Invoke-ForcedRestart {
    param([int]$DelaySeconds, [string]$Reason)
    $msg = "Security update restart in $DelaySeconds seconds. Save work now. $Reason"
    Write-UpdateLog $msg
    try { & "$env:SystemRoot\System32\msg.exe" * /TIME:60 $msg | Out-Null } catch {
        Write-UpdateLog "msg.exe failed: $($_.Exception.Message)" 'WARN'
    }
    & "$env:SystemRoot\System32\shutdown.exe" /r /t $DelaySeconds /f /c $msg /d p:2:17
    if ($LASTEXITCODE -ne 0) {
        throw "shutdown.exe failed with exit $LASTEXITCODE"
    }
}

try {
    Write-UpdateLog '===== Invoke-ForceQualityUpdate started ====='
    Write-UpdateLog ("Identity: {0}  64-bit: {1}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name, [Environment]::Is64BitProcess)
    if (-not [Environment]::Is64BitProcess) {
        throw 'Run in 64-bit PowerShell. Intune platform script: enable Run script in 64-bit PowerShell Host.'
    }

    $os = Get-OsBuild
    $need = Get-RequiredUbr -CurrentBuild $os.CurrentBuild
    Write-UpdateLog ("OS: {0} {1} edition {2} build {3}" -f $os.ProductName, $os.Edition, $os.CurrentBuild, $os.Display)

    $mii = Get-MachineIdentityIsolation
    foreach ($row in $mii) {
        Write-UpdateLog ("MachineIdentityIsolation {0} = {1}" -f $row.Path, $row.Value)
    }
    $miiRisk = @($mii | Where-Object { $_.Value -ge 1 })
    if ($miiRisk.Count -gt 0 -and -not $IgnoreMachineIdentityRisk) {
        throw 'MachineIdentityIsolation is 1 or 2. KB5124008 can drop the domain secure channel if DFL is not Server 2025. Disable the setting, or rerun with -IgnoreMachineIdentityRisk.'
    }

    if ($null -eq $need) {
        Write-UpdateLog 'Build is not in the CVE-2026-81963 affected set. Still installing pending quality updates.' 'WARN'
    } elseif ($SkipIfCompliant -and $os.UBR -ge $need -and -not (Test-RebootPending)) {
        Write-UpdateLog ("Compliant. Build {0} >= required UBR {1}. No reboot pending." -f $os.Display, $need)
        exit 0
    } else {
        Write-UpdateLog ("Need UBR >= {0} on build {1}. Current UBR {2}." -f $need, $os.CurrentBuild, $os.UBR)
    }

    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    Write-UpdateLog 'Searching for pending software updates...'
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
    Write-UpdateLog ("Search returned {0} update(s)." -f $result.Updates.Count)

    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in @($result.Updates)) {
        if ($u.EulaAccepted -eq $false) { $u.AcceptEula() }
        [void]$toInstall.Add($u)
        Write-UpdateLog ("Queued: {0}  KB: {1}" -f $u.Title, (($u.KBArticleIDs | ForEach-Object { $_ }) -join ','))
    }

    if ($toInstall.Count -eq 0) {
        Write-UpdateLog 'No pending software updates.'
        if ($ForceRestart -and (Test-RebootPending)) {
            Invoke-ForcedRestart -DelaySeconds $RestartDelaySeconds -Reason 'Reboot was already pending.'
        }
        exit 0
    }

    Write-UpdateLog 'Downloading...'
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    $dl = $downloader.Download()
    Write-UpdateLog ("Download result code {0}" -f $dl.ResultCode)
    if ([int]$dl.ResultCode -ne 2) {
        throw "Download failed. ResultCode=$($dl.ResultCode)  (2 = succeeded)"
    }

    Write-UpdateLog 'Installing...'
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $toInstall
    $installer.ForceQuiet = $true
    $inst = $installer.Install()
    Write-UpdateLog ("Install result code {0}  reboot required {1}" -f $inst.ResultCode, $inst.RebootRequired)
    for ($i = 0; $i -lt $toInstall.Count; $i++) {
        $r = $inst.GetUpdateResult($i)
        Write-UpdateLog ("  [{0}] {1} result {2}" -f $i, $toInstall.Item($i).Title, $r.ResultCode)
    }
    if ([int]$inst.ResultCode -notin 2, 3) {
        throw "Install failed. ResultCode=$($inst.ResultCode)  (2 = succeeded, 3 = succeeded with errors)"
    }

    if ($ForceRestart -and ($inst.RebootRequired -or (Test-RebootPending))) {
        Invoke-ForcedRestart -DelaySeconds $RestartDelaySeconds -Reason 'CVE-2026-81963 quality update installed.'
        exit 3010
    }

    if ($inst.RebootRequired) {
        Write-UpdateLog 'Reboot required. Rerun with -ForceRestart to interrupt the user.' 'WARN'
        exit 3010
    }

    Write-UpdateLog 'Install finished. No reboot required.'
    exit 0
}
catch {
    Write-UpdateLog $_.Exception.Message 'ERROR'
    exit 1
}
