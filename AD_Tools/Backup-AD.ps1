<#
==================================================================================
Title        : Backup Active Directory Objects
Module       : Backup-AD.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script exports key Active Directory objects (Users, Groups, OUs)
    to CSV files for backup or audit purposes.

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# Step 1: Import Required Module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "`n✅ Active Directory module loaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Failed to load Active Directory module. Exiting." -ForegroundColor Red
    exit
}

# Step 2: Setup Backup Folder
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$BackupRoot = Join-Path $UserDocuments "AD_Backups"
$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$BackupFolder = Join-Path $BackupRoot "ADBackup_$TimeStamp"

if (!(Test-Path $BackupFolder)) {
    Write-Host "`n📂 Creating backup folder: $BackupFolder" -ForegroundColor Yellow
    New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
}

# Step 3: Export Users
Write-Host "`n🔍 Backing up Users..." -ForegroundColor Cyan
Get-ADUser -Filter * -Properties SamAccountName, Name, Enabled, Department, Title, LastLogonDate |
    Select-Object Name, SamAccountName, Enabled, Department, Title, LastLogonDate |
    Export-Csv -Path (Join-Path $BackupFolder "Users_Backup.csv") -NoTypeInformation -Encoding UTF8

# Step 4: Export Groups
Write-Host "`n🔍 Backing up Groups..." -ForegroundColor Cyan
Get-ADGroup -Filter * -Properties Name, SamAccountName, GroupScope, GroupCategory, Description |
    Select-Object Name, SamAccountName, GroupScope, GroupCategory, Description |
    Export-Csv -Path (Join-Path $BackupFolder "Groups_Backup.csv") -NoTypeInformation -Encoding UTF8

# Step 5: Export Organizational Units (OUs)
Write-Host "`n🔍 Backing up Organizational Units (OUs)..." -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName, whenCreated |
    Export-Csv -Path (Join-Path $BackupFolder "OUs_Backup.csv") -NoTypeInformation -Encoding UTF8

# Final Message
Write-Host "`n✅ Active Directory Backup Completed Successfully!" -ForegroundColor Green
Write-Host "📂 Backup saved at: $BackupFolder" -ForegroundColor Yellow
