#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Run: Invoke-Pester ./tests
# The ActiveDirectory and DnsServer cmdlets are replaced by small in-memory stubs, so the tests
# run on any machine (Windows PowerShell 5.1 or PowerShell 7, with or without RSAT).

BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $root 'ADDnsToolkit/ADDnsToolkit.psd1') -Force
    $env:ADT_OUTPUT_ROOT = Join-Path ([IO.Path]::GetTempPath()) ('adt-tests-' + [guid]::NewGuid().ToString('N'))
    function InModule([scriptblock]$Script) { & (Get-Module ADDnsToolkit) $Script }

    # ---------------- Active Directory stubs ----------------
    $global:FakeDomain = [pscustomobject]@{ DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com'; UsersContainer = 'CN=Users,DC=contoso,DC=com'; NetBIOSName = 'CONTOSO'; DomainMode = 'Windows2016Domain'; DomainSID = [pscustomobject]@{ Value = 'S-1-5-21-1' } }
    $global:FakeObjects = @('DC=contoso,DC=com', 'CN=Users,DC=contoso,DC=com', 'OU=Corp,DC=contoso,DC=com', 'OU=Sales,OU=Corp,DC=contoso,DC=com')
    $global:FakeUsers = @(
        [pscustomobject]@{ SamAccountName = 'existing'; Name = 'Existing User'; UserPrincipalName = 'existing@contoso.com'; Enabled = $true; DistinguishedName = 'CN=Existing User,OU=Corp,DC=contoso,DC=com'; LastLogonDate = (Get-Date).AddDays(-200); whenCreated = (Get-Date).AddYears(-3); servicePrincipalName = @(); adminCount = $null; Description = ''; PasswordLastSet = (Get-Date).AddYears(-1); SID = 'S-1-5-21-1-1105' }
        [pscustomobject]@{ SamAccountName = 'svc-sql'; Name = 'svc-sql'; UserPrincipalName = 'svc-sql@contoso.com'; Enabled = $true; DistinguishedName = 'CN=svc-sql,OU=Corp,DC=contoso,DC=com'; LastLogonDate = (Get-Date).AddDays(-300); whenCreated = (Get-Date).AddYears(-5); servicePrincipalName = @('MSSQLSvc/sql01'); adminCount = $null; Description = ''; PasswordLastSet = (Get-Date).AddYears(-2); SID = 'S-1-5-21-1-1106' }
        [pscustomobject]@{ SamAccountName = 'krbtgt'; Name = 'krbtgt'; UserPrincipalName = $null; Enabled = $true; DistinguishedName = 'CN=krbtgt,CN=Users,DC=contoso,DC=com'; LastLogonDate = $null; whenCreated = (Get-Date).AddYears(-9); servicePrincipalName = @(); adminCount = 1; Description = ''; PasswordLastSet = (Get-Date).AddYears(-4); SID = 'S-1-5-21-1-502' }
        [pscustomobject]@{ SamAccountName = 'Administrator'; Name = 'Administrator'; UserPrincipalName = $null; Enabled = $true; DistinguishedName = 'CN=Administrator,CN=Users,DC=contoso,DC=com'; LastLogonDate = (Get-Date).AddDays(-400); whenCreated = (Get-Date).AddYears(-9); servicePrincipalName = @(); adminCount = 1; Description = ''; PasswordLastSet = (Get-Date).AddYears(-1); SID = 'S-1-5-21-1-500' }
        [pscustomobject]@{ SamAccountName = 'recent'; Name = 'Recent User'; UserPrincipalName = 'recent@contoso.com'; Enabled = $true; DistinguishedName = 'CN=Recent User,OU=Sales,OU=Corp,DC=contoso,DC=com'; LastLogonDate = (Get-Date).AddDays(-3); whenCreated = (Get-Date).AddYears(-1); servicePrincipalName = @(); adminCount = $null; Description = ''; PasswordLastSet = (Get-Date).AddDays(-20); SID = 'S-1-5-21-1-1107' }
        [pscustomobject]@{ SamAccountName = 'never'; Name = 'Never Used'; UserPrincipalName = 'never@contoso.com'; Enabled = $true; DistinguishedName = 'CN=Never Used,OU=Sales,OU=Corp,DC=contoso,DC=com'; LastLogonDate = $null; whenCreated = (Get-Date).AddDays(-400); servicePrincipalName = @(); adminCount = $null; Description = ''; PasswordLastSet = $null; SID = 'S-1-5-21-1-1108' }
    )
    $global:FakeGroups = @([pscustomobject]@{ SamAccountName = 'Sales'; Name = 'Sales'; member = @() })
    $global:Created = [Collections.Generic.List[object]]::new()

    function global:Get-ADDomain { [CmdletBinding()] param($Server) $global:FakeDomain }
    function global:Get-ADObject { [CmdletBinding()] param($Identity, $Server) if ($global:FakeObjects -contains $Identity) { [pscustomobject]@{ DistinguishedName = $Identity } } else { throw "Directory object not found: $Identity" } }
    function global:Get-ADUser {
        [CmdletBinding()] param($Filter, $Identity, $Properties, $Server, $SearchBase)
        if ($Identity) { $u = $global:FakeUsers | Where-Object SamAccountName -eq $Identity; if (-not $u) { throw "Cannot find $Identity" }; return $u }
        if ($Filter -match "SamAccountName -eq '(.+)'") { $v = $Matches[1] -replace "''", "'"; return $global:FakeUsers | Where-Object SamAccountName -eq $v }
        if ($Filter -match "UserPrincipalName -eq '(.+)'") { $v = $Matches[1]; return $global:FakeUsers | Where-Object UserPrincipalName -eq $v }
        if ("$Filter" -match 'Enabled') { return $global:FakeUsers | Where-Object Enabled }
        $global:FakeUsers
    }
    function global:Get-ADGroup {
        [CmdletBinding()] param($Filter, $Identity, $Properties, $Server)
        if ($Identity) { $g = $global:FakeGroups | Where-Object SamAccountName -eq $Identity; if (-not $g) { throw "Cannot find group $Identity" }; return $g }
        if ($Filter -match "SamAccountName -eq '(.+)'") { $v = $Matches[1]; return $global:FakeGroups | Where-Object SamAccountName -eq $v }
        $global:FakeGroups
    }
    function global:Get-ADGroupMember { [CmdletBinding()] param($Identity, [switch]$Recursive, $Server) @() }
    function global:New-ADUser { [CmdletBinding()] param($Name, $SamAccountName, $UserPrincipalName, $Path, $AccountPassword, $Enabled, $ChangePasswordAtLogon, $GivenName, $Surname, $DisplayName, $Department, $Title, $Company, $Office, $Description, $EmailAddress, $Manager, [switch]$PassThru, $Server) $global:Created.Add("User:$SamAccountName"); if ($PassThru) { [pscustomobject]@{ SamAccountName = $SamAccountName } } }
    function global:New-ADGroup { [CmdletBinding()] param($Name, $SamAccountName, $GroupScope, $GroupCategory, $Path, $Description, $Server) $global:Created.Add("Group:$SamAccountName") }
    function global:New-ADOrganizationalUnit { [CmdletBinding()] param($Name, $Path, $Description, $ProtectedFromAccidentalDeletion, $Server) $global:Created.Add("OU:$Name,$Path") }
    function global:Add-ADGroupMember { [CmdletBinding()] param($Identity, $Members, $Server) $global:Created.Add('Member') }
    function global:Disable-ADAccount { [CmdletBinding()] param($Identity, $Server) $global:Created.Add("Disabled:$Identity") }
    function global:Set-ADUser { [CmdletBinding()] param($Identity, $Description, $Server) }
    function global:Move-ADObject { [CmdletBinding()] param($Identity, $TargetPath, $Server) }
    function global:Get-ADForest { [CmdletBinding()] param($Server) [pscustomobject]@{ Name = 'contoso.com'; ForestMode = 'Windows2016Forest'; SchemaMaster = 'dc01.contoso.com'; DomainNamingMaster = 'dc01.contoso.com' } }
    function global:Get-ADComputer { [CmdletBinding()] param($Filter, $Properties, $Server, $SearchBase) @(
            [pscustomobject]@{ Name = 'OLD01'; DNSHostName = 'old01.contoso.com'; OperatingSystem = 'Windows Server 2012 R2 Standard'; OperatingSystemVersion = '6.3'; Enabled = $true; IPv4Address = '10.0.0.5'; LastLogonDate = (Get-Date).AddDays(-2); whenCreated = (Get-Date).AddYears(-8); DistinguishedName = 'CN=OLD01,DC=contoso,DC=com' }
            [pscustomobject]@{ Name = 'NEW01'; DNSHostName = 'new01.contoso.com'; OperatingSystem = 'Windows Server 2025 Datacenter'; OperatingSystemVersion = '10.0'; Enabled = $true; IPv4Address = '10.0.0.6'; LastLogonDate = (Get-Date).AddDays(-1); whenCreated = (Get-Date).AddDays(-30); DistinguishedName = 'CN=NEW01,DC=contoso,DC=com' }) }
    function global:Get-ADOrganizationalUnit { [CmdletBinding()] param($Filter, $Properties, $Server, $SearchBase) @([pscustomobject]@{ Name = 'Corp'; DistinguishedName = 'OU=Corp,DC=contoso,DC=com'; Description = ''; ProtectedFromAccidentalDeletion = $true; whenCreated = (Get-Date).AddYears(-5); gPLink = '[LDAP://cn={1},cn=policies][LDAP://cn={2},cn=policies]' }) }
    function global:Get-ADDomainController { [CmdletBinding()] param($Filter, $Server) @([pscustomobject]@{ Name = 'DC01'; HostName = 'dc01.contoso.com'; IPv4Address = '10.0.0.10'; Site = 'HQ'; OperatingSystem = 'Windows Server 2016 Standard'; IsGlobalCatalog = $true; IsReadOnly = $false; OperationMasterRoles = @('PDCEmulator', 'RIDMaster') }) }
    function global:Get-ADTrust { [CmdletBinding()] param($Filter, $Properties, $Server) @() }

    # ---------------- DNS stubs ----------------
    function global:New-FakeRecord($HostName, $Type, $Data, $AgeDays = $null) {
        $rd = switch ($Type) {
            'A' { [pscustomobject]@{ IPv4Address = $Data } } 'CNAME' { [pscustomobject]@{ HostNameAlias = $Data } } 'MX' { [pscustomobject]@{ MailExchange = $Data; Preference = 10 } }
            'TXT' { [pscustomobject]@{ DescriptiveText = $Data } } 'NS' { [pscustomobject]@{ NameServer = $Data } } 'SOA' { [pscustomobject]@{ PrimaryServer = $Data; ResponsiblePerson = 'hostmaster'; SerialNumber = 7 } }
            'SRV' { [pscustomobject]@{ Priority = 0; Weight = 100; Port = 389; DomainName = $Data } } 'PTR' { [pscustomobject]@{ PtrDomainName = $Data } }
        }
        [pscustomobject]@{ HostName = $HostName; RecordType = $Type; RecordData = $rd; TimeToLive = [timespan]::FromHours(1); Timestamp = $(if ($null -ne $AgeDays) { (Get-Date).AddDays(-$AgeDays) } else { $null }) }
    }
    $global:FakeZones = @(
        [pscustomobject]@{ ZoneName = 'contoso.com'; ZoneType = 'Primary'; IsAutoCreated = $false; IsDsIntegrated = $true; ReplicationScope = 'Domain'; DynamicUpdate = 'Secure'; IsReverseLookupZone = $false; IsPaused = $false; IsShutdown = $false; IsSigned = $false }
        [pscustomobject]@{ ZoneName = '_msdcs.contoso.com'; ZoneType = 'Primary'; IsAutoCreated = $false; IsDsIntegrated = $true; ReplicationScope = 'Forest'; DynamicUpdate = 'Secure'; IsReverseLookupZone = $false; IsPaused = $false; IsShutdown = $false; IsSigned = $false }
        [pscustomobject]@{ ZoneName = '0.in-addr.arpa'; ZoneType = 'Primary'; IsAutoCreated = $true; IsDsIntegrated = $false; ReplicationScope = 'None'; DynamicUpdate = 'None'; IsReverseLookupZone = $true; IsPaused = $false; IsShutdown = $false; IsSigned = $false }
    )
    $global:FakeRecords = @{
        'contoso.com'        = @(
            (New-FakeRecord '@' 'SOA' 'dc01.contoso.com' 400), (New-FakeRecord '@' 'NS' 'dc01.contoso.com' 400), (New-FakeRecord '@' 'A' '10.0.0.10' 400)
            (New-FakeRecord 'old-laptop' 'A' '10.0.5.20' 120), (New-FakeRecord 'fresh-laptop' 'A' '10.0.5.21' 2), (New-FakeRecord 'web' 'A' '10.0.0.80')
            (New-FakeRecord 'www' 'CNAME' 'web.contoso.com'), (New-FakeRecord 'mail' 'MX' 'mx1.contoso.com'), (New-FakeRecord 'spf' 'TXT' 'v=spf1 -all')
        )
        '_msdcs.contoso.com' = @((New-FakeRecord '_ldap._tcp.dc' 'SRV' 'dc01.contoso.com' 400))
    }
    function global:Get-DnsServerZone { [CmdletBinding()] param($Name, $ComputerName) if ($Name) { $global:FakeZones | Where-Object ZoneName -eq $Name } else { $global:FakeZones } }
    function global:Get-DnsServerZoneAging { [CmdletBinding()] param($Name, $ComputerName) [pscustomobject]@{ AgingEnabled = $true; NoRefreshInterval = [timespan]::FromDays(7); RefreshInterval = [timespan]::FromDays(7) } }
    function global:Get-DnsServerResourceRecord { [CmdletBinding()] param($ZoneName, $Name, $RRType, $ComputerName) $r = @($global:FakeRecords[$ZoneName]); if ($Name) { $r = @($r | Where-Object HostName -eq $Name) }; if ($RRType) { $r = @($r | Where-Object RecordType -eq $RRType) }; $r }
    function global:Remove-DnsServerResourceRecord { [CmdletBinding()] param($ZoneName, $InputObject, [switch]$Force, $ComputerName) $global:Created.Add("RemovedDns:$($InputObject.HostName)") }
    function global:Add-DnsServerResourceRecordA { [CmdletBinding()] param($ZoneName, $Name, $IPv4Address, [switch]$CreatePtr, $TimeToLive, $ComputerName) $global:Created.Add("AddA:$Name") }
}

