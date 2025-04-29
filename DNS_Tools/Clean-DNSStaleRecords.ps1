<#
==================================================================================
Title        : Clean Stale DNS Records Script
Module       : Clean-DNSStaleRecords.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script finds and deletes stale DNS records safely after prompting
    for user confirmation and offering to back up DNS zones before proceeding.

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# ==================================================================================
# Step 1: Import Required Module
# Ensure the DNSServer module is available.
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
# Step 2: Confirm Dangerous Operation Warning
# ==================================================================================
Write-Host "`n⚠️ WARNING: You are about to CLEAN stale DNS records." -ForegroundColor Red
Write-Host "⚠️ This action is irreversible and will permanently remove DNS entries!" -ForegroundColor Red

$proceedCleanup = Read-Host "`n❓ Do you wish to proceed with DNS stale record cleaning? (Yes/No)"

if ($proceedCleanup -notmatch '^(Yes|Y)$') {
    Write-Host "`n❌ User aborted cleanup. Exiting script." -ForegroundColor Yellow
    exit
}

# ==================================================================================
# Step 3: Offer DNS Backup Before Cleaning
# ==================================================================================
$backupBeforeCleanup = Read-Host "`n❓ Do you want to BACKUP all DNS zones before cleaning? (Highly recommended) (Yes/No)"

# Set backup path
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$BackupPath = Join-Path $UserDocuments "DNS_Backups"

if ($backupBeforeCleanup -match '^(Yes|Y)$') {
    if (!(Test-Path $BackupPath)) {
        Write-Host "`n📂 Creating DNS backup directory: $BackupPath" -ForegroundColor Yellow
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    }

    $zones = Get-DnsServerZone
    foreach ($zone in $zones) {
        $zoneFile = Join-Path $BackupPath "$($zone.ZoneName)_Backup.dns"
        try {
            Export-DnsServerZone -Name $zone.ZoneName -FileName $zoneFile -ErrorAction Stop
            Write-Host "✅ Backup created for zone: $($zone.ZoneName)" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to backup zone: $($zone.ZoneName) - $_" -ForegroundColor Red
        }
    }
    Write-Host "`n📄 DNS backups saved at: $BackupPath" -ForegroundColor Yellow
}
else {
    Write-Host "`n⚡ Proceeding without backup as per user choice." -ForegroundColor Yellow
}

# ==================================================================================
# Step 4: Confirm Again Before Cleaning
# ==================================================================================
$finalConfirm = Read-Host "`n❓ FINAL CONFIRMATION: Are you absolutely sure you want to clean stale DNS records? (Yes/No)"

if ($finalConfirm -notmatch '^(Yes|Y)$') {
    Write-Host "`n❌ User aborted cleanup after backup. Exiting script." -ForegroundColor Yellow
    exit
}

# ==================================================================================
# Step 5: Clean Stale DNS Records
# ==================================================================================
Write-Host "`n🔎 Searching for stale DNS records..." -ForegroundColor Cyan

$Zones = Get-DnsServerZone
$RecordsRemoved = @()

foreach ($zone in $Zones) {
    $staleRecords = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName | Where-Object {
        $_.Timestamp -ne $null
    }
    foreach ($record in $staleRecords) {
        try {
            Remove-DnsServerResourceRecord -ZoneName $zone.ZoneName -RRType $record.RecordType -Name $record.HostName -Force -Confirm:$false
            $RecordsRemoved += "$($zone.ZoneName) - $($record.HostName)"
            Write-Host "✅ Removed stale record: $($record.HostName) from $($zone.ZoneName)" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to remove record: $($record.HostName) from $($zone.ZoneName) - $_" -ForegroundColor Red
        }
    }
}

# ==================================================================================
# Step 6: Generate Cleanup Report
# ==================================================================================
$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$CleanupReport = Join-Path $UserDocuments "DNS_Cleanup_Report_$TimeStamp.txt"

if ($RecordsRemoved.Count -gt 0) {
    $RecordsRemoved | Out-File -FilePath $CleanupReport -Encoding UTF8
    Write-Host "`n✅ Cleanup Report saved at: $CleanupReport" -ForegroundColor Yellow
}
else {
    Write-Host "`nℹ️ No stale records found to clean." -ForegroundColor Cyan
}

Write-Host "`n✅ DNS Stale Records Cleanup Process Completed!" -ForegroundColor Green
