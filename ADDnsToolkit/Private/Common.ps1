# ==================================================================================
# AD & DNS Toolkit - shared helpers (configuration, logging, prerequisites, reports)
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

$script:ADTVersion = '2.0.0'
$script:ADTConfig = @{
    OutputRoot = $null
    LogFile    = $null
}

# Commands that prove a module's cmdlets are callable (also lets tests supply stubs).
$script:ADTModuleProbe = @{
    ActiveDirectory  = 'Get-ADDomain'
    DnsServer        = 'Get-DnsServerZone'
    FailoverClusters = 'Get-Cluster'
}
$script:ADTInstallHint = @{
    ActiveDirectory  = 'Server: Install-WindowsFeature RSAT-AD-PowerShell   |   Windows 10/11: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0   (or run Install-ADTPrerequisite -Component ActiveDirectory)'
    DnsServer        = 'Server: Install-WindowsFeature RSAT-DNS-Server   |   Windows 10/11: Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0   (or run Install-ADTPrerequisite -Component DnsServer)'
    FailoverClusters = 'Server: Install-WindowsFeature RSAT-Clustering-PowerShell   |   Windows 10/11: Add-WindowsCapability -Online -Name Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0'
}

function Get-ADTDocumentsPath {
    $p = $null
    try { $p = [Environment]::GetFolderPath('MyDocuments') } catch { $p = $null }
    if (-not $p) { $p = $HOME }
    if (-not $p) { $p = (Get-Location).Path }
    $p
}

function Get-ADTConfig {
    <#
    .SYNOPSIS
        Shows where the toolkit writes reports, backups and its log.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:ADTConfig.OutputRoot) {
        $root = $env:ADT_OUTPUT_ROOT
        if (-not $root) { $root = Join-Path (Get-ADTDocumentsPath) 'ADDnsToolkit' }
        $script:ADTConfig.OutputRoot = $root
    }
    if (-not $script:ADTConfig.LogFile) {
        $script:ADTConfig.LogFile = Join-Path (Join-Path $script:ADTConfig.OutputRoot 'Logs') ('ADDnsToolkit_{0}.log' -f (Get-Date -Format 'yyyyMM'))
    }
    [pscustomobject]@{
        Version    = $script:ADTVersion
        OutputRoot = $script:ADTConfig.OutputRoot
        LogFile    = $script:ADTConfig.LogFile
    }
}

function Set-ADTConfig {
    <#
    .SYNOPSIS
        Changes the folder that reports, backups and logs go to (for this session).
    .EXAMPLE
        Set-ADTConfig -OutputRoot D:\Toolkit
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$OutputRoot)
    if ($PSCmdlet.ShouldProcess($OutputRoot, 'Use as toolkit output folder')) {
        $script:ADTConfig.OutputRoot = $OutputRoot
        $script:ADTConfig.LogFile = $null
        Get-ADTConfig
    }
}

function Write-ADTLog {
    <# Appends one line to the toolkit log. Never throws. #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Change')][string]$Level = 'Info'
    )
    try {
        $cfg = Get-ADTConfig
        $dir = Split-Path $cfg.LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $user = if ($env:USERDOMAIN -and $env:USERNAME) { "$env:USERDOMAIN\$env:USERNAME" } elseif ($env:USER) { $env:USER } else { 'unknown' }
        $line = '{0}  {1,-6} {2} on {3}: {4}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $user, [Environment]::MachineName, $Message
        Add-Content -Path $cfg.LogFile -Value $line -Encoding UTF8
    }
    catch { Write-Verbose "Could not write to the toolkit log: $($_.Exception.Message)" }
}

function Write-ADTStatus {
    <# Progress messages. Written to the host (information stream), so the console shows them
       and the GUI's background runspace can capture them. #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Ok', 'Warn', 'Error', 'Step')][string]$Type = 'Info'
    )
    $map = @{ Info = @('[i]', 'Gray'); Ok = @('[+]', 'Green'); Warn = @('[!]', 'Yellow'); Error = @('[x]', 'Red'); Step = @('[>]', 'Cyan') }
    Write-Host ('{0} {1}' -f $map[$Type][0], $Message) -ForegroundColor $map[$Type][1]
}

