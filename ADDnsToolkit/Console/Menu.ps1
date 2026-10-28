# ==================================================================================
# AD & DNS Toolkit - interactive console menu (works over SSH, Server Core and remoting)
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

function Read-ADTValue {
    param([string]$Prompt, [string]$Default = '')
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $v = Read-Host "$Prompt$suffix"
    if (-not $v) { $Default } else { $v.Trim() }
}

function Read-ADTYesNo {
    param([string]$Prompt, [bool]$Default = $false)
    $d = if ($Default) { 'Y/n' } else { 'y/N' }
    $v = Read-Host "$Prompt ($d)"
    if (-not $v) { return $Default }
    $v -match '^(y|yes)$'
}

function Write-ADTFormatted {
    <# Formats objects as text and writes them to the host (works in every host, including redirected ones). #>
    param([Parameter(ValueFromPipeline)]$InputObject)
    begin { $items = [Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        $w = 160
        try { $bw = $Host.UI.RawUI.BufferSize.Width; if ($bw -gt 40) { $w = $bw - 1 } } catch { $w = 160 }
        $txt = ($items | Out-String -Width $w).TrimEnd()
        if ($txt) { Write-Host $txt }
    }
}

function Show-ADTResult {
    param($Data, [string[]]$Columns)
    $rows = @($Data)
    if (-not $rows.Count) { Write-ADTStatus 'Nothing to show.' Info; return }
    if ($Columns) { $rows | Format-Table $Columns -AutoSize -Wrap | Write-ADTFormatted } else { $rows | Format-Table -AutoSize -Wrap | Write-ADTFormatted }
}

function Open-ADTPath {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return }
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) { Invoke-Item $Path } else { Write-ADTStatus "Saved: $Path" Info }
}

function Invoke-ADTPreviewThenApply {
    <# Runs an action with -WhatIf, shows the preview and applies it only after a yes. #>
    param([string]$Command, [hashtable]$Parameters, [string[]]$Columns, [string]$Question = 'Apply these changes?')
    Write-ADTStatus 'Preview (nothing is changed yet):' Step
    $preview = @(& $Command @Parameters -WhatIf)
    Show-ADTResult $preview $Columns
    if (-not $preview.Count) { return }
    if (Read-ADTYesNo $Question) {
        $done = @(& $Command @Parameters -Confirm:$false)
        Show-ADTResult $done $Columns
    }
    else { Write-ADTStatus 'Cancelled. Nothing was changed.' Warn }
}

