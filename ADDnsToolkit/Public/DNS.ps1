# ==================================================================================
# AD & DNS Toolkit - DNS: records, zones, backup/restore, health, stale records, forwarders
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

$script:ADTProtectedTypes = @('SOA', 'NS')

function Get-ADTDnsParam {
    param([string]$ComputerName)
    $p = @{}
    if ($ComputerName) { $p['ComputerName'] = $ComputerName }
    $p
}

function Test-ADTLocalComputer {
    param([string]$ComputerName)
    if (-not $ComputerName) { return $true }
    $n = $ComputerName.ToLowerInvariant()
    $me = "$([Environment]::MachineName)".ToLowerInvariant()
    $n -in @('.', 'localhost', '127.0.0.1', '::1', $me) -or $n.StartsWith("$me.")
}

function Get-ADTDnsFolder {
    <# The %windir%\System32\dns folder of a DNS server, locally or through the admin$ share. #>
    param([string]$ComputerName)
    if (Test-ADTLocalComputer $ComputerName) { return (Join-Path $env:windir 'System32\dns') }
    "\\$ComputerName\admin$\System32\dns"
}

function ConvertTo-ADTDnsRecordView {
    <# Flattens a DnsServerResourceRecord into plain properties (CSV/JSON/grid friendly). #>
    param([Parameter(Mandatory)]$Record, [string]$ZoneName, [string]$ComputerName)
    $rd = $Record.RecordData
    $type = "$($Record.RecordType)"
    $pref = $null
    $data = switch ($type) {
        'A' { "$($rd.IPv4Address)" }
        'AAAA' { "$($rd.IPv6Address)" }
        'CNAME' { "$($rd.HostNameAlias)" }
        'MX' { $pref = $rd.Preference; "$($rd.MailExchange)" }
        'TXT' { "$($rd.DescriptiveText)" }
        'PTR' { "$($rd.PtrDomainName)" }
        'NS' { "$($rd.NameServer)" }
        'SRV' { '{0} {1} {2} {3}' -f $rd.Priority, $rd.Weight, $rd.Port, $rd.DomainName }
        'SOA' { '{0} {1} serial {2}' -f $rd.PrimaryServer, $rd.ResponsiblePerson, $rd.SerialNumber }
        default { "$rd" }
    }
    $ts = $Record.Timestamp
    $ttl = $null
    if ($Record.TimeToLive) { $ttl = [int]([timespan]$Record.TimeToLive).TotalSeconds }
    [pscustomobject][ordered]@{
        ZoneName = $ZoneName; HostName = $Record.HostName; RecordType = $type; Data = $data; Preference = $pref; TTL = $ttl
        Dynamic = [bool]$ts; Timestamp = $ts; AgeDays = $(if ($ts) { [int]((Get-Date) - [datetime]$ts).TotalDays } else { $null }); Server = $ComputerName
    }
}

function Get-ADTDnsServer {
    <#
    .SYNOPSIS
        Lists DNS servers to manage: domain controllers first, then this computer's DNS client servers.
    #>
    [CmdletBinding()]
    param()
    $list = [Collections.Generic.List[string]]::new()
    if (Test-ADTModule 'ActiveDirectory') {
        try { Get-ADDomainController -Filter * -ErrorAction Stop | ForEach-Object { if ($_.HostName -and -not $list.Contains($_.HostName)) { $list.Add($_.HostName) } } }
        catch { Write-Verbose "DC lookup failed: $($_.Exception.Message)" }
    }
    if (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue) {
        try {
            Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ -and $_ -notlike '127.*' } |
                ForEach-Object { if (-not $list.Contains($_)) { $list.Add($_) } }
        }
        catch { Write-Verbose 'No DNS client info' }
    }
    if (Get-Service -Name DNS -ErrorAction SilentlyContinue) { if (-not $list.Contains('localhost')) { $list.Insert(0, 'localhost') } }
    if (-not $list.Count) { $list.Add('localhost') }
    @($list)
}

function Get-ADTDnsZone {
    <#
    .SYNOPSIS
        Lists the zones on a DNS server with type, replication and dynamic-update settings.
    #>
    [CmdletBinding()]
    param([string]$ComputerName, [switch]$IncludeAutoCreated)
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    @(Get-DnsServerZone @p -ErrorAction Stop | Where-Object { $IncludeAutoCreated -or -not $_.IsAutoCreated } | ForEach-Object {
            [pscustomobject][ordered]@{
                ZoneName = $_.ZoneName; ZoneType = "$($_.ZoneType)"; IsDsIntegrated = $_.IsDsIntegrated; ReplicationScope = "$($_.ReplicationScope)"
                DynamicUpdate = "$($_.DynamicUpdate)"; IsReverseLookupZone = $_.IsReverseLookupZone; IsAutoCreated = $_.IsAutoCreated; IsPaused = $_.IsPaused; IsSigned = $_.IsSigned
            }
        })
}

function Get-ADTDnsRecord {
    <#
    .SYNOPSIS
        Lists DNS records as flat objects (ZoneName, HostName, RecordType, Data, TTL, Timestamp, AgeDays).
    .DESCRIPTION
        The output exports cleanly to CSV and can be re-imported with Import-ADTDnsRecord.
    .EXAMPLE
        Get-ADTDnsRecord -ZoneName contoso.com -Name 'web*' -RecordType A, CNAME
    .EXAMPLE
        Get-ADTDnsRecord -ZoneName contoso.com | Export-Csv records.csv -NoTypeInformation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$ZoneName,
        [string]$ComputerName,
        [string]$Name = '*',
        [string[]]$RecordType
    )
    begin { Assert-ADTModule DnsServer }
    process {
        $p = Get-ADTDnsParam $ComputerName
        Get-DnsServerResourceRecord -ZoneName $ZoneName @p -ErrorAction Stop |
            Where-Object { $_.HostName -like $Name -and (-not $RecordType -or "$($_.RecordType)" -in $RecordType) } |
            ForEach-Object { ConvertTo-ADTDnsRecordView -Record $_ -ZoneName $ZoneName -ComputerName $ComputerName }
    }
}

