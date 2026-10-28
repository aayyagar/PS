# Changelog

## 2.0.0 - 2026-10-28

The toolkit was rebuilt as a PowerShell module with three front ends: a Windows app, a console menu and cmdlets.

### Added
- **ADDnsToolkit module**: 37 documented commands, compatible with Windows PowerShell 5.1 and PowerShell 7.
- **Windows app** (`Launch-Toolkit.cmd`): 14 pages. Tasks run in background runspaces with live progress, results appear in sortable grids with selection, changes are previewed and confirmed, and there is a dark mode.
- **Console menu** (`Start-Toolkit.ps1 -Console`) for Server Core and remote sessions. It always previews before applying a change.
- **AD health check**, rebuilt with Pass/Warn/Fail results and a fix for each issue. It covers ports, services, SYSVOL/NETLOGON, time offset from the PDC, per-partner replication, FSMO reachability, Recycle Bin, krbtgt age and OS support.
- **Inventory** now includes privileged-group members, stale users and computers, unsupported Windows versions, empty groups and linked GPOs.
- **Object restore**, additive and parents first, with domain DN rewriting. Users are created disabled by default, and v1 backups can still be read.
- **Bulk user validation**: name rules, duplicates, existing accounts and UPNs, OUs, groups, managers and email. Adds group membership and managers, and can generate random passwords.
- **Inactive users**: exclusions for SPNs, built-in accounts and groups. Disabled accounts are stamped with the date and reason, can be moved to an OU, and are listed in an undo report.
- **DNS**: flat record output that round-trips through CSV; AAAA records and PTR creation; record removal by data; zone backup with a JSON copy of records and settings; zone restore that re-creates AD-integrated zones; conditional forwarders; and name resolution and port diagnostics.
- **DNS health check**: insecure dynamic updates, aging and scavenging, a live test of each forwarder, DC locator records and recent errors.
- **Stale records**: threshold from the zone's aging settings, a backup before removal, and an option to keep records whose host still answers.
- Environment detection (cloud, hypervisor, cluster, RSAT) and `Install-ADTPrerequisite`, which installs RSAT tools only.
- One HTML report design with summary cards, table filters and dark mode, with every value encoded.
- An audit log of every change, Pester tests with AD/DNS stubs, PSScriptAnalyzer, CI on Windows PowerShell 5.1, PowerShell 7 and Linux, and a release workflow that publishes a ZIP.

### Fixed
- Stale DNS cleanup removed every dynamically registered record, whatever its age.
- DNS zone backup passed a full path to `Export-DnsServerZone`, which only writes inside `%windir%\System32\dns`.
- DNS zone restore used a parameter combination `Add-DnsServerPrimaryZone` rejects.
- AD restore used hard-coded `DC=yourdomain,DC=com` paths, passed `LDAP://` paths where DNs were required, and created users without passwords.
- The bulk-user duplicate check never matched, because of `-Filter` scriptblock scoping.
- The health check's FSMO section was always empty, and replication output lost its line breaks.
- The DNS app could not add or delete records (`$host` is a read-only variable), its theme switch had no effect, its CSV import read the wrong column, and its "Create Trust" button called a cmdlet that doesn't exist.
- Inventory offered to install the AD DS role and Failover Clustering on the machine running it.
- Removed merge-conflict markers from `upload.ps1` and `.vscode/settings.json`, test files, and a truncated license. The license is now MIT throughout.

### Changed
- Reports and backups now go to `Documents\ADDnsToolkit\<task>\<task>_<timestamp>` (configurable).
- The v1 script names are thin wrappers around the new cmdlets.

## 1.0.0 - 2025

- First release: separate AD and DNS scripts, a menu launcher and a WinForms DNS tool.