Describe 'Module' {
    It 'exports the public commands and has a valid manifest' {
        $m = Test-ModuleManifest (Join-Path (Split-Path $PSScriptRoot -Parent) 'ADDnsToolkit/ADDnsToolkit.psd1')
        $m.Version.ToString() | Should -Be '2.0.0'
        @(Get-Command -Module ADDnsToolkit).Count | Should -Be 37
    }
    It 'documents every exported command' {
        foreach ($c in Get-Command -Module ADDnsToolkit) { (Get-Help $c.Name).Synopsis | Should -Not -Match ('^\s*$|^\s*' + [regex]::Escape($c.Name)) }
    }
    It 'makes every state-changing command support -WhatIf' {
        foreach ($c in Get-Command -Module ADDnsToolkit | Where-Object { $_.Verb -in 'New', 'Add', 'Remove', 'Restore', 'Disable', 'Import', 'Install', 'Set' -and $_.Name -ne 'New-ADTPassword' }) {
            $c.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        }
    }
}

Describe 'Shared helpers' {
    It 'handles distinguished names with escaped commas' {
        InModule { Get-ADTParentDN 'CN=Doe\, John,OU=Sales,DC=contoso,DC=com' } | Should -Be 'OU=Sales,DC=contoso,DC=com'
        InModule { Get-ADTDNDepth 'OU=Sales,OU=Corp,DC=contoso,DC=com' } | Should -Be 3
        InModule { ConvertTo-ADTTargetDN 'OU=Sales,DC=old,DC=local' 'DC=old,DC=local' 'DC=contoso,DC=com' } | Should -Be 'OU=Sales,DC=contoso,DC=com'
        InModule { ConvertTo-ADTFilterValue "O'Brien" } | Should -Be "O''Brien"
    }
    It 'generates strong random passwords' {
        $a = New-ADTPassword -Length 20; $b = New-ADTPassword -Length 20
        $a.Length | Should -Be 20
        $a | Should -Match '[A-Z]'; $a | Should -Match '[a-z]'; $a | Should -Match '\d'; $a | Should -Match '[^A-Za-z0-9]'
        $a | Should -Not -Be $b
    }
    It 'validates sAMAccountNames' {
        InModule { Test-ADTSamAccountName 'jdoe' } | Should -BeNullOrEmpty
        InModule { Test-ADTSamAccountName 'this-name-is-far-too-long' } | Should -Match '20 characters'
        InModule { Test-ADTSamAccountName 'bad/name' } | Should -Match 'character'
        InModule { Test-ADTSamAccountName 'dot.' } | Should -Match 'period'
    }
    It 'rates Windows releases' {
        InModule { Get-ADTOsSupport 'Windows Server 2012 R2 Datacenter' } | Should -Be 'Out of support'
        InModule { Get-ADTOsSupport 'Windows Server 2016 Standard' } | Should -Match '2027'
        InModule { Get-ADTOsSupport 'Windows Server 2025 Datacenter' } | Should -Be 'Supported'
    }
    It 'HTML-encodes everything in reports' {
        $f = Join-Path $env:ADT_OUTPUT_ROOT 'r.html'
        InModule { New-ADTHtmlReport -Title 'T <b>' -Sections @(@{ Title = 'S'; Data = @([pscustomobject]@{ Name = '<script>alert(1)</script>'; Status = 'Fail' }) }) -Path (Join-Path $env:ADT_OUTPUT_ROOT 'r.html') } | Out-Null
        $html = Get-Content $f -Raw
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;alert'
        $html | Should -Match 'st-fail'
    }
    It 'rolls check results up to the worst status' {
        InModule { Get-ADTOverallStatus @([pscustomobject]@{ Status = 'Pass' }, [pscustomobject]@{ Status = 'Warn' }) } | Should -Be 'Warn'
        InModule { Get-ADTOverallStatus @([pscustomobject]@{ Status = 'Warn' }, [pscustomobject]@{ Status = 'Fail' }) } | Should -Be 'Fail'
    }
}

