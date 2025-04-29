<#
==================================================================================
Title        : Create DNS Records Script
Module       : Create-DNSRecord.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    This script allows you to create DNS records (A, CNAME, PTR) 
    interactively or from a CSV file.

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
# Step 2: Ask for Input Mode
# ==================================================================================
$inputMode = Read-Host "`n❓ How do you want to create DNS records? (Interactive/CSV)"

if ($inputMode -match '^(CSV|csv)$') {
    # ==================================================================================
    # Step 3A: CSV Mode
    # ==================================================================================
    $csvPath = Read-Host "📄 Please enter the full path to your CSV file"

    if (!(Test-Path $csvPath)) {
        Write-Host "`n❌ CSV file not found. Exiting..." -ForegroundColor Red
        exit
    }

    try {
        $records = Import-Csv -Path $csvPath
        Write-Host "`n✅ Successfully imported $($records.Count) records from CSV." -ForegroundColor Green
    }
    catch {
        Write-Host "`n❌ Failed to import CSV. Exiting..." -ForegroundColor Red
        exit
    }

    foreach ($record in $records) {
        try {
            if ($record.RecordType -eq "A") {
                Add-DnsServerResourceRecordA -Name $record.Name -ZoneName $record.ZoneName -IPv4Address $record.IPAddress
            }
            elseif ($record.RecordType -eq "CNAME") {
                Add-DnsServerResourceRecordCName -Name $record.Name -ZoneName $record.ZoneName -HostNameAlias $record.AliasTarget
            }
            elseif ($record.RecordType -eq "PTR") {
                Add-DnsServerResourceRecordPtr -Name $record.Name -ZoneName $record.ZoneName -PtrDomainName $record.PtrTarget
            }
            Write-Host "✅ Created $($record.RecordType) record: $($record.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to create $($record.RecordType) record: $($record.Name) - $_" -ForegroundColor Red
        }
    }
}
elseif ($inputMode -match '^(Interactive|interactive)$') {
    # ==================================================================================
    # Step 3B: Interactive Mode
    # ==================================================================================
    $recordType = Read-Host "`n❓ What type of record do you want to create? (A/CNAME/PTR)"

    switch ($recordType.ToUpper()) {
        "A" {
            $zoneName = Read-Host "Zone Name (example: yourdomain.com)"
            $recordName = Read-Host "Record Name (example: server01)"
            $ipAddress = Read-Host "IPv4 Address (example: 192.168.1.10)"
            try {
                Add-DnsServerResourceRecordA -Name $recordName -ZoneName $zoneName -IPv4Address $ipAddress
                Write-Host "✅ A Record created: $recordName -> $ipAddress" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create A record - $_" -ForegroundColor Red
            }
        }
        "CNAME" {
            $zoneName = Read-Host "Zone Name (example: yourdomain.com)"
            $aliasName = Read-Host "Alias Name (example: web)"
            $aliasTarget = Read-Host "Alias Target FQDN (example: server01.yourdomain.com)"
            try {
                Add-DnsServerResourceRecordCName -Name $aliasName -ZoneName $zoneName -HostNameAlias $aliasTarget
                Write-Host "✅ CNAME Record created: $aliasName -> $aliasTarget" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create CNAME record - $_" -ForegroundColor Red
            }
        }
        "PTR" {
            $zoneName = Read-Host "Reverse Lookup Zone Name (example: 1.168.192.in-addr.arpa)"
            $ptrName = Read-Host "Record Name (last octet of IP, example: 10)"
            $ptrTarget = Read-Host "PTR Target FQDN (example: server01.yourdomain.com)"
            try {
                Add-DnsServerResourceRecordPtr -Name $ptrName -ZoneName $zoneName -PtrDomainName $ptrTarget
                Write-Host "✅ PTR Record created: $ptrName -> $ptrTarget" -ForegroundColor Green
            }
            catch {
                Write-Host "❌ Failed to create PTR record - $_" -ForegroundColor Red
            }
        }
        default {
            Write-Host "❌ Invalid record type selected." -ForegroundColor Red
        }
    }
}
else {
    Write-Host "`n❌ Invalid input mode. Exiting script..." -ForegroundColor Red
}
