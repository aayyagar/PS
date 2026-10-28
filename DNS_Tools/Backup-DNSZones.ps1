<#
.SYNOPSIS
    Back up all DNS zones (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Backup-ADTDnsZone from the ADDnsToolkit module. Same job, but safer: everything is
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
Backup-ADTDnsZone -ComputerName $ComputerName | Format-Table ZoneName, Records, ZoneFile, Status, Detail -AutoSize