function Add-ADTDnsRecord {
    <#
    .SYNOPSIS
        Adds an A, AAAA, CNAME, MX, TXT or PTR record, with input validation.
    .EXAMPLE
        Add-ADTDnsRecord -ZoneName contoso.com -Name web01 -Type A -Data 10.0.0.25 -CreatePtr
    .EXAMPLE
        Add-ADTDnsRecord -ZoneName contoso.com -Name '@' -Type MX -Data mail.contoso.com -Preference 10
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$ZoneName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias('HostName')][string]$Name,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias('RecordType')][ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'TXT', 'PTR')][string]$Type,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Data,
        [Parameter(ValueFromPipelineByPropertyName)][ValidateRange(0, 65535)][int]$Preference = 10,
        [Parameter(ValueFromPipelineByPropertyName)][Alias('TTL')][int]$TimeToLiveSeconds = 0,
        [switch]$CreatePtr,
        [string]$ComputerName
    )
    begin { Assert-ADTModule DnsServer }
    process {
        $p = Get-ADTDnsParam $ComputerName
        $res = [pscustomobject][ordered]@{ ZoneName = $ZoneName; HostName = $Name; RecordType = $Type; Data = $Data; Action = ''; Detail = '' }
        try {
            $common = @{ ZoneName = $ZoneName; Name = $Name; ErrorAction = 'Stop' } + $p
            if ($TimeToLiveSeconds -gt 0) { $common['TimeToLive'] = [timespan]::FromSeconds($TimeToLiveSeconds) }
            $ip = $null
            switch ($Type) {
                'A' { if (-not [Net.IPAddress]::TryParse($Data, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') { throw "'$Data' is not an IPv4 address" } }
                'AAAA' { if (-not [Net.IPAddress]::TryParse($Data, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetworkV6') { throw "'$Data' is not an IPv6 address" } }
                { $_ -in 'CNAME', 'MX', 'PTR' } { if ($Data -notmatch '^[A-Za-z0-9_]([A-Za-z0-9_\-]{0,62})(\.[A-Za-z0-9_\-]{1,63})*\.?$') { throw "'$Data' is not a valid host name" } }
            }
            if ($PSCmdlet.ShouldProcess("$Name.$ZoneName $Type $Data", 'Add DNS record')) {
                switch ($Type) {
                    'A' { Add-DnsServerResourceRecordA @common -IPv4Address $Data -CreatePtr:$CreatePtr }
                    'AAAA' { Add-DnsServerResourceRecordAAAA @common -IPv6Address $Data -CreatePtr:$CreatePtr }
                    'CNAME' { Add-DnsServerResourceRecordCName @common -HostNameAlias $Data }
                    'MX' { Add-DnsServerResourceRecordMX @common -MailExchange $Data -Preference ([uint16]$Preference) }
                    'TXT' { Add-DnsServerResourceRecord @common -Txt -DescriptiveText $Data }
                    'PTR' { Add-DnsServerResourceRecordPtr @common -PtrDomainName $Data }
                }
                $res.Action = 'Added'
                Write-ADTLog "Added DNS $Type $Name.$ZoneName -> $Data" Change
            }
            else { $res.Action = 'WouldAdd' }
        }
        catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message }
        $res
    }
}

function Import-ADTDnsRecord {
    <#
    .SYNOPSIS
        Adds DNS records from a CSV (skipping ones that already exist).
    .DESCRIPTION
        Columns: ZoneName (optional if -ZoneName is given), Name or HostName, Type or RecordType,
        Data (or the v1 columns IPAddress / AliasTarget / PtrTarget), Preference, TTL.
        A CSV exported from Get-ADTDnsRecord imports as-is. SOA and NS rows are ignored.
    .EXAMPLE
        Import-ADTDnsRecord -CsvPath .\Samples\DnsRecords.csv -ZoneName contoso.com -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string]$CsvPath, [string]$ZoneName, [string]$ComputerName)
    Assert-ADTModule DnsServer
    if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
    $p = Get-ADTDnsParam $ComputerName
    $existing = @{}
    foreach ($r in @(Import-Csv $CsvPath)) {
        $g = { param([string[]]$Names) foreach ($n in $Names) { if ($r.PSObject.Properties[$n] -and "$($r.$n)".Trim()) { return "$($r.$n)".Trim() } }; '' }
        $zone = & $g 'ZoneName'; if (-not $zone) { $zone = $ZoneName }
        $name = & $g 'Name', 'HostName'
        $type = (& $g 'Type', 'RecordType').ToUpperInvariant()
        $data = & $g 'Data', 'IPAddress', 'AliasTarget', 'PtrTarget', 'MailExchange'
        if ($type -in $script:ADTProtectedTypes) { continue }
        if (-not $zone -or -not $name -or -not $type -or -not $data) {
            [pscustomobject][ordered]@{ ZoneName = $zone; HostName = $name; RecordType = $type; Data = $data; Action = 'Invalid'; Detail = 'ZoneName, Name, Type and Data are required' }
            continue
        }
        if ($type -notin 'A', 'AAAA', 'CNAME', 'MX', 'TXT', 'PTR') {
            [pscustomobject][ordered]@{ ZoneName = $zone; HostName = $name; RecordType = $type; Data = $data; Action = 'Skipped'; Detail = "Type $type is not supported for import" }
            continue
        }
        if (-not $existing.ContainsKey($zone)) {
            $existing[$zone] = @{}
            try { Get-ADTDnsRecord -ZoneName $zone -ComputerName $ComputerName | ForEach-Object { $existing[$zone]["$($_.HostName)|$($_.RecordType)|$($_.Data)".ToLowerInvariant().TrimEnd('.')] = $true } }
            catch { [pscustomobject][ordered]@{ ZoneName = $zone; HostName = $name; RecordType = $type; Data = $data; Action = 'Failed'; Detail = "Zone not readable: $($_.Exception.Message)" }; continue }
        }
        if ($existing[$zone].ContainsKey("$name|$type|$data".ToLowerInvariant().TrimEnd('.'))) {
            [pscustomobject][ordered]@{ ZoneName = $zone; HostName = $name; RecordType = $type; Data = $data; Action = 'Skipped'; Detail = 'Already exists' }
            continue
        }
        $prm = @{ ZoneName = $zone; Name = $name; Type = $type; Data = $data }
        $pref = & $g 'Preference'; if ($pref) { $prm['Preference'] = [int]$pref }
        $ttl = & $g 'TTL'; if ($ttl) { $prm['TimeToLiveSeconds'] = [int]$ttl }
        Add-ADTDnsRecord @prm @p -WhatIf:$WhatIfPreference -Confirm:$false
    }
}

function Remove-ADTDnsRecordCore {
    param([string]$ZoneName, [string]$HostName, [string]$RecordType, [string]$Data, [string]$ComputerName)
    $p = Get-ADTDnsParam $ComputerName
    $live = @(Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $HostName -RRType $RecordType @p -ErrorAction Stop)
    if ($Data) { $live = @($live | Where-Object { (ConvertTo-ADTDnsRecordView -Record $_ -ZoneName $ZoneName).Data.TrimEnd('.') -eq $Data.TrimEnd('.') }) }
    if (-not $live.Count) { throw 'Record not found' }
    foreach ($rr in $live) { Remove-DnsServerResourceRecord -ZoneName $ZoneName -InputObject $rr -Force @p -ErrorAction Stop }
    $live.Count
}

function Remove-ADTDnsRecord {
    <#
    .SYNOPSIS
        Removes specific DNS records (by name, type and optionally data). SOA and NS records are protected.
    .EXAMPLE
        Remove-ADTDnsRecord -ZoneName contoso.com -Name web01 -Type A -Data 10.0.0.25
    .EXAMPLE
        Get-ADTDnsRecord -ZoneName contoso.com -Name 'test*' | Remove-ADTDnsRecord -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$ZoneName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias('HostName')][string]$Name,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias('RecordType')][string]$Type,
        [Parameter(ValueFromPipelineByPropertyName)][string]$Data,
        [Parameter(ValueFromPipelineByPropertyName)][Alias('Server')][string]$ComputerName
    )
    begin { Assert-ADTModule DnsServer }
    process {
        $res = [pscustomobject][ordered]@{ ZoneName = $ZoneName; HostName = $Name; RecordType = $Type; Data = $Data; Action = ''; Detail = '' }
        if ($Type -in $script:ADTProtectedTypes) { $res.Action = 'Skipped'; $res.Detail = "$Type records are protected"; return $res }
        $label = "$Name.$ZoneName $Type" + $(if ($Data) { " $Data" } else { ' (all records of this type)' })
        if ($PSCmdlet.ShouldProcess($label, 'Remove DNS record')) {
            try { $n = Remove-ADTDnsRecordCore -ZoneName $ZoneName -HostName $Name -RecordType $Type -Data $Data -ComputerName $ComputerName; $res.Action = 'Removed'; $res.Detail = "$n record(s)"; Write-ADTLog "Removed DNS $label" Change }
            catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message }
        }
        else { $res.Action = 'WouldRemove' }
        $res
    }
}