function Assert-ADTModule {
    <# Loads a management module or throws a clear, actionable error. #>
    param([Parameter(Mandatory)][ValidateSet('ActiveDirectory', 'DnsServer', 'FailoverClusters')][string]$Name)
    $probe = $script:ADTModuleProbe[$Name]
    if (Get-Command $probe -ErrorAction SilentlyContinue) { return }
    try {
        Import-Module $Name -ErrorAction Stop -Verbose:$false
        return
    }
    catch {
        throw "The $Name PowerShell module is not available on this computer. Install it first. $($script:ADTInstallHint[$Name])"
    }
}

function Test-ADTModule {
    param([Parameter(Mandatory)][string]$Name)
    $probe = $script:ADTModuleProbe[$Name]
    if ($probe -and (Get-Command $probe -ErrorAction SilentlyContinue)) { return $true }
    [bool](Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)
}

function Test-ADTIsAdmin {
    if (-not ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows)) { return $false }
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function New-ADTOutputFolder {
    <# Creates <OutputRoot>\<Category>\<Category>_<timestamp> (or uses -Path) and returns it. #>
    param([Parameter(Mandatory)][string]$Category, [string]$Path)
    if (-not $Path) {
        $Path = Join-Path (Join-Path (Get-ADTConfig).OutputRoot $Category) ('{0}_{1}' -f $Category, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    (Resolve-Path $Path).Path
}

function ConvertTo-ADTSafeFileName {
    param([string]$Name)
    $bad = [IO.Path]::GetInvalidFileNameChars() + [char[]]' '
    $s = -join ($Name.ToCharArray() | ForEach-Object { if ($bad -contains $_) { '_' } else { $_ } })
    if (-not $s) { $s = 'item' }
    $s
}

function ConvertTo-ADTFilterValue {
    <# Escapes a value for use inside single quotes in an Active Directory -Filter string. #>
    param([string]$Value)
    "$Value".Replace("'", "''")
}

function Get-ADTParentDN {
    <# Parent of a distinguished name, honouring escaped commas (CN=Doe\, John,OU=x -> OU=x). #>
    param([Parameter(Mandatory)][string]$DistinguishedName)
    $m = [regex]::Match($DistinguishedName, '^(?:\\.|[^,])+,(.+)$')
    if ($m.Success) { $m.Groups[1].Value } else { $null }
}

function Get-ADTDNDepth {
    param([string]$DistinguishedName)
    ([regex]::Matches($DistinguishedName, '(?<!\\),')).Count
}

function ConvertTo-ADTTargetDN {
    <# Rewrites a DN from the backup's domain to the current domain (restoring into a lab, say). #>
    param([string]$DistinguishedName, [string]$SourceDomainDN, [string]$TargetDomainDN)
    if (-not $SourceDomainDN -or -not $TargetDomainDN -or $SourceDomainDN -eq $TargetDomainDN) { return $DistinguishedName }
    if ($DistinguishedName -match ([regex]::Escape($SourceDomainDN) + '$')) {
        return $DistinguishedName.Substring(0, $DistinguishedName.Length - $SourceDomainDN.Length) + $TargetDomainDN
    }
    $DistinguishedName
}

function New-ADTPassword {
    <#
    .SYNOPSIS
        Generates a cryptographically random password with upper, lower, digit and symbol characters.
    .EXAMPLE
        New-ADTPassword -Length 20
    #>
    param([ValidateRange(12, 128)][int]$Length = 16)
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%*-_=+?')
    $all = -join $sets
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = {
        param([string]$From)
        $b = [byte[]]::new(4); $rng.GetBytes($b)
        $From[[BitConverter]::ToUInt32($b, 0) % $From.Length]
    }
    $chars = [Collections.Generic.List[char]]::new()
    foreach ($s in $sets) { $chars.Add((& $pick $s)) }
    while ($chars.Count -lt $Length) { $chars.Add((& $pick $all)) }
    # Fisher-Yates shuffle
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $b = [byte[]]::new(4); $rng.GetBytes($b)
        $j = [BitConverter]::ToUInt32($b, 0) % ($i + 1)
        $t = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $t
    }
    $rng.Dispose()
    -join $chars
}

function Get-ADTOverallStatus {
    <# Worst status in a set of check results: Fail > Warn > Pass. #>
    param([object[]]$Results)
    $s = @($Results | ForEach-Object { $_.Status })
    if ($s -contains 'Fail') { 'Fail' } elseif ($s -contains 'Warn') { 'Warn' } else { 'Pass' }
}

function New-ADTCheck {
    param([string]$Category, [string]$Check, [string]$Target, [ValidateSet('Pass', 'Warn', 'Fail', 'Info')][string]$Status, [string]$Detail, [string]$Fix = '')
    [pscustomobject][ordered]@{ Category = $Category; Check = $Check; Target = $Target; Status = $Status; Detail = $Detail; Fix = $Fix }
}

function Test-ADTTcpPort {
    <# Fast TCP connect test with a timeout (works in Windows PowerShell 5.1 and PowerShell 7). #>
    param([Parameter(Mandatory)][string]$ComputerName, [Parameter(Mandatory)][int]$Port, [int]$TimeoutMs = 1500)
    $c = [Net.Sockets.TcpClient]::new()
    try {
        $iar = $c.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $c.EndConnect($iar); return $true }
        return $false
    }
    catch { return $false }
    finally { $c.Close() }
}

