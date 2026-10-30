# Windows Admin Toolkit

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

Practical PowerShell scripts for day-to-day Windows administration and security hygiene: posture checks, patching, app updates, session cleanup, storage benchmarking, email-domain checks, DFIR workstation setup and Intune device sync.

They come out of the kinds of tasks I handle as a systems administrator in a hybrid Microsoft environment, rewritten here as clean, generic, parameterized tools with no environment-specific details.

## Scripts

| Script | Purpose | Changes system? |
| --- | --- | --- |
| [`Get-SecurityPosture.ps1`](scripts/Get-SecurityPosture.ps1) | PASS/WARN/FAIL report: build+UBR, pending reboot, password/lockout policy, local admins, BitLocker, Defender, firewall, SMBv1, RDP/NLA. Optional CSV. | No |
| [`Invoke-QualityUpdate.ps1`](scripts/Invoke-QualityUpdate.ps1) | Finds, downloads and installs pending Windows updates through the Windows Update Agent API, and reports the build before and after | Yes (`-WhatIf`) |
| [`Update-InstalledApps.ps1`](scripts/Update-InstalledApps.ps1) | `winget` upgrade of all apps with an exclusion list and a transcript log | Yes (`-WhatIf`) |
| [`Clear-BrowserSessions.ps1`](scripts/Clear-BrowserSessions.ps1) | Signs a user out of web sessions: clears cookies, sessions and (optionally) history for Chrome, Edge and Firefox profiles | Yes (`-WhatIf`) |
| [`Test-StorageThroughput.ps1`](scripts/Test-StorageThroughput.ps1) | Sequential write/read benchmark for a local disk or UNC share, in MB/s and Mbit/s | Temp file only |
| [`Test-EmailDomainSecurity.ps1`](scripts/Test-EmailDomainSecurity.ps1) | Checks MX, SPF (including `+all` and lookup count), DMARC policy and common DKIM selectors | No |
| [`Install-DfirTools.ps1`](scripts/Install-DfirTools.ps1) | Installs a baseline DFIR/analyst toolset with `winget`, one package at a time with progress shown | Yes (`-WhatIf`) |
| [`Invoke-IntuneDeviceSync.ps1`](scripts/Invoke-IntuneDeviceSync.ps1) | Microsoft Graph (device-code sign-in) Intune sync for devices matching a name pattern | Yes (`-WhatIf`) |

## Usage

```powershell
git clone https://github.com/ForgeVanguard/windows-admin-toolkit.git
cd windows-admin-toolkit\scripts

# If scripts are blocked for your user:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

Get-Help .\Get-SecurityPosture.ps1 -Detailed
.\Get-SecurityPosture.ps1 -CsvPath .\posture.csv
.\Test-EmailDomainSecurity.ps1 -Domain example.com
.\Invoke-QualityUpdate.ps1 -WhatIf
```

Every script has comment-based help (`Get-Help <script> -Full`). Anything that changes state supports `-WhatIf` / `-Confirm`, so preview first.

## Notes

- Check patch compliance by **OS build and UBR**, not by KB title. Both the posture and update scripts report `Build.UBR`.
- Clearing browser data on a device does not revoke tokens on the server. After a lost or shared device, also sign out other sessions from each account's security page.
- Scripts are linted with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) (see `PSScriptAnalyzerSettings.psd1`).

## Disclaimer

Test in a lab or on a non-production machine first. Provided as-is under the MIT license.

## License

MIT © Steven Drew
