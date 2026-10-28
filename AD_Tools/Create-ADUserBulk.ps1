<#
.SYNOPSIS
    Bulk-create Active Directory users from a CSV (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs New-ADTBulkUser from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$CsvPath, [switch]$GeneratePassword)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
if (-not $CsvPath) {
    $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AD_BulkUserImports\NewUsers.csv'
    $CsvPath = Read-Host "CSV file [$default]"
    if (-not $CsvPath) { $CsvPath = $default }
}
$prm = @{ CsvPath = $CsvPath; GeneratePassword = [bool]$GeneratePassword }
& $tk { param($p) Invoke-ADTPreviewThenApply -Command 'New-ADTBulkUser' -Parameters $p -Columns @('Row', 'SamAccountName', 'Path', 'Action', 'Detail', 'InitialPassword') } $prm
