# Copyright (c) 2025 Akhilesh Ayyagari. All rights reserved.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==== Auto-Detect All DNS Servers ====
$allDnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Count -gt 0 } | ForEach-Object { $_.ServerAddresses }) -join ','
$allDnsServers = $allDnsServers -split ',' | Sort-Object -Unique
if (-not $allDnsServers -or $allDnsServers.Count -eq 0) { $allDnsServers = @("localhost") }

function Get-PrimaryZones($dnsServer) {
    try {
        Import-Module DnsServer -ErrorAction Stop
        $zones = Get-DnsServerZone -ComputerName $dnsServer | Where-Object { $_.ZoneType -eq 'Primary' }
        if ($zones) { return $zones.ZoneName }
        else { return @("Unavailable") }
    } catch { return @("Unavailable") }
}

# Detect domain for AD Trusts
try { $currentDomain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name }
catch { $currentDomain = "" }

# ==== Logging ====
$logPath = "C:\temp\DNSManagementLog.txt"
if (!(Test-Path (Split-Path $logPath))) { New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null }
function Log-Action([string]$msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $msg"
}

# ==== Theme Colors ====
$useDark = $false
$lightBack = [System.Drawing.Color]::White
$darkBack = [System.Drawing.Color]::FromArgb(30,30,30)
$lightFore = [System.Drawing.Color]::Black
$darkFore = [System.Drawing.Color]::White

function Set-Theme {
    param($ctrl)
    if ($useDark) {
        $ctrl.BackColor = $darkBack
        $ctrl.ForeColor = $darkFore
    } else {
        $ctrl.BackColor = $lightBack
        $ctrl.ForeColor = $lightFore
    }
    foreach ($c in $ctrl.Controls) { Set-Theme $c }
}

# ==== Form + Tabs ====
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Advanced DNS Management Tool - By AA'
$form.Size = New-Object System.Drawing.Size(1050, 700)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'

# =============== 1. DNS Record Viewer/Search/Export ===============
$viewTab = New-Object System.Windows.Forms.TabPage
$viewTab.Text = "DNS Record Viewer"
$viewY = 25

$lblViewDnsServer = New-Object System.Windows.Forms.Label
$lblViewDnsServer.Location = New-Object System.Drawing.Point(20, $viewY)
$lblViewDnsServer.Size = New-Object System.Drawing.Size(120, 25)
$lblViewDnsServer.Text = "DNS Server:"
$viewTab.Controls.Add($lblViewDnsServer)
$cbViewDnsServer = New-Object System.Windows.Forms.ComboBox
$cbViewDnsServer.Location = New-Object System.Drawing.Point(140, $viewY)
$cbViewDnsServer.Size = New-Object System.Drawing.Size(220, 25)
$cbViewDnsServer.Items.AddRange($allDnsServers)
$cbViewDnsServer.SelectedIndex = 0
$viewTab.Controls.Add($cbViewDnsServer)
$viewY += 35

$lblViewZone = New-Object System.Windows.Forms.Label
$lblViewZone.Location = New-Object System.Drawing.Point(20, $viewY)
$lblViewZone.Size = New-Object System.Drawing.Size(120, 25)
$lblViewZone.Text = "DNS Zone:"
$viewTab.Controls.Add($lblViewZone)
$cbViewZone = New-Object System.Windows.Forms.ComboBox
$cbViewZone.Location = New-Object System.Drawing.Point(140, $viewY)
$cbViewZone.Size = New-Object System.Drawing.Size(220, 25)
$cbViewZone.Items.AddRange($(Get-PrimaryZones $cbViewDnsServer.Text))
$cbViewZone.SelectedIndex = 0
$viewTab.Controls.Add($cbViewZone)
$btnViewRefresh = New-Object System.Windows.Forms.Button
$btnViewRefresh.Location = New-Object System.Drawing.Point(380, $viewY)
$btnViewRefresh.Size = New-Object System.Drawing.Size(120, 28)
$btnViewRefresh.Text = "Refresh Zones"
$btnViewRefresh.Add_Click({
    $cbViewZone.Items.Clear()
    $cbViewZone.Items.AddRange($(Get-PrimaryZones $cbViewDnsServer.Text))
    if ($cbViewZone.Items.Count -gt 0) { $cbViewZone.SelectedIndex = 0 }
})
$viewTab.Controls.Add($btnViewRefresh)
$viewY += 35

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Location = New-Object System.Drawing.Point(20, $viewY)
$lblSearch.Size = New-Object System.Drawing.Size(120, 25)
$lblSearch.Text = "Filter:"
$viewTab.Controls.Add($lblSearch)
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(140, $viewY)
$txtSearch.Size = New-Object System.Drawing.Size(220, 25)
$viewTab.Controls.Add($txtSearch)
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(380, $viewY)
$btnExport.Size = New-Object System.Drawing.Size(120, 28)
$btnExport.Text = "Export CSV"
$viewTab.Controls.Add($btnExport)
$viewY += 35

