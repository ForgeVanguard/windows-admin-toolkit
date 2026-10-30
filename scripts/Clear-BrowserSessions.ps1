<#
.SYNOPSIS
  Close browsers and wipe local session data so sites treat this PC as logged out.

.DESCRIPTION
  Kills Chrome, Edge, Brave, and Firefox, then deletes cookies, history, cache,
  session storage, and local storage for every profile it finds.

  This logs you out of cookie-based sessions ON THIS MACHINE ONLY.
  It does not:
    - Sign out phones, other PCs, or "trusted device" tokens stored on the server
    - Revoke OAuth refresh tokens held by apps
    - Delete bookmarks, extensions, or (by default) saved passwords or autofill data

  For a real "log out everywhere", also use each account's security page
  (Google, Microsoft, Apple, banks, etc.) after this runs.

.PARAMETER IncludePasswords
  Also delete saved passwords (Chromium Login Data, Firefox logins.json/key4.db). Off by default.

.PARAMETER IncludeAutofill
  Also delete Chromium 'Web Data' (autofill addresses, saved payment methods, search engines)
  and Firefox form history. Off by default.

.PARAMETER IncludeFirefoxPlaces
  Also delete Firefox places.sqlite. That file holds history AND bookmarks, so it is only
  removed when asked. Without it, Firefox history is kept.

.PARAMETER Browsers
  Which browsers to clean. Default: Chrome, Edge, Brave, Firefox.

.EXAMPLE
  .\Clear-BrowserSessions.ps1

.EXAMPLE
  .\Clear-BrowserSessions.ps1 -IncludePasswords -Browsers Chrome, Edge

.EXAMPLE
  .\Clear-BrowserSessions.ps1 -WhatIf

.NOTES
  Author : Steven Drew
  License: MIT
  Runs in the current user's context; cleans that user's profiles only.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludePasswords,
    [switch]$IncludeAutofill,
    [switch]$IncludeFirefoxPlaces,
    [ValidateSet('Chrome', 'Edge', 'Brave', 'Firefox')]
    [string[]]$Browsers = @('Chrome', 'Edge', 'Brave', 'Firefox')
)

$ErrorActionPreference = 'Continue'

function Write-Step([string]$Message) {
    Write-Host "[*] $Message" -ForegroundColor Cyan
}
function Write-Ok([string]$Message) {
    Write-Host "[+] $Message" -ForegroundColor Green
}
function Write-Warn([string]$Message) {
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

# Process names that lock the profile databases.
$processMap = @{
    Chrome  = 'chrome'
    Edge    = 'msedge'
    Brave   = 'brave'
    Firefox = 'firefox'
}

# Roots that contain one folder per profile (Default, Profile 1, ...).
$userDataRoots = @{
    Chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    Edge   = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
    Brave  = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
}

# Files/folders that hold session state. Bookmarks and Preferences are intentionally excluded.
$sessionItems = @(
    'Cookies',
    'Cookies-journal',
    'History',
    'History-journal',
    'History Provider Cache',
    'Login Data',
    'Login Data-journal',
    'Login Data For Account',
    'Login Data For Account-journal',
    'Network\Cookies',
    'Network\Cookies-journal',
    'Network\Trust Tokens',
    'Network\Trust Tokens-journal',
    'Session Storage',
    'Local Storage',
    'IndexedDB',
    'Service Worker',
    'Cache',
    'Code Cache',
    'GPUCache',
    'DawnGraphiteCache',
    'DawnWebGPUCache',
    'Shared Dictionary',
    'Sessions',
    'Current Session',
    'Current Tabs',
    'Last Session',
    'Last Tabs',
    'Visited Links',
    'Top Sites',
    'Top Sites-journal',
    'Favicons',
    'Favicons-journal',
    'Extension State',
    'File System',
    'Platform Notifications',
    'shared_proto_db'
)

$autofillItems = @(
    'Web Data',
    'Web Data-journal'
)

$passwordItems = @(
    'Login Data',
    'Login Data-journal',
    'Login Data For Account',
    'Login Data For Account-journal'
)

function Stop-BrowserProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string[]]$Names)
    foreach ($name in $Names) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $procs) { continue }
        if (-not $PSCmdlet.ShouldProcess($name, 'Stop process')) { continue }
        Write-Step "Stopping $name ($(@($procs).Count) process(es))"
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    # Second pass: child processes sometimes respawn during shutdown.
    foreach ($name in $Names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

function Remove-SessionItem {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove')) { return $false }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warn "Locked or denied: $Path ($($_.Exception.Message))"
        return $false
    }
}

function Clear-ChromiumProfile {
    param(
        [string]$ProfilePath,
        [bool]$WipePasswords,
        [bool]$WipeAutofill
    )
    $items = @($sessionItems)
    if (-not $WipePasswords) { $items = @($items | Where-Object { $passwordItems -notcontains $_ }) }
    if ($WipeAutofill) { $items += $autofillItems }
    $removed = 0
    foreach ($rel in $items) {
        $full = Join-Path $ProfilePath $rel
        if (Remove-SessionItem -Path $full) { $removed++ }
    }
    return $removed
}