Describe 'DNS' {
    It 'flattens record data for every type' {
        (InModule { ConvertTo-ADTDnsRecordView -Record (New-FakeRecord 'mail' 'MX' 'mx1.contoso.com') -ZoneName 'contoso.com' }).Data | Should -Be 'mx1.contoso.com'
        (InModule { ConvertTo-ADTDnsRecordView -Record (New-FakeRecord 'mail' 'MX' 'mx1.contoso.com') -ZoneName 'contoso.com' }).Preference | Should -Be 10
        (InModule { ConvertTo-ADTDnsRecordView -Record (New-FakeRecord 'x' 'SRV' 'dc01.contoso.com') -ZoneName 'z' }).Data | Should -Be '0 100 389 dc01.contoso.com'
        (InModule { ConvertTo-ADTDnsRecordView -Record (New-FakeRecord 'x' 'A' '10.1.1.1' 5) -ZoneName 'z' }).AgeDays | Should -Be 5
        (InModule { ConvertTo-ADTDnsRecordView -Record (New-FakeRecord 'x' 'A' '10.1.1.1') -ZoneName 'z' }).TTL | Should -Be 3600
    }
    It 'finds only old dynamic records and never SOA, NS, the apex or _msdcs' {
        $s = @(Find-ADTStaleDnsRecord)
        $s.Count | Should -Be 1
        $s[0].HostName | Should -Be 'old-laptop'
        $s[0].ThresholdDays | Should -Be 14
        @(Find-ADTStaleDnsRecord -IncludeMsdcs -OlderThanDays 30).HostName | Should -Contain '_ldap._tcp.dc'
    }
    It 'previews stale record removal without changing anything' {
        $global:Created.Clear()
        $r = @(Find-ADTStaleDnsRecord | Remove-ADTStaleDnsRecord -WhatIf)
        $r[0].Action | Should -Be 'WouldRemove'
        $global:Created.Count | Should -Be 0
    }
    It 'removes a stale record after saving a re-importable copy' {
        $global:Created.Clear()
        $out = Join-Path $env:ADT_OUTPUT_ROOT 'stale'
        $r = @(Find-ADTStaleDnsRecord | Remove-ADTStaleDnsRecord -OutputPath $out -Confirm:$false)
        $r[0].Action | Should -Be 'Removed'
        $global:Created | Should -Contain 'RemovedDns:old-laptop'
        Join-Path $out 'StaleRecords.csv' | Should -Exist
    }
    It 'validates new records before touching the server' {
        (Add-ADTDnsRecord -ZoneName contoso.com -Name pc1 -Type A -Data '999.1.1.1' -Confirm:$false).Action | Should -Be 'Failed'
        (Add-ADTDnsRecord -ZoneName contoso.com -Name pc1 -Type A -Data '10.9.9.9' -WhatIf).Action | Should -Be 'WouldAdd'
        (Add-ADTDnsRecord -ZoneName contoso.com -Name alias -Type CNAME -Data 'not a host!' -Confirm:$false).Action | Should -Be 'Failed'
    }
    It 'protects SOA and NS records' {
        (Remove-ADTDnsRecord -ZoneName contoso.com -Name '@' -Type NS -Confirm:$false).Action | Should -Be 'Skipped'
    }
    It 'imports v1 CSV columns and skips records that already exist' {
        $csv = Join-Path $env:ADT_OUTPUT_ROOT 'dns.csv'
        "Name,RecordType,ZoneName,IPAddress`nweb,A,contoso.com,10.0.0.80`nnewbox,A,contoso.com,10.0.0.99`nbad,A,contoso.com," | Set-Content $csv
        $r = @(Import-ADTDnsRecord -CsvPath $csv -WhatIf)
        ($r | Where-Object HostName -eq 'web').Action | Should -Be 'Skipped'
        ($r | Where-Object HostName -eq 'newbox').Action | Should -Be 'WouldAdd'
        ($r | Where-Object HostName -eq 'bad').Action | Should -Be 'Invalid'
    }
}

