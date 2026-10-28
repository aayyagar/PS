<#
.SYNOPSIS
    Disable inactive Active Directory users (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs Get-ADTInactiveUser and Disable-ADTInactiveUser from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
[CmdletBinding()]
param([int]$Days = 90, [switch]$IncludeNeverLoggedOn, [string[]]$ExcludeGroup = @())
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../ADDnsToolkit/ADDnsToolkit.psd1') -Force
$tk = Get-Module ADDnsToolkit
$prm = @{ Days = $Days; IncludeNeverLoggedOn = [bool]$IncludeNeverLoggedOn; ExcludeGroup = $ExcludeGroup }
& $tk { param($p) Invoke-ADTPreviewThenApply -Command 'Disable-ADTInactiveUser' -Parameters $p -Columns @('SamAccountName', 'Name', 'DaysInactive', 'Action', 'Detail') } $prm