# ----------------------------------------------------------------------------------
# Zone backup and restore
# ----------------------------------------------------------------------------------
function Backup-ADTDnsZone {
    <#
    .SYNOPSIS
        Backs up DNS zones: the zone file (Export-DnsServerZone), every record as JSON, and the zone settings.
    .DESCRIPTION
        Export-DnsServerZone can only write into the server's %windir%\System32\dns folder, so the
        file is exported there and copied into the backup folder (through admin$ for a remote server).
        The JSON copy works even without admin$ access and lets Restore-ADTDnsZone re-add records.
    .EXAMPLE
        Backup-ADTDnsZone
    .EXAMPLE
        Backup-ADTDnsZone -ComputerName dc01 -ZoneName contoso.com, _msdcs.contoso.com
    #>
    [CmdletBinding()]
    param([string]$ComputerName, [string[]]$ZoneName, [string]$OutputPath, [switch]$IncludeAutoCreated)
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    $server = if ($ComputerName) { $ComputerName } else { [Environment]::MachineName }
    $folder = New-ADTOutputFolder -Category 'DNS_Backups' -Path $OutputPath
    $zones = @(Get-DnsServerZone @p -ErrorAction Stop | Where-Object {
            ($IncludeAutoCreated -or -not $_.IsAutoCreated) -and $_.ZoneName -ne 'TrustAnchors' -and "$($_.ZoneType)" -in 'Primary', 'Secondary', 'Stub' -and (-not $ZoneName -or $_.ZoneName -in $ZoneName)
        })
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $dnsDir = Get-ADTDnsFolder $ComputerName
    $entries = foreach ($z in $zones) {
        $safe = ConvertTo-ADTSafeFileName $z.ZoneName
        $entry = [ordered]@{ ZoneName = $z.ZoneName; ZoneFile = $null; RecordsFile = $null; Records = 0; Status = 'OK'; Detail = '' }
        Write-ADTStatus "Backing up $($z.ZoneName)..." Step
        try {
            $recs = @(Get-ADTDnsRecord -ZoneName $z.ZoneName -ComputerName $ComputerName)
            ConvertTo-Json -InputObject $recs -Depth 3 | Set-Content (Join-Path $folder "$safe.records.json") -Encoding UTF8
            $entry.RecordsFile = "$safe.records.json"; $entry.Records = $recs.Count
        }
        catch { $entry.Status = 'Warn'; $entry.Detail = "Records not exported: $($_.Exception.Message)" }
        $aging = $null
        try { $aging = Get-DnsServerZoneAging -Name $z.ZoneName @p -ErrorAction Stop } catch { $aging = $null }
        $entry.Settings = [ordered]@{
            ZoneType = "$($z.ZoneType)"; IsDsIntegrated = $z.IsDsIntegrated; ReplicationScope = "$($z.ReplicationScope)"; DynamicUpdate = "$($z.DynamicUpdate)"
            IsReverseLookupZone = $z.IsReverseLookupZone; AgingEnabled = $(if ($aging) { $aging.AgingEnabled } else { $null })
            NoRefreshDays = $(if ($aging) { [int]$aging.NoRefreshInterval.TotalDays } else { $null }); RefreshDays = $(if ($aging) { [int]$aging.RefreshInterval.TotalDays } else { $null })
        }
        if ("$($z.ZoneType)" -eq 'Primary') {
            $file = "ADT_${safe}_$stamp.dns"
            try {
                Export-DnsServerZone -Name $z.ZoneName -FileName $file @p -ErrorAction Stop
                $src = Join-Path $dnsDir $file
                try {
                    Copy-Item -Path $src -Destination (Join-Path $folder "$safe.dns") -ErrorAction Stop
                    Remove-Item -Path $src -ErrorAction SilentlyContinue
                    $entry.ZoneFile = "$safe.dns"
                }
                catch { $entry.Status = 'Warn'; $entry.Detail = "Zone file exported on $server as %windir%\System32\dns\$file but could not be copied ($($_.Exception.Message)). The JSON records copy is complete." }
            }
            catch { $entry.Status = 'Warn'; $entry.Detail = "Export-DnsServerZone failed: $($_.Exception.Message)" }
        }
        [pscustomobject]$entry
    }
    $entries = @($entries)
    [pscustomobject][ordered]@{ Tool = 'AD & DNS Toolkit'; Version = $script:ADTVersion; Type = 'DnsZones'; Server = $server; Created = (Get-Date).ToString('o'); Zones = $entries } |
        ConvertTo-Json -Depth 5 | Set-Content (Join-Path $folder 'manifest.json') -Encoding UTF8
    Write-ADTLog "DNS backup of $($entries.Count) zones on $server -> $folder"
    Write-ADTStatus "Backed up $($entries.Count) zones from $server to $folder" Ok
    $entries | ForEach-Object { [pscustomobject]@{ ZoneName = $_.ZoneName; Records = $_.Records; ZoneFile = [bool]$_.ZoneFile; Status = $_.Status; Detail = $_.Detail; Folder = $folder } }
}

