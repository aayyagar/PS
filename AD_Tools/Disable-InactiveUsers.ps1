<#
==================================================================================
Title        : Disable Inactive Active Directory Users
Module       : Disable-InactiveUsers.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script finds AD users who have not logged in for 90+ days
    and disables them safely after confirmation.
    Compatible across all Windows Server versions and RSAT installs.

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
    Write-Host "`n❌ Failed to load Active Directory module. Exiting script." -ForegroundColor Red
    exit
}

# Step 2: Prepare Export Path
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$ExportFolder = Join-Path $UserDocuments "AD_DisabledUsers_Logs"
if (!(Test-Path $ExportFolder)) {
    New-Item -Path $ExportFolder -ItemType Directory -Force | Out-Null
}

$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$DisabledReportPath = Join-Path $ExportFolder "DisabledUsers_$TimeStamp.csv"

# Step 3: Find Inactive Users
Write-Host "`n🔍 Searching for Active Directory users inactive for 90+ days..." -ForegroundColor Cyan
$thresholdDate = (Get-Date).AddDays(-90)

$inactiveUsers = Get-ADUser -Filter { Enabled -eq $true } -Properties LastLogonDate |
    Where-Object { $_.LastLogonDate -and $_.LastLogonDate -lt $thresholdDate } |
    Select-Object Name, SamAccountName, LastLogonDate

if (!$inactiveUsers -or $inactiveUsers.Count -eq 0) {
    Write-Host "`n✅ No inactive users found in Active Directory!" -ForegroundColor Green
    exit
}

Write-Host "`n⚠️ Found $($inactiveUsers.Count) inactive user(s)." -ForegroundColor Yellow

# Step 4: Confirm Before Disabling
$confirmDisable = Read-Host "`n❓ Do you want to DISABLE these accounts now? (Yes/No)"

if ($confirmDisable -notmatch '^(Yes|Y)$') {
    Write-Host "`n❌ Operation cancelled. No users were disabled." -ForegroundColor Red
    exit
}

# Step 5: Disable Users
$DisabledUsers = @()

foreach ($user in $inactiveUsers) {
    try {
        Disable-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
        Write-Host "✅ Disabled User: $($user.SamAccountName)" -ForegroundColor Green
        $DisabledUsers += $user
    }
    catch {
        Write-Host "❌ Failed to disable User: $($user.SamAccountName) - $_" -ForegroundColor Red
    }
}

# Step 6: Export Disabled Users Report
if ($DisabledUsers.Count -gt 0) {
    $DisabledUsers | Export-Csv -Path $DisabledReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n✅ Disabled Users Report saved to: $DisabledReportPath" -ForegroundColor Yellow
}
else {
    Write-Host "`n⚠️ No users were successfully disabled. No report generated." -ForegroundColor Yellow
}

# Step 7: Final Completion
Write-Host "`n✅ Script Completed Successfully!" -ForegroundColor Green
