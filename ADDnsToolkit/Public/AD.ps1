# ==================================================================================
# AD & DNS Toolkit - Active Directory: inventory, health, backup/restore, users, trusts
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

function Get-ADTServerParam {
    param([string]$Server)
    $p = @{}
    if ($Server) { $p['Server'] = $Server }
    $p
}

function Get-ADTOsSupport {
    <# Support status of a Windows release name, for inventory and health checks. #>
    param([string]$OperatingSystem)
    $o = "$OperatingSystem"
    if (-not $o) { return 'Unknown' }
    if ($o -match 'Server 2003|Server 2008|Server 2012|Windows 2000|Windows XP|Vista|Windows 7|Windows 8') { return 'Out of support' }
    if ($o -match 'Windows 10') { return 'Out of support (ended Oct 2025; ESU only)' }
    if ($o -match 'Server 2016') { return 'Extended support ends 12 Jan 2027' }
    if ($o -match 'Windows') { return 'Supported' }
    'Non-Windows'
}

function Get-ADTDaysSince {
    param($Date)
    if ($null -eq $Date -or "$Date" -eq '') { return $null }
    [int]((Get-Date) - [datetime]$Date).TotalDays
}

# ----------------------------------------------------------------------------------
# Inventory
# ----------------------------------------------------------------------------------
function Get-ADTInventory {
    <#
    .SYNOPSIS
        Collects an Active Directory inventory and writes HTML, CSV and JSON reports.
    .DESCRIPTION
        Users, computers, groups, OUs, domain controllers, trusts and privileged-group members,
        with stale accounts, non-expiring passwords and unsupported operating systems highlighted.
        Read-only.
    .EXAMPLE
        Get-ADTInventory
    .EXAMPLE
        Get-ADTInventory -Server dc01.contoso.com -SearchBase 'OU=Corp,DC=contoso,DC=com' -StaleDays 60
    #>
    [CmdletBinding()]
    param(
        [string]$Server,
        [string]$SearchBase,
        [ValidateRange(1, 3650)][int]$StaleDays = 90,
        [string]$OutputPath,
        [switch]$NoReport
    )
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $sb = @{}; if ($SearchBase) { $sb['SearchBase'] = $SearchBase }
    Write-ADTStatus 'Reading domain and forest...' Step
    $domain = Get-ADDomain @p -ErrorAction Stop
    $forest = Get-ADForest @p -ErrorAction Stop

    Write-ADTStatus 'Reading users...' Step
    $users = @(Get-ADUser -Filter * @p @sb -Properties EmailAddress, Enabled, LastLogonDate, PasswordLastSet, PasswordNeverExpires, AccountExpirationDate, Title, Department, Manager, whenCreated, LockedOut, servicePrincipalName, adminCount, UserPrincipalName |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Name = $_.Name; SamAccountName = $_.SamAccountName; UserPrincipalName = $_.UserPrincipalName; EmailAddress = $_.EmailAddress
                    Enabled = $_.Enabled; LastLogonDate = $_.LastLogonDate; DaysSinceLogon = Get-ADTDaysSince $_.LastLogonDate
                    PasswordLastSet = $_.PasswordLastSet; PasswordNeverExpires = $_.PasswordNeverExpires; AccountExpirationDate = $_.AccountExpirationDate
                    LockedOut = $_.LockedOut; Title = $_.Title; Department = $_.Department
                    Manager = $(if ($_.Manager) { ($_.Manager -replace '^CN=((?:\\.|[^,])+),.*$', '$1') -replace '\\', '' } else { $null })
                    ServiceAccount = [bool]@($_.servicePrincipalName).Where({ $_ }).Count; Privileged = ($_.adminCount -eq 1)
                    Created = $_.whenCreated; DistinguishedName = $_.DistinguishedName
                }
            })
    Write-ADTStatus 'Reading computers...' Step
    $computers = @(Get-ADComputer -Filter * @p @sb -Properties OperatingSystem, OperatingSystemVersion, LastLogonDate, Enabled, IPv4Address, whenCreated, DNSHostName |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Name = $_.Name; DNSHostName = $_.DNSHostName; OperatingSystem = $_.OperatingSystem; Version = $_.OperatingSystemVersion
                    Support = Get-ADTOsSupport $_.OperatingSystem; Enabled = $_.Enabled; IPv4Address = $_.IPv4Address
                    LastLogonDate = $_.LastLogonDate; DaysSinceLogon = Get-ADTDaysSince $_.LastLogonDate; Created = $_.whenCreated; DistinguishedName = $_.DistinguishedName
                }
            })
    Write-ADTStatus 'Reading groups and OUs...' Step
    $groups = @(Get-ADGroup -Filter * @p @sb -Properties GroupScope, GroupCategory, Description, ManagedBy, member |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Name = $_.Name; SamAccountName = $_.SamAccountName; Scope = "$($_.GroupScope)"; Category = "$($_.GroupCategory)"; Members = @($_.member).Where({ $_ }).Count
                    Description = $_.Description; ManagedBy = $_.ManagedBy; DistinguishedName = $_.DistinguishedName
                }
            })
    $ous = @(Get-ADOrganizationalUnit -Filter * @p @sb -Properties Description, ProtectedFromAccidentalDeletion, whenCreated, gPLink |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Name = $_.Name; DistinguishedName = $_.DistinguishedName; Description = $_.Description
                    ProtectedFromAccidentalDeletion = $_.ProtectedFromAccidentalDeletion; LinkedGPOs = ([regex]::Matches("$($_.gPLink)", 'LDAP://')).Count; Created = $_.whenCreated
                }
            })
    Write-ADTStatus 'Reading domain controllers and trusts...' Step
    $dcs = @(Get-ADDomainController -Filter * @p | ForEach-Object {
            [pscustomobject][ordered]@{
                Name = $_.Name; HostName = $_.HostName; IPv4Address = $_.IPv4Address; Site = $_.Site; OperatingSystem = $_.OperatingSystem
                Support = Get-ADTOsSupport $_.OperatingSystem; GlobalCatalog = $_.IsGlobalCatalog; ReadOnly = $_.IsReadOnly; Roles = (@($_.OperationMasterRoles) -join ', ')
            }
        })
    $trusts = @()
    try { $trusts = @(Get-ADTTrust -Server $Server) } catch { Write-ADTStatus "Could not read trusts: $($_.Exception.Message)" Warn }

    Write-ADTStatus 'Reading privileged group membership...' Step
    $sid = $domain.DomainSID.Value
    $priv = [ordered]@{ 'Domain Admins' = "$sid-512"; 'Enterprise Admins' = "$sid-519"; 'Schema Admins' = "$sid-518"; 'Administrators' = 'S-1-5-32-544'; 'Account Operators' = 'S-1-5-32-548'; 'Backup Operators' = 'S-1-5-32-551'; 'Server Operators' = 'S-1-5-32-549' }
    $privMembers = foreach ($g in $priv.Keys) {
        try {
            Get-ADGroupMember -Identity $priv[$g] -Recursive @p -ErrorAction Stop | ForEach-Object {
                [pscustomobject][ordered]@{ Group = $g; Member = $_.Name; SamAccountName = $_.SamAccountName; Type = $_.objectClass; DistinguishedName = $_.distinguishedName }
            }
        }
        catch { Write-Verbose "$g not readable here: $($_.Exception.Message)" }
    }
    $privMembers = @($privMembers)

    $cut = (Get-Date).AddDays(-$StaleDays)
    $enabled = @($users | Where-Object Enabled)
    $staleUsers = @($enabled | Where-Object { $_.LastLogonDate -and $_.LastLogonDate -lt $cut })
    $neverLogged = @($enabled | Where-Object { -not $_.LastLogonDate })
    $neverExp = @($enabled | Where-Object PasswordNeverExpires)
    $unsupported = @($computers | Where-Object { $_.Enabled -and $_.Support -like 'Out of support*' })
    $staleComputers = @($computers | Where-Object { $_.Enabled -and $_.LastLogonDate -and $_.LastLogonDate -lt $cut })
    $emptyGroups = @($groups | Where-Object { $_.Members -eq 0 })
    $privUnique = @($privMembers | Select-Object -ExpandProperty DistinguishedName -Unique)

    $summary = [pscustomobject][ordered]@{
        Domain = $domain.DNSRoot; Forest = $forest.Name; DomainMode = "$($domain.DomainMode)"; ForestMode = "$($forest.ForestMode)"
        Users = $users.Count; EnabledUsers = $enabled.Count; StaleUsers = $staleUsers.Count; NeverLoggedOn = $neverLogged.Count; PasswordNeverExpires = $neverExp.Count
        LockedOut = @($users | Where-Object LockedOut).Count; Computers = $computers.Count; StaleComputers = $staleComputers.Count; UnsupportedOS = $unsupported.Count
        Groups = $groups.Count; EmptyGroups = $emptyGroups.Count; OUs = $ous.Count; DomainControllers = $dcs.Count; Trusts = $trusts.Count
        PrivilegedAccounts = $privUnique.Count; StaleDays = $StaleDays; Collected = Get-Date
    }
    $result = [pscustomobject][ordered]@{
        Summary = $summary; Users = $users; Computers = $computers; Groups = $groups; OUs = $ous; DomainControllers = $dcs; Trusts = $trusts
        PrivilegedMembers = $privMembers; OutputFolder = $null; ReportPath = $null
    }
    if ($NoReport) { return $result }

    $folder = New-ADTOutputFolder -Category 'AD_Inventory' -Path $OutputPath
    Export-ADTDataSet -Folder $folder -Data ([ordered]@{ Users = $users; Computers = $computers; Groups = $groups; OUs = $ous; DomainControllers = $dcs; Trusts = $trusts; PrivilegedMembers = $privMembers; Summary = @($summary) })
    $tone = { param($n, $warnAt = 1) if ($n -ge $warnAt) { 'warn' } else { 'ok' } }
    $cards = @(
        @{ Label = 'Users (enabled)'; Value = "$($users.Count) ($($enabled.Count))" }
        @{ Label = "No sign-in for $StaleDays+ days"; Value = $staleUsers.Count; Tone = (& $tone $staleUsers.Count) }
        @{ Label = 'Password never expires'; Value = $neverExp.Count; Tone = (& $tone $neverExp.Count) }
        @{ Label = 'Privileged accounts'; Value = $privUnique.Count; Tone = (& $tone $privUnique.Count 10) }
        @{ Label = 'Computers'; Value = $computers.Count }
        @{ Label = 'Unsupported OS (enabled)'; Value = $unsupported.Count; Tone = $(if ($unsupported.Count) { 'bad' } else { 'ok' }) }
        @{ Label = 'Groups (empty)'; Value = "$($groups.Count) ($($emptyGroups.Count))" }
        @{ Label = 'Domain controllers'; Value = $dcs.Count }
    )
    $sections = @(
        @{ Title = 'Domain and forest'; Data = @([pscustomobject][ordered]@{ Domain = $domain.DNSRoot; NetBIOS = $domain.NetBIOSName; DomainMode = "$($domain.DomainMode)"; Forest = $forest.Name; ForestMode = "$($forest.ForestMode)"
                    PDCEmulator = $domain.PDCEmulator; RIDMaster = $domain.RIDMaster; InfrastructureMaster = $domain.InfrastructureMaster; SchemaMaster = $forest.SchemaMaster; DomainNamingMaster = $forest.DomainNamingMaster }) }
        @{ Title = 'Domain controllers'; Data = $dcs }
        @{ Title = "Enabled users with no sign-in for $StaleDays+ days"; Text = 'LastLogonDate replicates with a lag of up to 14 days.'; Data = $staleUsers; Columns = @('Name', 'SamAccountName', 'LastLogonDate', 'DaysSinceLogon', 'Department', 'ServiceAccount', 'Privileged') }
        @{ Title = 'Privileged group members'; Data = $privMembers; Columns = @('Group', 'Member', 'SamAccountName', 'Type') }
        @{ Title = 'Computers on unsupported Windows'; Data = $unsupported; Columns = @('Name', 'OperatingSystem', 'Version', 'Support', 'LastLogonDate') }
        @{ Title = 'Users'; Data = $users; Columns = @('Name', 'SamAccountName', 'Enabled', 'LastLogonDate', 'PasswordNeverExpires', 'LockedOut', 'Department', 'Title') }
        @{ Title = 'Computers'; Data = $computers; Columns = @('Name', 'OperatingSystem', 'Support', 'Enabled', 'IPv4Address', 'LastLogonDate') }
        @{ Title = 'Groups'; Data = $groups; Columns = @('Name', 'Scope', 'Category', 'Members', 'Description') }
        @{ Title = 'Organizational units'; Data = $ous; Columns = @('Name', 'DistinguishedName', 'ProtectedFromAccidentalDeletion', 'LinkedGPOs') }
        @{ Title = 'Trusts'; Data = $trusts }
    )
    $result.ReportPath = New-ADTHtmlReport -Title 'Active Directory inventory' -Subtitle "$($domain.DNSRoot) - forest $($forest.Name)" -Cards $cards -Sections $sections -Path (Join-Path $folder 'AD_Inventory.html')
    $result.OutputFolder = $folder
    Write-ADTLog "Inventory of $($domain.DNSRoot): $($users.Count) users, $($computers.Count) computers -> $folder"
    Write-ADTStatus "Inventory complete: $($users.Count) users, $($computers.Count) computers, $($groups.Count) groups. Report: $($result.ReportPath)" Ok
    $result
}

