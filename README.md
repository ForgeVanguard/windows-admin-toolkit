# Windows Admin Toolkit

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

Practical PowerShell scripts for day-to-day Windows administration and security hygiene: posture checks, patching, app installs and updates, session cleanup, email-domain checks and Intune device sync.

They come out of the kinds of tasks I handle as a systems administrator in a hybrid Microsoft environment, rewritten here as clean, generic, parameterized tools with no environment-specific details.

## Scripts

| Script | Purpose | Changes system? |
| --- | --- | --- |
| [`Get-SecurityPosture.ps1`](scripts/Get-SecurityPosture.ps1) | PASS/WARN/FAIL report: build+UBR, pending reboot, password/lockout policy, local admins, BitLocker, Defender, firewall, SMBv1, RDP/NLA. Optional CSV. | No |
| [`Invoke-QualityUpdate.ps1`](scripts/Invoke-QualityUpdate.ps1) | Finds, downloads and installs pending Windows updates through the Windows Update Agent API, and reports the build before and after | Yes (`-WhatIf`) |
| [`Invoke-ForceQualityUpdate.ps1`](scripts/Invoke-ForceQualityUpdate.ps1) | Intune/SYSTEM remediation: checks the build against a per-release UBR table for one advisory, installs every pending quality update, guards against the Machine Identity Isolation secure-channel issue, and optionally forces a timed restart | Yes |
| [`Update-InstalledApps.ps1`](scripts/Update-InstalledApps.ps1) | Updates all winget-managed apps via the Microsoft.WinGet.Client module (winget.exe fallback): all, pick in a grid (`-Interactive`), or `-ListOnly`; exclusions and transcript log | Yes (`-WhatIf`) |
| [`Install-MicrosoftStandardApp.ps1`](scripts/Install-MicrosoftStandardApp.ps1) | Installs or upgrades Edge, Teams, OneDrive and new Outlook with prerequisite checks, before/after versions and a log (PowerShell 7) | Yes (`-WhatIf`) |
| [`Clear-BrowserSessions.ps1`](scripts/Clear-BrowserSessions.ps1) | Signs this PC out of web sessions: closes Chrome, Edge, Brave and Firefox and clears cookies, sessions, site data and cache per profile. Passwords, autofill and Firefox history/bookmarks only on request | Yes (`-WhatIf`) |
| [`Test-EmailDomainSecurity.ps1`](scripts/Test-EmailDomainSecurity.ps1) | Checks MX, SPF (including `+all` and lookup count), DMARC policy and common DKIM selectors | No |
| [`Invoke-IntuneDeviceSync.ps1`](scripts/Invoke-IntuneDeviceSync.ps1) | Microsoft Graph (device-code sign-in) Intune sync for devices matching a name pattern | Yes (`-WhatIf`) |

## Related repositories

| Repo | What moved there |
| --- | --- |
| [windows-hardening-kit](https://github.com/ForgeVanguard/windows-hardening-kit) | Reversible workstation security baseline (ASR, SMB, LLMNR, firewall) with undo and weekly check |
| [storage-benchmark](https://github.com/ForgeVanguard/storage-benchmark) | Full robocopy-based storage benchmark (replaces the old `Test-StorageThroughput.ps1`) |
| [dfir-osint-toolkit](https://github.com/ForgeVanguard/dfir-osint-toolkit) | Windows and Kali DFIR/OSINT tool installers (replaces the old `Install-DfirTools.ps1`) |
| [windows-workstation-cleanup](https://github.com/ForgeVanguard/windows-workstation-cleanup) | Debloat, cleanup and post-cleanup setup scripts |

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

- Check patch compliance by **OS build and UBR**, not by KB title. The posture and update scripts all report `Build.UBR`.
- `Invoke-ForceQualityUpdate.ps1` ships with the UBR table for one specific advisory; edit `Get-RequiredUbr` for the next one.
- Windows-only scripts are tested for syntax only (parse + PSScriptAnalyzer); run them with `-WhatIf` first.
- Clearing browser data on a device does not revoke tokens on the server. After a lost or shared device, also sign out other sessions from each account's security page.
- Scripts are linted with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) (see `PSScriptAnalyzerSettings.psd1`).

## Disclaimer

Test in a lab or on a non-production machine first. Provided as-is under the MIT license.

## License

MIT © Steven Drew
