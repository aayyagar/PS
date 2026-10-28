<#
.SYNOPSIS
    DNS server health check (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Test-ADTDnsHealth from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$ComputerName)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
$r = Test-ADTDnsHealth -ComputerName $ComputerName
$r.Checks | Where-Object Status -ne 'Pass' | Format-Table Status, Category, Check, Target, Detail -AutoSize -Wrap | Out-String -Width 200 | Write-Host
if ($r.ReportPath) { Invoke-Item $r.ReportPath }