# ----------------------------------------------------------------------------------
# Health check
# ----------------------------------------------------------------------------------
function Get-ADTTimeOffset {
    <# Clock offset of a computer relative to this one, in seconds (w32tm /stripchart). #>
    param([string]$ComputerName)
    try {
        $out = & w32tm.exe /stripchart /computer:$ComputerName /samples:1 /dataonly 2>&1
        $m = [regex]::Match(($out -join "`n"), '([+-]\d+(?:\.\d+)?)s')
        if ($m.Success) { return [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) }
    }
    catch { Write-Verbose "w32tm failed for $($ComputerName): $($_.Exception.Message)" }
    $null
}

function Test-ADTHealth {
    <#
    .SYNOPSIS
        Active Directory health check with Pass / Warn / Fail results and fixes.
    .DESCRIPTION
        For every domain controller: reachability (LDAP, Kerberos, SMB, RPC, GC), core services,
        SYSVOL and NETLOGON shares, clock offset from the PDC emulator and operating system support.
        For the domain: replication status and failures, FSMO role holders, AD Recycle Bin,
        krbtgt password age and functional level. Read-only. Writes HTML, CSV and TXT reports.
    .EXAMPLE
        Test-ADTHealth
    .EXAMPLE
        (Test-ADTHealth -Server dc01).Checks | Where-Object Status -ne 'Pass'
    #>
    [CmdletBinding()]
    param([string]$Server, [string]$OutputPath, [switch]$NoReport)
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $checks = [Collections.Generic.List[object]]::new()
    Write-ADTStatus 'Reading domain, forest and domain controllers...' Step
    $domain = Get-ADDomain @p -ErrorAction Stop
    $forest = Get-ADForest @p -ErrorAction Stop
    $dcs = @(Get-ADDomainController -Filter * @p -ErrorAction Stop)
    $checks.Add((New-ADTCheck 'Domain' 'Functional level' $domain.DNSRoot $(if ("$($domain.DomainMode)" -match '2003|2008|2012') { 'Warn' } else { 'Pass' }) "Domain $($domain.DomainMode), forest $($forest.ForestMode)" 'Raise the functional level once every DC runs a supported release.'))

    $pdcOffset = $null
    if ($domain.PDCEmulator) { $pdcOffset = Get-ADTTimeOffset $domain.PDCEmulator }
    $reachable = @{}
    foreach ($dc in $dcs) {
        $h = $dc.HostName
        Write-ADTStatus "Checking $h..." Step
        $ports = [ordered]@{ LDAP = 389; Kerberos = 88; SMB = 445; RPC = 135 }
        if ($dc.IsGlobalCatalog) { $ports['GlobalCatalog'] = 3268 }
        $closed = @($ports.Keys | Where-Object { -not (Test-ADTTcpPort -ComputerName $h -Port $ports[$_]) })
        if ($closed.Count -eq $ports.Count) {
            $checks.Add((New-ADTCheck 'Domain controller' 'Reachable' $h 'Fail' 'No AD ports answered (389, 88, 445, 135).' 'Check the server is running, DNS resolves it and firewalls allow AD traffic.'))
            $reachable[$h] = $false
            continue
        }
        $reachable[$h] = $true
        $checks.Add((New-ADTCheck 'Domain controller' 'Reachable' $h $(if ($closed.Count) { 'Warn' } else { 'Pass' }) $(if ($closed.Count) { "Not answering: $($closed -join ', ')" } else { 'LDAP, Kerberos, SMB, RPC' + $(if ($dc.IsGlobalCatalog) { ', GC' } else { '' }) + ' answer' }) 'Open the missing ports or check the service behind them.'))

        try {
            $svc = @(Get-CimInstance -ClassName Win32_Service -ComputerName $h -Filter "Name='NTDS' OR Name='Netlogon' OR Name='Kdc' OR Name='W32Time' OR Name='DFSR' OR Name='DNS' OR Name='ADWS' OR Name='IsmServ'" -ErrorAction Stop -OperationTimeoutSec 15)
            foreach ($s in $svc) {
                $ok = $s.State -eq 'Running'
                $st = if ($ok) { 'Pass' } elseif ($s.StartMode -eq 'Auto') { 'Fail' } else { 'Warn' }
                $checks.Add((New-ADTCheck 'Service' $s.DisplayName $h $st "$($s.State) (start: $($s.StartMode))" "Start-Service -Name $($s.Name) on $h and check the System and Directory Service event logs."))
            }
        }
        catch { $checks.Add((New-ADTCheck 'Service' 'Service status' $h 'Warn' "Could not query services: $($_.Exception.Message)" 'Allow WinRM/DCOM (CIM) from this computer or run the check on the DC.')) }

        foreach ($share in 'SYSVOL', 'NETLOGON') {
            $ok = Test-Path ("\\{0}\{1}" -f $h, $share)
            $checks.Add((New-ADTCheck 'Share' $share $h $(if ($ok) { 'Pass' } else { 'Fail' }) $(if ($ok) { 'Shared' } else { 'Not reachable' }) 'Check DFSR replication of SYSVOL (dfsrdiag, event log DFS Replication) and that Netlogon is running.'))
        }

        if ($null -ne $pdcOffset -and $h -ne $domain.PDCEmulator) {
            $o = Get-ADTTimeOffset $h
            if ($null -ne $o) {
                $rel = [math]::Round([math]::Abs($o - $pdcOffset), 3)
                $st = if ($rel -gt 300) { 'Fail' } elseif ($rel -gt 2) { 'Warn' } else { 'Pass' }
                $checks.Add((New-ADTCheck 'Time' 'Clock offset from PDC' $h $st "$rel s" 'Kerberos fails beyond 5 minutes. Make sure DCs sync from the domain hierarchy (w32tm /config /syncfromflags:domhier /update) and the PDC from a reliable source.'))
            }
        }
        $sup = Get-ADTOsSupport $dc.OperatingSystem
        $checks.Add((New-ADTCheck 'Domain controller' 'Operating system' $h $(if ($sup -like 'Out of support*') { 'Fail' } elseif ($sup -like 'Extended*') { 'Warn' } else { 'Pass' }) "$($dc.OperatingSystem) - $sup" 'Replace the DC with Windows Server 2022 or 2025.'))
    }

    Write-ADTStatus 'Checking replication...' Step
    try {
        $meta = @(Get-ADReplicationPartnerMetadata -Target $domain.DNSRoot -Scope Domain @p -ErrorAction Stop)
        foreach ($m in $meta) {
            $srv = ($m.Server -split '\.')[0]
            $partner = ([regex]::Match("$($m.Partner)", 'CN=NTDS Settings,CN=([^,]+)')).Groups[1].Value
            $part = ([regex]::Match("$($m.Partition)", '^(?:DC|CN)=([^,]+)')).Groups[1].Value
            $age = if ($m.LastReplicationSuccess) { [math]::Round(((Get-Date) - $m.LastReplicationSuccess).TotalHours, 1) } else { $null }
            $st = if ($m.LastReplicationResult -ne 0) { 'Fail' } elseif ($null -eq $age -or $age -gt 24) { 'Warn' } else { 'Pass' }
            $detail = "Result $($m.LastReplicationResult); last success $(if ($m.LastReplicationSuccess) { $m.LastReplicationSuccess.ToString('yyyy-MM-dd HH:mm') } else { 'never' })"
            $checks.Add((New-ADTCheck 'Replication' "$part from $partner" $srv $st $detail 'Run repadmin /showrepl and repadmin /replsummary on the DC; check DNS, connectivity and the Directory Service log.'))
        }
        $fail = @(Get-ADReplicationFailure -Target $domain.DNSRoot -Scope Domain @p -ErrorAction SilentlyContinue | Where-Object { $_.FailureCount -gt 0 })
        foreach ($f in $fail) { $checks.Add((New-ADTCheck 'Replication' 'Replication failure' "$($f.Server)" 'Fail' "$($f.FailureCount) failures with $($f.Partner); first $($f.FirstFailureTime); error $($f.LastError)" 'repadmin /showrepl * /errorsonly')) }
    }
    catch {
        $txt = (& repadmin.exe /replsummary 2>&1 | Out-String)
        $st = if ($txt -match '\s[1-9]\d*\s*/\s*\d+') { 'Warn' } else { 'Info' }
        $checks.Add((New-ADTCheck 'Replication' 'repadmin /replsummary' $domain.DNSRoot $st ($txt.Trim() -replace '\s+', ' ') 'Install the AD replication cmdlets (RSAT) for detailed per-partner results.'))
    }

    Write-ADTStatus 'Checking FSMO roles, Recycle Bin and krbtgt...' Step
    $roles = [ordered]@{ 'Schema master' = $forest.SchemaMaster; 'Domain naming master' = $forest.DomainNamingMaster; 'PDC emulator' = $domain.PDCEmulator; 'RID master' = $domain.RIDMaster; 'Infrastructure master' = $domain.InfrastructureMaster }
    foreach ($r in $roles.Keys) {
        $hn = "$($roles[$r])"
        $ok = if ($reachable.ContainsKey($hn)) { $reachable[$hn] } else { Test-ADTTcpPort -ComputerName $hn -Port 389 }
        $checks.Add((New-ADTCheck 'FSMO' $r $hn $(if ($ok) { 'Pass' } else { 'Fail' }) $(if ($ok) { 'Holder reachable' } else { 'Holder not reachable' }) 'If the holder is gone for good, seize the role with Move-ADDirectoryServerOperationMasterRole -Force.'))
    }
    try {
        $rb = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" @p -ErrorAction Stop
        $on = @($rb.EnabledScopes).Count -gt 0
        $checks.Add((New-ADTCheck 'Domain' 'AD Recycle Bin' $forest.Name $(if ($on) { 'Pass' } else { 'Warn' }) $(if ($on) { 'Enabled' } else { 'Not enabled' }) "Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $($forest.Name) (cannot be turned off again)."))
    }
    catch { Write-Verbose "Recycle Bin check skipped: $($_.Exception.Message)" }
    try {
        $k = Get-ADUser -Identity krbtgt -Properties PasswordLastSet @p -ErrorAction Stop
        $d = Get-ADTDaysSince $k.PasswordLastSet
        $checks.Add((New-ADTCheck 'Domain' 'krbtgt password age' $domain.DNSRoot $(if ($d -gt 180) { 'Warn' } else { 'Pass' }) "$d days (last set $($k.PasswordLastSet))" 'Rotate krbtgt twice, allowing replication in between (Microsoft New-KrbtgtKeys.ps1).'))
    }
    catch { Write-Verbose "krbtgt check skipped: $($_.Exception.Message)" }

    $overall = Get-ADTOverallStatus $checks
    $result = [pscustomobject][ordered]@{
        Domain = $domain.DNSRoot; Overall = $overall
        Pass = @($checks | Where-Object Status -eq 'Pass').Count; Warn = @($checks | Where-Object Status -eq 'Warn').Count; Fail = @($checks | Where-Object Status -eq 'Fail').Count
        Checks = @($checks); OutputFolder = $null; ReportPath = $null
    }
    if (-not $NoReport) {
        $folder = New-ADTOutputFolder -Category 'AD_HealthCheck' -Path $OutputPath
        $checks | Export-Csv -Path (Join-Path $folder 'AD_HealthCheck.csv') -NoTypeInformation -Encoding UTF8
        ($checks | Format-Table Status, Category, Check, Target, Detail -AutoSize -Wrap | Out-String -Width 220) | Set-Content -Path (Join-Path $folder 'AD_HealthCheck.txt') -Encoding UTF8
        $cards = @(
            @{ Label = 'Overall'; Value = $overall; Tone = $(switch ($overall) { 'Fail' { 'bad' } 'Warn' { 'warn' } default { 'ok' } }) }
            @{ Label = 'Passed'; Value = $result.Pass; Tone = 'ok' }
            @{ Label = 'Warnings'; Value = $result.Warn; Tone = $(if ($result.Warn) { 'warn' } else { 'ok' }) }
            @{ Label = 'Failures'; Value = $result.Fail; Tone = $(if ($result.Fail) { 'bad' } else { 'ok' }) }
            @{ Label = 'Domain controllers'; Value = $dcs.Count }
        )
        $problems = @($checks | Where-Object { $_.Status -in 'Fail', 'Warn' })
        $sections = @(@{ Title = 'Needs attention'; Data = $problems; Columns = @('Status', 'Category', 'Check', 'Target', 'Detail', 'Fix') })
        foreach ($cat in @($checks | Select-Object -ExpandProperty Category -Unique)) { $sections += @{ Title = $cat; Data = @($checks | Where-Object Category -eq $cat); Columns = @('Status', 'Check', 'Target', 'Detail') } }
        $result.ReportPath = New-ADTHtmlReport -Title 'Active Directory health check' -Subtitle "$($domain.DNSRoot) - overall: $overall" -Cards $cards -Sections $sections -Path (Join-Path $folder 'AD_HealthCheck.html')
        $result.OutputFolder = $folder
    }
    Write-ADTLog "AD health check of $($domain.DNSRoot): $overall ($($result.Fail) fail, $($result.Warn) warn)"
    Write-ADTStatus "Health check: $overall - $($result.Pass) passed, $($result.Warn) warnings, $($result.Fail) failures." $(switch ($overall) { 'Fail' { 'Error' } 'Warn' { 'Warn' } default { 'Ok' } })
    $result
}

