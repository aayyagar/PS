<#
==================================================================================
Title        : Active Directory Inventory Script with Environment Detection
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script collects Active Directory inventory, detects system environment, 
    checks OS architecture, offers optional feature installation (AD DS, Failover 
    Clustering, RSAT), detects cluster status, and generates professional HTML and 
    CSV reports.

License      : This script is the intellectual property of Akhilesh Ayyagari.
               Unauthorized copying, distribution, or modification is prohibited.
==================================================================================
#>

# ==================================================================================
# Step 2: Required Modules Check
# Verify if ActiveDirectory and FailoverClusters modules are available.
# If missing, prompt user to continue or exit.
# ==================================================================================
$RequiredModules = @("ActiveDirectory", "FailoverClusters")
$MissingModules = @()

foreach ($module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        $MissingModules += $module
    }
}

if ($MissingModules.Count -gt 0) {
    Write-Host "`n❌ Missing required modules:" -ForegroundColor Red
    foreach ($m in $MissingModules) {
        Write-Host " - $m" -ForegroundColor Yellow
    }
    $proceedWithoutModules = Read-Host "`n⚡ Some modules are missing. Do you want to proceed anyway? (Yes/No)"
    
    if ($proceedWithoutModules -notmatch '^(Yes|Y)$') {
        Write-Host "`n❌ User chose not to proceed without modules. Exiting." -ForegroundColor Red
        exit
    }
    else {
        Write-Host "`n✅ Proceeding without required modules as per user choice." -ForegroundColor Yellow
    }
}
else {
    Write-Host "`n✅ All required modules are available. Continuing..." -ForegroundColor Green
}

# ==================================================================================
# Step 3: Operating System Architecture Check
# Check if the machine is running 64-bit OS (required for AD DS and clustering).
# ==================================================================================
$osInfo = Get-CimInstance Win32_OperatingSystem
$localOSName = $osInfo.Caption
$localArchitecture = $osInfo.OSArchitecture
$isServer = $localOSName -match "Server"

Write-Host "`n🖥️ Detected Local OS: $localOSName" -ForegroundColor Cyan
Write-Host "🔍 Detected Architecture: $localArchitecture" -ForegroundColor Cyan

