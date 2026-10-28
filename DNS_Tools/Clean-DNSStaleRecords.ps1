<#
.SYNOPSIS
    Find and remove stale DNS records (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Find-ADTStaleDnsRecord and Remove-ADTStaleDnsRecord (removed records are saved first) from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$ComputerName, [int]$OlderThanDays)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
$prm = @{ ComputerName = $ComputerName; SkipIfResponding = $true }
if ($OlderThanDays) { $prm['OlderThanDays'] = $OlderThanDays }
& $tk { param($p) Invoke-ADTPreviewThenApply -Command 'Remove-ADTStaleDnsRecord' -Parameters $p -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'AgeDays', 'Action', 'Detail') } $prm
