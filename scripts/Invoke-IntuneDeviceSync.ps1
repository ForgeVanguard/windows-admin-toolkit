#Requires -Version 5.1
<#
.SYNOPSIS
    Sends an Intune sync request to managed devices whose name matches a pattern.
.DESCRIPTION
    Connects to Microsoft Graph with device-code sign-in (works where interactive browser
    sign-in fails, for example in ISE or over remote sessions), finds managed devices by
    name, and calls syncDevice on each. Use -WhatIf first to see the matches.
    Requires the Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement modules
    and the DeviceManagementManagedDevices.PrivilegedOperations.All permission.
.PARAMETER NameLike
    Device name wildcard, for example 'LAB-PC-*'.
.PARAMETER ModulePath
    Optional folder with saved Graph modules (Save-Module) for machines without gallery access.
.EXAMPLE
    .\Invoke-IntuneDeviceSync.ps1 -NameLike 'CLASSROOM-*' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$NameLike,
    [string]$ModulePath
)

if ($ModulePath) { $env:PSModulePath = "$ModulePath;$env:PSModulePath" }
foreach ($m in 'Microsoft.Graph.Authentication','Microsoft.Graph.DeviceManagement') {
    if (-not (Get-Module -ListAvailable $m)) { throw "Module $m not found. Install-Module $m -Scope CurrentUser" }
    Import-Module $m -ErrorAction Stop
}

$scopes = 'DeviceManagementManagedDevices.Read.All','DeviceManagementManagedDevices.PrivilegedOperations.All'
if (-not (Get-MgContext)) { Connect-MgGraph -Scopes $scopes -UseDeviceCode -NoWelcome }

$devices = Get-MgDeviceManagementManagedDevice -All -Property id,deviceName,lastSyncDateTime,operatingSystem,complianceState |
    Where-Object { $_.DeviceName -like $NameLike }
if (-not $devices) { Write-Output "No managed devices match '$NameLike'."; return }

$devices | Sort-Object DeviceName | ForEach-Object {
    $status = 'skipped'
    if ($PSCmdlet.ShouldProcess($_.DeviceName, 'Intune sync')) {
        try { Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $_.Id -ErrorAction Stop; $status = 'sync requested' }
        catch { $status = "error: $($_.Exception.Message)" }
    }
    [pscustomobject]@{
        Device     = $_.DeviceName
        OS         = $_.OperatingSystem
        Compliance = $_.ComplianceState
        LastSync   = $_.LastSyncDateTime
        Result     = $status
    }
} | Format-Table -AutoSize
