<#
.SYNOPSIS
    Back up Active Directory users, groups and OUs (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Backup-ADTObject from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$Server, [switch]$IncludeComputers)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
Backup-ADTObject -Server $Server -IncludeComputers:$IncludeComputers | Format-List OutputFolder, OUs, Groups, Users, Computers
