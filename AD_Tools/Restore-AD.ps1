<#
==================================================================================
Title        : Restore Active Directory Objects
Module       : Restore-AD.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script restores Active Directory objects (Users, Groups, OUs)
    from CSV backup files created by Backup-AD.ps1.

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

# Step 2: Ask for Backup Folder Path
$BackupRoot = Read-Host "`n📂 Please enter the FULL path to your AD backup folder (created by Backup-AD.ps1)"

if (!(Test-Path $BackupRoot)) {
    Write-Host "`n❌ Specified folder does not exist. Exiting..." -ForegroundColor Red
    exit
}

# Step 3: Restore Organizational Units (OUs)
$OUFile = Join-Path $BackupRoot "OUs_Backup.csv"
if (Test-Path $OUFile) {
    Write-Host "`n🔍 Restoring OUs..." -ForegroundColor Cyan
    $OUs = Import-Csv -Path $OUFile
    foreach ($ou in $OUs) {
        if (!(Get-ADOrganizationalUnit -Filter {DistinguishedName -eq $ou.DistinguishedName} -ErrorAction SilentlyContinue)) {
            try {
                New-ADOrganizationalUnit -Name $ou.Name -Path (([ADSI]"LDAP://$($ou.DistinguishedName)").Parent) -ErrorAction Stop
                Write-Host "✅ Created OU: $($ou.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create OU: $($ou.Name) - $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "ℹ️ OU already exists: $($ou.Name)" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "`n⚠️ OUs_Backup.csv not found. Skipping OU restoration." -ForegroundColor Yellow
}

# Step 4: Restore Groups
$GroupFile = Join-Path $BackupRoot "Groups_Backup.csv"
if (Test-Path $GroupFile) {
    Write-Host "`n🔍 Restoring Groups..." -ForegroundColor Cyan
    $Groups = Import-Csv -Path $GroupFile
    foreach ($group in $Groups) {
        if (!(Get-ADGroup -Filter {SamAccountName -eq $group.SamAccountName} -ErrorAction SilentlyContinue)) {
            try {
                New-ADGroup -Name $group.Name -SamAccountName $group.SamAccountName -GroupScope $group.GroupScope -GroupCategory $group.GroupCategory -Path "OU=Groups,DC=yourdomain,DC=com" -ErrorAction Stop
                Write-Host "✅ Created Group: $($group.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create Group: $($group.Name) - $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "ℹ️ Group already exists: $($group.Name)" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "`n⚠️ Groups_Backup.csv not found. Skipping Group restoration." -ForegroundColor Yellow
}

# Step 5: Restore Users
$UserFile = Join-Path $BackupRoot "Users_Backup.csv"
if (Test-Path $UserFile) {
    Write-Host "`n🔍 Restoring Users..." -ForegroundColor Cyan
    $Users = Import-Csv -Path $UserFile
    foreach ($user in $Users) {
        if (!(Get-ADUser -Filter {SamAccountName -eq $user.SamAccountName} -ErrorAction SilentlyContinue)) {
            try {
                New-ADUser -Name $user.Name -SamAccountName $user.SamAccountName -Department $user.Department -Title $user.Title -Enabled $user.Enabled -Path "OU=Users,DC=yourdomain,DC=com" -ErrorAction Stop
                Write-Host "✅ Created User: $($user.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create User: $($user.Name) - $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "ℹ️ User already exists: $($user.Name)" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "`n⚠️ Users_Backup.csv not found. Skipping User restoration." -ForegroundColor Yellow
}

# Final Message
Write-Host "`n✅ Active Directory Restore Process Completed!" -ForegroundColor Green