# ----------------------------------------------------------------------------------
# Object backup and restore (users, groups, OUs, membership)
# ----------------------------------------------------------------------------------
function Backup-ADTObject {
    <#
    .SYNOPSIS
        Exports users, groups (with members), OUs and optionally computers to JSON and CSV.
    .DESCRIPTION
        An object-level export for audits and for re-creating objects with Restore-ADTObject.
        It is not a replacement for a system-state backup of a domain controller
        (Windows Server Backup) or for the AD Recycle Bin. Passwords are never exported.
    .EXAMPLE
        Backup-ADTObject -IncludeComputers
    #>
    [CmdletBinding()]
    param([string]$Server, [string]$SearchBase, [string]$OutputPath, [switch]$IncludeComputers)
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $sb = @{}; if ($SearchBase) { $sb['SearchBase'] = $SearchBase }
    $domain = Get-ADDomain @p -ErrorAction Stop
    $folder = New-ADTOutputFolder -Category 'AD_Backups' -Path $OutputPath
    Write-ADTStatus 'Exporting OUs...' Step
    $ous = @(Get-ADOrganizationalUnit -Filter * @p @sb -Properties Description, ProtectedFromAccidentalDeletion | Select-Object Name, DistinguishedName, Description, ProtectedFromAccidentalDeletion)
    Write-ADTStatus 'Exporting groups and members...' Step
    $groups = @(Get-ADGroup -Filter * @p @sb -Properties Description, ManagedBy, member, isCriticalSystemObject | ForEach-Object {
            [pscustomobject][ordered]@{ Name = $_.Name; SamAccountName = $_.SamAccountName; GroupScope = "$($_.GroupScope)"; GroupCategory = "$($_.GroupCategory)"
                Description = $_.Description; ManagedBy = $_.ManagedBy; DistinguishedName = $_.DistinguishedName; SystemObject = [bool]$_.isCriticalSystemObject; Members = @($_.member) }
        })
    Write-ADTStatus 'Exporting users...' Step
    $users = @(Get-ADUser -Filter * @p @sb -Properties GivenName, Surname, DisplayName, UserPrincipalName, EmailAddress, Department, Title, Company, Office, Description, Manager, Enabled, LastLogonDate, isCriticalSystemObject |
            Select-Object Name, GivenName, Surname, DisplayName, SamAccountName, UserPrincipalName, EmailAddress, Enabled, Department, Title, Company, Office, Description, Manager, DistinguishedName, LastLogonDate, @{ n = 'SystemObject'; e = { [bool]$_.isCriticalSystemObject } })
    $computers = @()
    if ($IncludeComputers) {
        Write-ADTStatus 'Exporting computers...' Step
        $computers = @(Get-ADComputer -Filter * @p @sb -Properties DNSHostName, OperatingSystem, Description, Enabled | Select-Object Name, DNSHostName, OperatingSystem, Description, Enabled, DistinguishedName)
    }
    foreach ($set in @(@('ous', $ous), @('groups', $groups), @('users', $users), @('computers', $computers))) {
        if (@($set[1]).Count) { ConvertTo-Json -InputObject @($set[1]) -Depth 4 | Set-Content -Path (Join-Path $folder "$($set[0]).json") -Encoding UTF8 }
    }
    # CSV copies for people (and for v1 compatibility)
    $users | Export-Csv (Join-Path $folder 'Users_Backup.csv') -NoTypeInformation -Encoding UTF8
    $groups | Select-Object Name, SamAccountName, GroupScope, GroupCategory, Description, DistinguishedName, @{ n = 'Members'; e = { $_.Members -join '; ' } } | Export-Csv (Join-Path $folder 'Groups_Backup.csv') -NoTypeInformation -Encoding UTF8
    $ous | Export-Csv (Join-Path $folder 'OUs_Backup.csv') -NoTypeInformation -Encoding UTF8
    if ($computers.Count) { $computers | Export-Csv (Join-Path $folder 'Computers_Backup.csv') -NoTypeInformation -Encoding UTF8 }
    $manifest = [pscustomobject][ordered]@{
        Tool = 'AD & DNS Toolkit'; Version = $script:ADTVersion; Type = 'ADObjects'; Created = (Get-Date).ToString('o')
        Domain = $domain.DNSRoot; DomainDN = $domain.DistinguishedName; SearchBase = $SearchBase
        Counts = [pscustomobject]@{ OUs = $ous.Count; Groups = $groups.Count; Users = $users.Count; Computers = $computers.Count }
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $folder 'manifest.json') -Encoding UTF8
    Write-ADTLog "AD object backup of $($domain.DNSRoot): $($users.Count) users, $($groups.Count) groups, $($ous.Count) OUs -> $folder"
    Write-ADTStatus "Backup saved: $($users.Count) users, $($groups.Count) groups, $($ous.Count) OUs in $folder" Ok
    [pscustomobject][ordered]@{ OutputFolder = $folder; OUs = $ous.Count; Groups = $groups.Count; Users = $users.Count; Computers = $computers.Count; Manifest = $manifest }
}