# ----------------------------------------------------------------------------------
# HTML reports - one consistent, self-contained, HTML-encoded design for every tool
# ----------------------------------------------------------------------------------
function ConvertTo-ADTHtmlText { param($Value) [Net.WebUtility]::HtmlEncode("$Value") }

function ConvertTo-ADTHtmlTable {
    param([object[]]$Data, [string[]]$Columns, [int]$MaxRows = 5000)
    $rows = @($Data)
    if (-not $rows.Count) { return '<p class="empty">Nothing to show.</p>' }
    if (-not $Columns) { $Columns = @($rows[0].PSObject.Properties.Name) }
    $sb = [Text.StringBuilder]::new()
    $null = $sb.Append('<div class="tbl"><table><thead><tr>')
    foreach ($c in $Columns) { $null = $sb.Append('<th>').Append((ConvertTo-ADTHtmlText $c)).Append('</th>') }
    $null = $sb.Append('</tr></thead><tbody>')
    $n = 0
    foreach ($r in $rows) {
        if (++$n -gt $MaxRows) { break }
        $null = $sb.Append('<tr>')
        foreach ($c in $Columns) {
            $v = $r.$c
            if ($v -is [array]) { $v = $v -join '; ' }
            if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm') }
            $cls = ''
            if ($c -eq 'Status' -and "$v" -in 'Pass', 'Warn', 'Fail', 'Info') { $cls = ' class="st st-' + "$v".ToLower() + '"' }
            $null = $sb.Append("<td$cls>").Append((ConvertTo-ADTHtmlText $v)).Append('</td>')
        }
        $null = $sb.Append('</tr>')
    }
    $null = $sb.Append('</tbody></table></div>')
    if ($rows.Count -gt $MaxRows) { $null = $sb.Append("<p class=`"empty`">Showing the first $MaxRows of $($rows.Count) rows; the CSV has all of them.</p>") }
    $sb.ToString()
}

function New-ADTHtmlReport {
    <#
    Builds a self-contained HTML report.
    -Cards    : array of @{ Label; Value; Tone = 'ok'|'warn'|'bad'|'' }
    -Sections : array of @{ Title; Text; Data; Columns; Pre }
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle,
        [object[]]$Cards = @(),
        [object[]]$Sections = @(),
        [Parameter(Mandatory)][string]$Path
    )
    $cardHtml = ($Cards | ForEach-Object {
            $tone = if ($_.Tone) { ' ' + $_.Tone } else { '' }
            '<div class="card' + $tone + '"><div class="v">' + (ConvertTo-ADTHtmlText $_.Value) + '</div><div class="l">' + (ConvertTo-ADTHtmlText $_.Label) + '</div></div>'
        }) -join ''
    $nav = ($Sections | ForEach-Object { $i = [array]::IndexOf($Sections, $_); '<a href="#s' + $i + '">' + (ConvertTo-ADTHtmlText $_.Title) + '</a>' }) -join ''
    $body = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Sections.Count; $i++) {
        $s = $Sections[$i]
        $null = $body.Append('<section id="s' + $i + '"><h2>' + (ConvertTo-ADTHtmlText $s.Title))
        if ($null -ne $s.Data) { $null = $body.Append(' <span class="count">' + @($s.Data).Count + '</span>') }
        $null = $body.Append('</h2>')
        if ($s.Text) { $null = $body.Append('<p>' + (ConvertTo-ADTHtmlText $s.Text) + '</p>') }
        if ($null -ne $s.Data) {
            if (@($s.Data).Count -gt 8) { $null = $body.Append('<input class="filter" type="search" placeholder="Filter this table" aria-label="Filter ' + (ConvertTo-ADTHtmlText $s.Title) + '">') }
            $null = $body.Append((ConvertTo-ADTHtmlTable -Data $s.Data -Columns $s.Columns))
        }
        if ($s.Pre) { $null = $body.Append('<pre>' + (ConvertTo-ADTHtmlText (($s.Pre | Out-String).Trim())) + '</pre>') }
        $null = $body.Append('</section>')
    }
    $sub = if ($Subtitle) { ConvertTo-ADTHtmlText $Subtitle } else { '' }
    $generated = '{0} by {1} on {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $env:USERNAME, [Environment]::MachineName
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(ConvertTo-ADTHtmlText $Title)</title>
<style>
:root{--bg:#f4f6fa;--surface:#fff;--ink:#16203a;--muted:#5b6478;--line:#dde3ec;--accent:#0a66c8;--ok:#1e8a5a;--warn:#b7791f;--bad:#c2362b}
@media (prefers-color-scheme:dark){:root{--bg:#0e1322;--surface:#161c2e;--ink:#e9edf5;--muted:#9aa3ba;--line:#283149;--accent:#4c9bff;--ok:#4cc38a;--warn:#e8c04f;--bad:#ff6b5e}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
header{background:var(--surface);border-bottom:1px solid var(--line);padding:22px 16px}
.wrap{max-width:1200px;margin:0 auto;padding:0 16px}
h1{margin:0;font-size:1.7rem}.sub{color:var(--muted);margin-top:4px}
nav{display:flex;flex-wrap:wrap;gap:6px;margin-top:14px}nav a{font-size:.82rem;color:var(--accent);text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:3px 10px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin:20px 0}
.card{background:var(--surface);border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:12px;padding:12px 14px}
.card.ok{border-left-color:var(--ok)}.card.warn{border-left-color:var(--warn)}.card.bad{border-left-color:var(--bad)}
.card .v{font-size:1.5rem;font-weight:700;font-variant-numeric:tabular-nums}.card .l{color:var(--muted);font-size:.85rem}
section{margin:26px 0}h2{font-size:1.2rem;margin:0 0 8px}.count{font-size:.8rem;color:var(--muted);font-weight:500;border:1px solid var(--line);border-radius:999px;padding:1px 8px;vertical-align:2px}
.tbl{background:var(--surface);border:1px solid var(--line);border-radius:12px;overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:.86rem}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{position:sticky;top:0;background:var(--surface);font-size:.72rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
tr:last-child td{border-bottom:0}.st{font-weight:600}.st-pass{color:var(--ok)}.st-warn{color:var(--warn)}.st-fail{color:var(--bad)}.st-info{color:var(--muted)}
pre{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px;overflow-x:auto;font-size:.8rem}
.filter{width:100%;max-width:320px;margin:0 0 8px;padding:7px 10px;border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink)}
.empty{color:var(--muted)}footer{color:var(--muted);font-size:.8rem;padding:30px 0}
</style></head><body>
<header><div class="wrap"><h1>$(ConvertTo-ADTHtmlText $Title)</h1><div class="sub">$sub</div><nav>$nav</nav></div></header>
<main class="wrap"><div class="cards">$cardHtml</div>$($body.ToString())</main>
<footer class="wrap">Generated $(ConvertTo-ADTHtmlText $generated) &middot; AD &amp; DNS Toolkit v$script:ADTVersion &middot; MIT License</footer>
<script>
document.querySelectorAll('input.filter').forEach(function(f){var t=f.nextElementSibling;f.addEventListener('input',function(){var q=f.value.toLowerCase();t.querySelectorAll('tbody tr').forEach(function(r){r.style.display=r.textContent.toLowerCase().indexOf(q)>-1?'':'none'})})});
</script></body></html>
"@
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $Path -Value $html -Encoding UTF8
    $Path
}

function Export-ADTDataSet {
    <# Writes each named dataset as CSV (and the whole set as JSON). #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data, [Parameter(Mandatory)][string]$Folder, [switch]$NoJson)
    foreach ($k in $Data.Keys) {
        $rows = @($Data[$k])
        if ($rows.Count) {
            $rows | Select-Object * | ForEach-Object {
                $o = $_
                foreach ($p in @($o.PSObject.Properties)) { if ($p.Value -is [array] -or $p.Value -is [System.Collections.IList] -and $p.Value -isnot [string]) { $p.Value = (@($p.Value) -join '; ') } }
                $o
            } | Export-Csv -Path (Join-Path $Folder "$k.csv") -NoTypeInformation -Encoding UTF8
        }
    }
    if (-not $NoJson) { $Data | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Folder 'data.json') -Encoding UTF8 }
}