$gridRecords = New-Object System.Windows.Forms.DataGridView
$gridRecords.Location = New-Object System.Drawing.Point(20, $viewY)
$gridRecords.Size = New-Object System.Drawing.Size(950, 350)
$gridRecords.ReadOnly = $true
$gridRecords.AllowUserToAddRows = $false
$gridRecords.AllowUserToDeleteRows = $false
$gridRecords.SelectionMode = 'FullRowSelect'
$viewTab.Controls.Add($gridRecords)

function Show-Records {
    param($server, $zone, $filter="")
    $data = @()
    if ($zone -and $zone -ne "Unavailable") {
        try {
            $data += Get-DnsServerResourceRecord -ZoneName $zone -ComputerName $server | Select-Object HostName,RecordType,RecordClass,RecordData
            if ($filter -ne "") {
                $data = $data | Where-Object { $_.HostName -like "*$filter*" -or $_.RecordType -like "*$filter*" }
            }
        } catch { $data = @() }
    }
    $gridRecords.DataSource = $null
    $gridRecords.DataSource = $data
}
$btnViewRefresh.Add_Click({ $cbViewZone.Items.Clear(); $cbViewZone.Items.AddRange($(Get-PrimaryZones $cbViewDnsServer.Text)); if ($cbViewZone.Items.Count -gt 0) { $cbViewZone.SelectedIndex = 0 } })
$cbViewDnsServer.Add_SelectedIndexChanged({ $cbViewZone.Items.Clear(); $cbViewZone.Items.AddRange($(Get-PrimaryZones $cbViewDnsServer.Text)); if ($cbViewZone.Items.Count -gt 0) { $cbViewZone.SelectedIndex = 0 } })
$btnExport.Add_Click({
    $csvPath = New-Object System.Windows.Forms.SaveFileDialog
    $csvPath.Filter = "CSV files (*.csv)|*.csv"
    $csvPath.Title = "Export DNS Records to CSV"
    if ($csvPath.ShowDialog() -eq "OK") {
        $gridRecords.DataSource | Export-Csv $csvPath.FileName -NoTypeInformation
        [System.Windows.Forms.MessageBox]::Show("Exported to $($csvPath.FileName)")
        Log-Action ("Exported records for zone " + $cbViewZone.Text + " to " + $csvPath.FileName)
    }
})
$cbViewZone.Add_SelectedIndexChanged({ Show-Records $cbViewDnsServer.Text $cbViewZone.Text $txtSearch.Text })
$txtSearch.Add_TextChanged({ Show-Records $cbViewDnsServer.Text $cbViewZone.Text $txtSearch.Text })

# =============== 2. DNS Records CRUD ===============
$dnsTab = New-Object System.Windows.Forms.TabPage
$dnsTab.Text = "DNS Records"
$dnsY = 25

