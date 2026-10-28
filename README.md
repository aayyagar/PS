# AD & DNS Toolkit

**A free, open-source toolkit for administering Active Directory and Windows DNS, from the command line or a desktop app.** It covers health checks, inventory, backup and restore, bulk user creation, inactive accounts, DNS records and zones, stale records, conditional forwarders and trusts.

Everything is **read-only until you ask for a change**. When you do, you see a preview first and confirm it, and every change is logged.

[![CI](https://github.com/aayyagar/PS/actions/workflows/ci.yml/badge.svg)](https://github.com/aayyagar/PS/actions/workflows/ci.yml) · Windows PowerShell 5.1 and PowerShell 7 · Windows Server 2016–2025, Windows 10/11 with RSAT · MIT license · v2.0.0

```text
  ==========================================================
    AD & DNS Toolkit v2.0.0
    Output: C:\Users\you\Documents\ADDnsToolkit
  ==========================================================
   ACTIVE DIRECTORY
     2. Active Directory health check
     3. Active Directory inventory report
     ...
   DNS
     9. DNS health check
    10. DNS records: list / export
     ...
```

---

## Three ways to use it

| | How | Best for |
|---|---|---|
| **App (GUI)** | Double-click `Launch-Toolkit.cmd` | Day-to-day admin work, help desk, people who don't script |
| **Console menu** | `.\Start-Toolkit.ps1 -Console` | Server Core, SSH, remote sessions |
| **Cmdlets** | `Import-Module .\ADDnsToolkit` | Automation, scheduled tasks, pipelines |

All three run the same code. The app runs each task in the background so the window never freezes, and shows progress in an activity pane.

## Quick start

1. Download the [latest release ZIP](https://github.com/aayyagar/PS/releases), or run:
   ```powershell
   git clone https://github.com/aayyagar/PS.git
   ```
2. Double-click **`Launch-Toolkit.cmd`**. Right-click it and choose *Run as administrator* if you'll install RSAT or make changes that need elevation.
3. On the **Home** page, check the prerequisites. If the Active Directory or DNS tools are missing, click **Install RSAT tools**.

The launcher uses PowerShell 7 if it's installed and falls back to Windows PowerShell 5.1. It also clears the "downloaded from the internet" mark on the toolkit's own files, so a ZIP download works under the default `RemoteSigned` policy.

## What it does

### Active Directory

| Feature | Cmdlet | What you get |
|---|---|---|
| **Health check** | `Test-ADTHealth` | Pass/Warn/Fail with a fix for each issue. Per DC: ports (LDAP, Kerberos, SMB, RPC, GC), NTDS/Netlogon/KDC/DNS/DFSR/W32Time services, SYSVOL and NETLOGON, clock offset from the PDC, OS support. Domain-wide: replication per partner and partition, replication failures, FSMO holders, AD Recycle Bin, krbtgt password age, functional level. Output: HTML, CSV and TXT. |
| **Inventory** | `Get-ADTInventory` | Users, computers, groups, OUs, DCs, trusts and privileged-group members. Highlights stale accounts, non-expiring passwords, unsupported Windows versions, empty groups and linked GPOs. Output: HTML, CSV and JSON. |
| **Backup** | `Backup-ADTObject` | Users, groups (with members), OUs and optionally computers, as JSON and CSV with a manifest. |
| **Restore** | `Restore-ADTObject` | Creates **only what's missing**, parents first, and never changes existing objects. Users come back disabled unless you give them an initial password. Distinguished names are rewritten when you restore into another domain. Reads v1 CSV backups too. |
| **Bulk users** | `Test-ADTBulkUserCsv`, `New-ADTBulkUser` | Validates every row: name rules, duplicates, existing accounts and UPNs, OUs, groups, managers, email. Rows can also add users to groups and set managers. Rows without a password can get a random one. |
| **Inactive users** | `Get-ADTInactiveUser`, `Disable-ADTInactiveUser` | Skips service accounts (SPNs), built-in accounts and excluded groups. Each disabled account is stamped with the date and reason and can be moved to an OU. You get a CSV for undoing the change. |
| **Trusts** | `Get-ADTTrust`, `Test-ADTTrust` | Direction, type, selective authentication, SID filtering and AES/RC4 for each trust, plus secure-channel verification. |

### DNS

| Feature | Cmdlet | What you get |
|---|---|---|
| **Health check** | `Test-ADTDnsHealth` | Service and port 53. Per zone: state, insecure dynamic updates and aging. Server-wide: scavenging, recursion, and each forwarder (tested by asking it to resolve a name). Also checks the DC locator records (`_ldap._tcp.dc._msdcs`), DNS Server errors from the last 24 hours, and stale records. |
| **Records** | `Get-ADTDnsRecord`, `Add-ADTDnsRecord`, `Remove-ADTDnsRecord`, `Import-ADTDnsRecord` | A, AAAA, CNAME, MX, TXT and PTR records, with validation and optional PTR creation. The flat output exports to CSV and imports back. SOA and NS records are protected. |
| **Zone backup** | `Backup-ADTDnsZone` | Saves the zone file, every record as JSON, and the zone settings (replication scope, dynamic updates, aging). Works for remote servers through `admin$`. |
| **Zone restore** | `Restore-ADTDnsZone` | Re-creates a missing zone and makes it AD-integrated again with its original scope. For an existing zone, it adds only the records that are missing. |
| **Stale records** | `Find-ADTStaleDnsRecord`, `Remove-ADTStaleDnsRecord` | Considers only dynamic records older than the zone's aging interval, or a threshold you choose. Saves the records before removing them, so you can re-import them. Can keep records whose address still answers. |
| **Conditional forwarders** | `Get-/Add-/Remove-ADTConditionalForwarder` | Replicated to the forest, the domain, or kept on one server. |

### Tools

`Get-ADTEnvironment` reports the OS, PowerShell version, domain, admin rights, cloud (Azure/AWS/GCP), hypervisor, cluster and installed RSAT modules. `Install-ADTPrerequisite` installs RSAT tools only, never server roles. `Test-ADTConnection` pings a host and tests its AD/DNS ports. `Test-ADTDnsResolution` resolves a name against any server.

Run `Get-Command -Module ADDnsToolkit` for the full list, and `Get-Help <cmdlet> -Examples` for examples.

## Safe by design

- **Read-only by default.** Health checks, inventory, backups and finds never change anything.
- **Preview everything.** Every cmdlet that changes AD or DNS supports `-WhatIf` and returns rows such as `WouldCreate`, `WouldDisable` and `WouldRemove`. The menu always previews first, and the app has a **Preview** button and a confirmation dialog for each change.
- **Additive restores.** Restores create only missing objects, users come back disabled by default, and nothing is ever overwritten.
- **Undo paths.** Disabled users get a DN report. Removed stale records are saved as CSV and JSON for `Import-ADTDnsRecord`. Zones can be backed up in one click.
- **Audit log.** Each change is written to `Documents\ADDnsToolkit\Logs` with who, where and when. The app shows it on the **Activity log** page.
- **No secrets on disk** unless you ask. Generated passwords are written to a file only through `-IncludePasswordsInReport` or the app's **Save passwords...** button.
- **Encoded reports.** Every value is HTML-encoded, and reports are self-contained files with no external scripts.

## Cmdlet examples

```powershell
Import-Module .\ADDnsToolkit\ADDnsToolkit.psd1

# Health and inventory
Test-ADTHealth | Select-Object -ExpandProperty Checks | Where-Object Status -ne 'Pass'
Get-ADTInventory -StaleDays 60
Test-ADTDnsHealth -ComputerName dc01.contoso.com

# Users
New-ADTBulkUser -CsvPath .\Samples\NewUsers.csv -GeneratePassword -WhatIf
Get-ADTInactiveUser -Days 120 -ExcludeGroup 'Break Glass' | Disable-ADTInactiveUser -MoveToOU 'OU=Disabled,DC=contoso,DC=com'

# Backup and restore
$b = Backup-ADTObject
Restore-ADTObject -Path $b.OutputFolder -Include OU, Group -WhatIf

# DNS
Get-ADTDnsRecord -ZoneName contoso.com -Name 'web*' | Export-Csv web.csv -NoTypeInformation
Add-ADTDnsRecord -ZoneName contoso.com -Name app01 -Type A -Data 10.0.0.25 -CreatePtr
Find-ADTStaleDnsRecord -OlderThanDays 90 | Remove-ADTStaleDnsRecord -SkipIfResponding -WhatIf
Backup-ADTDnsZone -ComputerName dc01

# Weekly health report from a scheduled task
pwsh -NoProfile -Command "Import-Module C:\Tools\PS\ADDnsToolkit; Test-ADTHealth; Test-ADTDnsHealth"
```

## Requirements and permissions

| Need | Details |
|---|---|
| PowerShell | Windows PowerShell 5.1 or PowerShell 7.2+. The app needs a Windows desktop session; everything else also runs on Server Core. |
| Modules | RSAT **ActiveDirectory** and **DnsServer**, installed with `Install-ADTPrerequisite` or the **Install RSAT tools** button. **FailoverClusters** is optional and only used for cluster detection. |
| Read tasks | Any domain user can run inventory and most checks. Remote service checks need WinRM or DCOM access to the DCs, and DNS checks need DnsAdmins or equivalent read rights. |
| Changes | Rights for the object you're changing: delegated OU rights for users and groups, DnsAdmins for records and zones, and `admin$` access to a remote DNS server for zone files. |

Reports, backups and logs go to `Documents\ADDnsToolkit\<task>\<task>_<timestamp>`. Change this with `Set-ADTConfig -OutputRoot D:\Toolkit`, the `ADT_OUTPUT_ROOT` environment variable, or **Home > Change output folder**.

## Upgrading from v1

The v1 script names still work. Each one is now a short wrapper that runs the new cmdlet, with validation and a preview first.

| v1 script | Now runs |
|---|---|
| `AD_Tools\Get-ADInventory.ps1` | `Get-ADTInventory`. It no longer offers to install the AD DS server role or Failover Clustering. |
| `AD_Tools\HealthCheck-AD.ps1` | `Test-ADTHealth` |
| `AD_Tools\Backup-AD.ps1` / `Restore-AD.ps1` | `Backup-ADTObject` / `Restore-ADTObject`, which also reads v1 backups |
| `AD_Tools\Create-ADUserBulk.ps1` | `New-ADTBulkUser` |
| `AD_Tools\Disable-InactiveUsers.ps1` | `Get-ADTInactiveUser` + `Disable-ADTInactiveUser` |
| `DNS_Tools\Backup-DNSZones.ps1` / `Restore-DNSZones.ps1` | `Backup-ADTDnsZone` / `Restore-ADTDnsZone` |
| `DNS_Tools\Get-DNSHealth.ps1` | `Test-ADTDnsHealth` |
| `DNS_Tools\Create-DNSRecord.ps1` | `Add-ADTDnsRecord` / `Import-ADTDnsRecord` |
| `DNS_Tools\Clean-DNSStaleRecords.ps1` | `Find-` / `Remove-ADTStaleDnsRecord` |
| `DNS_Tools\Advanced DNS Management Tool.ps1`, `Launcher\*.ps1` | The app or the console menu |

v2 also fixes these v1 problems:

- **Stale DNS cleanup removed every dynamic record**, whatever its age. It now uses an age threshold, never touches SOA/NS or the zone apex, and saves the records first.
- **DNS zone backups failed**, because `Export-DnsServerZone` can only write inside `%windir%\System32\dns`. The zone restore also used a parameter combination `Add-DnsServerPrimaryZone` rejects.
- **AD restore** used a hard-coded `DC=yourdomain,DC=com`, tried to create enabled users without a password, and passed `LDAP://` paths where distinguished names were required.
- **Bulk users:** the duplicate check never matched, because of the `-Filter { $User.SamAccountName }` scoping issue.
- **Health check:** the FSMO section was always empty, and replication output lost its line breaks.
- **DNS GUI:** Add and Delete record failed (`$host` is read-only), the dark theme didn't apply, CSV import read the wrong column, and "Create Trust" called a cmdlet that doesn't exist.
- `upload.ps1` and `.vscode/settings.json` contained merge-conflict markers, and the license was truncated and contradicted by the script headers.

## Project layout

```text
Launch-Toolkit.cmd            double-click launcher
Start-Toolkit.ps1             GUI on a desktop, console menu otherwise
ADDnsToolkit/                 the module (works with Import-Module)
  Public/   AD.ps1, DNS.ps1, Environment.ps1
  Private/  Common.ps1        config, logging, reports, helpers
  Console/  Menu.ps1          text menu
  GUI/      ToolkitGui.ps1    Windows Forms app (async runspaces)
Samples/                      NewUsers.csv, DnsRecords.csv
AD_Tools/, DNS_Tools/, Launcher/   v1 script names (wrappers)
tests/                        Pester 5 tests with in-memory AD/DNS stubs
```

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To run the checks locally:

```powershell
Invoke-Pester ./tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

The tests replace the AD and DNS cmdlets with in-memory stubs, so they run on any machine, including Linux. On Windows they also build the app window.

## License

[MIT](LICENSE) © 2024-2026 Akhilesh Ayyagari. Free to use, change and share. Provided as is: preview changes in your environment before applying them.