function Read-ADTBackupSet {
    <# Loads a backup folder written by Backup-ADTObject (JSON) or by v1 Backup-AD.ps1 (CSV). #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path -PathType Container)) { throw "Backup folder not found: $Path" }
    $read = {
        param([string]$Json, [string]$Csv)
        $j = Join-Path $Path $Json; $c = Join-Path $Path $Csv
        if (Test-Path $j) { return @(Get-Content $j -Raw -Encoding UTF8 | ConvertFrom-Json) }
        if (Test-Path $c) { return @(Import-Csv $c) }
        @()
    }
    $m = Join-Path $Path 'manifest.json'
    [pscustomobject]@{
        Manifest = $(if (Test-Path $m) { Get-Content $m -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null })
        OUs = & $read 'ous.json' 'OUs_Backup.csv'
        Groups = & $read 'groups.json' 'Groups_Backup.csv'
        Users = & $read 'users.json' 'Users_Backup.csv'
    }
}

function Restore-ADTObject {
    <#
    .SYNOPSIS
        Re-creates missing OUs, groups, users and group memberships from a backup folder.
    .DESCRIPTION
        Never changes or deletes existing objects - it only creates what is missing, parents first.
        Users are created DISABLED unless you supply -InitialPassword and -EnableUsers (backups
        contain no passwords). DNs are rewritten when restoring into a different domain.
        Use -WhatIf to preview: every row comes back with Action 'WouldCreate' / 'WouldAdd'.
        Works with v2 JSON backups and with v1 Backup-AD.ps1 CSV backups.
    .EXAMPLE
        Restore-ADTObject -Path C:\Users\me\Documents\ADDnsToolkit\AD_Backups\AD_Backups_20261028_101500 -WhatIf
    .EXAMPLE
        Restore-ADTObject -Path .\backup -Include OU, Group -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('OU', 'Group', 'User', 'Membership')][string[]]$Include = @('OU', 'Group', 'User', 'Membership'),
        [string]$Server,
        [string]$DefaultUserPath,
        [string]$DefaultGroupPath,
        [securestring]$InitialPassword,
        [switch]$EnableUsers,
        [switch]$IncludeSystemObjects
    )
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $set = Read-ADTBackupSet -Path $Path
    $domain = Get-ADDomain @p -ErrorAction Stop
    $srcDN = if ($set.Manifest) { $set.Manifest.DomainDN } else { $null }
    $dstDN = $domain.DistinguishedName
    if (-not $DefaultUserPath) { $DefaultUserPath = $domain.UsersContainer }
    if (-not $DefaultGroupPath) { $DefaultGroupPath = $domain.UsersContainer }
    $results = [Collections.Generic.List[object]]::new()
    $planned = @{}
    $add = { param($Type, $Name, $Action, $Detail) $results.Add([pscustomobject][ordered]@{ Type = $Type; Name = $Name; Action = $Action; Detail = $Detail }) }
    $exists = {
        param([string]$Dn)
        if (-not $Dn) { return $false }
        if ($planned.ContainsKey($Dn.ToLowerInvariant())) { return $true }
        try { $null = Get-ADObject -Identity $Dn @p -ErrorAction Stop; return $true } catch { return $false }
    }
    $nonEmpty = { param([hashtable]$H, [string]$Key, $Value) if ($null -ne $Value -and "$Value" -ne '') { $H[$Key] = "$Value" } }

    if ('OU' -in $Include) {
        foreach ($ou in @($set.OUs | Sort-Object { Get-ADTDNDepth $_.DistinguishedName })) {
            $dn = ConvertTo-ADTTargetDN $ou.DistinguishedName $srcDN $dstDN
            if (& $exists $dn) { & $add 'OU' $dn 'Skipped' 'Already exists'; continue }
            $parent = Get-ADTParentDN $dn
            if (-not (& $exists $parent)) { & $add 'OU' $dn 'Failed' "Parent $parent does not exist"; continue }
            if ($PSCmdlet.ShouldProcess($dn, 'Create OU')) {
                try {
                    $prm = @{ Name = $ou.Name; Path = $parent; ProtectedFromAccidentalDeletion = ("$($ou.ProtectedFromAccidentalDeletion)" -ne 'False') }
                    & $nonEmpty $prm 'Description' $ou.Description
                    New-ADOrganizationalUnit @prm @p -ErrorAction Stop
                    $planned[$dn.ToLowerInvariant()] = $true
                    & $add 'OU' $dn 'Created' ''
                    Write-ADTLog "Restored OU $dn" Change
                }
                catch { & $add 'OU' $dn 'Failed' $_.Exception.Message }
            }
            else { $planned[$dn.ToLowerInvariant()] = $true; & $add 'OU' $dn 'WouldCreate' "In $parent" }
        }
    }

    $groupExists = {
        param([string]$Sam)
        try { [bool](Get-ADGroup -Filter "SamAccountName -eq '$(ConvertTo-ADTFilterValue $Sam)'" @p -ErrorAction Stop) } catch { $false }
    }
    if ('Group' -in $Include) {
        foreach ($g in @($set.Groups)) {
            if (-not $IncludeSystemObjects -and "$($g.SystemObject)" -eq 'True') { continue }
            $sam = if ($g.SamAccountName) { $g.SamAccountName } else { $g.Name }
            if (& $groupExists $sam) { & $add 'Group' $sam 'Skipped' 'Already exists'; continue }
            $target = if ($g.DistinguishedName) { Get-ADTParentDN (ConvertTo-ADTTargetDN $g.DistinguishedName $srcDN $dstDN) } else { $null }
            if (-not (& $exists $target)) { $target = $DefaultGroupPath }
            if ($PSCmdlet.ShouldProcess("$sam in $target", 'Create group')) {
                try {
                    $prm = @{ Name = $g.Name; SamAccountName = $sam; GroupScope = $(if ($g.GroupScope) { "$($g.GroupScope)" } else { 'Global' }); GroupCategory = $(if ($g.GroupCategory) { "$($g.GroupCategory)" } else { 'Security' }); Path = $target }
                    & $nonEmpty $prm 'Description' $g.Description
                    New-ADGroup @prm @p -ErrorAction Stop
                    & $add 'Group' $sam 'Created' "In $target"
                    Write-ADTLog "Restored group $sam in $target" Change
                }
                catch { & $add 'Group' $sam 'Failed' $_.Exception.Message }
            }
            else { & $add 'Group' $sam 'WouldCreate' "In $target" }
        }
    }

    if ('User' -in $Include) {
        foreach ($u in @($set.Users)) {
            if (-not $IncludeSystemObjects -and ("$($u.SystemObject)" -eq 'True' -or $u.SamAccountName -in 'krbtgt', 'Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount')) { continue }
            $sam = $u.SamAccountName
            if (-not $sam) { & $add 'User' $u.Name 'Failed' 'No SamAccountName in backup'; continue }
            $existing = $null
            try { $existing = Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADTFilterValue $sam)'" @p -ErrorAction Stop } catch { $existing = $null }
            if ($existing) { & $add 'User' $sam 'Skipped' 'Already exists'; continue }
            $target = if ($u.DistinguishedName) { Get-ADTParentDN (ConvertTo-ADTTargetDN $u.DistinguishedName $srcDN $dstDN) } else { $null }
            if (-not (& $exists $target)) { $target = $DefaultUserPath }
            $enable = [bool]($EnableUsers -and $InitialPassword)
            if ($PSCmdlet.ShouldProcess("$sam in $target", 'Create user' + $(if ($enable) { ' (enabled)' } else { ' (disabled)' }))) {
                try {
                    $prm = @{ Name = $(if ($u.Name) { $u.Name } else { $sam }); SamAccountName = $sam; Path = $target; Enabled = $enable }
                    foreach ($k in 'GivenName', 'Surname', 'DisplayName', 'UserPrincipalName', 'EmailAddress', 'Department', 'Title', 'Company', 'Office', 'Description') { & $nonEmpty $prm $k $u.$k }
                    if (-not $prm.ContainsKey('UserPrincipalName')) { $prm['UserPrincipalName'] = "$sam@$($domain.DNSRoot)" }
                    if ($InitialPassword) { $prm['AccountPassword'] = $InitialPassword; $prm['ChangePasswordAtLogon'] = $true }
                    New-ADUser @prm @p -ErrorAction Stop
                    & $add 'User' $sam 'Created' ("In $target" + $(if ($enable) { '' } else { '; disabled until a password is set' }))
                    Write-ADTLog "Restored user $sam in $target" Change
                }
                catch { & $add 'User' $sam 'Failed' $_.Exception.Message }
            }
            else { & $add 'User' $sam 'WouldCreate' ("In $target" + $(if ($enable) { '' } else { ' (disabled)' })) }
        }
    }

    if ('Membership' -in $Include) {
        foreach ($g in @($set.Groups | Where-Object { $_.Members })) {
            $sam = if ($g.SamAccountName) { $g.SamAccountName } else { $g.Name }
            $members = @($g.Members | ForEach-Object { "$_" -split ';\s*' } | Where-Object { $_ } | ForEach-Object { ConvertTo-ADTTargetDN $_ $srcDN $dstDN })
            $grp = $null
            try { $grp = Get-ADGroup -Filter "SamAccountName -eq '$(ConvertTo-ADTFilterValue $sam)'" -Properties member @p -ErrorAction Stop } catch { $grp = $null }
            $current = @{}
            if ($grp) { foreach ($m in @($grp.member)) { $current["$m".ToLowerInvariant()] = $true } }
            $missing = @($members | Where-Object { -not $current.ContainsKey($_.ToLowerInvariant()) })
            if (-not $missing.Count) { continue }
            $ok = @(); $absent = @()
            foreach ($m in $missing) { if (& $exists $m) { $ok += $m } else { $absent += $m } }
            if ($absent.Count) { & $add 'Membership' $sam 'Skipped' "$($absent.Count) member(s) not in the directory" }
            if (-not $ok.Count) { continue }
            if (-not $grp -and -not $WhatIfPreference) { & $add 'Membership' $sam 'Failed' 'Group does not exist'; continue }
            if ($PSCmdlet.ShouldProcess($sam, "Add $($ok.Count) member(s)")) {
                try { Add-ADGroupMember -Identity $grp -Members $ok @p -ErrorAction Stop; & $add 'Membership' $sam 'Added' "$($ok.Count) member(s)"; Write-ADTLog "Restored $($ok.Count) members to $sam" Change }
                catch { & $add 'Membership' $sam 'Failed' $_.Exception.Message }
            }
            else { & $add 'Membership' $sam 'WouldAdd' "$($ok.Count) member(s)" }
        }
    }
    $s = $results | Group-Object Action | ForEach-Object { "$($_.Name): $($_.Count)" }
    Write-ADTStatus ("Restore " + $(if ($WhatIfPreference) { 'preview' } else { 'finished' }) + ' - ' + ($s -join ', ')) Ok
    $results
}

