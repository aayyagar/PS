<#
==================================================================================
Title        : Restore DNS Zones from Backup
Module       : Restore-DNSZones.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script restores DNS zones from previously created backup files (.dns).

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# ==================================================================================
# Step 1: Import Required Module
# ==================================================================================
try {
    Import-Module DNSServer -ErrorAction Stop
    Write-Host "`n✅ DNS Server module loaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Failed to load DNS Server module. Exiting." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 2: Ask for Backup Folder Path
# ==================================================================================
$BackupFolder = Read-Host "`n📂 Please enter the FULL path to your DNS backup folder (where .dns files are located)"

if (!(Test-Path $BackupFolder)) {
    Write-Host "`n❌ Specified folder does not exist. Exiting..." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 3: List and Import Backup Files
# ==================================================================================
$BackupFiles = Get-ChildItem -Path $BackupFolder -Filter "*.dns"

if ($BackupFiles.Count -eq 0) {
    Write-Host "`n❌ No DNS backup files (.dns) found in the folder. Exiting..." -ForegroundColor Red
    exit
}

Write-Host "`n🔍 Found $($BackupFiles.Count) DNS backup files. Starting restore..." -ForegroundColor Cyan

foreach ($file in $BackupFiles) {
    $zoneName = $file.BaseName -replace '_Backup$', ''
    try {
        if (Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue) {
            Write-Host "ℹ️ Zone already exists: $zoneName - Skipping restore." -ForegroundColor Yellow
        }
        else {
            Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile $file.Name -DirectoryPartition "DomainDnsZones" -PassThru
            Write-Host "✅ Restored zone: $zoneName" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Failed to restore zone: $zoneName - $_" -ForegroundColor Red
    }
}

Write-Host "`n✅ DNS Zones Restoration Completed!" -ForegroundColor Green
