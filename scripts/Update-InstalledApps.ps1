#Requires -Version 5.1
<#
.SYNOPSIS
    Upgrades installed applications with winget, with an exclusion list and a log file.
.PARAMETER Exclude
    winget package IDs to skip (for example pinned line-of-business tools).
.PARAMETER LogPath
    Where to write the transcript. Defaults to %TEMP%.
.EXAMPLE
    .\Update-InstalledApps.ps1 -WhatIf
.EXAMPLE
    .\Update-InstalledApps.ps1 -Exclude 'Mozilla.Firefox','Oracle.VirtualBox'
.NOTES
    If scripts are blocked, run once per user:  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Exclude = @(),
    [string]$LogPath = (Join-Path $env:TEMP ("winget-upgrade-{0:yyyyMMdd-HHmm}.log" -f (Get-Date)))
)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget (App Installer) is not installed.' }
Start-Transcript -Path $LogPath -Append | Out-Null
try {
    winget source update | Out-Null
    # Parse the upgrade table by column positions from the header line
    $raw = winget upgrade --include-unknown --accept-source-agreements 2>$null
    $header = $raw | Where-Object { $_ -match '^Name\s+Id\s+Version' } | Select-Object -First 1
    if (-not $header) { Write-Output 'Nothing to upgrade (or unexpected winget output).'; return }
    $idStart  = $header.IndexOf('Id')
    $verStart = $header.IndexOf('Version')
    $rows = $raw[([array]::IndexOf($raw, $header) + 2)..($raw.Count - 1)] |
        Where-Object { $_.Length -gt $verStart -and $_ -notmatch 'upgrades available' }

    $ids = foreach ($r in $rows) { $r.Substring($idStart, $verStart - $idStart).Trim() }
    $ids = $ids | Where-Object { $_ -and $Exclude -notcontains $_ }
    Write-Output ("{0} package(s) to upgrade" -f @($ids).Count)

    foreach ($id in $ids) {
        if ($PSCmdlet.ShouldProcess($id, 'winget upgrade')) {
            winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements
            Write-Output ("{0}: exit {1}" -f $id, $LASTEXITCODE)
        }
    }
} finally {
    Stop-Transcript | Out-Null
    Write-Output "Log: $LogPath"
}