# ----------------------------------------------------------------------------------
# Bulk user creation
# ----------------------------------------------------------------------------------
function Test-ADTSamAccountName {
    <# Returns $null when valid, otherwise the reason. #>
    param([string]$Name)
    if (-not $Name -or -not $Name.Trim()) { return 'SamAccountName is empty' }
    if ($Name.Length -gt 20) { return 'SamAccountName is longer than 20 characters' }
    if ($Name -match '["/\\\[\]:;|=,+*?<>@]') { return 'SamAccountName contains a character AD does not allow (" / \ [ ] : ; | = , + * ? < > @)' }
    if ($Name -match '\.$') { return 'SamAccountName cannot end with a period' }
    $null
}

function Test-ADTBulkUserCsv {
    <#
    .SYNOPSIS
        Validates a bulk-user CSV before anything is created.
    .DESCRIPTION
        Required: SamAccountName, and Name or GivenName + Surname. Optional: Password, OU (or Path),
        UserPrincipalName, EmailAddress, Department, Title, Company, Office, Manager (sAMAccountName),
        Groups (separated by ;), Description. Checks names, duplicates, existing accounts, OUs,
        groups and managers.
    .EXAMPLE
        Test-ADTBulkUserCsv -CsvPath .\Samples\NewUsers.csv | Where-Object { -not $_.Valid }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CsvPath, [string]$Server, [string]$DefaultPath, [switch]$SkipDirectoryChecks)
    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $rows = @(Import-Csv -Path $CsvPath)
    if (-not $rows.Count) { throw "The CSV has no rows: $CsvPath" }
    $cols = @($rows[0].PSObject.Properties.Name)
    if ('SamAccountName' -notin $cols) { throw "The CSV needs a SamAccountName column. Found: $($cols -join ', ')" }
    if ('Name' -notin $cols -and -not ('GivenName' -in $cols -and 'Surname' -in $cols)) { throw 'The CSV needs a Name column, or GivenName and Surname columns.' }
    $p = Get-ADTServerParam $Server
    $dnsRoot = $null; $usersContainer = $null
    if (-not $SkipDirectoryChecks) {
        Assert-ADTModule ActiveDirectory
        $d = Get-ADDomain @p -ErrorAction Stop
        $dnsRoot = $d.DNSRoot; $usersContainer = $d.UsersContainer
    }
    if (-not $DefaultPath) { $DefaultPath = $usersContainer }
    $seen = @{}; $ouCache = @{}; $grpCache = @{}; $mgrCache = @{}
    $i = 0
    foreach ($r in $rows) {
        $i++
        $issues = [Collections.Generic.List[string]]::new()
        $get = { param($n) if ($r.PSObject.Properties[$n]) { "$($r.$n)".Trim() } else { '' } }
        $sam = & $get 'SamAccountName'
        $name = & $get 'Name'
        if (-not $name) { $name = ('{0} {1}' -f (& $get 'GivenName'), (& $get 'Surname')).Trim() }
        if (-not $name) { $issues.Add('Name is empty') }
        $why = Test-ADTSamAccountName $sam
        if ($why) { $issues.Add($why) }
        $key = $sam.ToLowerInvariant()
        if ($sam -and $seen.ContainsKey($key)) { $issues.Add("Duplicate of row $($seen[$key]) in this CSV") } elseif ($sam) { $seen[$key] = $i }
        $path = & $get 'OU'; if (-not $path) { $path = & $get 'Path' }; if (-not $path) { $path = $DefaultPath }
        $upn = & $get 'UserPrincipalName'; if (-not $upn -and $dnsRoot -and $sam) { $upn = "$sam@$dnsRoot" }
        $mail = & $get 'EmailAddress'; if (-not $mail) { $mail = & $get 'Email' }
        if ($mail -and $mail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $issues.Add("Email address '$mail' is not valid") }
        $groups = @((& $get 'Groups') -split '[;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $mgr = & $get 'Manager'
        if (-not $SkipDirectoryChecks -and -not $why) {
            try { if (Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADTFilterValue $sam)'" @p -ErrorAction Stop) { $issues.Add('An account with this SamAccountName already exists') } } catch { $issues.Add("Lookup failed: $($_.Exception.Message)") }
            if ($upn) { try { if (Get-ADUser -Filter "UserPrincipalName -eq '$(ConvertTo-ADTFilterValue $upn)'" @p -ErrorAction Stop) { $issues.Add("UPN $upn is already in use") } } catch { Write-Verbose 'UPN lookup failed' } }
            if ($path) {
                if (-not $ouCache.ContainsKey($path)) { try { $null = Get-ADObject -Identity $path @p -ErrorAction Stop; $ouCache[$path] = $true } catch { $ouCache[$path] = $false } }
                if (-not $ouCache[$path]) { $issues.Add("OU/container not found: $path") }
            }
            foreach ($g in $groups) {
                if (-not $grpCache.ContainsKey($g)) { try { $grpCache[$g] = [bool](Get-ADGroup -Identity $g @p -ErrorAction Stop) } catch { $grpCache[$g] = $false } }
                if (-not $grpCache[$g]) { $issues.Add("Group not found: $g") }
            }
            if ($mgr) {
                if (-not $mgrCache.ContainsKey($mgr)) { try { $mgrCache[$mgr] = [bool](Get-ADUser -Identity $mgr @p -ErrorAction Stop) } catch { $mgrCache[$mgr] = $false } }
                if (-not $mgrCache[$mgr]) { $issues.Add("Manager not found: $mgr") }
            }
        }
        [pscustomobject][ordered]@{
            Row = $i; SamAccountName = $sam; Name = $name; UserPrincipalName = $upn; Path = $path; Groups = ($groups -join '; ')
            HasPassword = [bool](& $get 'Password'); Valid = ($issues.Count -eq 0); Issues = ($issues -join '; '); Source = $r
        }
    }
}

function New-ADTBulkUser {
    <#
    .SYNOPSIS
        Creates Active Directory users from a CSV, after validating every row.
    .DESCRIPTION
        Invalid rows are reported and skipped; nothing is half-created. Rows without a Password
        get a random 16-character password with -GeneratePassword (returned on the result
        objects; written to the report only with -IncludePasswordsInReport). Users must change
        their password at first sign-in unless -NoChangePasswordAtLogon.
        Use -WhatIf to preview (Action 'WouldCreate').
    .EXAMPLE
        New-ADTBulkUser -CsvPath .\Samples\NewUsers.csv -GeneratePassword -WhatIf
    .EXAMPLE
        New-ADTBulkUser -CsvPath .\hires.csv -GeneratePassword -DefaultPath 'OU=Staff,DC=contoso,DC=com'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [string]$Server,
        [string]$DefaultPath,
        [switch]$GeneratePassword,
        [ValidateRange(12, 128)][int]$PasswordLength = 16,
        [switch]$Disabled,
        [switch]$NoChangePasswordAtLogon,
        [string]$OutputPath,
        [switch]$IncludePasswordsInReport
    )
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $rows = @(Test-ADTBulkUserCsv -CsvPath $CsvPath -Server $Server -DefaultPath $DefaultPath)
    Write-ADTStatus "$($rows.Count) rows read, $(@($rows | Where-Object Valid).Count) valid." Info
    $results = foreach ($r in $rows) {
        $res = [pscustomobject][ordered]@{ Row = $r.Row; SamAccountName = $r.SamAccountName; Name = $r.Name; UserPrincipalName = $r.UserPrincipalName; Path = $r.Path; Action = ''; Detail = ''; InitialPassword = $null }
        if (-not $r.Valid) { $res.Action = 'Invalid'; $res.Detail = $r.Issues; $res; continue }
        $src = $r.Source
        $pw = if ($r.HasPassword) { "$($src.Password)" } elseif ($GeneratePassword) { New-ADTPassword -Length $PasswordLength } else { $null }
        if (-not $pw) { $res.Action = 'Invalid'; $res.Detail = 'No password in the CSV; use -GeneratePassword'; $res; continue }
        if (-not $r.HasPassword) { $res.InitialPassword = $pw }
        if ($PSCmdlet.ShouldProcess("$($r.SamAccountName) in $($r.Path)", 'Create user')) {
            try {
                $prm = @{
                    Name = $r.Name; SamAccountName = $r.SamAccountName; UserPrincipalName = $r.UserPrincipalName; Path = $r.Path
                    AccountPassword = (ConvertTo-SecureString $pw -AsPlainText -Force); Enabled = (-not $Disabled); ChangePasswordAtLogon = (-not $NoChangePasswordAtLogon)
                }
                foreach ($k in 'GivenName', 'Surname', 'DisplayName', 'Department', 'Title', 'Company', 'Office', 'Description', 'EmailAddress') {
                    if ($src.PSObject.Properties[$k] -and "$($src.$k)".Trim()) { $prm[$k] = "$($src.$k)".Trim() }
                }
                if (-not $prm.ContainsKey('EmailAddress') -and $src.PSObject.Properties['Email'] -and "$($src.Email)".Trim()) { $prm['EmailAddress'] = "$($src.Email)".Trim() }
                if ($src.PSObject.Properties['Manager'] -and "$($src.Manager)".Trim()) { $prm['Manager'] = "$($src.Manager)".Trim() }
                $u = New-ADUser @prm @p -PassThru -ErrorAction Stop
                $notes = @()
                foreach ($g in @($r.Groups -split ';\s*' | Where-Object { $_ })) {
                    try { Add-ADGroupMember -Identity $g -Members $u @p -ErrorAction Stop } catch { $notes += "not added to $($g): $($_.Exception.Message)" }
                }
                $res.Action = 'Created'; $res.Detail = $(if ($notes) { $notes -join '; ' } else { "In $($r.Path)" })
                Write-ADTLog "Created user $($r.SamAccountName) in $($r.Path)" Change
                Write-ADTStatus "Created $($r.SamAccountName)" Ok
            }
            catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message; $res.InitialPassword = $null; Write-ADTStatus "Failed $($r.SamAccountName): $($_.Exception.Message)" Error }
        }
        else { $res.Action = 'WouldCreate'; $res.Detail = "In $($r.Path)" + $(if ($r.Groups) { "; groups: $($r.Groups)" } else { '' }); $res.InitialPassword = $null }
        $res
    }
    $results = @($results)
    if (-not $WhatIfPreference) {
        $folder = New-ADTOutputFolder -Category 'AD_BulkUsers' -Path $OutputPath
        $cols = @('Row', 'SamAccountName', 'Name', 'UserPrincipalName', 'Path', 'Action', 'Detail')
        if ($IncludePasswordsInReport) { $cols += 'InitialPassword'; Write-ADTStatus 'The report contains initial passwords. Store it securely and delete it after hand-over.' Warn }
        $results | Select-Object $cols | Export-Csv (Join-Path $folder 'BulkUserResults.csv') -NoTypeInformation -Encoding UTF8
        Write-ADTStatus "Report: $(Join-Path $folder 'BulkUserResults.csv')" Info
    }
    $summary = $results | Group-Object Action | ForEach-Object { "$($_.Name): $($_.Count)" }
    Write-ADTStatus ('Bulk users - ' + ($summary -join ', ')) Ok
    $results
}