function Restore-ADTDnsZone {
    <#
    .SYNOPSIS
        Restores DNS zones from a Backup-ADTDnsZone folder (or v1 *_Backup.dns files).
    .DESCRIPTION
        Missing zone: the zone file is copied to the server, loaded with Add-DnsServerPrimaryZone
        -LoadExisting, then converted back to AD-integrated with its original replication scope and
        dynamic-update setting. Existing zone (or -Mode Records): only records that are missing are
        added from the JSON copy; nothing is overwritten or removed. Supports -WhatIf.
    .EXAMPLE
        Restore-ADTDnsZone -Path .\DNS_Backups_20261028_101500 -ZoneName contoso.com -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ZoneName,
        [string]$ComputerName,
        [ValidateSet('Auto', 'Records')][string]$Mode = 'Auto',
        [switch]$KeepFileBacked
    )
    Assert-ADTModule DnsServer
    if (-not (Test-Path $Path -PathType Container)) { throw "Backup folder not found: $Path" }
    $p = Get-ADTDnsParam $ComputerName
    $manifestFile = Join-Path $Path 'manifest.json'
    $zones = if (Test-Path $manifestFile) { @((Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json).Zones) }
    else {
        @(Get-ChildItem -Path $Path -Filter '*.dns' | ForEach-Object { [pscustomobject]@{ ZoneName = ($_.BaseName -replace '_Backup$', ''); ZoneFile = $_.Name; RecordsFile = $null; Settings = $null } })
    }
    if ($ZoneName) { $zones = @($zones | Where-Object { $_.ZoneName -in $ZoneName }) }
    if (-not $zones.Count) { throw "No zones to restore in $Path" }
    $dnsDir = Get-ADTDnsFolder $ComputerName
    foreach ($z in $zones) {
        $res = [pscustomobject][ordered]@{ ZoneName = $z.ZoneName; Action = ''; Detail = '' }
        $current = Get-DnsServerZone -Name $z.ZoneName @p -ErrorAction SilentlyContinue
        if ($current -or $Mode -eq 'Records') {
            if (-not $current) { $res.Action = 'Failed'; $res.Detail = 'Zone does not exist; use -Mode Auto to re-create it'; $res; continue }
            if (-not $z.RecordsFile -or -not (Test-Path (Join-Path $Path $z.RecordsFile))) { $res.Action = 'Skipped'; $res.Detail = 'Zone exists and the backup has no records file'; $res; continue }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("adt_" + [guid]::NewGuid().ToString('N') + '.csv')
            (Get-Content (Join-Path $Path $z.RecordsFile) -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $_ } | Export-Csv $tmp -NoTypeInformation -Encoding UTF8
            $r = @(Import-ADTDnsRecord -CsvPath $tmp -ZoneName $z.ZoneName -ComputerName $ComputerName -WhatIf:$WhatIfPreference)
            Remove-Item $tmp -ErrorAction SilentlyContinue
            $res.Action = $(if ($WhatIfPreference) { 'WouldAddRecords' } else { 'RecordsAdded' })
            $res.Detail = ($r | Group-Object Action | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
            $res; continue
        }
        if (-not $z.ZoneFile -or -not (Test-Path (Join-Path $Path $z.ZoneFile))) { $res.Action = 'Failed'; $res.Detail = 'Zone missing and no zone file in the backup'; $res; continue }
        $set = $z.Settings
        $target = 'ADTRestore_' + (ConvertTo-ADTSafeFileName $z.ZoneName) + '.dns'
        $toAd = $set -and "$($set.IsDsIntegrated)" -eq 'True' -and -not $KeepFileBacked
        if ($PSCmdlet.ShouldProcess($z.ZoneName, 'Re-create zone from backup' + $(if ($toAd) { " (AD-integrated, $($set.ReplicationScope))" } else { ' (file-backed)' }))) {
            try {
                Copy-Item -Path (Join-Path $Path $z.ZoneFile) -Destination (Join-Path $dnsDir $target) -Force -ErrorAction Stop
                Add-DnsServerPrimaryZone -Name $z.ZoneName -ZoneFile $target -LoadExisting @p -ErrorAction Stop
                if ($toAd) {
                    $scope = if ("$($set.ReplicationScope)" -in 'Forest', 'Domain', 'Legacy') { "$($set.ReplicationScope)" } else { 'Domain' }
                    ConvertTo-DnsServerPrimaryZone -Name $z.ZoneName -ReplicationScope $scope -Force @p -ErrorAction Stop
                }
                if ($set -and "$($set.DynamicUpdate)" -in 'None', 'Secure', 'NonsecureAndSecure') {
                    $du = "$($set.DynamicUpdate)"; if ($du -eq 'Secure' -and -not $toAd) { $du = 'None' }
                    Set-DnsServerPrimaryZone -Name $z.ZoneName -DynamicUpdate $du @p -ErrorAction SilentlyContinue
                }
                if ($set -and "$($set.AgingEnabled)" -eq 'True') { Set-DnsServerZoneAging -Name $z.ZoneName -Aging $true @p -ErrorAction SilentlyContinue }
                $res.Action = 'Restored'; $res.Detail = $(if ($toAd) { "AD-integrated ($scope)" } else { "File-backed ($target)" })
                Write-ADTLog "Restored DNS zone $($z.ZoneName) from $Path" Change
            }
            catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message }
        }
        else { $res.Action = 'WouldRestore'; $res.Detail = "From $($z.ZoneFile)" }
        $res
    }
}

