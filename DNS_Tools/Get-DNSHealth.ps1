<#
==================================================================================
Title        : DNS Server Health Check Script
Module       : Get-DNSHealth.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script performs a complete DNS server health check:
    - Service status
    - Zone status
    - Aging/Scavenging settings
    - Stale records detection
    - DNS configuration validations

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# Step 1: Import Required Module
try {
    Import-Module DNSServer -ErrorAction Stop
    Write-Host "`n✅ DNS Server module loaded successfully." -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Failed to load DNS Server module. Exiting." -ForegroundColor Red
    exit
}

# Step 2: Prepare Export Paths
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$DNSHealthPath = Join-Path $UserDocuments "DNS_HealthCheck"
if (!(Test-Path $DNSHealthPath)) {
    Write-Host "`n📂 Creating DNS Health Check folder: $DNSHealthPath" -ForegroundColor Yellow
    New-Item -Path $DNSHealthPath -ItemType Directory -Force | Out-Null
}

$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$TxtReportPath = Join-Path $DNSHealthPath "DNS_HealthCheck_$TimeStamp.txt"
$HtmlReportPath = Join-Path $DNSHealthPath "DNS_HealthCheck_$TimeStamp.html"

$HealthSummary = @()
$HtmlBody = ""

# Step 3: Check DNS Service Status
Write-Host "`n🔍 Checking DNS Service Status..." -ForegroundColor Cyan
$dnsService = Get-Service -Name "DNS" -ErrorAction SilentlyContinue

if ($dnsService.Status -eq "Running") {
    $HealthSummary += "✅ DNS Service is Running."
    $HtmlBody += "<h2>DNS Service Status: <span style='color:green;'>Running</span></h2>"
} else {
    $HealthSummary += "❌ DNS Service is NOT Running!"
    $HtmlBody += "<h2>DNS Service Status: <span style='color:red;'>Not Running!</span></h2>"
}

# Step 4: Check Zones Health
Write-Host "`n🔍 Checking DNS Zones..." -ForegroundColor Cyan
$zones = Get-DnsServerZone

$HtmlBody += "<h2>DNS Zones</h2><table><tr><th>Zone Name</th><th>Type</th><th>Dynamic Update</th><th>Status</th></tr>"

foreach ($zone in $zones) {
    if ($zone.IsAutoCreated) {
        $dynamicUpdate = "Auto"
    }
    elseif ($zone.IsDsIntegrated) {
        $dynamicUpdate = "Secure"
    }
    else {
        $dynamicUpdate = "Non-Secure"
    }

    $zoneStatus = if ($zone.ZoneType -eq "Primary" -or $zone.ZoneType -eq "ActiveDirectoryIntegrated") {"✅ Healthy"} else {"⚠️ Warning"}

    $HealthSummary += "Zone: $($zone.ZoneName), Type: $($zone.ZoneType), DynamicUpdate: $dynamicUpdate"
    $HtmlBody += "<tr><td>$($zone.ZoneName)</td><td>$($zone.ZoneType)</td><td>$dynamicUpdate</td><td>$zoneStatus</td></tr>"
}

$HtmlBody += "</table>"

# Step 5: Aging and Scavenging Settings
Write-Host "`n🔍 Checking Aging/Scavenging settings..." -ForegroundColor Cyan
$agingZones = $zones | Where-Object { $_.AgingEnabled -eq $true }

if ($agingZones.Count -gt 0) {
    $HealthSummary += "`n✅ Aging/Scavenging is enabled on some zones."
    $HtmlBody += "<h2>Aging/Scavenging</h2><p style='color:green;'>Enabled on some zones.</p>"
} else {
    $HealthSummary += "`n⚠️ Aging/Scavenging is NOT enabled on any zone."
    $HtmlBody += "<h2>Aging/Scavenging</h2><p style='color:red;'>Not Enabled</p>"
}

# Step 6: Check Stale DNS Records
Write-Host "`n🔍 Checking for stale DNS records..." -ForegroundColor Cyan
$staleRecords = @()

foreach ($zone in $zones) {
    $records = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -ErrorAction SilentlyContinue
    $zoneStale = $records | Where-Object { $_.Timestamp -ne $null }

    if ($zoneStale.Count -gt 0) {
        foreach ($stale in $zoneStale) {
            $staleRecords += "$($zone.ZoneName) - $($stale.HostName)"
        }
    }
}

if ($staleRecords.Count -gt 0) {
    $HealthSummary += "`n⚠️ Found $($staleRecords.Count) stale records across zones."
    $HtmlBody += "<h2>Stale DNS Records</h2><p style='color:red;'>$($staleRecords.Count) stale records found.</p>"
} else {
    $HealthSummary += "`n✅ No stale DNS records found."
    $HtmlBody += "<h2>Stale DNS Records</h2><p style='color:green;'>No stale records found.</p>"
}

# Step 7: Generate TXT and HTML Report
$HealthSummary | Out-File -FilePath $TxtReportPath -Encoding UTF8

$HtmlFull = @"
<!DOCTYPE html>
<html>
<head>
<title>DNS Server Health Check Report</title>
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
<h1>DNS Server Health Check Report</h1>
$HtmlBody
<footer><p>Generated by Akhilesh Ayyagari | © 2024</p></footer>
</body>
</html>
"@

$HtmlFull | Out-File -FilePath $HtmlReportPath -Encoding UTF8

Write-Host "`n✅ TXT Report saved to: $TxtReportPath" -ForegroundColor Green
Write-Host "✅ HTML Report saved to: $HtmlReportPath" -ForegroundColor Green

# Step 8: Final Summary
Write-Host "`n✅ DNS Health Check Completed!" -ForegroundColor Green
Write-Host "📄 Check the reports in: $DNSHealthPath" -ForegroundColor Yellow