# DNS Server ComboBox
$lblDnsServer = New-Object System.Windows.Forms.Label
$lblDnsServer.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblDnsServer.Size = New-Object System.Drawing.Size(140, 25)
$lblDnsServer.Text = "DNS Server:"
$dnsTab.Controls.Add($lblDnsServer)
$cbDnsServer = New-Object System.Windows.Forms.ComboBox
$cbDnsServer.Location = New-Object System.Drawing.Point(200, $dnsY)
$cbDnsServer.Size = New-Object System.Drawing.Size(350, 25)
$cbDnsServer.Items.AddRange($allDnsServers)
$cbDnsServer.SelectedIndex = 0
$dnsTab.Controls.Add($cbDnsServer)
$dnsY += 40

# DNS Zone ComboBox (dynamic)
$lblZone = New-Object System.Windows.Forms.Label
$lblZone.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblZone.Size = New-Object System.Drawing.Size(140, 25)
$lblZone.Text = "DNS Zone:"
$dnsTab.Controls.Add($lblZone)
$cbZone = New-Object System.Windows.Forms.ComboBox
$cbZone.Location = New-Object System.Drawing.Point(200, $dnsY)
$cbZone.Size = New-Object System.Drawing.Size(350, 25)
$cbZone.Items.AddRange($(Get-PrimaryZones $cbDnsServer.Text))
$cbZone.SelectedIndex = 0
$dnsTab.Controls.Add($cbZone)
$dnsY += 40
$cbDnsServer.Add_SelectedIndexChanged({
    $cbZone.Items.Clear()
    $cbZone.Items.AddRange($(Get-PrimaryZones $cbDnsServer.Text))
    if ($cbZone.Items.Count -gt 0) { $cbZone.SelectedIndex = 0 }
})

$lblType = New-Object System.Windows.Forms.Label
$lblType.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblType.Size = New-Object System.Drawing.Size(140, 25)
$lblType.Text = "Record Type:"
$dnsTab.Controls.Add($lblType)
$cbType = New-Object System.Windows.Forms.ComboBox
$cbType.Location = New-Object System.Drawing.Point(200, $dnsY)
$cbType.Size = New-Object System.Drawing.Size(350, 25)
$cbType.Items.AddRange(@("A-Record","CNAME","MX","TXT"))
$cbType.SelectedIndex = 0
$dnsTab.Controls.Add($cbType)
$dnsY += 40
$lblHost = New-Object System.Windows.Forms.Label
$lblHost.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblHost.Size = New-Object System.Drawing.Size(140, 25)
$lblHost.Text = "Hostname:"
$dnsTab.Controls.Add($lblHost)
$txtHost = New-Object System.Windows.Forms.TextBox
$txtHost.Location = New-Object System.Drawing.Point(200, $dnsY)
$txtHost.Size = New-Object System.Drawing.Size(350, 25)
$dnsTab.Controls.Add($txtHost)
$dnsY += 40
$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblTarget.Size = New-Object System.Drawing.Size(140, 25)
$lblTarget.Text = "Target (IP/FQDN):"
$dnsTab.Controls.Add($lblTarget)
$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Location = New-Object System.Drawing.Point(200, $dnsY)
$txtTarget.Size = New-Object System.Drawing.Size(350, 25)
$dnsTab.Controls.Add($txtTarget)
$dnsY += 40
$lblPref = New-Object System.Windows.Forms.Label
$lblPref.Location = New-Object System.Drawing.Point(30, $dnsY)
$lblPref.Size = New-Object System.Drawing.Size(140, 25)
$lblPref.Text = "MX Preference:"
$dnsTab.Controls.Add($lblPref)
$txtPref = New-Object System.Windows.Forms.TextBox
$txtPref.Location = New-Object System.Drawing.Point(200, $dnsY)
$txtPref.Size = New-Object System.Drawing.Size(350, 25)
$txtPref.Text = "10"
$dnsTab.Controls.Add($txtPref)
$dnsY += 45

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Location = New-Object System.Drawing.Point(200, $dnsY)
$btnAdd.Size = New-Object System.Drawing.Size(140, 32)
$btnAdd.Text = "Add Record"
$btnAdd.Add_Click({
    if ($cbZone.Text -ne "Unavailable") {
        $type = $cbType.Text; $host = $txtHost.Text; $target = $txtTarget.Text; $pref = [int]$txtPref.Text; $zone = $cbZone.Text; $server = $cbDnsServer.Text
        try {
            switch ($type) {
                "A-Record" { Add-DnsServerResourceRecordA -Name $host -IPv4Address $target -ZoneName $zone -ComputerName $server }
                "CNAME" { Add-DnsServerResourceRecordCName -Name $host -HostNameAlias $target -ZoneName $zone -ComputerName $server }
                "MX" { Add-DnsServerResourceRecordMX -Name $host -MailExchange $target -Preference $pref -ZoneName $zone -ComputerName $server }
                "TXT" { Add-DnsServerResourceRecord -ZoneName $zone -Name $host -Txt $target -ComputerName $server }
            }
            [System.Windows.Forms.MessageBox]::Show("$type record added for $host in $zone ($server)")
            Log-Action ("Added $type for $host in $zone ($server) [$target]")
        } catch {
            $err = $_
            [System.Windows.Forms.MessageBox]::Show("Error: $err")
            Log-Action ("Error adding $type for $host in $zone ($server): $err")
        }
    } else { [System.Windows.Forms.MessageBox]::Show("DNS module missing or no valid DNS zone") }
})
$dnsTab.Controls.Add($btnAdd)