Describe 'Active Directory' {
    It 'validates a bulk-user CSV row by row' {
        $csv = Join-Path $env:ADT_OUTPUT_ROOT 'users.csv'
        @(
            'Name,SamAccountName,OU,Groups,EmailAddress'
            'Ann Lee,alee,"OU=Sales,OU=Corp,DC=contoso,DC=com",Sales,ann@contoso.com'
            'Dup Lee,alee,,,'
            'Old One,existing,,,'
            'Bad Ou,bou,"OU=Nowhere,DC=contoso,DC=com",,'
            'Bad Name,bad/name,,,'
            'No Group,nogrp,,Ghosts,not-an-email'
        ) | Set-Content $csv
        $v = @(Test-ADTBulkUserCsv -CsvPath $csv)
        $v[0].Valid | Should -BeTrue
        $v[0].UserPrincipalName | Should -Be 'alee@contoso.com'
        $v[1].Issues | Should -Match 'Duplicate of row 1'
        $v[2].Issues | Should -Match 'already exists'
        $v[3].Issues | Should -Match 'not found'
        $v[4].Issues | Should -Match 'character'
        $v[5].Issues | Should -Match 'Group not found'
        $v[5].Issues | Should -Match 'Email'
    }
    It 'previews bulk creation, and creates only valid rows' {
        $csv = Join-Path $env:ADT_OUTPUT_ROOT 'users2.csv'
        "Name,SamAccountName,Password`nAnn Lee,alee,`nOld One,existing,Pa55word!Pa55" | Set-Content $csv
        $global:Created.Clear()
        $p = @(New-ADTBulkUser -CsvPath $csv -GeneratePassword -WhatIf)
        $p[0].Action | Should -Be 'WouldCreate'
        $p[1].Action | Should -Be 'Invalid'
        $global:Created.Count | Should -Be 0
        $r = @(New-ADTBulkUser -CsvPath $csv -GeneratePassword -Confirm:$false -OutputPath (Join-Path $env:ADT_OUTPUT_ROOT 'bulk'))
        $r[0].Action | Should -Be 'Created'
        $r[0].InitialPassword.Length | Should -Be 16
        $global:Created | Should -Contain 'User:alee'
        (Get-Content (Join-Path $env:ADT_OUTPUT_ROOT 'bulk/BulkUserResults.csv') -Raw) | Should -Not -Match $r[0].InitialPassword
    }
    It 'refuses rows with no password unless asked to generate one' {
        $csv = Join-Path $env:ADT_OUTPUT_ROOT 'users3.csv'
        "Name,SamAccountName`nAnn Lee,alee" | Set-Content $csv
        (New-ADTBulkUser -CsvPath $csv -WhatIf).Detail | Should -Match 'GeneratePassword'
    }
    It 'restores parents before children, into another domain, and only what is missing' {
        $b = Join-Path $env:ADT_OUTPUT_ROOT 'backup'
        New-Item -ItemType Directory $b -Force | Out-Null
        @{ DomainDN = 'DC=old,DC=local' } | ConvertTo-Json | Set-Content (Join-Path $b 'manifest.json')
        ConvertTo-Json @(
            @{ Name = 'Team'; DistinguishedName = 'OU=Team,OU=Region,OU=Corp,DC=old,DC=local' }
            @{ Name = 'Region'; DistinguishedName = 'OU=Region,OU=Corp,DC=old,DC=local' }
            @{ Name = 'Corp'; DistinguishedName = 'OU=Corp,DC=old,DC=local' }
        ) | Set-Content (Join-Path $b 'ous.json')
        ConvertTo-Json @(@{ Name = 'Zed'; SamAccountName = 'zed'; DistinguishedName = 'CN=Zed,OU=Team,OU=Region,OU=Corp,DC=old,DC=local' }, @{ Name = 'Existing User'; SamAccountName = 'existing' }) | Set-Content (Join-Path $b 'users.json')
        $global:Created.Clear()
        $r = @(Restore-ADTObject -Path $b -Include OU, User -WhatIf)
        ($r | Where-Object Type -eq 'OU')[0].Action | Should -Be 'Skipped'
        ($r | Where-Object Type -eq 'OU')[1].Name | Should -Be 'OU=Region,OU=Corp,DC=contoso,DC=com'
        ($r | Where-Object Type -eq 'OU')[2].Action | Should -Be 'WouldCreate'
        ($r | Where-Object Name -eq 'zed').Detail | Should -Match 'OU=Team,OU=Region,OU=Corp,DC=contoso,DC=com'
        ($r | Where-Object Name -eq 'zed').Detail | Should -Match 'disabled'
        ($r | Where-Object Name -eq 'existing').Action | Should -Be 'Skipped'
        $global:Created.Count | Should -Be 0
    }
    It 'reads v1 CSV backups' {
        $b = Join-Path $env:ADT_OUTPUT_ROOT 'v1backup'
        New-Item -ItemType Directory $b -Force | Out-Null
        "Name,SamAccountName,Enabled,Department,Title,LastLogonDate`nOld Timer,oldtimer,True,IT,Admin," | Set-Content (Join-Path $b 'Users_Backup.csv')
        $r = @(Restore-ADTObject -Path $b -Include User -WhatIf)
        $r[0].Action | Should -Be 'WouldCreate'
        $r[0].Detail | Should -Match 'CN=Users,DC=contoso,DC=com'
    }
    It 'finds inactive users but skips service, built-in and recent accounts' {
        $u = @(Get-ADTInactiveUser -Days 90)
        @($u.SamAccountName) | Should -Contain 'existing'
        @($u.SamAccountName) | Should -Not -Contain 'svc-sql'
        @($u.SamAccountName) | Should -Not -Contain 'krbtgt'
        @($u.SamAccountName) | Should -Not -Contain 'Administrator'
        @($u.SamAccountName) | Should -Not -Contain 'recent'
        @($u.SamAccountName) | Should -Not -Contain 'never'
        @(Get-ADTInactiveUser -Days 90 -IncludeNeverLoggedOn).SamAccountName | Should -Contain 'never'
    }
    It 'builds an inventory report with stale accounts and unsupported Windows flagged' {
        $out = Join-Path $env:ADT_OUTPUT_ROOT 'inv'
        $r = Get-ADTInventory -OutputPath $out -StaleDays 90
        $r.Summary.Users | Should -Be 6
        $r.Summary.UnsupportedOS | Should -Be 1
        $r.Summary.StaleUsers | Should -BeGreaterOrEqual 2
        ($r.OUs | Select-Object -First 1).LinkedGPOs | Should -Be 2
        ($r.DomainControllers | Select-Object -First 1).Support | Should -Match '2027'
        Join-Path $out 'AD_Inventory.html' | Should -Exist
        Join-Path $out 'Users.csv' | Should -Exist
    }
    It 'previews disabling without changing anything' {
        $global:Created.Clear()
        $r = @(Get-ADTInactiveUser -Days 90 | Disable-ADTInactiveUser -WhatIf)
        $r[0].Action | Should -Be 'WouldDisable'
        $global:Created.Count | Should -Be 0
    }
}

Describe 'Interfaces' {
    It 'turns objects into a grid table with a selection column' {
        $dt = InModule { ConvertTo-ADTDataTable -InputObject @([pscustomobject]@{ A = 1; B = @('x', 'y') }) -Selectable }
        $dt.Columns.Contains('Select') | Should -BeTrue
        $dt.Rows[0]['B'] | Should -Be 'x; y'
    }
    It 'builds the window without showing it (Windows only)' {
        if (-not (Test-ADTGuiAvailable)) { return }
        $f = Show-ADTGui -NoShow
        $f.Text | Should -Match 'AD & DNS Toolkit'
        (InModule { $script:ADTGui.Pages.Count }) | Should -Be 14
        $f.Dispose()
    }
}