# ----------------------------------------------------------------------------------
# Inactive users
# ----------------------------------------------------------------------------------
function Get-ADTInactiveUser {
    <#
    .SYNOPSIS
        Finds enabled user accounts with no sign-in for a number of days.
    .DESCRIPTION
        Uses LastLogonDate (lastLogonTimestamp, which replicates with up to ~14 days lag).
        Skips built-in accounts, accounts with service principal names (service accounts) and
        members of -ExcludeGroup unless told otherwise. Read-only.
    .EXAMPLE
        Get-ADTInactiveUser -Days 120 -IncludeNeverLoggedOn -ExcludeGroup 'Break Glass'
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(14, 3650)][int]$Days = 90,
        [switch]$IncludeNeverLoggedOn,
        [switch]$IncludeServiceAccounts,
        [string[]]$ExcludeGroup = @(),
        [string[]]$ExcludeSamAccountName = @(),
        [string]$SearchBase,
        [string]$Server
    )
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    $sb = @{}; if ($SearchBase) { $sb['SearchBase'] = $SearchBase }
    $cut = (Get-Date).AddDays(-$Days)
    $excludedDn = @{}
    foreach ($g in $ExcludeGroup) {
        try { Get-ADGroupMember -Identity $g -Recursive @p -ErrorAction Stop | ForEach-Object { $excludedDn["$($_.distinguishedName)".ToLowerInvariant()] = $g } }
        catch { Write-ADTStatus "Exclude group '$g' not found: $($_.Exception.Message)" Warn }
    }
    $skipSam = @('krbtgt', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount') + $ExcludeSamAccountName
    Get-ADUser -Filter 'Enabled -eq $true' @p @sb -Properties LastLogonDate, whenCreated, servicePrincipalName, adminCount, Description, PasswordLastSet, objectSid |
        Where-Object {
            $_.SamAccountName -notin $skipSam -and "$($_.SID)" -notmatch '-500$' -and
            -not $excludedDn.ContainsKey("$($_.DistinguishedName)".ToLowerInvariant()) -and
            ($IncludeServiceAccounts -or -not @($_.servicePrincipalName).Where({ $_ }).Count)
        } |
        ForEach-Object {
            $never = -not $_.LastLogonDate
            $inactive = ($_.LastLogonDate -and $_.LastLogonDate -lt $cut) -or ($IncludeNeverLoggedOn -and $never -and $_.whenCreated -lt $cut)
            if ($inactive) {
                [pscustomobject][ordered]@{
                    Name = $_.Name; SamAccountName = $_.SamAccountName; LastLogonDate = $_.LastLogonDate
                    DaysInactive = $(if ($never) { Get-ADTDaysSince $_.whenCreated } else { Get-ADTDaysSince $_.LastLogonDate })
                    Reason = $(if ($never) { "Never signed in (created $($_.whenCreated.ToString('yyyy-MM-dd')))" } else { "No sign-in for $Days+ days" })
                    Created = $_.whenCreated; PasswordLastSet = $_.PasswordLastSet; Privileged = ($_.adminCount -eq 1)
                    ServiceAccount = [bool]@($_.servicePrincipalName).Where({ $_ }).Count; Description = $_.Description; DistinguishedName = $_.DistinguishedName
                }
            }
        } | Sort-Object DaysInactive -Descending
}

