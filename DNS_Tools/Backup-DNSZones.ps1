<#
==================================================================================
Title        : Backup All DNS Zones Script
Module       : Backup-DNSZones.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script exports all DNS Zones from the server and saves them 
    into a backup folder with timestamp for easy restoration.

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
# Step 2: Prepare Backup Path
# ==================================================================================
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$BackupRoot = Join-Path $UserDocuments "DNS_Backups"
$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$BackupFolder = Join-Path $BackupRoot "DNSBackup_$TimeStamp"

if (!(Test-Path $BackupFolder)) {
    Write-Host "`n📂 Creating DNS backup folder: $BackupFolder" -ForegroundColor Yellow
    New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
}

# ==================================================================================
# Step 3: Export All DNS Zones
# ==================================================================================
Write-Host "`n🔍 Exporting all DNS Zones..." -ForegroundColor Cyan
$zones = Get-DnsServerZone

foreach ($zone in $zones) {
    $zoneFileName = Join-Path $BackupFolder "$($zone.ZoneName)_Backup.dns"
    try {
        Export-DnsServerZone -Name $zone.ZoneName -FileName $zoneFileName -ErrorAction Stop
        Write-Host "✅ Exported zone: $($zone.ZoneName)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to export zone: $($zone.ZoneName) - $_" -ForegroundColor Red
    }
}

Write-Host "`n✅ All DNS zones exported successfully!" -ForegroundColor Green
Write-Host "📄 Backup files saved at: $BackupFolder" -ForegroundColor Yellow
