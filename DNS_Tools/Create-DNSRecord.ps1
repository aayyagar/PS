<#
.SYNOPSIS
    Create DNS records interactively or from a CSV (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Add-ADTDnsRecord / Import-ADTDnsRecord from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$CsvPath, [string]$ComputerName)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
if (-not $CsvPath) {
    $mode = Read-Host 'Create one record interactively or import a CSV? (Interactive/CSV)'
    if ($mode -match '^c') { $CsvPath = Read-Host 'CSV file' }
}
if ($CsvPath) {
    $prm = @{ CsvPath = $CsvPath; ComputerName = $ComputerName }
    & $tk { param($p) Invoke-ADTPreviewThenApply -Command 'Import-ADTDnsRecord' -Parameters $p -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'Action', 'Detail') } $prm
}
else {
    $prm = @{ ComputerName = $ComputerName; ZoneName = (Read-Host 'Zone (example: yourdomain.com)'); Type = (Read-Host 'Type (A, AAAA, CNAME, MX, TXT, PTR)').ToUpper(); Name = (Read-Host 'Name (example: server01)'); Data = (Read-Host 'Data (IP address or target name)') }
    Add-ADTDnsRecord @prm -Confirm:$false | Format-List
}
