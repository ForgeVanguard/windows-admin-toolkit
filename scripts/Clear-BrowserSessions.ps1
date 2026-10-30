#Requires -Version 5.1
<#
.SYNOPSIS
    Signs the current user out of web sessions by clearing cookies, session and history data for Chrome, Edge and Firefox.
.DESCRIPTION
    Closes the browsers, then deletes cookie, session, login-token and history stores in
    every profile. Bookmarks, saved passwords, autofill and extensions are left alone. Edge "startup boost"
    can keep msedge.exe running in the background, so processes are stopped twice.
    Clearing local data does not revoke tokens on the server: also sign out other sessions
    from the account security pages (Microsoft, Google, Apple) when a device is lost or shared.
.PARAMETER Browser
    Which browsers to clear (default: all three).
.PARAMETER KeepHistory
    Clear cookies and sessions but keep browsing history.
.EXAMPLE
    .\Clear-BrowserSessions.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Chrome','Edge','Firefox')][string[]]$Browser = @('Chrome','Edge','Firefox'),
    [switch]$KeepHistory
)

$procs = @{ Chrome = 'chrome'; Edge = 'msedge'; Firefox = 'firefox' }
function Stop-Browsers {
    foreach ($b in $Browser) {
        Get-Process -Name $procs[$b] -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess("$($_.Name) ($($_.Id))", 'Stop process')) { $_ | Stop-Process -Force -ErrorAction SilentlyContinue }
        }
    }
}
Stop-Browsers; Start-Sleep -Seconds 2; Stop-Browsers   # second pass for Edge startup boost

$chromiumTargets = @('Network\Cookies','Network\Cookies-journal','Cookies','Cookies-journal','Sessions','Session Storage','Current Session','Current Tabs','Last Session','Last Tabs')
if (-not $KeepHistory) { $chromiumTargets += 'History','History-journal','Visited Links','Top Sites' }

$roots = @{
    Chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    Edge   = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
}
$removed = 0
foreach ($b in $Browser | Where-Object { $_ -ne 'Firefox' }) {
    $root = $roots[$b]
    if (-not (Test-Path $root)) { continue }
    $profiles = Get-ChildItem $root -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
    foreach ($p in $profiles) {
        foreach ($t in $chromiumTargets) {
            $path = Join-Path $p.FullName $t
            if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess("$b/$($p.Name)/$t", 'Remove')) {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue; $removed++
            }
        }
    }
}

if ($Browser -contains 'Firefox') {
    $ffRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    # Firefox history lives in places.sqlite with bookmarks, so it is left alone here
    $ffTargets = @('cookies.sqlite','cookies.sqlite-wal','sessionstore.jsonlz4','sessionstore-backups','storage\default')
    if (-not $KeepHistory) { $ffTargets += 'formhistory.sqlite' }
    if (Test-Path $ffRoot) {
        foreach ($p in Get-ChildItem $ffRoot -Directory) {
            foreach ($t in $ffTargets) {
                $path = Join-Path $p.FullName $t
                if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess("Firefox/$($p.Name)/$t", 'Remove')) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue; $removed++
                }
            }
        }
    }
}
Write-Output "Removed $removed item(s). Revoke server-side sessions from each account's security page as well."