function Clear-ChromiumBrowser {
    param(
        [string]$Name,
        [string]$Root,
        [bool]$WipePasswords,
        [bool]$WipeAutofill
    )
    if (-not (Test-Path -LiteralPath $Root)) {
        Write-Warn "$Name not installed (no $Root)"
        return
    }
    Write-Step "Cleaning $Name profiles under $Root"

    $profiles = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' }

    if (-not $profiles) {
        Write-Warn "$Name has no profiles"
        return
    }

    foreach ($browserProfile in $profiles) {
        $count = Clear-ChromiumProfile -ProfilePath $browserProfile.FullName -WipePasswords $WipePasswords -WipeAutofill $WipeAutofill
        Write-Ok "$Name\$($browserProfile.Name): removed $count session items"
    }

    # Browser-level shader / crash caches sit next to profiles, not inside them.
    foreach ($rel in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache', 'Crashpad')) {
        Remove-SessionItem -Path (Join-Path $Root $rel) | Out-Null
    }
}

function Clear-Firefox {
    param(
        [bool]$WipePasswords,
        [bool]$WipeAutofill,
        [bool]$WipePlaces
    )
    $profileRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    if (-not (Test-Path -LiteralPath $profileRoot)) {
        Write-Warn "Firefox not installed (no $profileRoot)"
        return
    }
    Write-Step "Cleaning Firefox profiles under $profileRoot"

    $targets = @(
        'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm',
        'webappsstore.sqlite', 'webappsstore.sqlite-wal', 'webappsstore.sqlite-shm',
        'storage',
        'sessionstore.jsonlz4', 'sessionstore-backups',
        'cache2', 'startupCache', 'shader-cache',
        'serviceworker.txt',
        'cookies.sqlite-journal'
    )
    if ($WipePlaces) {
        # History and bookmarks share this database.
        $targets += @('places.sqlite', 'places.sqlite-wal', 'places.sqlite-shm')
    }
    if ($WipeAutofill) {
        $targets += @('formhistory.sqlite', 'formhistory.sqlite-wal', 'formhistory.sqlite-shm')
    }
    if ($WipePasswords) {
        # cert9.db is the certificate store, not passwords; it is left alone.
        $targets += @('logins.json', 'logins-backup.json', 'key4.db', 'key3.db', 'signons.sqlite')
    }

    $profiles = Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue
    foreach ($browserProfile in $profiles) {
        $removed = 0
        foreach ($rel in $targets) {
            if (Remove-SessionItem -Path (Join-Path $browserProfile.FullName $rel)) { $removed++ }
        }
        Write-Ok "Firefox\$($browserProfile.Name): removed $removed session items"
    }

    # Local cache lives outside the profile.
    $localCache = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $localCache) {
        Get-ChildItem -LiteralPath $localCache -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-SessionItem -Path (Join-Path $_.FullName 'cache2') | Out-Null
        }
    }
}

Write-Host ""
Write-Host "Browser session wipe" -ForegroundColor White
Write-Host "Browsers : $($Browsers -join ', ')"
Write-Host "Passwords: $(if ($IncludePasswords) { 'DELETE' } else { 'keep' })"
Write-Host "Autofill : $(if ($IncludeAutofill) { 'DELETE' } else { 'keep' })"
Write-Host "Firefox history/bookmarks (places): $(if ($IncludeFirefoxPlaces) { 'DELETE' } else { 'keep' })"
Write-Host ""
Write-Warn "Close anything unsaved. This signs this PC out of sites that use cookies."
Write-Warn "It does not sign out other devices. Do that in each account's security page."
Write-Host ""

if (-not $PSCmdlet.ShouldProcess("local browser profiles", "clear cookies, history, cache, site data")) {
    Write-Warn "Cancelled."
    return
}

$toKill = foreach ($b in $Browsers) { $processMap[$b] }
Stop-BrowserProcess -Names $toKill -Confirm:$false

foreach ($b in $Browsers) {
    switch ($b) {
        'Firefox' { Clear-Firefox -WipePasswords $IncludePasswords.IsPresent -WipeAutofill $IncludeAutofill.IsPresent -WipePlaces $IncludeFirefoxPlaces.IsPresent }
        default   { Clear-ChromiumBrowser -Name $b -Root $userDataRoots[$b] -WipePasswords $IncludePasswords.IsPresent -WipeAutofill $IncludeAutofill.IsPresent }
    }
}

Write-Host ""
Write-Ok "Done. Reopen the browser; sites should ask you to sign in again."
Write-Host ""
Write-Host "Still logged in on other devices? Revoke those sessions here:" -ForegroundColor White
Write-Host "  Google    https://myaccount.google.com/device-activity"
Write-Host "  Microsoft https://account.live.com/Activity"
Write-Host "  Apple     https://account.apple.com  (Devices)"
Write-Host "  Facebook  https://www.facebook.com/settings?tab=security"
Write-Host "  Discord   User Settings > Devices"
Write-Host ""
