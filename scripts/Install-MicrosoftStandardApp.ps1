#Requires -Version 7.0
<#
.SYNOPSIS
    Installs or updates the standard Microsoft desktop apps (Edge, Teams, OneDrive, new Outlook)
    with winget, with prerequisite checks, before/after versions and a log file.

.DESCRIPTION
    For each selected app:
      * not installed      -> winget install
      * installed          -> winget upgrade (reports "Already latest" when nothing newer exists)
      * installed + -Force -> winget install --force (reinstall)

    Prerequisite checks: elevation, internet reachability, free space on the system drive,
    and winget availability. Per-app failures are logged and the script continues.

    "Outlook" is the new Outlook for Windows from the Microsoft Store (9NRX63209R7B). Classic
    Outlook ships with Microsoft 365 Apps; deploy that with the Office Deployment Tool.

    Add apps by adding an entry to $AppCatalog (Key, FriendlyName, Id, Source, Scoped) and the
    Key to the -App ValidateSet.

.PARAMETER App
    Which apps to process. Default: all four.

.PARAMETER Force
    Reinstall even when the app is already installed.

.PARAMETER Scope
    Machine (default, needs elevation) or User. Applied to winget-source packages; Store apps
    install per-user.

.PARAMETER LogPath
    Log file. Defaults to %TEMP%\Install-MicrosoftApps_<timestamp>.log.

.EXAMPLE
    .\Install-MicrosoftStandardApp.ps1 -WhatIf

.EXAMPLE
    .\Install-MicrosoftStandardApp.ps1 -App Edge, OneDrive -Verbose

.NOTES
    Author : Steven Drew
    License: MIT
    Run in an elevated PowerShell 7 session for machine-scope installs.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Edge', 'Teams', 'OneDrive', 'Outlook')]
    [string[]]$App = @('Edge', 'Teams', 'OneDrive', 'Outlook'),

    [switch]$Force,

    [ValidateSet('Machine', 'User')]
    [string]$Scope = 'Machine',

    [string]$LogPath = (Join-Path $env:TEMP "Install-MicrosoftApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
)

# winget exit code: no applicable upgrade found.
$script:NoUpgradeExitCode = -1978335189
$script:LogFile = $LogPath

function Write-InstallLog {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $script:LogFile -Value $entry -ErrorAction Stop }
    catch { Write-Warning "Failed to write to log file: $_" }
    $color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'DEBUG'   { 'DarkGray' }
        default   { 'White' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Test-Prerequisite {
    Write-InstallLog 'Running prerequisite checks...'

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { Write-InstallLog 'Running elevated.' -Level SUCCESS }
    else { Write-InstallLog 'Not elevated. Machine-scope installs may fail or fall back to per-user.' -Level WARN }

    try {
        $null = Invoke-WebRequest -Uri 'https://www.microsoft.com' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        Write-InstallLog 'Internet connectivity: OK' -Level SUCCESS
    }
    catch {
        Write-InstallLog 'Internet connectivity check failed. winget needs internet access.' -Level ERROR
        throw 'No internet access. Aborting.'
    }

    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" | Select-Object -First 1
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $level = if ($freeGB -lt 8) { 'WARN' } else { 'SUCCESS' }
        Write-InstallLog "Free space on ${env:SystemDrive}: $freeGB GB (8 GB recommended)" -Level $level
    }
    catch { Write-InstallLog "Could not check disk space: $_" -Level WARN }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-InstallLog 'winget is not available. Install App Installer from the Microsoft Store, or run:' -Level ERROR
        Write-InstallLog '  Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
        throw 'winget not found.'
    }
    Write-InstallLog ("winget detected: {0}" -f (winget --version).Trim()) -Level SUCCESS
}

function Get-InstalledVersion {
    param([Parameter(Mandatory)][string]$Id, [string]$Source = 'winget')
    try {
        $output = & winget list --id $Id --exact --source $Source --accept-source-agreements 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or $output -match 'No installed package found') { return $null }
        $line = ($output -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($Id) } | Select-Object -First 1
        if ($line -and $line -match '(\d+(\.\d+){1,3})') { return $Matches[1] }
        return 'Unknown'
    }
    catch {
        Write-InstallLog "Version query failed for '$Id': $_" -Level DEBUG
        return 'Unknown'
    }
}