if ($localArchitecture -notmatch "64") {
    Write-Host "`n❌ 32-bit OS detected. Active Directory roles require 64-bit. Exiting..." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 4: Check if Features are Already Installed
# Determine whether AD DS, Failover Clustering, or RSAT features are installed.
# ==================================================================================
function Get-FeatureStatus {
    param ([string]$FeatureName)
    try {
        $feature = Get-WindowsFeature -Name $FeatureName
        return $feature.Installed
    }
    catch {
        return $false
    }
}

$featuresAlreadyInstalled = $false

if ($isServer) {
    $adDSInstalled = Get-FeatureStatus -FeatureName "AD-Domain-Services"
    $failoverClusteringInstalled = Get-FeatureStatus -FeatureName "Failover-Clustering"

    if ($adDSInstalled -and $failoverClusteringInstalled) {
        $featuresAlreadyInstalled = $true
    }
}
else {
    $rsatADInstalled = (Get-WindowsCapability -Online | Where-Object { $_.Name -match "RSAT.ActiveDirectory.DS-LDS.Tools" }).State -eq "Installed"
    $rsatClusteringInstalled = (Get-WindowsCapability -Online | Where-Object { $_.Name -match "RSAT.Clustering" }).State -eq "Installed"

    if ($rsatADInstalled -and $rsatClusteringInstalled) {
        $featuresAlreadyInstalled = $true
    }
}

if ($featuresAlreadyInstalled) {
    Write-Host "`n✅ Required features are already installed. Proceeding to next steps..." -ForegroundColor Green
}
else {
    Write-Host "`n⚡ Some required features are not installed." -ForegroundColor Yellow
    $installMissingFeatures = Read-Host "❓ Do you want to install the missing features now? (Yes/No)"

    if ($installMissingFeatures -match '^(Yes|Y)$') {
        if ($isServer) {
            try {
                Import-Module ServerManager -ErrorAction Stop
                Write-Host "Installing Active Directory Domain Services and Failover Clustering..." -ForegroundColor Cyan
                Install-WindowsFeature -Name AD-Domain-Services, Failover-Clustering -IncludeManagementTools
                Write-Host "✅ Features installed successfully." -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Error installing features: $_" -ForegroundColor Red
            }
        }
        else {
            try {
                Write-Host "Installing RSAT Active Directory and Failover Clustering tools..." -ForegroundColor Cyan
                Get-WindowsCapability -Name RSAT.ActiveDirectory.DS-LDS.Tools* -Online | Add-WindowsCapability -Online
                Get-WindowsCapability -Name RSAT.Clustering* -Online | Add-WindowsCapability -Online
                Write-Host "✅ RSAT tools installed successfully!" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ RSAT installation error: $_" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "`n✅ Skipping feature installation and proceeding..." -ForegroundColor Yellow
    }
}

# ==================================================================================
# Step 5: Cloud Provider Detection
# Detect whether system is on Azure, AWS, GCP, or On-Premises based on metadata.
# ==================================================================================
function Get-CloudProvider {
    try {
        $azure = Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" -TimeoutSec 2 -ErrorAction Stop
        if ($azure) { return "Azure" }
    } catch {}
    try {
        $aws = Invoke-RestMethod -Method GET -Uri "http://169.254.169.254/latest/meta-data/" -TimeoutSec 2 -ErrorAction Stop
        if ($aws) { return "AWS" }
    } catch {}
    try {
        $gcp = Invoke-RestMethod -Headers @{"Metadata-Flavor"="Google"} -Method GET -Uri "http://169.254.169.254/computeMetadata/v1/" -TimeoutSec 2 -ErrorAction Stop
        if ($gcp) { return "GCP" }
    } catch {}
    return "On-Premises"
}
$EnvironmentLocation = Get-CloudProvider
Write-Host "`n🌐 Detected Environment: $EnvironmentLocation" -ForegroundColor Green

# ==================================================================================
# Step 6: Platform Detection (Virtual or Physical)
# Detect if system is VMware, Hyper-V, KVM/QEMU, Xen, or Physical Server.
# ==================================================================================
function Get-PlatformType {
    try {
        $model = (Get-WmiObject Win32_ComputerSystem).Model
        $bios = (Get-WmiObject Win32_BIOS).Manufacturer

        if ($model -match "VMware") { return "VMware Virtual Machine" }
        elseif ($model -match "Virtual Machine" -or $bios -match "Microsoft Corporation") { return "Hyper-V Virtual Machine" }
        elseif ($model -match "KVM" -or $model -match "QEMU") { return "KVM/QEMU Virtual Machine" }
        elseif ($model -match "Xen") { return "Xen Virtual Machine" }
        else { return "Physical Server" }
    } catch {
        return "Unknown"
    }
}

$PlatformType = Get-PlatformType
Write-Host "`n🖥️ Detected Platform: $PlatformType" -ForegroundColor Green

# ==================================================================================
# Step 7: Cluster Detection
# Check if system is part of a Failover Cluster and its health status.
# ==================================================================================
function Get-ClusterStatus {
    try {
        Import-Module FailoverClusters -ErrorAction Stop
        $cluster = Get-Cluster -ErrorAction Stop
        $nodes = Get-ClusterNode
        $groups = Get-ClusterGroup
        $NodeIssues = $nodes | Where-Object {$_.State -ne "Up"}
        $GroupIssues = $groups | Where-Object {$_.State -ne "Online"}

        $ClusterHealth = if ($NodeIssues.Count -eq 0 -and $GroupIssues.Count -eq 0) { "Healthy" } else { "Warning" }

        return @{
            ClusterName = $cluster.Name
            NodeName = $env:COMPUTERNAME
            ClusterStatus = "Clustered Node"
            ClusterHealth = $ClusterHealth
        }
    }
    catch {
        return @{
            ClusterName = "N/A"
            NodeName = $env:COMPUTERNAME
            ClusterStatus = "Standalone Server"
            ClusterHealth = "N/A"
        }
    }
}

$ClusterInfo = Get-ClusterStatus
Write-Host "`n🛡️ Cluster Status: $($ClusterInfo.ClusterStatus) | Health: $($ClusterInfo.ClusterHealth)" -ForegroundColor Green

# ==================================================================================
# Step 8: Prompt to Proceed to AD Inventory Collection
# ==================================================================================
$ProceedInventory = Read-Host "`n❓ Shall we proceed to collect Active Directory Inventory? (Yes/No)"
if ($ProceedInventory -notmatch '^(Yes|Y)$') {
    Write-Host "`n❌ User chose not to proceed. Exiting." -ForegroundColor Red
    exit
}

Write-Host "`n🔎 Collecting Active Directory Inventory..." -ForegroundColor Cyan

# ==================================================================================
# Step 9: Active Directory Inventory Collection
# ==================================================================================
Import-Module ActiveDirectory

# Create Export Path
$UserDocuments = [Environment]::GetFolderPath('MyDocuments')
$ExportPath = Join-Path $UserDocuments "AD_Report"
if (!(Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

# Collect Users
$Users = Get-ADUser -Filter * -Properties SamAccountName, EmailAddress, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, AccountExpirationDate, Title, Department, Manager |
Select-Object Name, SamAccountName, EmailAddress, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, AccountExpirationDate, Title, Department, Manager

# Collect Computers
$Computers = Get-ADComputer -Filter * -Properties OperatingSystem, OperatingSystemVersion, LastLogonDate, Enabled |
Select-Object Name, OperatingSystem, OperatingSystemVersion, Enabled, LastLogonDate, DistinguishedName

# Collect Groups
$Groups = Get-ADGroup -Filter * -Properties GroupScope, GroupCategory, Description, ManagedBy |
Select-Object Name, GroupScope, GroupCategory, Description, ManagedBy

# Collect OUs
$OUs = Get-ADOrganizationalUnit -Filter * |
Select-Object Name, DistinguishedName, whenCreated

# Collect Domain Controllers
$DCs = Get-ADDomainController -Filter * |
Select-Object Name, IPv4Address, OperatingSystem, OperatingSystemVersion, Site, IsGlobalCatalog

# Collect Trusts
try {
    $Trusts = Get-ADTrust -Filter * |
    Select-Object Name, TrustType, TrustDirection, TrustAttributes
}
catch {
    $Trusts = @()
}

Write-Host "`n✅ Active Directory Inventory Collection Completed." -ForegroundColor Green

# ==================================================================================
# Step 10: Prompt to Proceed to Report Generation
# ==================================================================================
$ProceedReport = Read-Host "`n❓ Shall we proceed to generate the HTML Report and CSV Files? (Yes/No)"
if ($ProceedReport -notmatch '^(Yes|Y)$') {
    Write-Host "`n❌ User chose not to proceed. Exiting." -ForegroundColor Red
    exit
}

# ==================================================================================
# Step 11: HTML and CSV Report Generation
# ==================================================================================
$HTMLReport = Join-Path $ExportPath "AD_Inventory_Report.html"

function Convert-TableToHtml {
    param ([string]$Title, [array]$Data)
    if ($Data.Count -eq 0) { return "<h2>$Title</h2><p>No data found.</p>" }
    $html = "<h2>$Title</h2><table><thead><tr>"
    foreach ($col in $Data[0].PSObject.Properties.Name) { $html += "<th>$col</th>" }
    $html += "</tr></thead><tbody>"
    foreach ($row in $Data) {
        $html += "<tr>"
        foreach ($col in $row.PSObject.Properties.Name) {
            $html += "<td>$($row.$col)</td>"
        }
        $html += "</tr>"
    }
    $html += "</tbody></table>"
    return $html
}

$HtmlHeader = @"
<!DOCTYPE html>
<html>
<head>
<title>Active Directory Inventory Report</title>
<meta charset="utf-8">
<style>
body { font-family: Arial, sans-serif; margin: 20px; background-color: #f9f9f9; }
h1, h2 { color: #2c3e50; }
table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
table, th, td { border: 1px solid #ccc; }
th, td { padding: 8px; text-align: left; }
th { background-color: #2c3e50; color: white; }
.summary { background-color: #ecf0f1; padding: 15px; margin-bottom: 20px; border-radius: 8px; }
footer { text-align: center; font-size: 0.8em; color: #888; margin-top: 40px; }
</style>
</head>
<body>
<h1>Active Directory Inventory Report</h1>
"@

$HtmlFooter = "</body></html>"

$FullHtmlReport = $HtmlHeader
$FullHtmlReport += "<div class='summary'><b>Environment:</b> $EnvironmentLocation<br><b>Platform:</b> $PlatformType<br><b>Cluster:</b> $($ClusterInfo.ClusterStatus) - Health: $($ClusterInfo.ClusterHealth)</div>"
$FullHtmlReport += Convert-TableToHtml -Title "Users" -Data $Users
$FullHtmlReport += Convert-TableToHtml -Title "Computers" -Data $Computers
$FullHtmlReport += Convert-TableToHtml -Title "Groups" -Data $Groups
$FullHtmlReport += Convert-TableToHtml -Title "Organizational Units" -Data $OUs
$FullHtmlReport += Convert-TableToHtml -Title "Domain Controllers" -Data $DCs
$FullHtmlReport += Convert-TableToHtml -Title "Trusts" -Data $Trusts
$FullHtmlReport += $HtmlFooter

# Save HTML
$FullHtmlReport | Out-File -FilePath $HTMLReport -Encoding UTF8

# Save CSVs
$Users | Export-Csv -Path (Join-Path $ExportPath "AD_Users.csv") -NoTypeInformation
$Computers | Export-Csv -Path (Join-Path $ExportPath "AD_Computers.csv") -NoTypeInformation
$Groups | Export-Csv -Path (Join-Path $ExportPath "AD_Groups.csv") -NoTypeInformation
$OUs | Export-Csv -Path (Join-Path $ExportPath "AD_OUs.csv") -NoTypeInformation
$DCs | Export-Csv -Path (Join-Path $ExportPath "AD_DomainControllers.csv") -NoTypeInformation
if ($Trusts.Count -gt 0) {
    $Trusts | Export-Csv -Path (Join-Path $ExportPath "AD_Trusts.csv") -NoTypeInformation
}

Write-Host "`n✅ HTML and CSV Reports exported successfully!" -ForegroundColor Green
Write-Host "📄 Reports saved in: $ExportPath" -ForegroundColor Yellow
