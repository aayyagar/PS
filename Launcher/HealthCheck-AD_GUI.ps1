<#
.SYNOPSIS
    Active Directory health check (GUI) (v1 script name, kept for compatibility).
.DESCRIPTION
    Since v2 this runs the toolkit GUI on the AD health page from the ADDnsToolkit module. Same job, but safer: everything is
    validated and previewed before anything changes. See README.md for all options, the
    console menu (Start-Toolkit.ps1 -Console) and the GUI (Launch-Toolkit.cmd).
.NOTES
    Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
#>
& (Join-Path $PSScriptRoot '../Start-Toolkit.ps1') -Page ADHealth