# ----------------------------------------------------------------------------------
# Stale records
# ----------------------------------------------------------------------------------
function Find-ADTStaleDnsRecord {
    <#
    .SYNOPSIS
        Finds dynamically registered records whose timestamp is older than the threshold.
    .DESCRIPTION
        Only dynamic records (with a timestamp) are considered; static records, SOA and NS are
        never returned. The default threshold is the zone's no-refresh + refresh interval when
        aging is enabled, otherwise 30 days. _msdcs zones are skipped unless -IncludeMsdcs.
        Read-only.
    .EXAMPLE
        Find-ADTStaleDnsRecord -ZoneName contoso.com -OlderThanDays 60
    #>
    [CmdletBinding()]
    param([string]$ComputerName, [string[]]$ZoneName, [ValidateRange(1, 3650)][int]$OlderThanDays, [string[]]$ExcludeName = @(), [switch]$IncludeMsdcs)
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    $zones = @(Get-DnsServerZone @p -ErrorAction Stop | Where-Object {
            "$($_.ZoneType)" -eq 'Primary' -and -not $_.IsAutoCreated -and $_.ZoneName -ne 'TrustAnchors' -and
            (-not $ZoneName -or $_.ZoneName -in $ZoneName) -and ($IncludeMsdcs -or $_.ZoneName -notlike '_msdcs.*')
        })
    $skip = @('@', 'DomainDnsZones', 'ForestDnsZones') + $ExcludeName
    foreach ($z in $zones) {
        $days = $OlderThanDays
        if (-not $days) {
            $days = 30
            try {
                $a = Get-DnsServerZoneAging -Name $z.ZoneName @p -ErrorAction Stop
                if ($a.AgingEnabled) { $days = [int]($a.NoRefreshInterval.TotalDays + $a.RefreshInterval.TotalDays) }
            }
            catch { Write-Verbose "No aging info for $($z.ZoneName)" }
        }
        $cut = (Get-Date).AddDays(-$days)
        Get-DnsServerResourceRecord -ZoneName $z.ZoneName @p -ErrorAction SilentlyContinue |
            Where-Object { $_.Timestamp -and [datetime]$_.Timestamp -lt $cut -and "$($_.RecordType)" -notin $script:ADTProtectedTypes -and $_.HostName -notin $skip } |
            ForEach-Object { $v = ConvertTo-ADTDnsRecordView -Record $_ -ZoneName $z.ZoneName -ComputerName $ComputerName; $v | Add-Member -NotePropertyName ThresholdDays -NotePropertyValue $days -PassThru }
    }
}

function Remove-ADTStaleDnsRecord {
    <#
    .SYNOPSIS
        Removes stale dynamic records, after saving them to a file you can re-import.
    .DESCRIPTION
        Takes records from Find-ADTStaleDnsRecord (pipeline) or finds them itself. Before anything
        is removed, the records are written to StaleRecords.csv/json in the output folder; run
        Import-ADTDnsRecord -CsvPath <that csv> to put them back. -SkipIfResponding keeps A records
        whose address still answers ping or common ports. Asks for confirmation; supports -WhatIf.
    .EXAMPLE
        Find-ADTStaleDnsRecord -OlderThanDays 90 | Remove-ADTStaleDnsRecord -SkipIfResponding -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ValueFromPipeline)][object[]]$InputObject,
        [string]$ComputerName,
        [string[]]$ZoneName,
        [ValidateRange(1, 3650)][int]$OlderThanDays,
        [switch]$SkipIfResponding,
        [string]$OutputPath
    )
    begin { $items = [Collections.Generic.List[object]]::new() }
    process { foreach ($o in @($InputObject)) { if ($o) { $items.Add($o) } } }
    end {
        Assert-ADTModule DnsServer
        if (-not $items.Count) {
            $prm = @{ ComputerName = $ComputerName }
            if ($ZoneName) { $prm['ZoneName'] = $ZoneName }
            if ($OlderThanDays) { $prm['OlderThanDays'] = $OlderThanDays }
            foreach ($r in @(Find-ADTStaleDnsRecord @prm)) { $items.Add($r) }
        }
        if (-not $items.Count) { Write-ADTStatus 'No stale records found.' Ok; return }
        $folder = $null
        if (-not $WhatIfPreference) {
            $folder = New-ADTOutputFolder -Category 'DNS_StaleCleanup' -Path $OutputPath
            $items | Select-Object ZoneName, HostName, RecordType, Data, Preference, TTL, Timestamp, AgeDays | Export-Csv (Join-Path $folder 'StaleRecords.csv') -NoTypeInformation -Encoding UTF8
            ConvertTo-Json -InputObject @($items) -Depth 3 | Set-Content (Join-Path $folder 'StaleRecords.json') -Encoding UTF8
            Write-ADTStatus "Saved $($items.Count) records to $folder before removal (re-import with Import-ADTDnsRecord)." Info
        }
        $ping = [Net.NetworkInformation.Ping]::new()
        $results = foreach ($r in $items) {
            $res = [pscustomobject][ordered]@{ ZoneName = $r.ZoneName; HostName = $r.HostName; RecordType = $r.RecordType; Data = $r.Data; AgeDays = $r.AgeDays; Action = ''; Detail = '' }
            if ($SkipIfResponding -and $r.RecordType -in 'A', 'AAAA') {
                $alive = $false
                try { $alive = $ping.Send($r.Data, 800).Status -eq 'Success' } catch { $alive = $false }
                if (-not $alive) { foreach ($port in 445, 3389, 22, 80, 443) { if (Test-ADTTcpPort -ComputerName $r.Data -Port $port -TimeoutMs 400) { $alive = $true; break } } }
                if ($alive) { $res.Action = 'Kept'; $res.Detail = 'Address still responds'; $res; continue }
            }
            $srv = if ($r.PSObject.Properties['Server'] -and $r.Server) { $r.Server } else { $ComputerName }
            if ($PSCmdlet.ShouldProcess("$($r.HostName).$($r.ZoneName) $($r.RecordType) $($r.Data) ($($r.AgeDays) days old)", 'Remove stale DNS record')) {
                try { $null = Remove-ADTDnsRecordCore -ZoneName $r.ZoneName -HostName $r.HostName -RecordType $r.RecordType -Data $r.Data -ComputerName $srv; $res.Action = 'Removed'; Write-ADTLog "Removed stale DNS $($r.RecordType) $($r.HostName).$($r.ZoneName) $($r.Data)" Change }
                catch { $res.Action = 'Failed'; $res.Detail = $_.Exception.Message }
            }
            else { $res.Action = 'WouldRemove' }
            $res
        }
        $ping.Dispose()
        $results = @($results)
        if ($folder) { $results | Export-Csv (Join-Path $folder 'CleanupResults.csv') -NoTypeInformation -Encoding UTF8 }
        Write-ADTStatus ('Stale records - ' + (($results | Group-Object Action | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', ')) Ok
        $results
    }
}

