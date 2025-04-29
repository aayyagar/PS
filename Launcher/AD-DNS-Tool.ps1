<#
==================================================================================
Title        : AD & DNS Management Toolkit Launcher
Module       : AD-DNS-Tool.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script provides an interactive menu to launch various Active Directory
    and DNS management scripts (Health Check, Inventory, Bulk User Creation, etc.).
==================================================================================
#>

# ==================================================================================
# Step 1: Define Scripts Locations
# ==================================================================================
$ToolkitRoot = $PSScriptRoot
$ADToolsPath = Join-Path $ToolkitRoot "..\AD_Tools"
$DNSToolsPath = Join-Path $ToolkitRoot "..\DNS_Tools"

# ==================================================================================
# Step 2: Display Menu
# ==================================================================================
function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "        🛡️ AD & DNS Management Toolkit         " -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Active Directory Inventory Report"
    Write-Host "2. Bulk Create Active Directory Users"
    Write-Host "3. Backup Active Directory"
    Write-Host "4. Restore Active Directory"
    Write-Host "5. Disable Inactive AD Users"
    Write-Host "6. Active Directory Health Check (GUI)"
    Write-Host "---------------------------------------------"
    Write-Host "7. Backup DNS Zones"
    Write-Host "8. Restore DNS Zones"
    Write-Host "9. DNS Health Check"
    Write-Host "10. Create New DNS Record"
    Write-Host "11. Clean Stale DNS Records"
    Write-Host "---------------------------------------------"
    Write-Host "0. Exit"
    Write-Host "=============================================" -ForegroundColor Cyan
}

# ==================================================================================
# Step 3: Menu Execution
# ==================================================================================
do {
    Show-Menu
    $choice = Read-Host "`nSelect an option (0-11)"

    switch ($choice) {
        '1' { 
            $script = Join-Path $ADToolsPath "Get-ADInventory.ps1"
        }
        '2' { 
            $script = Join-Path $ADToolsPath "Create-ADUserBulk.ps1"
        }
        '3' { 
            $script = Join-Path $ADToolsPath "Backup-AD.ps1"
        }
        '4' { 
            $script = Join-Path $ADToolsPath "Restore-AD.ps1"
        }
        '5' { 
            $script = Join-Path $ADToolsPath "Disable-InactiveUsers.ps1"
        }
        '6' { 
            $script = Join-Path $ToolkitRoot "HealthCheck-AD_GUI.ps1"
        }
        '7' { 
            $script = Join-Path $DNSToolsPath "Backup-DNSZones.ps1"
        }
        '8' { 
            $script = Join-Path $DNSToolsPath "Restore-DNSZones.ps1"
        }
        '9' { 
            $script = Join-Path $DNSToolsPath "Get-DNSHealth.ps1"
        }
        '10' { 
            $script = Join-Path $DNSToolsPath "Create-DNSRecord.ps1"
        }
        '11' { 
            $script = Join-Path $DNSToolsPath "Clean-DNSStaleRecords.ps1"
        }
        '0' { 
            Write-Host "`n👋 Exiting AD & DNS Toolkit. Goodbye!" -ForegroundColor Green
            break
        }
        default {
            Write-Host "`n⚠️ Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1.5
            continue
        }
    }

    # Launch the selected script if it exists
    if ($choice -ne '0' -and $script) {
        if (Test-Path $script) {
            Write-Host "`n🚀 Launching: $script" -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoExit", "-ExecutionPolicy Bypass", "-File `"$script`""
        }
        else {
            Write-Host "`n❌ Script not found: $script" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
while ($choice -ne '0')