$btnDel = New-Object System.Windows.Forms.Button
$btnDel.Location = New-Object System.Drawing.Point(360, $dnsY)
$btnDel.Size = New-Object System.Drawing.Size(140, 32)
$btnDel.Text = "Delete Record"
$btnDel.Add_Click({
    if ($cbZone.Text -ne "Unavailable") {
        $type = $cbType.Text; $host = $txtHost.Text; $zone = $cbZone.Text; $server = $cbDnsServer.Text
        try {
            $rrType = switch ($type) { "A-Record" { "A" }; "CNAME" { "CNAME" }; "MX" { "MX" }; "TXT" { "TXT" } }
            Remove-DnsServerResourceRecord -ZoneName $zone -RRType $rrType -Name $host -ComputerName $server -Force
            [System.Windows.Forms.MessageBox]::Show("$type record deleted for $host in $zone ($server)")
            Log-Action ("Deleted $type for $host in $zone ($server)")
        } catch {
            $err = $_
            [System.Windows.Forms.MessageBox]::Show("Error: $err")
            Log-Action ("Error deleting $type for $host in $zone ($server): $err")
        }
    } else { [System.Windows.Forms.MessageBox]::Show("DNS module missing or no valid DNS zone") }
})
$dnsTab.Controls.Add($btnDel)