# ----------------------------------------------------------------------------------
# Health
# ----------------------------------------------------------------------------------
function Test-ADTDnsHealth {
    <#
    .SYNOPSIS
        DNS server health check with Pass / Warn / Fail results and fixes.
    .DESCRIPTION
        Service and port 53, every zone (paused, shut down, insecure dynamic updates, aging),
        server scavenging, forwarders (each one is asked to resolve a name), recursion, the AD
        locator records (_ldap._tcp.dc._msdcs), recent DNS Server errors and stale records. Read-only.
    .EXAMPLE
        Test-ADTDnsHealth -ComputerName dc01.contoso.com
    #>
    [CmdletBinding()]
    param([string]$ComputerName, [ValidateRange(1, 3650)][int]$StaleDays = 30, [string]$OutputPath, [switch]$NoReport)
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    $server = if ($ComputerName) { $ComputerName } else { 'localhost' }
    $checks = [Collections.Generic.List[object]]::new()
    Write-ADTStatus "Checking DNS on $server..." Step
    try {
        $cim = @{ ClassName = 'Win32_Service'; Filter = "Name='DNS'"; ErrorAction = 'Stop' }
        if (-not (Test-ADTLocalComputer $ComputerName)) { $cim['ComputerName'] = $ComputerName }
        $svc = Get-CimInstance @cim
        if ($svc) { $checks.Add((New-ADTCheck 'Service' 'DNS Server service' $server $(if ($svc.State -eq 'Running') { 'Pass' } else { 'Fail' }) "$($svc.State) (start: $($svc.StartMode))" 'Start-Service DNS and check the DNS Server event log.')) }
        else { $checks.Add((New-ADTCheck 'Service' 'DNS Server service' $server 'Fail' 'Not installed' 'Point the check at a DNS server.')) }
    }
    catch { $checks.Add((New-ADTCheck 'Service' 'DNS Server service' $server 'Warn' "Could not query: $($_.Exception.Message)" 'Allow CIM/WinRM from this computer.')) }
    $tcp = Test-ADTTcpPort -ComputerName $(if ($ComputerName) { $ComputerName } else { '127.0.0.1' }) -Port 53
    $checks.Add((New-ADTCheck 'Service' 'TCP port 53' $server $(if ($tcp) { 'Pass' } else { 'Fail' }) $(if ($tcp) { 'Answering' } else { 'Not answering' }) 'Check the firewall (DNS needs TCP and UDP 53).'))

    $zones = @(Get-DnsServerZone @p -ErrorAction Stop | Where-Object { -not $_.IsAutoCreated -and $_.ZoneName -ne 'TrustAnchors' })
    $agingZones = 0
    foreach ($z in $zones) {
        $n = $z.ZoneName
        if ("$($z.ZoneType)" -eq 'Forwarder') { continue }
        if ($z.IsPaused -or $z.IsShutdown) { $checks.Add((New-ADTCheck 'Zone' 'State' $n 'Fail' $(if ($z.IsPaused) { 'Paused' } else { 'Shut down' }) "Resume-DnsServerZone -Name $n")) }
        else { $checks.Add((New-ADTCheck 'Zone' 'State' $n 'Pass' "$($z.ZoneType)$(if ($z.IsDsIntegrated) { ", AD-integrated ($($z.ReplicationScope))" } else { ', file-backed' })" '')) }
        if ("$($z.ZoneType)" -eq 'Primary') {
            switch ("$($z.DynamicUpdate)") {
                'NonsecureAndSecure' { $checks.Add((New-ADTCheck 'Zone' 'Dynamic updates' $n 'Warn' 'Non-secure and secure: anyone on the network can register or overwrite names' $(if ($z.IsDsIntegrated) { "Set-DnsServerPrimaryZone -Name $n -DynamicUpdate Secure" } else { 'Make the zone AD-integrated, then allow secure updates only.' }))) }
                'Secure' { $checks.Add((New-ADTCheck 'Zone' 'Dynamic updates' $n 'Pass' 'Secure only' '')) }
                default { $checks.Add((New-ADTCheck 'Zone' 'Dynamic updates' $n 'Info' "$($z.DynamicUpdate)" '')) }
            }
            if ("$($z.DynamicUpdate)" -ne 'None') {
                try {
                    $a = Get-DnsServerZoneAging -Name $n @p -ErrorAction Stop
                    if ($a.AgingEnabled) { $agingZones++ }
                    $checks.Add((New-ADTCheck 'Zone' 'Aging' $n $(if ($a.AgingEnabled) { 'Pass' } else { 'Warn' }) $(if ($a.AgingEnabled) { "No-refresh $([int]$a.NoRefreshInterval.TotalDays) d, refresh $([int]$a.RefreshInterval.TotalDays) d" } else { 'Aging off: stale dynamic records are never scavenged' }) "Set-DnsServerZoneAging -Name $n -Aging `$true -NoRefreshInterval 7.00:00:00 -RefreshInterval 7.00:00:00"))
                }
                catch { Write-Verbose "Aging not readable for $n" }
            }
        }
    }
    try {
        $sc = Get-DnsServerScavenging @p -ErrorAction Stop
        $st = if ($sc.ScavengingState) { 'Pass' } elseif ($agingZones) { 'Warn' } else { 'Info' }
        $checks.Add((New-ADTCheck 'Server' 'Scavenging' $server $st $(if ($sc.ScavengingState) { "Every $([int]$sc.ScavengingInterval.TotalDays) days; last run $($sc.LastScavengeTime)" } else { 'Off on this server' }) 'Enable scavenging on one DNS server only: Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -ApplyOnAllZones'))
    }
    catch { Write-Verbose 'Scavenging not readable' }
    try {
        $fw = Get-DnsServerForwarder @p -ErrorAction Stop
        $ips = @($fw.IPAddress | ForEach-Object { "$_" } | Where-Object { $_ })
        if (-not $ips.Count) { $checks.Add((New-ADTCheck 'Server' 'Forwarders' $server 'Info' 'None - root hints are used' '')) }
        foreach ($ip in $ips) {
            $ok = $false
            try { $null = Resolve-DnsName -Name 'www.microsoft.com' -Server $ip -DnsOnly -QuickTimeout -ErrorAction Stop; $ok = $true } catch { $ok = $false }
            $checks.Add((New-ADTCheck 'Server' 'Forwarder' $ip $(if ($ok) { 'Pass' } else { 'Fail' }) $(if ($ok) { 'Resolves names' } else { 'Did not answer from this computer' }) 'Remove dead forwarders: Remove-DnsServerForwarder -IPAddress <ip>'))
        }
    }
    catch { Write-Verbose 'Forwarders not readable' }
    try { $rec = Get-DnsServerRecursion @p -ErrorAction Stop; $checks.Add((New-ADTCheck 'Server' 'Recursion' $server 'Info' $(if ($rec.Enable) { 'Enabled' } else { 'Disabled' }) '')) } catch { Write-Verbose 'Recursion not readable' }

    $dom = $env:USERDNSDOMAIN
    if (-not $dom -and (Test-ADTModule 'ActiveDirectory')) { try { $dom = (Get-ADDomain -ErrorAction Stop).DNSRoot } catch { $dom = $null } }
    if ($dom -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
        $q = "_ldap._tcp.dc._msdcs.$dom"
        try {
            $srv = @(Resolve-DnsName -Name $q -Type SRV -Server $(if ($ComputerName) { $ComputerName } else { '127.0.0.1' }) -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'SRV' })
            $checks.Add((New-ADTCheck 'Active Directory' 'DC locator records' $q $(if ($srv.Count) { 'Pass' } else { 'Fail' }) "$($srv.Count) domain controllers registered" 'Restart Netlogon on each DC (it re-registers its records) or run dcdiag /test:registerindns.'))
        }
        catch { $checks.Add((New-ADTCheck 'Active Directory' 'DC locator records' $q 'Fail' $_.Exception.Message 'Make sure the _msdcs zone exists and replicates; restart Netlogon on the DCs.')) }
    }
    try {
        $wev = @{ FilterHashtable = @{ LogName = 'DNS Server'; Level = 2; StartTime = (Get-Date).AddDays(-1) }; MaxEvents = 200; ErrorAction = 'Stop' }
        if (-not (Test-ADTLocalComputer $ComputerName)) { $wev['ComputerName'] = $ComputerName }
        $ev = @(Get-WinEvent @wev)
        $top = ($ev | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "event $($_.Name) x$($_.Count)" }) -join ', '
        $checks.Add((New-ADTCheck 'Server' 'Errors in the last 24 hours' $server $(if ($ev.Count) { 'Warn' } else { 'Pass' }) $(if ($ev.Count) { "$($ev.Count) errors: $top" } else { 'None' }) 'Review the DNS Server log in Event Viewer.'))
    }
    catch { if ("$($_.Exception.Message)" -match 'No events') { $checks.Add((New-ADTCheck 'Server' 'Errors in the last 24 hours' $server 'Pass' 'None' '')) } }
    try {
        $stale = @(Find-ADTStaleDnsRecord -ComputerName $ComputerName -OlderThanDays $StaleDays)
        $checks.Add((New-ADTCheck 'Records' "Dynamic records older than $StaleDays days" $server $(if ($stale.Count) { 'Warn' } else { 'Pass' }) "$($stale.Count) records" 'Review with Find-ADTStaleDnsRecord, then Remove-ADTStaleDnsRecord (keeps a backup), or enable aging and scavenging.'))
    }
    catch { Write-Verbose 'Stale check failed' }

    $overall = Get-ADTOverallStatus $checks
    $result = [pscustomobject][ordered]@{
        Server = $server; Overall = $overall; Pass = @($checks | Where-Object Status -eq 'Pass').Count; Warn = @($checks | Where-Object Status -eq 'Warn').Count
        Fail = @($checks | Where-Object Status -eq 'Fail').Count; Checks = @($checks); OutputFolder = $null; ReportPath = $null
    }
    if (-not $NoReport) {
        $folder = New-ADTOutputFolder -Category 'DNS_HealthCheck' -Path $OutputPath
        $checks | Export-Csv (Join-Path $folder 'DNS_HealthCheck.csv') -NoTypeInformation -Encoding UTF8
        ($checks | Format-Table Status, Category, Check, Target, Detail -AutoSize -Wrap | Out-String -Width 220) | Set-Content (Join-Path $folder 'DNS_HealthCheck.txt') -Encoding UTF8
        $cards = @(
            @{ Label = 'Overall'; Value = $overall; Tone = $(switch ($overall) { 'Fail' { 'bad' } 'Warn' { 'warn' } default { 'ok' } }) }
            @{ Label = 'Passed'; Value = $result.Pass; Tone = 'ok' }
            @{ Label = 'Warnings'; Value = $result.Warn; Tone = $(if ($result.Warn) { 'warn' } else { 'ok' }) }
            @{ Label = 'Failures'; Value = $result.Fail; Tone = $(if ($result.Fail) { 'bad' } else { 'ok' }) }
            @{ Label = 'Zones'; Value = $zones.Count }
        )
        $sections = @(@{ Title = 'Needs attention'; Data = @($checks | Where-Object { $_.Status -in 'Fail', 'Warn' }); Columns = @('Status', 'Category', 'Check', 'Target', 'Detail', 'Fix') })
        foreach ($cat in @($checks | Select-Object -ExpandProperty Category -Unique)) { $sections += @{ Title = $cat; Data = @($checks | Where-Object Category -eq $cat); Columns = @('Status', 'Check', 'Target', 'Detail') } }
        $result.ReportPath = New-ADTHtmlReport -Title 'DNS server health check' -Subtitle "$server - overall: $overall" -Cards $cards -Sections $sections -Path (Join-Path $folder 'DNS_HealthCheck.html')
        $result.OutputFolder = $folder
    }
    Write-ADTLog "DNS health check of $($server): $overall"
    Write-ADTStatus "DNS health: $overall - $($result.Pass) passed, $($result.Warn) warnings, $($result.Fail) failures." $(switch ($overall) { 'Fail' { 'Error' } 'Warn' { 'Warn' } default { 'Ok' } })
    $result
}

