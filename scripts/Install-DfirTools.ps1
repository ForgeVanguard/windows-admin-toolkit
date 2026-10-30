#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a baseline DFIR / security analyst toolset with winget.
.DESCRIPTION
    Installs each package one at a time with progress visible, so a slow download (Git is
    a common one) does not look like a hang. Already-installed packages are skipped.
    Edit $Packages to suit your workflow.
.EXAMPLE
    .\Install-DfirTools.ps1 -WhatIf
.EXAMPLE
    .\Install-DfirTools.ps1 -Only Git.Git,WiresharkFoundation.Wireshark
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Only)

$Packages = [ordered]@{
    'Git.Git'                         = 'Git'
    '7zip.7zip'                       = '7-Zip'
    'Microsoft.WindowsTerminal'       = 'Windows Terminal'
    'Microsoft.PowerShell'            = 'PowerShell 7'
    'Microsoft.VisualStudioCode'      = 'VS Code'
    'Python.Python.3.12'              = 'Python 3.12'
    'Microsoft.Sysinternals.Suite'    = 'Sysinternals Suite'
    'WiresharkFoundation.Wireshark'   = 'Wireshark'
    'Insecure.Nmap'                   = 'Nmap'
    'Hashicorp.Vagrant'               = 'Vagrant'
    'DBBrowserForSQLite.DBBrowserForSQLite' = 'DB Browser for SQLite'
    'MHNexus.HxD'                     = 'HxD hex editor'
    'KeePassXCTeam.KeePassXC'         = 'KeePassXC'
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget (App Installer) is not installed.' }
$ids = if ($Only) { $Only } else { $Packages.Keys }

$summary = foreach ($id in $ids) {
    $label = if ($Packages.Contains($id)) { $Packages[$id] } else { $id }
    $listed = winget list --id $id --exact --accept-source-agreements 2>$null | Select-String -SimpleMatch $id
    if ($listed) { [pscustomobject]@{ Package = $label; Id = $id; Result = 'already installed' }; continue }
    if ($PSCmdlet.ShouldProcess("$label ($id)", 'winget install')) {
        Write-Host "==> Installing $label" -ForegroundColor Cyan
        winget install --id $id --exact --accept-package-agreements --accept-source-agreements
        [pscustomobject]@{ Package = $label; Id = $id; Result = if ($LASTEXITCODE -eq 0) { 'installed' } else { "exit $LASTEXITCODE" } }
    }
}
$summary | Format-Table -AutoSize
Write-Output 'Tools like Autopsy, FTK Imager, KAPE and Eric Zimmerman tools need vendor downloads or registration and are not installed here.'
