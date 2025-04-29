<#
==================================================================================
Title        : Active Directory Health Check Script
Module       : HealthCheck-AD.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script performs a comprehensive Active Directory health check:
    - Domain / Forest Information
    - Domain Controllers Online Status
    - AD Replication Health
    - SYSVOL / NETLOGON Share Availability
    - FSMO Roles Verification
    - Time Synchronization Status
    - Final health report generation (TXT + HTML)

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
# Step 2: Prepare Export Paths
# ==================================================================================
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$HealthCheckPath = Join-Path $UserDocuments "AD_HealthCheck"
if (!(Test-Path $HealthCheckPath)) {
    Write-Host "`n📂 Creating directory for health reports: $HealthCheckPath" -ForegroundColor Yellow
    New-Item -Path $HealthCheckPath -ItemType Directory -Force | Out-Null
}

$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$TxtReportPath = Join-Path $HealthCheckPath "AD_HealthCheck_$TimeStamp.txt"
$HtmlReportPath = Join-Path $HealthCheckPath "AD_HealthCheck_$TimeStamp.html"

# Initialize report content
$HealthSummary = @()
$HtmlBody = ""

# ==================================================================================
# Step 3: Collect Domain and Forest Information
# ==================================================================================
Write-Host "`n🔍 Gathering Domain and Forest information..." -ForegroundColor Cyan
$domain = Get-ADDomain
$forest = Get-ADForest

$HealthSummary += "Domain Name: $($domain.Name)"
$HealthSummary += "Forest Name: $($forest.Name)"
$HealthSummary += "Domain Functional Level: $($domain.DomainMode)"
$HealthSummary += "Forest Functional Level: $($forest.ForestMode)"
$HtmlBody += "<h2>Domain and Forest Info</h2><ul><li>Domain: $($domain.Name)</li><li>Forest: $($forest.Name)</li><li>Domain Mode: $($domain.DomainMode)</li><li>Forest Mode: $($forest.ForestMode)</li></ul>"

# ==================================================================================
# Step 4: Check Domain Controllers Online Status
# ==================================================================================
Write-Host "`n🔍 Checking Domain Controllers..." -ForegroundColor Cyan
$DCs = Get-ADDomainController -Filter *

$HtmlBody += "<h2>Domain Controllers Status</h2><table><tr><th>DC Name</th><th>Status</th></tr>"

foreach ($dc in $DCs) {
    if (Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet) {
        $HealthSummary += "✅ DC Online: $($dc.HostName)"
        $HtmlBody += "<tr><td>$($dc.HostName)</td><td style='color:green;'>Online</td></tr>"
    }
    else {
        $HealthSummary += "❌ DC Offline: $($dc.HostName)"
        $HtmlBody += "<tr><td>$($dc.HostName)</td><td style='color:red;'>Offline</td></tr>"
    }
}

$HtmlBody += "</table>"

# ==================================================================================
# Step 5: AD Replication Health
# ==================================================================================
Write-Host "`n🔍 Checking AD Replication Health..." -ForegroundColor Cyan
$ReplicationSummary = repadmin /replsummary

$HealthSummary += "`nReplication Summary:"
$HealthSummary += $ReplicationSummary
$HtmlBody += "<h2>Replication Summary</h2><pre>$ReplicationSummary</pre>"

# ==================================================================================
# Step 6: Check SYSVOL and NETLOGON shares
# ==================================================================================
Write-Host "`n🔍 Checking SYSVOL and NETLOGON shares on DCs..." -ForegroundColor Cyan
$HtmlBody += "<h2>SYSVOL / NETLOGON Share Check</h2><table><tr><th>DC Name</th><th>SYSVOL</th><th>NETLOGON</th></tr>"

foreach ($dc in $DCs) {
    $sysvol = Test-Path "\\$($dc.HostName)\SYSVOL"
    $netlogon = Test-Path "\\$($dc.HostName)\NETLOGON"
    $sysvolStatus = if ($sysvol) {"✅"} else {"❌"}
    $netlogonStatus = if ($netlogon) {"✅"} else {"❌"}

    $HealthSummary += "$($dc.HostName): SYSVOL = $sysvolStatus, NETLOGON = $netlogonStatus"
    $HtmlBody += "<tr><td>$($dc.HostName)</td><td>$sysvolStatus</td><td>$netlogonStatus</td></tr>"
}

$HtmlBody += "</table>"

# ==================================================================================
# Step 7: FSMO Roles Holders
# ==================================================================================
Write-Host "`n🔍 Checking FSMO Role Holders..." -ForegroundColor Cyan
$FSMORoles = Get-ADDomain | Select-Object -ExpandProperty FSMORoleOwner
$HtmlBody += "<h2>FSMO Role Holders</h2><pre>$FSMORoles</pre>"
$HealthSummary += "`nFSMO Roles Owners:"
$HealthSummary += $FSMORoles

# ==================================================================================
# Step 8: Time Synchronization Check
# ==================================================================================
Write-Host "`n🔍 Checking Time Synchronization..." -ForegroundColor Cyan
try {
    $PDC = ($DCs | Where-Object { $_.OperationMasterRoles -contains "PDCEmulator" }).HostName
    $timeSource = (w32tm /query /status /computer:$PDC) 2>&1
    $HealthSummary += "`nTime Sync Info for PDC ($PDC):"
    $HealthSummary += $timeSource
    $HtmlBody += "<h2>Time Synchronization (PDC)</h2><pre>$timeSource</pre>"
}
catch {
    $HealthSummary += "`n⚠️ Unable to retrieve Time Sync information."
    $HtmlBody += "<h2>Time Synchronization (PDC)</h2><pre>⚠️ Error retrieving time sync info.</pre>"
}

# ==================================================================================
# Step 9: Generate TXT and HTML Report
# ==================================================================================
$HealthSummary | Out-File -FilePath $TxtReportPath -Encoding UTF8

$HtmlFull = @"
<!DOCTYPE html>
<html>
<head>
<title>Active Directory Health Check Report</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background-color: #f9f9f9; }
h1, h2 { color: #2c3e50; }
table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
table, th, td { border: 1px solid #ccc; }
th, td { padding: 8px; text-align: left; }
th { background-color: #2c3e50; color: white; }
footer { text-align: center; font-size: 0.8em; color: #888; margin-top: 40px; }
</style>
</head>
<body>
<h1>Active Directory Health Check Report</h1>
$HtmlBody
<footer><p>Generated by Akhilesh Ayyagari | © 2024</p></footer>
</body>
</html>
"@

$HtmlFull | Out-File -FilePath $HtmlReportPath -Encoding UTF8

Write-Host "`n✅ TXT Report saved to: $TxtReportPath" -ForegroundColor Green
Write-Host "✅ HTML Report saved to: $HtmlReportPath" -ForegroundColor Green

# ==================================================================================
# Step 10: Final Health Summary
# ==================================================================================
Write-Host "`n✅ Active Directory Health Check Completed Successfully!" -ForegroundColor Green
Write-Host "📄 Check the reports in: $HealthCheckPath" -ForegroundColor Yellow
