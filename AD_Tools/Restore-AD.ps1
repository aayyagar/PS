<#
.SYNOPSIS
    Restore Active Directory objects from a backup folder (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Restore-ADTObject from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([string]$Path)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
if (-not $Path) { $Path = Read-Host 'Full path of the backup folder (created by Backup-AD.ps1 or Backup-ADTObject)' }
$prm = @{ Path = $Path }
& $tk { param($p) Invoke-ADTPreviewThenApply -Command 'Restore-ADTObject' -Parameters $p -Columns @('Type', 'Name', 'Action', 'Detail') } $prm
