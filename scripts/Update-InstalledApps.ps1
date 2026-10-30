#Requires -Version 5.1
<#
.SYNOPSIS
    Checks every winget-managed application for updates and installs them: all at once,
    a hand-picked selection, or a preview only.

.DESCRIPTION
    Uses the Microsoft.WinGet.Client PowerShell module when it is available (clean objects,
    no text parsing) and falls back to winget.exe otherwise.

      * Default            : upgrade everything that has an update, minus -Exclude.
      * -Interactive       : pick packages in an Out-GridView window.
      * -ListOnly / -WhatIf: show what would be upgraded and stop.

    Only applications installed or registered through winget sources appear. Some legacy
    installers are not covered.

.PARAMETER Exclude
    winget package IDs to skip (for example pinned line-of-business tools).

.PARAMETER Interactive
    Choose packages in a grid window (requires a desktop session).

.PARAMETER ListOnly
    Show available updates and exit.

.PARAMETER IncludeUnknown
    Include packages whose installed version winget cannot determine (CLI mode).

.PARAMETER InstallModule
    Install Microsoft.WinGet.Client for the current user if it is missing.

.PARAMETER LogPath
    Transcript location. Defaults to %TEMP%.

.EXAMPLE
    .\Update-InstalledApps.ps1 -ListOnly

.EXAMPLE
    .\Update-InstalledApps.ps1 -Interactive

.EXAMPLE
    .\Update-InstalledApps.ps1 -Exclude 'Mozilla.Firefox','Oracle.VirtualBox'

.NOTES
    Author : Steven Drew
    License: MIT
    Run elevated for machine-scope packages. If scripts are blocked, run once per user:
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Exclude = @(),
    [switch]$Interactive,
    [switch]$ListOnly,
    [switch]$IncludeUnknown,
    [switch]$InstallModule,
    [string]$LogPath = (Join-Path $env:TEMP ("winget-upgrade-{0:yyyyMMdd-HHmm}.log" -f (Get-Date)))
)

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-UpdateFromModule {
    Get-WinGetPackage | Where-Object { $_.IsUpdateAvailable } | ForEach-Object {
        [pscustomobject]@{
            Name             = $_.Name
            Id               = $_.Id
            InstalledVersion = $_.InstalledVersion
            AvailableVersion = @($_.AvailableVersions)[0]
            Source           = $_.Source
        }
    }
}

function Get-UpdateFromCli {
    param([switch]$Unknown)
    $cliArgs = @('upgrade', '--accept-source-agreements')
    if ($Unknown) { $cliArgs += '--include-unknown' }
    $raw = @(& winget @cliArgs 2>$null)
    # Parse by column positions taken from the header line; works regardless of name spacing.
    $header = $raw | Where-Object { $_ -match '^Name\s+Id\s+Version\s+Available' } | Select-Object -First 1
    if (-not $header) { return }
    $idStart    = $header.IndexOf('Id')
    $verStart   = $header.IndexOf('Version')
    $availStart = $header.IndexOf('Available')
    $srcStart   = $header.IndexOf('Source')
    $rows = $raw[([array]::IndexOf($raw, $header) + 2)..($raw.Count - 1)] |
        Where-Object { $_.Length -gt $availStart -and $_ -notmatch 'upgrades? available|require explicit targeting' }
    foreach ($r in $rows) {
        $availEnd = if ($srcStart -gt 0 -and $r.Length -gt $srcStart) { $srcStart } else { $r.Length }
        [pscustomobject]@{
            Name             = $r.Substring(0, $idStart).Trim()
            Id               = $r.Substring($idStart, $verStart - $idStart).Trim()
            InstalledVersion = $r.Substring($verStart, $availStart - $verStart).Trim()
            AvailableVersion = $r.Substring($availStart, $availEnd - $availStart).Trim()
            Source           = $(if ($srcStart -gt 0 -and $r.Length -gt $srcStart) { $r.Substring($srcStart).Trim() } else { '' })
        }
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget (App Installer) is not installed.' }
if (-not (Test-IsAdmin)) { Write-Warning 'Not elevated: machine-scope packages may fail to upgrade.' }

Start-Transcript -Path $LogPath -Append | Out-Null
try {
    # Prefer the PowerShell module.
    $useModule = $false
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) -and $InstallModule) {
        try {
            Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not install Microsoft.WinGet.Client: $($_.Exception.Message)"
        }
    }
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            $useModule = $true
        }
        catch {
            Write-Warning 'Microsoft.WinGet.Client failed to load; using winget.exe.'
        }
    }
    Write-Output ("Mode: {0}" -f $(if ($useModule) { 'Microsoft.WinGet.Client module' } else { 'winget.exe' }))

    & winget source update 2>$null | Out-Null

    $updates = @(if ($useModule) { Get-UpdateFromModule } else { Get-UpdateFromCli -Unknown:$IncludeUnknown })
    $updates = @($updates | Where-Object { $_.Id -and $Exclude -notcontains $_.Id })

    if ($updates.Count -eq 0) {
        Write-Output 'No winget-managed updates available.'
        return
    }

    Write-Output ("{0} update(s) available:" -f $updates.Count)
    $updates | Format-Table Name, Id, InstalledVersion, AvailableVersion, Source -AutoSize | Out-String | Write-Output

    if ($ListOnly) { return }

    $selected = $updates
    if ($Interactive) {
        if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
            throw 'Out-GridView is not available in this host. Use -Exclude instead.'
        }
        $selected = @($updates | Out-GridView -Title 'Select applications to update' -PassThru)
        if ($selected.Count -eq 0) { Write-Output 'Nothing selected.'; return }
    }

    $results = foreach ($pkg in $selected) {
        if (-not $PSCmdlet.ShouldProcess("$($pkg.Name) [$($pkg.Id)]", "Upgrade to $($pkg.AvailableVersion)")) { continue }
        if ($useModule) {
            $r = Update-WinGetPackage -Id $pkg.Id -MatchOption Equals -Mode Silent
            [pscustomobject]@{ Id = $pkg.Id; Status = [string]$r.Status; RebootRequired = [bool]$r.RebootRequired }
        }
        else {
            & winget upgrade --id $pkg.Id --exact --silent --accept-package-agreements --accept-source-agreements
            [pscustomobject]@{ Id = $pkg.Id; Status = "exit $LASTEXITCODE"; RebootRequired = $null }
        }
    }
    if ($results) { $results | Format-Table -AutoSize | Out-String | Write-Output }
}
finally {
    Stop-Transcript | Out-Null
    Write-Output "Log: $LogPath"
}
