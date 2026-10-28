<#
.SYNOPSIS
    Restore DNS zones from a backup folder (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Restore-ADTDnsZone from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$Path, [string]$ComputerName)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
if (-not $Path) { $Path = Read-Host 'Full path of the DNS backup folder' }
$prm = @{ Path = $Path; ComputerName = $ComputerName }
& $tk { param($p) Invoke-ADTPreviewThenApply -Command 'Restore-ADTDnsZone' -Parameters $p -Columns @('ZoneName', 'Action', 'Detail') } $prm