# =============== 3. Bulk Import/Export ===============
$bulkTab = New-Object System.Windows.Forms.TabPage
$bulkTab.Text = "Bulk Import/Export"
$bulkY = 25
$lblBulkZone = New-Object System.Windows.Forms.Label
$lblBulkZone.Location = New-Object System.Drawing.Point(30,$bulkY)
$lblBulkZone.Size = New-Object System.Drawing.Size(120,25)
$lblBulkZone.Text = "DNS Zone:"
$bulkTab.Controls.Add($lblBulkZone)
$cbBulkServer = New-Object System.Windows.Forms.ComboBox
$cbBulkServer.Location = New-Object System.Drawing.Point(180,$bulkY)
$cbBulkServer.Size = New-Object System.Drawing.Size(180,25)
$cbBulkServer.Items.AddRange($allDnsServers)
$cbBulkServer.SelectedIndex = 0
$bulkTab.Controls.Add($cbBulkServer)
$cbBulkZone = New-Object System.Windows.Forms.ComboBox
$cbBulkZone.Location = New-Object System.Drawing.Point(370,$bulkY)
$cbBulkZone.Size = New-Object System.Drawing.Size(180,25)
$cbBulkZone.Items.AddRange($(Get-PrimaryZones $cbBulkServer.Text))
$cbBulkZone.SelectedIndex = 0
$bulkTab.Controls.Add($cbBulkZone)
$cbBulkServer.Add_SelectedIndexChanged({
    $cbBulkZone.Items.Clear()
    $cbBulkZone.Items.AddRange($(Get-PrimaryZones $cbBulkServer.Text))
    if ($cbBulkZone.Items.Count -gt 0) { $cbBulkZone.SelectedIndex = 0 }
})
$bulkY += 40
$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Location = New-Object System.Drawing.Point(180, $bulkY)
$btnImport.Size = New-Object System.Drawing.Size(160,32)
$btnImport.Text = "Import Records (CSV)"
$btnImport.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "CSV files (*.csv)|*.csv"
    if ($dlg.ShowDialog() -eq "OK") {
        $records = Import-Csv $dlg.FileName
        foreach ($r in $records) {
            # Basic add (expand logic as needed)
            try { 
                Add-DnsServerResourceRecordA -Name $r.HostName -IPv4Address $r.RecordData.IPv4Address -ZoneName $cbBulkZone.Text -ComputerName $cbBulkServer.Text
            } catch {}
            Log-Action ("Bulk Import: " + $r.HostName + " to " + $cbBulkZone.Text)
        }
        [System.Windows.Forms.MessageBox]::Show("Imported records from " + $dlg.FileName)
    }
})
$bulkTab.Controls.Add($btnImport)
$btnExport2 = New-Object System.Windows.Forms.Button
$btnExport2.Location = New-Object System.Drawing.Point(350, $bulkY)
$btnExport2.Size = New-Object System.Drawing.Size(160,32)
$btnExport2.Text = "Export All Records"
$btnExport2.Add_Click({
    $csvPath = New-Object System.Windows.Forms.SaveFileDialog
    $csvPath.Filter = "CSV files (*.csv)|*.csv"
    if ($csvPath.ShowDialog() -eq "OK") {
        Get-DnsServerResourceRecord -ZoneName $cbBulkZone.Text -ComputerName $cbBulkServer.Text | Export-Csv $csvPath.FileName -NoTypeInformation
        [System.Windows.Forms.MessageBox]::Show("Exported all records to " + $csvPath.FileName)
        Log-Action ("Bulk Export: " + $cbBulkZone.Text + " to " + $csvPath.FileName)
    }
})
$bulkTab.Controls.Add($btnExport2)

# =============== 4. Change Log/Audit Trail ===============
$auditTab = New-Object System.Windows.Forms.TabPage
$auditTab.Text = "Change Log"
$auditY = 25
$auditBox = New-Object System.Windows.Forms.TextBox
$auditBox.Multiline = $true
$auditBox.ScrollBars = 'Vertical'
$auditBox.ReadOnly = $true
$auditBox.Location = New-Object System.Drawing.Point(20,$auditY)
$auditBox.Size = New-Object System.Drawing.Size(950,500)
$auditTab.Controls.Add($auditBox)
function Refresh-Log { if (Test-Path $logPath) { $auditBox.Text = Get-Content $logPath -Raw } else { $auditBox.Text = "No log file yet." } }
$auditTab.Add_Enter({Refresh-Log})

