<#
==================================================================================
Title        : Bulk Active Directory User Creation Script
Module       : Create-ADUserBulk.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script reads a CSV file containing user account information and 
    creates Active Directory users in bulk with appropriate settings.
    Compatible with all versions: Windows Server 2012R2+, Windows 10/11 RSAT.

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# ==================================================================================
# Step 1: Import Required Module
# ==================================================================================
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "`n✅ Active Directory module loaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Failed to load Active Directory module. Exiting." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 2: Prepare Import Folder & CSV Path
# ==================================================================================
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$BulkImportPath = Join-Path $UserDocuments "AD_BulkUserImports"

# Ensure folder exists
if (!(Test-Path $BulkImportPath)) {
    Write-Host "`n📂 Creating directory for bulk user imports: $BulkImportPath" -ForegroundColor Yellow
    New-Item -Path $BulkImportPath -ItemType Directory -Force | Out-Null
}

$DefaultCSV = Join-Path $BulkImportPath "NewUsers.csv"

# Prompt user for CSV path
$useDefault = Read-Host "`n❓ Use default import CSV path ($DefaultCSV)? (Yes/No)"

if ($useDefault -match '^(Yes|Y)$') {
    $CSVPath = $DefaultCSV
}
else {
    $CSVPath = Read-Host "🔍 Please enter the full path to your CSV file"
}

# Validate CSV
if (!(Test-Path $CSVPath)) {
    Write-Host "`n❌ CSV file not found at: $CSVPath" -ForegroundColor Red
    Write-Host "📋 Please ensure the file exists. Exiting script." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 3: Import CSV User Data
# ==================================================================================
try {
    $UserList = Import-Csv -Path $CSVPath
    Write-Host "`n✅ Successfully imported $($UserList.Count) users from CSV." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Failed to import CSV. Exiting." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 4: Get Domain Suffix Automatically
# ==================================================================================
try {
    $domainSuffix = (Get-ADDomain).DNSRoot
    Write-Host "`n🌐 Detected domain: $domainSuffix" -ForegroundColor Cyan
}
catch {
    Write-Host "`n❌ Failed to detect domain suffix. Using 'yourdomain.com' fallback." -ForegroundColor Yellow
    $domainSuffix = "yourdomain.com"
}

# ==================================================================================
# Step 5: Bulk User Creation Process
# ==================================================================================
$SuccessList = @()
$FailureList = @()

foreach ($User in $UserList) {
    try {
        # Check mandatory fields
        if (-not $User.SamAccountName -or -not $User.Password) {
            throw "Missing mandatory field (SamAccountName or Password). Skipping user."
        }

        # Check if user already exists
        $existingUser = Get-ADUser -Filter { SamAccountName -eq $User.SamAccountName } -ErrorAction SilentlyContinue
        if ($existingUser) {
            throw "User already exists: $($User.SamAccountName)"
        }

        # Create new AD User
        $newUserParams = @{
            Name                  = $User.Name
            SamAccountName        = $User.SamAccountName
            UserPrincipalName     = ($User.SamAccountName + "@" + $domainSuffix)
            Path                  = if ($User.OU) { $User.OU } else { "CN=Users,$((Get-ADDomain).DistinguishedName)" }
            Department            = $User.Department
            Title                 = $User.Title
            AccountPassword       = (ConvertTo-SecureString $User.Password -AsPlainText -Force)
            Enabled               = $true
            ChangePasswordAtLogon = $true
        }

        New-ADUser @newUserParams -PassThru | Out-Null

        Write-Host "✅ Created User: $($User.SamAccountName)" -ForegroundColor Green
        $SuccessList += $User.SamAccountName
    }
    catch {
        Write-Host "❌ Failed to create User: $($User.SamAccountName) - $_" -ForegroundColor Red
        $FailureList += "$($User.SamAccountName) : $_"
    }
}

# ==================================================================================
# Step 6: Save Success and Failure Reports
# ==================================================================================
$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$SuccessReport = Join-Path $BulkImportPath "SuccessReport_$TimeStamp.csv"
$FailureReport = Join-Path $BulkImportPath "FailureReport_$TimeStamp.csv"

$SuccessList | Out-File -FilePath $SuccessReport -Encoding UTF8
$FailureList | Out-File -FilePath $FailureReport -Encoding UTF8

# ==================================================================================
# Final Summary
# ==================================================================================
Write-Host "`n✅ Bulk AD User Creation Process Completed!" -ForegroundColor Green
Write-Host "📄 Success Report: $SuccessReport" -ForegroundColor Yellow
Write-Host "📄 Failure Report: $FailureReport" -ForegroundColor Yellow


#Documents\AD_BulkUserImports
#Name | SamAccountName | Password | Department | Title | OU