<#
.SYNOPSIS
    Starts the AD & DNS Toolkit: the graphical interface on a Windows desktop, otherwise the console menu.
.DESCRIPTION
    Double-click Launch-Toolkit.cmd, or run this script from PowerShell 5.1 or 7.
    For scripting, import the module instead: Import-Module .\ADDnsToolkit\ADDnsToolkit.psd1
.PARAMETER Console
    Use the text menu even when a desktop is available (handy over SSH or on Server Core).
.PARAMETER Page
    The GUI page to open on.
.EXAMPLE
    .\Start-Toolkit.ps1
.EXAMPLE
    .\Start-Toolkit.ps1 -Console
.EXAMPLE
    .\Start-Toolkit.ps1 -Page DnsRecords
.NOTES
    AD & DNS Toolkit v2.0.0 - Copyright (c) 2024-2026 Akhilesh Ayyagari - MIT License
    https://github.com/aayyagar/PS
#>
[CmdletBinding()]
param(
    [switch]$Console,
    [ValidateSet('Home', 'ADHealth', 'ADInventory', 'ADBackup', 'BulkUsers', 'Inactive', 'Trusts', 'DnsHealth', 'DnsRecords', 'DnsBackup', 'StaleDns', 'Forwarders', 'Diagnostics', 'Log')]
    [string]$Page = 'Home'
)
$ErrorActionPreference = 'Stop'
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows)

# Files from a downloaded ZIP carry the "downloaded from the internet" mark, which blocks them
# under the RemoteSigned policy. Clear it once for the toolkit's own files.
if ($onWindows) {
    Get-ChildItem -Path $PSScriptRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
}

Import-Module (Join-Path $PSScriptRoot 'ADDnsToolkit/ADDnsToolkit.psd1') -Force

$useGui = (-not $Console) -and (Test-ADTGuiAvailable)
if ($useGui -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    # Windows Forms needs STA: start a fresh PowerShell that has it.
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -ExecutionPolicy Bypass -STA -File $PSCommandPath -Page $Page
    return
}
if ($useGui) { Show-ADTGui -Page $Page } else { Show-ADTMenu }