# =============== 5. Conditional Forwarding ===============
$cfTab = New-Object System.Windows.Forms.TabPage
$cfTab.Text = "Conditional Forwarding"
$cfY = 25
$lblCFServer = New-Object System.Windows.Forms.Label
$lblCFServer.Location = New-Object System.Drawing.Point(30, $cfY)
$lblCFServer.Size = New-Object System.Drawing.Size(140, 25)
$lblCFServer.Text = "DNS Server:"
$cfTab.Controls.Add($lblCFServer)
$cbCFServer = New-Object System.Windows.Forms.ComboBox
$cbCFServer.Location = New-Object System.Drawing.Point(200, $cfY)
$cbCFServer.Size = New-Object System.Drawing.Size(350, 25)
$cbCFServer.Items.AddRange($allDnsServers)
$cbCFServer.SelectedIndex = 0
$cfTab.Controls.Add($cbCFServer)
$cfY += 40
$lblCFDomain = New-Object System.Windows.Forms.Label
$lblCFDomain.Location = New-Object System.Drawing.Point(30, $cfY)
$lblCFDomain.Size = New-Object System.Drawing.Size(140, 25)
$lblCFDomain.Text = "Domain:"
$cfTab.Controls.Add($lblCFDomain)
$txtCFDomain = New-Object System.Windows.Forms.TextBox
$txtCFDomain.Location = New-Object System.Drawing.Point(200, $cfY)
$txtCFDomain.Size = New-Object System.Drawing.Size(350, 25)
$cfTab.Controls.Add($txtCFDomain)
$cfY += 40
$lblCFIP = New-Object System.Windows.Forms.Label
$lblCFIP.Location = New-Object System.Drawing.Point(30, $cfY)
$lblCFIP.Size = New-Object System.Drawing.Size(140, 25)
$lblCFIP.Text = "Forwarder IP:"
$cfTab.Controls.Add($lblCFIP)
$txtCFIP = New-Object System.Windows.Forms.TextBox
$txtCFIP.Location = New-Object System.Drawing.Point(200, $cfY)
$txtCFIP.Size = New-Object System.Drawing.Size(350, 25)
$cfTab.Controls.Add($txtCFIP)
$cfY += 45
$btnCFAdd = New-Object System.Windows.Forms.Button
$btnCFAdd.Location = New-Object System.Drawing.Point(200, $cfY)
$btnCFAdd.Size = New-Object System.Drawing.Size(140, 32)
$btnCFAdd.Text = "Add Forwarder"
$btnCFAdd.Add_Click({
    try {
        Add-DnsServerConditionalForwarderZone -Name $txtCFDomain.Text -MasterServers $txtCFIP.Text -ReplicationScope Forest -ComputerName $cbCFServer.Text
        [System.Windows.Forms.MessageBox]::Show("Forwarder added")
        Log-Action ("Add Forwarder: " + $txtCFDomain.Text + " " + $txtCFIP.Text)
    } catch {
        $err = $_
        [System.Windows.Forms.MessageBox]::Show("Error: $err")
        Log-Action ("Error Add Forwarder: " + $err)
    }
})
$cfTab.Controls.Add($btnCFAdd)
$btnCFDel = New-Object System.Windows.Forms.Button
$btnCFDel.Location = New-Object System.Drawing.Point(360, $cfY)
$btnCFDel.Size = New-Object System.Drawing.Size(140, 32)
$btnCFDel.Text = "Remove Forwarder"
$btnCFDel.Add_Click({
    try {
        Remove-DnsServerConditionalForwarderZone -Name $txtCFDomain.Text -Force -ComputerName $cbCFServer.Text
        [System.Windows.Forms.MessageBox]::Show("Forwarder removed")
        Log-Action ("Remove Forwarder: " + $txtCFDomain.Text)
    } catch {
        $err = $_
        [System.Windows.Forms.MessageBox]::Show("Error: $err")
        Log-Action ("Error Remove Forwarder: " + $err)
    }
})
$cfTab.Controls.Add($btnCFDel)