# ----------------------------------------------------------------------------------
# Conditional forwarders and diagnostics
# ----------------------------------------------------------------------------------
function Get-ADTConditionalForwarder {
    <#
    .SYNOPSIS
        Lists conditional forwarders on a DNS server.
    #>
    [CmdletBinding()]
    param([string]$ComputerName)
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    @(Get-DnsServerZone @p -ErrorAction Stop | Where-Object { "$($_.ZoneType)" -eq 'Forwarder' } | ForEach-Object {
            [pscustomobject][ordered]@{ ZoneName = $_.ZoneName; MasterServers = (@($_.MasterServers | ForEach-Object { "$_" }) -join ', '); IsDsIntegrated = $_.IsDsIntegrated; ReplicationScope = "$($_.ReplicationScope)" }
        })
}

function Add-ADTConditionalForwarder {
    <#
    .SYNOPSIS
        Adds a conditional forwarder (AD-replicated to the forest or domain, or stored on this server only).
    .EXAMPLE
        Add-ADTConditionalForwarder -Name fabrikam.com -MasterServers 10.1.0.10, 10.1.0.11 -ReplicationScope Forest
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$MasterServers,
        [ValidateSet('Forest', 'Domain', 'None')][string]$ReplicationScope = 'Forest',
        [string]$ComputerName
    )
    Assert-ADTModule DnsServer
    $p = Get-ADTDnsParam $ComputerName
    $ips = @($MasterServers | ForEach-Object { $_ -split '[,; ]+' } | Where-Object { $_ })
    foreach ($ip in $ips) { $tmp = $null; if (-not [Net.IPAddress]::TryParse($ip, [ref]$tmp)) { throw "'$ip' is not an IP address" } }
    if ($PSCmdlet.ShouldProcess("$Name -> $($ips -join ', ')", 'Add conditional forwarder')) {
        $prm = @{ Name = $Name; MasterServers = $ips; ErrorAction = 'Stop' } + $p
        if ($ReplicationScope -ne 'None') { $prm['ReplicationScope'] = $ReplicationScope }
        Add-DnsServerConditionalForwarderZone @prm
        Write-ADTLog "Added conditional forwarder $Name -> $($ips -join ', ') ($ReplicationScope)" Change
        Write-ADTStatus "Added conditional forwarder $Name" Ok
    }
}

