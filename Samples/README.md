# Samples

| File | Used by | Notes |
|---|---|---|
| `NewUsers.csv` | `New-ADTBulkUser`, GUI **Bulk users** | Required: `SamAccountName` and `Name` (or `GivenName` + `Surname`). Optional: `Password`, `OU` (or `Path`), `UserPrincipalName`, `EmailAddress`, `Department`, `Title`, `Company`, `Office`, `Description`, `Manager` (sAMAccountName), `Groups` (separated by `;`). Leave `Password` empty and use `-GeneratePassword` rather than storing passwords in a file. Quote OUs, because they contain commas. |
| `DnsRecords.csv` | `Import-ADTDnsRecord`, GUI **DNS records > Import CSV** | Columns `ZoneName`, `Name`, `Type` (A, AAAA, CNAME, MX, TXT, PTR), `Data`, `Preference` (MX), `TTL` (seconds). A CSV exported from `Get-ADTDnsRecord` imports as-is; v1 columns `IPAddress`, `AliasTarget` and `PtrTarget` still work. |

Replace `yourdomain.com` and the OUs with your own before running, and always preview first (`-WhatIf`, or the **Preview** button).