function Show-ADTMenu {
    <#
    .SYNOPSIS
        Interactive text menu for every toolkit feature. Changes are always previewed first.
    .EXAMPLE
        Show-ADTMenu
    #>
    [CmdletBinding()]
    param()
    $items = [ordered]@{
        '1' = 'Environment and prerequisites'
        '2' = 'Active Directory health check'
        '3' = 'Active Directory inventory report'
        '4' = 'Back up AD objects (users, groups, OUs)'
        '5' = 'Restore AD objects from a backup'
        '6' = 'Bulk-create users from CSV'
        '7' = 'Find / disable inactive users'
        '8' = 'Trusts: list and verify'
        '9' = 'DNS health check'
        '10' = 'DNS records: list / export'
        '11' = 'DNS records: add one'
        '12' = 'DNS records: remove one'
        '13' = 'DNS records: import from CSV'
        '14' = 'Back up DNS zones'
        '15' = 'Restore DNS zones'
        '16' = 'Stale DNS records: find / remove'
        '17' = 'Conditional forwarders'
        '18' = 'Connectivity and name resolution test'
        '19' = 'Open the output folder'
        '20' = 'Open the graphical interface'
    }
    while ($true) {
        Clear-Host
        $cfg = Get-ADTConfig
        Write-Host ''
        Write-Host '  ==========================================================' -ForegroundColor Cyan
        Write-Host "    AD & DNS Toolkit v$($cfg.Version)" -ForegroundColor Yellow
        Write-Host "    Output: $($cfg.OutputRoot)" -ForegroundColor DarkGray
        Write-Host '  ==========================================================' -ForegroundColor Cyan
        foreach ($k in $items.Keys) {
            if ($k -eq '2') { Write-Host '   ACTIVE DIRECTORY' -ForegroundColor DarkCyan }
            if ($k -eq '9') { Write-Host '   DNS' -ForegroundColor DarkCyan }
            if ($k -eq '18') { Write-Host '   TOOLS' -ForegroundColor DarkCyan }
            Write-Host ('   {0,3}. {1}' -f $k, $items[$k])
        }
        Write-Host '     0. Exit'
        $choice = Read-Host "`n  Choose an option"
        if ($choice -eq '0' -or $choice -eq 'q') { break }
        if (-not $items.Contains($choice)) { Write-ADTStatus 'Not an option on the menu.' Warn; Start-Sleep -Milliseconds 900; continue }
        Write-Host ''
        Write-Host "  -- $($items[$choice]) --" -ForegroundColor Cyan
        try {
            switch ($choice) {
                '1' {
                    Get-ADTEnvironment | Format-List | Write-ADTFormatted
                    if ((-not (Test-ADTModule 'ActiveDirectory') -or -not (Test-ADTModule 'DnsServer')) -and (Read-ADTYesNo 'Install the missing RSAT tools now? (needs Administrator)')) { Install-ADTPrerequisite -Confirm:$false }
                }
                '2' {
                    $r = Test-ADTHealth -Server (Read-ADTValue 'Domain controller to query (blank = automatic)')
                    Show-ADTResult @($r.Checks | Where-Object Status -ne 'Pass') @('Status', 'Category', 'Check', 'Target', 'Detail')
                    if ($r.ReportPath -and (Read-ADTYesNo 'Open the HTML report?' $true)) { Open-ADTPath $r.ReportPath }
                }
                '3' {
                    $r = Get-ADTInventory -Server (Read-ADTValue 'Domain controller (blank = automatic)') -StaleDays ([int](Read-ADTValue 'Stale after how many days' '90'))
                    $r.Summary | Format-List | Write-ADTFormatted
                    if (Read-ADTYesNo 'Open the HTML report?' $true) { Open-ADTPath $r.ReportPath }
                }
                '4' {
                    $r = Backup-ADTObject -Server (Read-ADTValue 'Domain controller (blank = automatic)') -IncludeComputers:(Read-ADTYesNo 'Include computers?')
                    $r | Format-List OutputFolder, OUs, Groups, Users, Computers | Write-ADTFormatted
                }
                '5' {
                    $path = Read-ADTValue 'Backup folder'
                    $inc = (Read-ADTValue 'What to restore (OU, Group, User, Membership)' 'OU,Group,User,Membership') -split '[,; ]+' | Where-Object { $_ }
                    $prm = @{ Path = $path; Include = $inc }
                    if (Read-ADTYesNo 'Set an initial password and enable restored users? (otherwise they are created disabled)') {
                        $prm['InitialPassword'] = Read-Host 'Initial password' -AsSecureString; $prm['EnableUsers'] = $true
                    }
                    Invoke-ADTPreviewThenApply -Command 'Restore-ADTObject' -Parameters $prm -Columns @('Type', 'Name', 'Action', 'Detail')
                }
                '6' {
                    $csv = Read-ADTValue 'CSV file' (Join-Path $script:ADTModuleRoot '..\Samples\NewUsers.csv')
                    Write-ADTStatus 'Validating...' Step
                    $v = @(Test-ADTBulkUserCsv -CsvPath $csv)
                    Show-ADTResult $v @('Row', 'SamAccountName', 'Name', 'Path', 'Valid', 'Issues')
                    $prm = @{ CsvPath = $csv; GeneratePassword = (Read-ADTYesNo 'Generate passwords for rows without one?' $true) }
                    $dp = Read-ADTValue 'Default OU for rows without one (blank = Users container)'; if ($dp) { $prm['DefaultPath'] = $dp }
                    Invoke-ADTPreviewThenApply -Command 'New-ADTBulkUser' -Parameters $prm -Columns @('Row', 'SamAccountName', 'Path', 'Action', 'Detail', 'InitialPassword') -Question 'Create these users?'
                }
                '7' {
                    $days = [int](Read-ADTValue 'Inactive for how many days' '90')
                    $never = Read-ADTYesNo 'Include accounts that never signed in?'
                    $exg = @((Read-ADTValue 'Groups to exclude (comma separated, blank = none)') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    $found = @(Get-ADTInactiveUser -Days $days -IncludeNeverLoggedOn:$never -ExcludeGroup $exg)
                    Show-ADTResult $found @('SamAccountName', 'Name', 'LastLogonDate', 'DaysInactive', 'Privileged', 'Reason')
                    if ($found.Count -and (Read-ADTYesNo "Disable these $($found.Count) accounts?")) {
                        $mv = Read-ADTValue 'Move them to an OU (blank = leave in place)'
                        $prm = @{ InputObject = $found; Confirm = $false }; if ($mv) { $prm['MoveToOU'] = $mv }
                        Show-ADTResult @(Disable-ADTInactiveUser @prm) @('SamAccountName', 'Action', 'Detail')
                    }
                }
                '8' {
                    $t = @(Get-ADTTrust)
                    Show-ADTResult $t @('Name', 'Direction', 'TrustType', 'ForestTransitive', 'SelectiveAuthentication', 'UsesAESKeys')
                    if ($t.Count -and (Read-ADTYesNo 'Verify each outbound trust?')) { Show-ADTResult @($t | Where-Object { $_.Direction -ne 'Inbound' } | Test-ADTTrust) @('Status', 'Target', 'Detail') }
                }
                '9' {
                    $r = Test-ADTDnsHealth -ComputerName (Read-ADTValue 'DNS server' 'localhost')
                    Show-ADTResult @($r.Checks | Where-Object Status -ne 'Pass') @('Status', 'Category', 'Check', 'Target', 'Detail')
                    if ($r.ReportPath -and (Read-ADTYesNo 'Open the HTML report?' $true)) { Open-ADTPath $r.ReportPath }
                }
                '10' {
                    $srv = Read-ADTValue 'DNS server' 'localhost'
                    Show-ADTResult @(Get-ADTDnsZone -ComputerName $srv) @('ZoneName', 'ZoneType', 'IsDsIntegrated', 'DynamicUpdate')
                    $zone = Read-ADTValue 'Zone'
                    $recs = @(Get-ADTDnsRecord -ZoneName $zone -ComputerName $srv -Name (Read-ADTValue 'Name filter' '*'))
                    Show-ADTResult $recs @('HostName', 'RecordType', 'Data', 'TTL', 'Dynamic', 'AgeDays')
                    if ($recs.Count -and (Read-ADTYesNo 'Export to CSV?')) {
                        $f = Join-Path (New-ADTOutputFolder -Category 'DNS_Exports') ("$(ConvertTo-ADTSafeFileName $zone).csv")
                        $recs | Export-Csv $f -NoTypeInformation -Encoding UTF8; Write-ADTStatus "Saved $f" Ok
                    }
                }
                '11' {
                    $prm = @{ ComputerName = (Read-ADTValue 'DNS server' 'localhost'); ZoneName = (Read-ADTValue 'Zone'); Type = (Read-ADTValue 'Type (A, AAAA, CNAME, MX, TXT, PTR)' 'A').ToUpper(); Name = (Read-ADTValue 'Name (@ for the zone apex)'); Data = (Read-ADTValue 'Data (IP address, host name or text)') }
                    if ($prm.Type -eq 'MX') { $prm['Preference'] = [int](Read-ADTValue 'MX preference' '10') }
                    if ($prm.Type -in 'A', 'AAAA') { $prm['CreatePtr'] = Read-ADTYesNo 'Also create the PTR record?' }
                    Show-ADTResult @(Add-ADTDnsRecord @prm -Confirm:$false)
                }
                '12' {
                    $prm = @{ ComputerName = (Read-ADTValue 'DNS server' 'localhost'); ZoneName = (Read-ADTValue 'Zone'); Name = (Read-ADTValue 'Name'); Type = (Read-ADTValue 'Type' 'A').ToUpper(); Data = (Read-ADTValue 'Data (blank = every record of this type)') }
                    Invoke-ADTPreviewThenApply -Command 'Remove-ADTDnsRecord' -Parameters $prm -Question 'Remove?'
                }
                '13' {
                    $prm = @{ CsvPath = (Read-ADTValue 'CSV file' (Join-Path $script:ADTModuleRoot '..\Samples\DnsRecords.csv')); ComputerName = (Read-ADTValue 'DNS server' 'localhost') }
                    $z = Read-ADTValue 'Zone for rows without a ZoneName (blank = none)'; if ($z) { $prm['ZoneName'] = $z }
                    Invoke-ADTPreviewThenApply -Command 'Import-ADTDnsRecord' -Parameters $prm -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'Action', 'Detail') -Question 'Add these records?'
                }
                '14' { Show-ADTResult @(Backup-ADTDnsZone -ComputerName (Read-ADTValue 'DNS server' 'localhost')) @('ZoneName', 'Records', 'ZoneFile', 'Status', 'Detail') }
                '15' {
                    $prm = @{ Path = (Read-ADTValue 'Backup folder'); ComputerName = (Read-ADTValue 'DNS server' 'localhost') }
                    $zs = @((Read-ADTValue 'Zones (comma separated, blank = all)') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); if ($zs.Count) { $prm['ZoneName'] = $zs }
                    Invoke-ADTPreviewThenApply -Command 'Restore-ADTDnsZone' -Parameters $prm -Question 'Restore?'
                }
                '16' {
                    $srv = Read-ADTValue 'DNS server' 'localhost'
                    $d = Read-ADTValue 'Older than how many days (blank = zone aging settings, or 30)'
                    $prm = @{ ComputerName = $srv }; if ($d) { $prm['OlderThanDays'] = [int]$d }
                    $z = Read-ADTValue 'Zone (blank = all primary zones)'; if ($z) { $prm['ZoneName'] = $z }
                    $found = @(Find-ADTStaleDnsRecord @prm)
                    Show-ADTResult $found @('ZoneName', 'HostName', 'RecordType', 'Data', 'AgeDays')
                    if ($found.Count -and (Read-ADTYesNo "Remove these $($found.Count) records? A backup is saved first")) {
                        Show-ADTResult @(Remove-ADTStaleDnsRecord -InputObject $found -ComputerName $srv -SkipIfResponding:(Read-ADTYesNo 'Keep A records whose address still responds?' $true) -Confirm:$false) @('HostName', 'RecordType', 'Data', 'Action', 'Detail')
                    }
                }
                '17' {
                    $srv = Read-ADTValue 'DNS server' 'localhost'
                    Show-ADTResult @(Get-ADTConditionalForwarder -ComputerName $srv)
                    switch (Read-ADTValue 'a = add, r = remove, Enter = back') {
                        'a' { Add-ADTConditionalForwarder -ComputerName $srv -Name (Read-ADTValue 'Domain') -MasterServers ((Read-ADTValue 'Forwarder IP addresses (comma separated)') -split ',') -ReplicationScope (Read-ADTValue 'Replication (Forest, Domain, None)' 'Forest') -Confirm:$false }
                        'r' { $n = Read-ADTValue 'Domain'; if (Read-ADTYesNo "Remove the conditional forwarder for $n?") { Remove-ADTConditionalForwarder -Name $n -ComputerName $srv -Confirm:$false } }
                    }
                }
                '18' {
                    $h = Read-ADTValue 'Host name or IP'
                    if ($h) { Show-ADTResult @(Test-ADTConnection -ComputerName $h) }
                    $n = Read-ADTValue 'Name to resolve (blank = skip)'
                    if ($n) { Show-ADTResult @(Test-ADTDnsResolution -Name $n -Server (Read-ADTValue 'DNS server (blank = default)') -Type (Read-ADTValue 'Record type' 'A_AAAA')) }
                }
                '19' { $root = (Get-ADTConfig).OutputRoot; if (-not (Test-Path $root)) { New-Item -ItemType Directory $root -Force | Out-Null }; Open-ADTPath $root }
                '20' { Show-ADTGui }
            }
        }
        catch { Write-ADTStatus $_.Exception.Message Error }
        Write-Host ''
        $null = Read-Host '  Press Enter to return to the menu'
    }
}