function Disable-ADTInactiveUser {
    <#
    .SYNOPSIS
        Disables inactive accounts (from Get-ADTInactiveUser or the pipeline), with a report for undo.
    .DESCRIPTION
        Each account is disabled, stamped with a description saying why and when, and optionally
        moved to -MoveToOU. The CSV report lists every DN so the change can be reversed with
        Enable-ADAccount. Asks for confirmation unless -Confirm:$false. Supports -WhatIf.
    .EXAMPLE
        Get-ADTInactiveUser -Days 120 | Disable-ADTInactiveUser -WhatIf
    .EXAMPLE
        Disable-ADTInactiveUser -Days 180 -MoveToOU 'OU=Disabled,DC=contoso,DC=com' -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ValueFromPipeline)][object[]]$InputObject,
        [ValidateRange(14, 3650)][int]$Days = 90,
        [switch]$IncludeNeverLoggedOn,
        [string[]]$ExcludeGroup = @(),
        [string[]]$ExcludeSamAccountName = @(),
        [string]$MoveToOU,
        [string]$Server,
        [string]$OutputPath
    )
    begin { $items = [Collections.Generic.List[object]]::new() }
    process { foreach ($o in @($InputObject)) { if ($o) { $items.Add($o) } } }
    end {
        Assert-ADTModule ActiveDirectory
        $p = Get-ADTServerParam $Server
        if (-not $items.Count) { foreach ($u in @(Get-ADTInactiveUser -Days $Days -IncludeNeverLoggedOn:$IncludeNeverLoggedOn -ExcludeGroup $ExcludeGroup -ExcludeSamAccountName $ExcludeSamAccountName -Server $Server)) { $items.Add($u) } }
        if (-not $items.Count) { Write-ADTStatus 'No inactive users found.' Ok; return }
        $stamp = Get-Date -Format 'yyyy-MM-dd'
        $results = foreach ($u in $items) {
            $dn = if ($u.DistinguishedName) { $u.DistinguishedName } else { $u.SamAccountName }
            $res = [pscustomobject][ordered]@{ SamAccountName = $u.SamAccountName; Name = $u.Name; DaysInactive = $u.DaysInactive; Action = ''; Detail = ''; DistinguishedName = $dn }
            if ($PSCmdlet.ShouldProcess("$($u.SamAccountName) ($($u.DaysInactive) days inactive)", 'Disable account')) {
                try {
                    Disable-ADAccount -Identity $dn @p -ErrorAction Stop
                    $desc = "Disabled $stamp by AD & DNS Toolkit: inactive $($u.DaysInactive) days." + $(if ($u.Description) { " Was: $($u.Description)" } else { '' })
                    if ($desc.Length -gt 1000) { $desc = $desc.Substring(0, 1000) }
                    Set-ADUser -Identity $dn -Description $desc @p -ErrorAction SilentlyContinue
                    $res.Action = 'Disabled'
                    if ($MoveToOU) { Move-ADObject -Identity $dn -TargetPath $MoveToOU @p -ErrorAction Stop; $res.Detail = "Moved to $MoveToOU" }
                    Write-ADTLog "Disabled inactive user $($u.SamAccountName) ($dn)" Change
                }
                catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message }
            }
            else { $res.Action = 'WouldDisable'; $res.Detail = $u.Reason }
            $res
        }
        $results = @($results)
        if (-not $WhatIfPreference -and @($results | Where-Object Action -eq 'Disabled').Count) {
            $folder = New-ADTOutputFolder -Category 'AD_InactiveUsers' -Path $OutputPath
            $file = Join-Path $folder 'DisabledUsers.csv'
            $results | Export-Csv $file -NoTypeInformation -Encoding UTF8
            Write-ADTStatus "Report (use it to undo with Enable-ADAccount): $file" Info
        }
        Write-ADTStatus ('Inactive users - ' + (($results | Group-Object Action | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ')) Ok
        $results
    }
}

# ----------------------------------------------------------------------------------
# Trusts
# ----------------------------------------------------------------------------------
function Get-ADTTrust {
    <#
    .SYNOPSIS
        Lists domain and forest trusts with direction, type and encryption settings.
    #>
    [CmdletBinding()]
    param([string]$Server)
    Assert-ADTModule ActiveDirectory
    $p = Get-ADTServerParam $Server
    @(Get-ADTrust -Filter * @p -Properties whenCreated -ErrorAction Stop | ForEach-Object {
            [pscustomobject][ordered]@{
                Name = $_.Name; Direction = "$($_.Direction)"; TrustType = "$($_.TrustType)"; ForestTransitive = $_.ForestTransitive; IntraForest = $_.IntraForest
                SelectiveAuthentication = $_.SelectiveAuthentication; SIDFiltering = $_.SIDFilteringQuarantined; UsesAESKeys = $_.UsesAESKeys; UsesRC4 = $_.UsesRC4Encryption; Created = $_.whenCreated
            }
        })
}

function Test-ADTTrust {
    <#
    .SYNOPSIS
        Verifies the secure channel of an outbound trust (like netdom trust /verify).
    .EXAMPLE
        Get-ADTTrust | Test-ADTTrust
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $err = $null
        try {
            [DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().VerifyOutboundTrustRelationship($Name)
            return (New-ADTCheck 'Trust' 'Verify outbound trust' $Name 'Pass' 'Secure channel verified' '')
        }
        catch { $err = $_.Exception.InnerException; if (-not $err) { $err = $_.Exception } }
        try {
            [DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().VerifyOutboundTrustRelationship($Name)
            return (New-ADTCheck 'Trust' 'Verify outbound trust' $Name 'Pass' 'Forest trust verified' '')
        }
        catch { Write-Verbose "Forest verification failed too: $($_.Exception.Message)" }
        New-ADTCheck 'Trust' 'Verify outbound trust' $Name 'Fail' $err.Message 'Check DNS (conditional forwarders) and connectivity to the other domain, then reset the trust password with netdom trust /reset.'
    }
}