function Remove-ADTConditionalForwarder {
    <#
    .SYNOPSIS
        Removes a conditional forwarder.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][Alias('ZoneName')][string]$Name, [string]$ComputerName)
    begin { Assert-ADTModule DnsServer }
    process {
        $p = Get-ADTDnsParam $ComputerName
        $z = Get-DnsServerZone -Name $Name @p -ErrorAction Stop
        if ("$($z.ZoneType)" -ne 'Forwarder') { throw "$Name is a $($z.ZoneType) zone, not a conditional forwarder." }
        if ($PSCmdlet.ShouldProcess($Name, 'Remove conditional forwarder')) {
            Remove-DnsServerZone -Name $Name -Force @p -ErrorAction Stop
            Write-ADTLog "Removed conditional forwarder $Name" Change
            Write-ADTStatus "Removed conditional forwarder $Name" Ok
        }
    }
}

function Test-ADTDnsResolution {
    <#
    .SYNOPSIS
        Resolves a name (optionally against a specific DNS server) and returns the answers.
    .EXAMPLE
        Test-ADTDnsResolution -Name _ldap._tcp.contoso.com -Type SRV -Server dc01
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [string]$Server, [string]$Type = 'A_AAAA')
    $prm = @{ Name = $Name; Type = $Type; DnsOnly = $true; ErrorAction = 'Stop' }
    if ($Server) { $prm['Server'] = $Server }
    try {
        @(Resolve-DnsName @prm | ForEach-Object {
                $d = switch ("$($_.Type)") { 'A' { $_.IPAddress } 'AAAA' { $_.IPAddress } 'CNAME' { $_.NameHost } 'PTR' { $_.NameHost } 'MX' { "$($_.Preference) $($_.NameExchange)" } 'SRV' { "$($_.Priority) $($_.Weight) $($_.Port) $($_.NameTarget)" } 'TXT' { $_.Strings -join ' ' } 'NS' { $_.NameHost } 'SOA' { $_.PrimaryServer } default { "$_" } }
                [pscustomobject][ordered]@{ Name = $_.Name; Type = "$($_.Type)"; Data = $d; TTL = $_.TTL; Section = "$($_.Section)" }
            })
    }
    catch { [pscustomobject][ordered]@{ Name = $Name; Type = $Type; Data = "No answer: $($_.Exception.Message)"; TTL = $null; Section = 'Error' } }
}

function Test-ADTConnection {
    <#
    .SYNOPSIS
        Ping and TCP port tests for a host (defaults to the ports AD and DNS use).
    .EXAMPLE
        Test-ADTConnection -ComputerName dc01 -Port 53, 88, 389, 445, 636, 3268, 5985
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName, [int[]]$Port = @(53, 88, 135, 389, 445, 636, 3268, 3389, 5985))
    $ping = [Net.NetworkInformation.Ping]::new()
    $status = $null; $ms = $null
    try { $r = $ping.Send($ComputerName, 1500); $status = "$($r.Status)"; if ($r.Status -eq 'Success') { $ms = $r.RoundtripTime } } catch { $status = $_.Exception.InnerException.Message; if (-not $status) { $status = $_.Exception.Message } }
    finally { $ping.Dispose() }
    [pscustomobject][ordered]@{ ComputerName = $ComputerName; Test = 'Ping'; Result = $status; Detail = $(if ($null -ne $ms) { "$ms ms" } else { '' }) }
    $names = @{ 53 = 'DNS'; 88 = 'Kerberos'; 135 = 'RPC'; 389 = 'LDAP'; 445 = 'SMB'; 636 = 'LDAPS'; 3268 = 'Global Catalog'; 3269 = 'GC over TLS'; 3389 = 'RDP'; 5985 = 'WinRM'; 5986 = 'WinRM HTTPS'; 9389 = 'AD Web Services' }
    foreach ($pt in $Port) {
        $ok = Test-ADTTcpPort -ComputerName $ComputerName -Port $pt
        [pscustomobject][ordered]@{ ComputerName = $ComputerName; Test = "TCP $pt"; Result = $(if ($ok) { 'Open' } else { 'Closed or filtered' }); Detail = $names[$pt] }
    }
}