# =============== 6. Trust Management ===============
$trTab = New-Object System.Windows.Forms.TabPage
$trTab.Text = "Trust Management"
$trY = 25
$lblTrDomain = New-Object System.Windows.Forms.Label
$lblTrDomain.Location = New-Object System.Drawing.Point(30, $trY)
$lblTrDomain.Size = New-Object System.Drawing.Size(140, 25)
$lblTrDomain.Text = "Domain:"
$trTab.Controls.Add($lblTrDomain)
$txtTrDomain = New-Object System.Windows.Forms.TextBox
$txtTrDomain.Location = New-Object System.Drawing.Point(200, $trY)
$txtTrDomain.Size = New-Object System.Drawing.Size(350, 25)
$txtTrDomain.Text = $currentDomain
$trTab.Controls.Add($txtTrDomain)
$trY += 40
$lblTrType = New-Object System.Windows.Forms.Label
$lblTrType.Location = New-Object System.Drawing.Point(30, $trY)
$lblTrType.Size = New-Object System.Drawing.Size(140, 25)
$lblTrType.Text = "Trust Type:"
$trTab.Controls.Add($lblTrType)
$cbTrType = New-Object System.Windows.Forms.ComboBox
$cbTrType.Location = New-Object System.Drawing.Point(200, $trY)
$cbTrType.Size = New-Object System.Drawing.Size(350, 25)
$cbTrType.Items.AddRange(@("External","Forest"))
$trTab.Controls.Add($cbTrType)
$trY += 40
$lblTrDir = New-Object System.Windows.Forms.Label
$lblTrDir.Location = New-Object System.Drawing.Point(30, $trY)
$lblTrDir.Size = New-Object System.Drawing.Size(140, 25)
$lblTrDir.Text = "Direction:"
$trTab.Controls.Add($lblTrDir)
$cbTrDir = New-Object System.Windows.Forms.ComboBox
$cbTrDir.Location = New-Object System.Drawing.Point(200, $trY)
$cbTrDir.Size = New-Object System.Drawing.Size(350, 25)
$cbTrDir.Items.AddRange(@("Inbound","Outbound","Bidirectional"))
$trTab.Controls.Add($cbTrDir)
$trY += 45
$btnTrList = New-Object System.Windows.Forms.Button
$btnTrList.Location = New-Object System.Drawing.Point(200, $trY)
$btnTrList.Size = New-Object System.Drawing.Size(140, 32)
$btnTrList.Text = "List Trusts"
$btnTrList.Add_Click({
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $trusts = Get-ADTrust -Filter * | Select-Object Name,TrustType,TrustDirection,TrustedDomain
        if ($trusts -and $trusts.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(($trusts | Out-String))
        } else {
            [System.Windows.Forms.MessageBox]::Show("No trusts found.")
        }
        Log-Action "Listed Trusts"
    } catch {
        $err = $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show("Error: $err")
        Log-Action ("Error List Trusts: " + $err)
    }
})
$trTab.Controls.Add($btnTrList)
$btnTrCreate = New-Object System.Windows.Forms.Button
$btnTrCreate.Location = New-Object System.Drawing.Point(360, $trY)
$btnTrCreate.Size = New-Object System.Drawing.Size(140, 32)
$btnTrCreate.Text = "Create Trust"
$btnTrCreate.Add_Click({
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        New-ADTrust -Name $txtTrDomain.Text -TrustType $cbTrType.Text -Direction $cbTrDir.Text -Confirm:$false
        [System.Windows.Forms.MessageBox]::Show("Trust created")
        Log-Action ("Created Trust: " + $txtTrDomain.Text + " " + $cbTrType.Text + " " + $cbTrDir.Text)
    } catch {
        $err = $_
        [System.Windows.Forms.MessageBox]::Show("ActiveDirectory module missing or error")
        Log-Action ("Error Create Trust: " + $err)
    }
})
$trTab.Controls.Add($btnTrCreate)