$AppCatalog = @(
    [pscustomobject]@{ Key = 'Edge';     FriendlyName = 'Microsoft Edge';          Id = 'Microsoft.Edge';     Source = 'winget';  Scoped = $true }
    [pscustomobject]@{ Key = 'Teams';    FriendlyName = 'Microsoft Teams';         Id = 'Microsoft.Teams';    Source = 'winget';  Scoped = $true }
    [pscustomobject]@{ Key = 'OneDrive'; FriendlyName = 'Microsoft OneDrive';      Id = 'Microsoft.OneDrive'; Source = 'winget';  Scoped = $true }
    [pscustomobject]@{ Key = 'Outlook';  FriendlyName = 'New Outlook for Windows'; Id = '9NRX63209R7B';       Source = 'msstore'; Scoped = $false }
)

Write-InstallLog '=== Microsoft standard apps deployment started ==='
Write-InstallLog "Log file: $LogPath"
Test-Prerequisite

# Select by Key; the friendly names do not reliably map to the parameter values.
$selectedApps = @($AppCatalog | Where-Object { $App -contains $_.Key })
Write-InstallLog "Apps to process: $($selectedApps.FriendlyName -join ', ')"

$results = New-Object System.Collections.Generic.List[object]
$counter = 0
foreach ($item in $selectedApps) {
    $counter++
    Write-Progress -Activity 'Deploying Microsoft applications' -Status $item.FriendlyName -PercentComplete ([math]::Round($counter / $selectedApps.Count * 100))
    Write-InstallLog "----- $($item.FriendlyName) -----"

    $before = Get-InstalledVersion -Id $item.Id -Source $item.Source
    Write-InstallLog ("Current version: {0}" -f ($before ?? 'not installed'))

    $verb = if (-not $before) { 'install' } elseif ($Force) { 'reinstall' } else { 'upgrade' }
    $status = 'Skipped'
    $after = $before

    if ($PSCmdlet.ShouldProcess("$($item.FriendlyName) [$($item.Id)]", "winget $verb")) {
        $wingetArgs = @(
            $(if ($verb -eq 'upgrade') { 'upgrade' } else { 'install' }),
            '--exact', '--id', $item.Id, '--source', $item.Source,
            '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        if ($verb -eq 'reinstall') { $wingetArgs += '--force' }
        if ($item.Scoped) { $wingetArgs += @('--scope', $Scope.ToLowerInvariant()) }

        try {
            & winget @wingetArgs
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                $after = Get-InstalledVersion -Id $item.Id -Source $item.Source
                $status = switch ($verb) {
                    'install'   { 'Installed' }
                    'reinstall' { 'Reinstalled' }
                    default     { if ($before -eq $after) { 'Already latest' } else { 'Updated' } }
                }
                Write-InstallLog "$($item.FriendlyName): $status ($($before ?? 'none') -> $after)" -Level SUCCESS
            }
            elseif ($verb -eq 'upgrade' -and $exitCode -eq $script:NoUpgradeExitCode) {
                $status = 'Already latest'
                Write-InstallLog "$($item.FriendlyName): no newer version available." -Level SUCCESS
            }
            else {
                $status = "Failed (exit $exitCode)"
                Write-InstallLog "$($item.FriendlyName): winget $verb failed with exit code $exitCode" -Level ERROR
            }
        }
        catch {
            $status = 'Failed (exception)'
            Write-InstallLog "$($item.FriendlyName): $_" -Level ERROR
        }
    }
    else {
        $status = 'WhatIf'
    }

    $results.Add([pscustomobject]@{
        App             = $item.FriendlyName
        Status          = $status
        PreviousVersion = $before ?? 'N/A'
        CurrentVersion  = $after ?? 'N/A'
        Id              = $item.Id
    })
}
Write-Progress -Activity 'Deploying Microsoft applications' -Completed

Write-InstallLog '=== Summary ==='
($results | Format-Table -AutoSize | Out-String).Trim() -split "`r?`n" | ForEach-Object { Write-InstallLog $_ }
$ok = @($results | Where-Object { $_.Status -in 'Installed', 'Reinstalled', 'Updated', 'Already latest' }).Count
Write-InstallLog "Completed: $ok of $($results.Count) applications OK." -Level $(if ($ok -eq $results.Count) { 'SUCCESS' } else { 'WARN' })
Write-InstallLog "Log: $LogPath"
if ($ok -ne $results.Count -and -not $WhatIfPreference) { exit 1 }