# =============== 7. Diagnostics Tab ===============
$dgTab = New-Object System.Windows.Forms.TabPage
$dgTab.Text = "Diagnostics"
$dgY = 25
$lblPing = New-Object System.Windows.Forms.Label
$lblPing.Location = New-Object System.Drawing.Point(30, $dgY)
$lblPing.Size = New-Object System.Drawing.Size(140, 25)
$lblPing.Text = "Ping Host/IP:"
$dgTab.Controls.Add($lblPing)
$txtPing = New-Object System.Windows.Forms.TextBox
$txtPing.Location = New-Object System.Drawing.Point(200, $dgY)
$txtPing.Size = New-Object System.Drawing.Size(350, 25)
$dgTab.Controls.Add($txtPing)
$dgY += 40
$btnPing = New-Object System.Windows.Forms.Button
$btnPing.Location = New-Object System.Drawing.Point(200, $dgY)
$btnPing.Size = New-Object System.Drawing.Size(140, 32)
$btnPing.Text = "Ping"
$btnPing.Add_Click({
    try {
        $targetHost = $txtPing.Text
        $result = Test-Connection $targetHost -Count 4 | Out-String
        [System.Windows.Forms.MessageBox]::Show($result)
        Log-Action ("Ping " + $targetHost)
    } catch {
        $err = $_
        [System.Windows.Forms.MessageBox]::Show("Error: $err")
        Log-Action ("Error Ping: " + $err)
    }
})
$dgTab.Controls.Add($btnPing)
$dgY += 50
$lblNS = New-Object System.Windows.Forms.Label
$lblNS.Location = New-Object System.Drawing.Point(30, $dgY)
$lblNS.Size = New-Object System.Drawing.Size(140, 25)
$lblNS.Text = "nslookup Domain:"
$dgTab.Controls.Add($lblNS)
$txtNS = New-Object System.Windows.Forms.TextBox
$txtNS.Location = New-Object System.Drawing.Point(200, $dgY)
$txtNS.Size = New-Object System.Drawing.Size(350, 25)
$dgTab.Controls.Add($txtNS)
$dgY += 40
$btnNS = New-Object System.Windows.Forms.Button
$btnNS.Location = New-Object System.Drawing.Point(200, $dgY)
$btnNS.Size = New-Object System.Drawing.Size(140, 32)
$btnNS.Text = "nslookup"
$btnNS.Add_Click({
    try {
        $domain = $txtNS.Text
        $result = Resolve-DnsName $domain | Out-String
        [System.Windows.Forms.MessageBox]::Show($result)
        Log-Action ("nslookup " + $domain)
    } catch {
        $err = $_
        [System.Windows.Forms.MessageBox]::Show("Error: $err")
        Log-Action ("Error nslookup: " + $err)
    }
})
$dgTab.Controls.Add($btnNS)

# =============== 8. Preferences Tab ===============
$prefTab = New-Object System.Windows.Forms.TabPage
$prefTab.Text = "Preferences"
$prefY = 25
$lblTheme = New-Object System.Windows.Forms.Label
$lblTheme.Location = New-Object System.Drawing.Point(30,$prefY)
$lblTheme.Size = New-Object System.Drawing.Size(150,25)
$lblTheme.Text = "Theme:"
$prefTab.Controls.Add($lblTheme)
$cbTheme = New-Object System.Windows.Forms.ComboBox
$cbTheme.Location = New-Object System.Drawing.Point(180,$prefY)
$cbTheme.Size = New-Object System.Drawing.Size(200,25)
$cbTheme.Items.AddRange(@("Light","Dark"))
$cbTheme.SelectedIndex = 0
$cbTheme.Add_SelectedIndexChanged({
    $useDark = $cbTheme.SelectedIndex -eq 1
    Set-Theme $form
})
$prefTab.Controls.Add($cbTheme)

# =============== Finalize ===============
$tabs.TabPages.Add($viewTab)
$tabs.TabPages.Add($dnsTab)
$tabs.TabPages.Add($bulkTab)
$tabs.TabPages.Add($auditTab)
$tabs.TabPages.Add($cfTab)
$tabs.TabPages.Add($trTab)
$tabs.TabPages.Add($dgTab)
$tabs.TabPages.Add($prefTab)
$form.Controls.Add($tabs)

$copyrightLabel = New-Object System.Windows.Forms.Label
$copyrightLabel.Text = "© 2025 Akhilesh Ayyagari. All Rights Reserved."
$copyrightLabel.Dock = 'Bottom'
$copyrightLabel.TextAlign = 'MiddleCenter'
$form.Controls.Add($copyrightLabel)
$form.Topmost = $true
$form.Add_Shown({$form.Activate()})
Set-Theme $form
[void]$form.ShowDialog()
