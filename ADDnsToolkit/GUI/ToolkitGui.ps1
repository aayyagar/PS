# ==================================================================================
# AD & DNS Toolkit - Windows Forms interface
#  * Every task runs in a background runspace, so the window never freezes.
#  * Changes are previewed first and confirmed in a dialog before anything is written.
#  * Progress messages from the cmdlets stream into the activity pane.
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

$script:ADTGui = $null

$script:ADTGuiPages = [ordered]@{
    Home         = @{ Group = 'START'; Text = 'Home' }
    ADHealth     = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Health check' }
    ADInventory  = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Inventory' }
    ADBackup     = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Backup and restore' }
    BulkUsers    = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Bulk users' }
    Inactive     = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Inactive users' }
    Trusts       = @{ Group = 'ACTIVE DIRECTORY'; Text = 'Trusts' }
    DnsHealth    = @{ Group = 'DNS'; Text = 'Health check' }
    DnsRecords   = @{ Group = 'DNS'; Text = 'Records' }
    DnsBackup    = @{ Group = 'DNS'; Text = 'Zone backup and restore' }
    StaleDns     = @{ Group = 'DNS'; Text = 'Stale records' }
    Forwarders   = @{ Group = 'DNS'; Text = 'Conditional forwarders' }
    Diagnostics  = @{ Group = 'TOOLS'; Text = 'Diagnostics' }
    Log          = @{ Group = 'TOOLS'; Text = 'Activity log' }
}

# ----------------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------------
function Test-ADTGuiAvailable {
    <#
    .SYNOPSIS
        True when the Windows Forms interface can be used (Windows with a desktop session).
    #>
    if (-not ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows)) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop; return $true } catch { return $false }
}

function Write-ADTGuiLog {
    param([string]$Text)
    $g = $script:ADTGui
    if (-not $g -or -not $g.LogBox) { return }
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Text
    $g.LogBox.AppendText($line + [Environment]::NewLine)
}

function Set-ADTGuiStatus {
    param([string]$Text)
    if ($script:ADTGui -and $script:ADTGui.StatusLabel) { $script:ADTGui.StatusLabel.Text = $Text }
}

function Confirm-ADTGui {
    param([string]$Text, [string]$Title = 'Please confirm')
    $r = [System.Windows.Forms.MessageBox]::Show($script:ADTGui.Form, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    $r -eq [System.Windows.Forms.DialogResult]::Yes
}

function Show-ADTGuiMessage {
    param([string]$Text, [string]$Title = 'AD & DNS Toolkit', [ValidateSet('Info', 'Warning', 'Error')][string]$Icon = 'Info')
    $i = switch ($Icon) { 'Warning' { [System.Windows.Forms.MessageBoxIcon]::Warning } 'Error' { [System.Windows.Forms.MessageBoxIcon]::Error } default { [System.Windows.Forms.MessageBoxIcon]::Information } }
    [void][System.Windows.Forms.MessageBox]::Show($script:ADTGui.Form, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $i)
}

function Get-ADTGuiControl {
    param([string]$Page, [string]$Name)
    $script:ADTGui.Pages[$Page].Controls[$Name]
}

function Get-ADTGuiText {
    param([string]$Page, [string]$Name)
    $c = Get-ADTGuiControl $Page $Name
    if ($null -eq $c) { return '' }
    "$($c.Text)".Trim()
}

function Open-ADTGuiPath {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) { Invoke-Item -Path $Path } else { Show-ADTGuiMessage 'Nothing to open yet - run the task first.' -Icon Warning }
}

function ConvertTo-ADTDataTable {
    <# DataGridView cannot show PSObject properties directly; a string DataTable can. #>
    param([object[]]$InputObject, [string[]]$Columns, [switch]$Selectable)
    $dt = New-Object System.Data.DataTable
    if ($Selectable) { [void]$dt.Columns.Add('Select', [bool]) }
    [void]$dt.Columns.Add('_i', [int])
    $rows = @($InputObject | Where-Object { $null -ne $_ })
    if (-not $Columns -and $rows.Count) { $Columns = @($rows[0].PSObject.Properties.Name) }
    foreach ($c in $Columns) { if (-not $dt.Columns.Contains($c)) { [void]$dt.Columns.Add($c, [string]) } }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $o = $rows[$i]; $r = $dt.NewRow()
        if ($Selectable) { $r['Select'] = $false }
        $r['_i'] = $i
        foreach ($c in $Columns) {
            $v = $o.$c
            if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm') }
            elseif ($v -is [array] -or ($v -is [System.Collections.IList] -and $v -isnot [string])) { $v = (@($v) -join '; ') }
            $r[$c] = "$v"
        }
        $dt.Rows.Add($r)
    }
    , $dt
}

function Set-ADTGuiGrid {
    <# Shows objects in a page's grid. The objects stay attached for selection. #>
    param([string]$Page, [object[]]$InputObject, [string[]]$Columns, [switch]$Selectable)
    $pg = $script:ADTGui.Pages[$Page]
    $items = @($InputObject | Where-Object { $null -ne $_ })
    $pg.Items = $items
    $pg.Selectable = [bool]$Selectable
    $grid = $pg.Grid
    $grid.DataSource = $null
    $grid.DataSource = (ConvertTo-ADTDataTable -InputObject $items -Columns $Columns -Selectable:$Selectable)
    $pg.CountLabel.Text = "$($items.Count) item(s)"
}

function Get-ADTGuiSelection {
    param([string]$Page)
    $pg = $script:ADTGui.Pages[$Page]
    $grid = $pg.Grid
    [void]$grid.EndEdit()
    $sel = @()
    foreach ($row in $grid.Rows) {
        if ($pg.Selectable -and $row.Cells['Select'].Value -eq $true) { $sel += $pg.Items[[int]$row.Cells['_i'].Value] }
    }
    if (-not $sel.Count -and -not $pg.Selectable) {
        foreach ($row in $grid.SelectedRows) { $sel += $pg.Items[[int]$row.Cells['_i'].Value] }
    }
    $sel
}

function Set-ADTGuiSelectAll {
    param([string]$Page, [bool]$Value)
    $pg = $script:ADTGui.Pages[$Page]
    if (-not $pg.Selectable) { return }
    foreach ($row in $pg.Grid.Rows) { if ($row.Visible) { $row.Cells['Select'].Value = $Value } }
    [void]$pg.Grid.EndEdit()
}

function ConvertTo-ADTNameValue {
    param($Object)
    foreach ($p in $Object.PSObject.Properties) {
        $v = $p.Value
        if ($v -is [array]) { $v = $v -join '; ' }
        [pscustomobject]@{ Property = $p.Name; Value = "$v" }
    }
}

# ----------------------------------------------------------------------------------
# Background tasks
# ----------------------------------------------------------------------------------
function Start-ADTGuiJob {
    <#
    Runs $Script in a new runspace that has the toolkit module loaded. $Parameters are splatted
    into it. $OnDone runs on the UI thread with the output array.
    #>
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Script, [hashtable]$Parameters = @{}, [scriptblock]$OnDone)
    $g = $script:ADTGui
    if ($g.Job) {
        if ($g.Queue.Count -ge 5) { Show-ADTGuiMessage "Please wait - '$($g.Job.Title)' is still running." -Icon Warning; return }
        $g.Queue.Add(@{ Title = $Title; Script = $Script; Parameters = $Parameters; OnDone = $OnDone })
        Write-ADTGuiLog "  (queued: $Title)"
        return
    }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { Write-Verbose 'ExecutionPolicy not settable on this version' }
    $iss.ImportPSModule([string[]]@($script:ADTManifestPath))
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    $rs.ApartmentState = [Threading.ApartmentState]::STA
    $rs.Open()
    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $wrapper = 'param($__root, $__params) $null = Set-ADTConfig -OutputRoot $__root -WhatIf:$false; & {' + $Script.ToString() + '} @__params'
    [void]$ps.AddScript($wrapper).AddArgument((Get-ADTConfig).OutputRoot).AddArgument($Parameters)
    $g.Job = @{ PS = $ps; Runspace = $rs; Handle = $ps.BeginInvoke(); Info = 0; Err = 0; Warn = 0; OnDone = $OnDone; Title = $Title; Started = Get-Date }
    $g.Progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $g.Progress.Visible = $true
    Set-ADTGuiStatus "$Title..."
    Write-ADTGuiLog "> $Title"
}

function Update-ADTGuiJob {
    $g = $script:ADTGui
    $j = $g.Job
    if (-not $j) { return }
    $st = $j.PS.Streams
    while ($j.Info -lt $st.Information.Count) { Write-ADTGuiLog ("  " + "$($st.Information[$j.Info].MessageData)"); $j.Info++ }
    while ($j.Warn -lt $st.Warning.Count) { Write-ADTGuiLog ("  [!] " + "$($st.Warning[$j.Warn].Message)"); $j.Warn++ }
    while ($j.Err -lt $st.Error.Count) { Write-ADTGuiLog ("  [x] " + "$($st.Error[$j.Err].Exception.Message)"); $j.Err++ }
    if (-not $j.Handle.IsCompleted) { return }
    $out = @(); $failure = $null
    try { $out = @($j.PS.EndInvoke($j.Handle) | ForEach-Object { $_ }) }
    catch {
        $e = $_.Exception
        while ($e.InnerException) { $e = $e.InnerException }
        $failure = $e.Message
    }
    while ($j.Info -lt $st.Information.Count) { Write-ADTGuiLog ("  " + "$($st.Information[$j.Info].MessageData)"); $j.Info++ }
    $j.PS.Dispose(); $j.Runspace.Dispose()
    $g.Job = $null
    $g.Progress.Visible = $false
    $secs = [math]::Round(((Get-Date) - $j.Started).TotalSeconds, 1)
    if ($failure) {
        Set-ADTGuiStatus "$($j.Title) failed"
        Write-ADTGuiLog "  [x] $failure"
        Show-ADTGuiMessage $failure -Title "$($j.Title) failed" -Icon Error
        Start-ADTGuiNextJob
        return
    }
    Set-ADTGuiStatus "$($j.Title) - done in $secs s"
    if ($j.OnDone) {
        try { & $j.OnDone $out }
        catch { Write-ADTGuiLog "  [x] Could not show the result: $($_.Exception.Message)" }
    }
    Start-ADTGuiNextJob
}

function Start-ADTGuiNextJob {
    $g = $script:ADTGui
    if ($g.Job -or -not $g.Queue.Count) { return }
    $n = $g.Queue[0]; $g.Queue.RemoveAt(0)
    Start-ADTGuiJob -Title $n.Title -Script $n.Script -Parameters $n.Parameters -OnDone $n.OnDone
}

# ----------------------------------------------------------------------------------
# Building blocks
# ----------------------------------------------------------------------------------
function New-ADTGuiGrid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.AutoSizeColumnsMode = 'DisplayedCells'
    $grid.BorderStyle = 'None'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(238, 242, 248)
    $grid.ColumnHeadersHeight = 30
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 253)
    $grid.Add_DataBindingComplete({
            param($s, $e)
            if ($s.Columns.Contains('_i')) { $s.Columns['_i'].Visible = $false }
            foreach ($c in $s.Columns) { $c.ReadOnly = ($c.Name -ne 'Select'); if ($c.Name -ne 'Select') { $c.SortMode = 'Automatic' } }
            if ($s.Columns.Contains('Select')) { $s.Columns['Select'].Width = 52; $s.Columns['Select'].DisplayIndex = 0 }
        })
    $grid.Add_CurrentCellDirtyStateChanged({ param($s, $e) if ($s.IsCurrentCellDirty) { [void]$s.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })
    $grid.Add_CellFormatting({
            param($s, $e)
            $name = $s.Columns[$e.ColumnIndex].Name
            if ($name -notin 'Status', 'Action', 'Valid', 'Result') { return }
            $v = "$($e.Value)"
            $color = switch -Regex ($v) {
                '^(Pass|Created|Added|Removed|Disabled|Restored|RecordsAdded|True|Open|Success|OK)$' { [System.Drawing.Color]::FromArgb(30, 138, 90) }
                '^(Warn|Skipped|Kept|Would.*)$' { [System.Drawing.Color]::FromArgb(183, 121, 31) }
                '^(Fail|Failed|Invalid|False|Closed.*)$' { [System.Drawing.Color]::FromArgb(194, 54, 43) }
                default { $null }
            }
            if ($color) { $e.CellStyle.ForeColor = $color; $e.CellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9) }
        })
    $grid.Add_DataError({ param($s, $e) $e.ThrowException = $false })
    $grid
}

function New-ADTGuiPage {
    param([string]$Key, [string]$Title, [string]$Description)
    $g = $script:ADTGui
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Fill'; $panel.Padding = New-Object System.Windows.Forms.Padding(18, 12, 18, 8); $panel.Visible = $false

    $grid = New-ADTGuiGrid
    $foot = New-Object System.Windows.Forms.Label
    $foot.Dock = 'Bottom'; $foot.Height = 22; $foot.TextAlign = 'MiddleLeft'; $foot.ForeColor = [System.Drawing.Color]::DimGray

    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'; $bar.WrapContents = $true
    $bar.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)

    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'; $head.Height = 64
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title; $t.UseMnemonic = $false; $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15); $t.AutoSize = $true; $t.Location = New-Object System.Drawing.Point(0, 0)
    $d = New-Object System.Windows.Forms.Label
    $d.Text = $Description; $d.UseMnemonic = $false; $d.AutoSize = $false; $d.Location = New-Object System.Drawing.Point(2, 34); $d.Size = New-Object System.Drawing.Size(900, 28)
    $d.Anchor = 'Top, Left, Right'; $d.ForeColor = [System.Drawing.Color]::DimGray
    $head.Controls.AddRange(@($t, $d))

    $panel.Controls.Add($grid)
    $panel.Controls.Add($foot)
    $panel.Controls.Add($bar)
    $panel.Controls.Add($head)
    $g.Content.Controls.Add($panel)
    $pg = @{ Key = $Key; Panel = $panel; Grid = $grid; Bar = $bar; CountLabel = $foot; Controls = @{}; Items = @(); Selectable = $false; Report = $null; Folder = $null; Loaded = $false }
    $g.Pages[$Key] = $pg
    $pg
}

function Add-ADTGuiLabel {
    param($Page, [string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.UseMnemonic = $false; $l.AutoSize = $true; $l.Margin = New-Object System.Windows.Forms.Padding(6, 9, 2, 0)
    $Page.Bar.Controls.Add($l)
    $l
}

function Add-ADTGuiText {
    param($Page, [string]$Name, [string]$Label, [int]$Width = 180, [string]$Default = '', [switch]$Password)
    if ($Label) { $null = Add-ADTGuiLabel $Page $Label }
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Width = $Width; $tb.Text = $Default; $tb.Margin = New-Object System.Windows.Forms.Padding(2, 5, 8, 3)
    if ($Password) { $tb.UseSystemPasswordChar = $true }
    $Page.Bar.Controls.Add($tb)
    $Page.Controls[$Name] = $tb
    $tb
}

function Add-ADTGuiCombo {
    param($Page, [string]$Name, [string]$Label, [string[]]$Items = @(), [int]$Width = 180, [switch]$List)
    if ($Label) { $null = Add-ADTGuiLabel $Page $Label }
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.Width = $Width; $cb.Margin = New-Object System.Windows.Forms.Padding(2, 5, 8, 3)
    if ($List) { $cb.DropDownStyle = 'DropDownList' }
    if ($Items.Count) { $cb.Items.AddRange([object[]]$Items); $cb.SelectedIndex = 0 }
    $Page.Bar.Controls.Add($cb)
    $Page.Controls[$Name] = $cb
    $cb
}

function Add-ADTGuiNumber {
    param($Page, [string]$Name, [string]$Label, [int]$Value, [int]$Min = 0, [int]$Max = 3650)
    if ($Label) { $null = Add-ADTGuiLabel $Page $Label }
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Minimum = $Min; $n.Maximum = $Max; $n.Value = $Value; $n.Width = 70; $n.Margin = New-Object System.Windows.Forms.Padding(2, 5, 8, 3)
    $Page.Bar.Controls.Add($n)
    $Page.Controls[$Name] = $n
    $n
}

function Add-ADTGuiCheck {
    param($Page, [string]$Name, [string]$Text, [bool]$Checked = $false)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text; $c.AutoSize = $true; $c.Checked = $Checked; $c.Margin = New-Object System.Windows.Forms.Padding(6, 7, 8, 3)
    $Page.Bar.Controls.Add($c)
    $Page.Controls[$Name] = $c
    $c
}

function Add-ADTGuiButton {
    param($Page, [string]$Text, [scriptblock]$OnClick, [ValidateSet('Normal', 'Primary', 'Danger')][string]$Kind = 'Normal', [string]$Name)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.AutoSize = $true; $b.Height = 30; $b.Padding = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $b.Margin = New-Object System.Windows.Forms.Padding(2, 3, 6, 3); $b.FlatStyle = 'Flat'; $b.UseVisualStyleBackColor = $false
    switch ($Kind) {
        'Primary' { $b.BackColor = [System.Drawing.Color]::FromArgb(10, 102, 200); $b.ForeColor = [System.Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0 }
        'Danger' { $b.BackColor = [System.Drawing.Color]::FromArgb(194, 54, 43); $b.ForeColor = [System.Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0 }
        default { $b.BackColor = [System.Drawing.Color]::FromArgb(238, 242, 248); $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 208, 222) }
    }
    $b.Add_Click($OnClick)
    $Page.Bar.Controls.Add($b)
    if ($Name) { $Page.Controls[$Name] = $b }
    $b
}

function Add-ADTGuiBreak {
    param($Page)
    $n = $Page.Bar.Controls.Count
    if ($n) { $Page.Bar.SetFlowBreak($Page.Bar.Controls[$n - 1], $true) }
}

function Add-ADTGuiBrowse {
    <# A Browse... button that fills a text box from a file or folder picker. #>
    param($Page, [string]$Target, [ValidateSet('OpenFile', 'Folder')][string]$Mode = 'OpenFile', [string]$Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*')
    $script:ADTGui.BrowseInfo["$($Page.Key)|$Target"] = @{ Mode = $Mode; Filter = $Filter }
    $b = Add-ADTGuiButton $Page 'Browse...' {
        $key = $this.Tag
        $info = $script:ADTGui.BrowseInfo[$key]
        $parts = $key -split '\|'
        $tb = Get-ADTGuiControl $parts[0] $parts[1]
        if ($info.Mode -eq 'Folder') {
            $d = New-Object System.Windows.Forms.FolderBrowserDialog
            $d.SelectedPath = $(if ($tb.Text -and (Test-Path $tb.Text)) { $tb.Text } else { (Get-ADTConfig).OutputRoot })
            if ($d.ShowDialog($script:ADTGui.Form) -eq 'OK') { $tb.Text = $d.SelectedPath }
        }
        else {
            $d = New-Object System.Windows.Forms.OpenFileDialog
            $d.Filter = $info.Filter
            if ($d.ShowDialog($script:ADTGui.Form) -eq 'OK') { $tb.Text = $d.FileName }
        }
    }
    $b.Tag = "$($Page.Key)|$Target"
    $b
}

function Save-ADTGuiGridCsv {
    param([string]$Page, [string]$DefaultName = 'export.csv')
    $pg = $script:ADTGui.Pages[$Page]
    if (-not @($pg.Items).Count) { Show-ADTGuiMessage 'Nothing to export yet.' -Icon Warning; return }
    $d = New-Object System.Windows.Forms.SaveFileDialog
    $d.Filter = 'CSV files (*.csv)|*.csv'; $d.FileName = $DefaultName
    if ($d.ShowDialog($script:ADTGui.Form) -eq 'OK') {
        $pg.Items | Export-Csv -Path $d.FileName -NoTypeInformation -Encoding UTF8
        Write-ADTGuiLog "Saved $($d.FileName)"
    }
}

function Show-ADTGuiPage {
    param([string]$Key)
    $g = $script:ADTGui
    foreach ($k in $g.Pages.Keys) { $g.Pages[$k].Panel.Visible = ($k -eq $Key) }
    foreach ($b in $g.NavButtons.Values) { $b.BackColor = $g.NavBack; $b.ForeColor = $g.NavFore }
    if ($g.NavButtons.ContainsKey($Key)) { $g.NavButtons[$Key].BackColor = [System.Drawing.Color]::FromArgb(10, 102, 200); $g.NavButtons[$Key].ForeColor = [System.Drawing.Color]::White }
    $g.Current = $Key
    $pg = $g.Pages[$Key]
    if (-not $pg.Loaded) {
        $pg.Loaded = $true
        switch ($Key) {
            'Home' { Invoke-ADTGuiHomeCheck }
            'Log' { Update-ADTGuiLogPage }
            { $_ -in 'DnsRecords', 'DnsHealth', 'DnsBackup', 'StaleDns', 'Forwarders' } { Initialize-ADTGuiDnsServers }
        }
    }
}

function Initialize-ADTGuiDnsServers {
    <# Fills every DNS page's server box once, from the DCs and this computer's DNS settings. #>
    $g = $script:ADTGui
    if ($g.DnsServers) { return }
    $g.DnsServers = @('localhost')
    $fill = {
        param($out)
        $list = @($out | ForEach-Object { "$_" } | Where-Object { $_ })
        if (-not $list.Count) { $list = @('localhost') }
        $script:ADTGui.DnsServers = $list
        foreach ($p in 'DnsRecords', 'DnsHealth', 'DnsBackup', 'StaleDns', 'Forwarders') {
            $cb = Get-ADTGuiControl $p 'Server'
            if ($cb -and $cb -is [System.Windows.Forms.ComboBox]) {
                $keep = $cb.Text; $cb.Items.Clear(); $cb.Items.AddRange([object[]]$list)
                $cb.Text = $(if ($keep -and $keep -ne 'localhost') { $keep } else { $list[0] })
            }
        }
    }
    Start-ADTGuiJob -Title 'Finding DNS servers' -Script { Get-ADTDnsServer } -OnDone $fill
}

function Invoke-ADTGuiHomeCheck {
    Start-ADTGuiJob -Title 'Checking this computer' -Script { Get-ADTEnvironment } -OnDone {
        param($out)
        if (-not $out.Count) { return }
        $e = $out[0]
        Set-ADTGuiGrid -Page 'Home' -InputObject @(ConvertTo-ADTNameValue $e) -Columns @('Property', 'Value')
        $missing = @()
        if (-not $e.ActiveDirectoryRsat) { $missing += 'Active Directory' }
        if (-not $e.DnsServerRsat) { $missing += 'DNS Server' }
        $script:ADTGui.Pages['Home'].Controls['Hint'].Text = $(if ($missing.Count) { "Missing management tools: $($missing -join ', '). Use 'Install RSAT tools' (run as Administrator)." } else { 'All management tools are installed.' })
    }
}

function Update-ADTGuiLogPage {
    $f = (Get-ADTConfig).LogFile
    $lines = @()
    if (Test-Path $f) { $lines = @(Get-Content $f -Tail 500 -Encoding UTF8) }
    [array]::Reverse($lines)
    Set-ADTGuiGrid -Page 'Log' -InputObject @($lines | ForEach-Object { [pscustomobject]@{ Entry = $_ } }) -Columns @('Entry')
}

function Set-ADTGuiTheme {
    param([bool]$Dark)
    $g = $script:ADTGui
    $bg = if ($Dark) { [System.Drawing.Color]::FromArgb(22, 28, 46) } else { [System.Drawing.Color]::FromArgb(246, 248, 252) }
    $fg = if ($Dark) { [System.Drawing.Color]::FromArgb(233, 237, 245) } else { [System.Drawing.Color]::FromArgb(22, 32, 58) }
    $field = if ($Dark) { [System.Drawing.Color]::FromArgb(32, 40, 62) } else { [System.Drawing.Color]::White }
    $apply = {
        param($c)
        foreach ($x in $c.Controls) {
            if ($x -is [System.Windows.Forms.DataGridView]) {
                $x.BackgroundColor = $field; $x.DefaultCellStyle.BackColor = $field; $x.DefaultCellStyle.ForeColor = $fg
                $x.AlternatingRowsDefaultCellStyle.BackColor = $(if ($Dark) { [System.Drawing.Color]::FromArgb(28, 35, 56) } else { [System.Drawing.Color]::FromArgb(248, 250, 253) })
                $x.ColumnHeadersDefaultCellStyle.BackColor = $bg; $x.ColumnHeadersDefaultCellStyle.ForeColor = $fg; $x.GridColor = $(if ($Dark) { [System.Drawing.Color]::FromArgb(48, 58, 84) } else { [System.Drawing.Color]::FromArgb(220, 226, 236) })
            }
            elseif ($x -is [System.Windows.Forms.TextBox] -or $x -is [System.Windows.Forms.ComboBox] -or $x -is [System.Windows.Forms.NumericUpDown]) { $x.BackColor = $field; $x.ForeColor = $fg }
            elseif ($x -is [System.Windows.Forms.Button]) { if ($x.ForeColor -ne [System.Drawing.Color]::White) { $x.BackColor = $field; $x.ForeColor = $fg } }
            elseif ($x -isnot [System.Windows.Forms.StatusStrip]) { if ($x.Parent -ne $g.Nav) { $x.BackColor = $bg; $x.ForeColor = $fg } }
            & $apply $x
        }
    }
    $g.Content.BackColor = $bg
    & $apply $g.Content
    $g.LogBox.BackColor = $field; $g.LogBox.ForeColor = $fg
}

# ----------------------------------------------------------------------------------
# Pages
# ----------------------------------------------------------------------------------
function Initialize-ADTGuiPages {
    # HOME -----------------------------------------------------------------------
    $p = New-ADTGuiPage 'Home' 'AD & DNS Toolkit' 'Free, open-source tools for Active Directory and DNS administration. Read-only by default: every change is previewed and confirmed first.'
    $null = Add-ADTGuiButton $p 'Check this computer' { Invoke-ADTGuiHomeCheck } -Kind Primary
    $null = Add-ADTGuiButton $p 'Install RSAT tools' {
        if (-not (Test-ADTIsAdmin)) { Show-ADTGuiMessage 'Close the toolkit and start it again with "Run as administrator" to install RSAT tools.' -Icon Warning; return }
        if (Confirm-ADTGui 'Install the Active Directory and DNS management tools (RSAT) on this computer? Windows 10/11 downloads them from Windows Update.') {
            Start-ADTGuiJob -Title 'Installing RSAT tools' -Script { Install-ADTPrerequisite -Component ActiveDirectory, DnsServer -Confirm:$false } -OnDone { Invoke-ADTGuiHomeCheck }
        }
    }
    $null = Add-ADTGuiButton $p 'Open output folder' { $r = (Get-ADTConfig).OutputRoot; if (-not (Test-Path $r)) { New-Item -ItemType Directory $r -Force | Out-Null }; Invoke-Item $r }
    $null = Add-ADTGuiButton $p 'Change output folder...' {
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.SelectedPath = (Get-ADTConfig).OutputRoot
        if ($d.ShowDialog($script:ADTGui.Form) -eq 'OK') { $null = Set-ADTConfig -OutputRoot $d.SelectedPath; $script:ADTGui.OutputLabel.Text = "Output: $($d.SelectedPath)"; Write-ADTGuiLog "Output folder: $($d.SelectedPath)"; Invoke-ADTGuiHomeCheck }
    }
    Add-ADTGuiBreak $p
    $p.Controls['Hint'] = Add-ADTGuiLabel $p 'Checking...'

    # AD HEALTH ------------------------------------------------------------------
    $p = New-ADTGuiPage 'ADHealth' 'Active Directory health check' 'Domain controllers (ports, services, SYSVOL, time, OS support), replication, FSMO roles, Recycle Bin and krbtgt. Read-only.'
    $null = Add-ADTGuiText $p 'Server' 'Domain controller (optional):' 200
    $po = Add-ADTGuiCheck $p 'ProblemsOnly' 'Show problems only' $false
    $po.Add_CheckedChanged({
            $pg = $script:ADTGui.Pages['ADHealth']
            if (-not $pg.All) { return }
            $rows = if ($this.Checked) { @($pg.All | Where-Object Status -ne 'Pass') } else { @($pg.All) }
            $label = $pg.CountLabel.Text
            Set-ADTGuiGrid -Page 'ADHealth' -InputObject $rows -Columns @('Status', 'Category', 'Check', 'Target', 'Detail', 'Fix')
            $pg.CountLabel.Text = $label
        })
    $null = Add-ADTGuiButton $p 'Run health check' {
        Start-ADTGuiJob -Title 'AD health check' -Parameters @{ Server = (Get-ADTGuiText 'ADHealth' 'Server') } -Script { param($Server) Test-ADTHealth -Server $Server } -OnDone {
            param($out)
            $r = $out[0]; $pg = $script:ADTGui.Pages['ADHealth']
            $pg.Report = $r.ReportPath; $pg.Folder = $r.OutputFolder; $pg.All = @($r.Checks)
            $rows = if ((Get-ADTGuiControl 'ADHealth' 'ProblemsOnly').Checked) { @($r.Checks | Where-Object Status -ne 'Pass') } else { @($r.Checks) }
            Set-ADTGuiGrid -Page 'ADHealth' -InputObject $rows -Columns @('Status', 'Category', 'Check', 'Target', 'Detail', 'Fix')
            $pg.CountLabel.Text = "Overall: $($r.Overall)  -  $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failures"
        }
    } -Kind Primary
    $null = Add-ADTGuiButton $p 'Open report' { Open-ADTGuiPath $script:ADTGui.Pages['ADHealth'].Report }
    $null = Add-ADTGuiButton $p 'Export CSV' { Save-ADTGuiGridCsv 'ADHealth' 'AD_HealthCheck.csv' }

    # AD INVENTORY -----------------------------------------------------------------
    $p = New-ADTGuiPage 'ADInventory' 'Active Directory inventory' 'Users, computers, groups, OUs, DCs, trusts and privileged accounts, with stale accounts and unsupported Windows flagged. Writes HTML, CSV and JSON.'
    $null = Add-ADTGuiText $p 'Server' 'Domain controller (optional):' 170
    $null = Add-ADTGuiText $p 'SearchBase' 'Search base (optional):' 230
    $null = Add-ADTGuiNumber $p 'StaleDays' 'Stale after (days):' 90 14 3650
    $null = Add-ADTGuiButton $p 'Collect inventory' {
        $prm = @{ Server = (Get-ADTGuiText 'ADInventory' 'Server'); SearchBase = (Get-ADTGuiText 'ADInventory' 'SearchBase'); StaleDays = [int](Get-ADTGuiControl 'ADInventory' 'StaleDays').Value }
        Start-ADTGuiJob -Title 'AD inventory' -Parameters $prm -Script { param($Server, $SearchBase, $StaleDays) Get-ADTInventory -Server $Server -SearchBase $SearchBase -StaleDays $StaleDays } -OnDone {
            param($out)
            $r = $out[0]; $pg = $script:ADTGui.Pages['ADInventory']
            $pg.Report = $r.ReportPath; $pg.Folder = $r.OutputFolder; $pg.Data = $r
            $v = Get-ADTGuiControl 'ADInventory' 'View'; $v.SelectedIndex = 0
            Set-ADTGuiGrid -Page 'ADInventory' -InputObject @(ConvertTo-ADTNameValue $r.Summary) -Columns @('Property', 'Value')
        }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $v = Add-ADTGuiCombo $p 'View' 'Show:' @('Summary', 'Users', 'Computers', 'Groups', 'OUs', 'DomainControllers', 'Trusts', 'PrivilegedMembers') 170 -List
    $v.Add_SelectedIndexChanged({
            $pg = $script:ADTGui.Pages['ADInventory']
            if (-not $pg.Data) { return }
            $k = $this.SelectedItem
            if ($k -eq 'Summary') { Set-ADTGuiGrid -Page 'ADInventory' -InputObject @(ConvertTo-ADTNameValue $pg.Data.Summary) -Columns @('Property', 'Value') }
            else { Set-ADTGuiGrid -Page 'ADInventory' -InputObject @($pg.Data.$k) }
        })
    $null = Add-ADTGuiButton $p 'Open report' { Open-ADTGuiPath $script:ADTGui.Pages['ADInventory'].Report }
    $null = Add-ADTGuiButton $p 'Open folder' { Open-ADTGuiPath $script:ADTGui.Pages['ADInventory'].Folder }

    # AD BACKUP / RESTORE ----------------------------------------------------------
    $p = New-ADTGuiPage 'ADBackup' 'Back up and restore AD objects' 'Exports users, groups (with members) and OUs. Restore only creates what is missing - nothing existing is changed. Users come back disabled unless you set an initial password.'
    $null = Add-ADTGuiText $p 'Server' 'Domain controller (optional):' 170
    $null = Add-ADTGuiCheck $p 'Computers' 'Include computers' $false
    $null = Add-ADTGuiButton $p 'Back up now' {
        Start-ADTGuiJob -Title 'AD object backup' -Parameters @{ Server = (Get-ADTGuiText 'ADBackup' 'Server'); IncludeComputers = (Get-ADTGuiControl 'ADBackup' 'Computers').Checked } -Script { param($Server, $IncludeComputers) Backup-ADTObject -Server $Server -IncludeComputers:$IncludeComputers } -OnDone {
            param($out)
            $r = $out[0]
            (Get-ADTGuiControl 'ADBackup' 'Path').Text = $r.OutputFolder
            Set-ADTGuiGrid -Page 'ADBackup' -InputObject @(ConvertTo-ADTNameValue ($r | Select-Object OutputFolder, OUs, Groups, Users, Computers)) -Columns @('Property', 'Value')
        }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiText $p 'Path' 'Backup folder:' 380
    $null = Add-ADTGuiBrowse $p 'Path' -Mode Folder
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiLabel $p 'Restore:'
    foreach ($t in 'OU', 'Group', 'User', 'Membership') { $null = Add-ADTGuiCheck $p "Inc$t" $t $true }
    $null = Add-ADTGuiText $p 'Password' 'Initial password (optional):' 150 -Password
    $null = Add-ADTGuiCheck $p 'Enable' 'Enable restored users' $false
    Add-ADTGuiBreak $p
    $restore = {
        param([bool]$Preview)
        $path = Get-ADTGuiText 'ADBackup' 'Path'
        if (-not $path) { Show-ADTGuiMessage 'Choose a backup folder first.' -Icon Warning; return }
        $inc = @('OU', 'Group', 'User', 'Membership' | Where-Object { (Get-ADTGuiControl 'ADBackup' "Inc$_").Checked })
        $prm = @{ Path = $path; Include = $inc; Server = (Get-ADTGuiText 'ADBackup' 'Server'); Preview = $Preview; Enable = (Get-ADTGuiControl 'ADBackup' 'Enable').Checked; Password = $null }
        $pw = (Get-ADTGuiControl 'ADBackup' 'Password').Text
        if ($pw) { $prm.Password = ConvertTo-SecureString $pw -AsPlainText -Force }
        if (-not $Preview -and -not (Confirm-ADTGui "Create the missing objects from`n$path`nin Active Directory?`n`nTip: run Preview first.")) { return }
        Start-ADTGuiJob -Title $(if ($Preview) { 'Restore preview' } else { 'Restoring AD objects' }) -Parameters $prm -Script {
            param($Path, $Include, $Server, $Preview, $Enable, $Password)
            $a = @{ Path = $Path; Include = $Include; Server = $Server }
            if ($Password) { $a['InitialPassword'] = $Password; $a['EnableUsers'] = $Enable }
            if ($Preview) { Restore-ADTObject @a -WhatIf } else { Restore-ADTObject @a -Confirm:$false }
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'ADBackup' -InputObject $out -Columns @('Type', 'Name', 'Action', 'Detail') }
    }
    $script:ADTGui.Actions['ADRestore'] = $restore
    $null = Add-ADTGuiButton $p 'Preview restore' { & $script:ADTGui.Actions['ADRestore'] $true }
    $null = Add-ADTGuiButton $p 'Restore' { & $script:ADTGui.Actions['ADRestore'] $false } -Kind Danger

    # BULK USERS -------------------------------------------------------------------
    $p = New-ADTGuiPage 'BulkUsers' 'Bulk-create users from CSV' 'Validate every row first (names, duplicates, OUs, groups, managers), preview, then create. Required columns: SamAccountName and Name (or GivenName + Surname).'
    $null = Add-ADTGuiText $p 'Csv' 'CSV file:' 380 (Join-Path (Split-Path $script:ADTModuleRoot -Parent) 'Samples\NewUsers.csv')
    $null = Add-ADTGuiBrowse $p 'Csv'
    $null = Add-ADTGuiButton $p 'Open sample' { Invoke-Item (Join-Path (Split-Path $script:ADTModuleRoot -Parent) 'Samples\NewUsers.csv') }
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiText $p 'DefaultPath' 'Default OU (optional):' 280
    $null = Add-ADTGuiCheck $p 'Generate' 'Generate passwords for rows without one' $true
    $null = Add-ADTGuiCheck $p 'Disabled' 'Create disabled' $false
    Add-ADTGuiBreak $p
    $bulk = {
        param([string]$Mode)
        $csv = Get-ADTGuiText 'BulkUsers' 'Csv'
        if (-not $csv -or -not (Test-Path $csv)) { Show-ADTGuiMessage 'Choose a CSV file first.' -Icon Warning; return }
        $prm = @{ CsvPath = $csv; DefaultPath = (Get-ADTGuiText 'BulkUsers' 'DefaultPath'); Generate = (Get-ADTGuiControl 'BulkUsers' 'Generate').Checked; Disabled = (Get-ADTGuiControl 'BulkUsers' 'Disabled').Checked; Mode = $Mode }
        if ($Mode -eq 'Create' -and -not (Confirm-ADTGui "Create the valid users from`n$csv ?")) { return }
        Start-ADTGuiJob -Title $(switch ($Mode) { 'Validate' { 'Validating CSV' } 'Preview' { 'Bulk user preview' } default { 'Creating users' } }) -Parameters $prm -Script {
            param($CsvPath, $DefaultPath, $Generate, $Disabled, $Mode)
            $a = @{ CsvPath = $CsvPath }; if ($DefaultPath) { $a['DefaultPath'] = $DefaultPath }
            if ($Mode -eq 'Validate') { Test-ADTBulkUserCsv @a | Select-Object Row, Valid, SamAccountName, Name, UserPrincipalName, Path, Groups, HasPassword, Issues }
            elseif ($Mode -eq 'Preview') { New-ADTBulkUser @a -GeneratePassword:$Generate -Disabled:$Disabled -WhatIf }
            else { New-ADTBulkUser @a -GeneratePassword:$Generate -Disabled:$Disabled -Confirm:$false }
        } -OnDone {
            param($out)
            Set-ADTGuiGrid -Page 'BulkUsers' -InputObject $out
            if (@($out | Where-Object { $_.PSObject.Properties['InitialPassword'] -and $_.InitialPassword }).Count) { Write-ADTGuiLog '  Generated passwords are shown in the grid. Use "Save passwords..." to hand them over, then delete the file.' }
        }
    }
    $script:ADTGui.Actions['Bulk'] = $bulk
    $null = Add-ADTGuiButton $p 'Validate' { & $script:ADTGui.Actions['Bulk'] 'Validate' }
    $null = Add-ADTGuiButton $p 'Preview' { & $script:ADTGui.Actions['Bulk'] 'Preview' }
    $null = Add-ADTGuiButton $p 'Create users' { & $script:ADTGui.Actions['Bulk'] 'Create' } -Kind Primary
    $null = Add-ADTGuiButton $p 'Save passwords...' {
        $rows = @($script:ADTGui.Pages['BulkUsers'].Items | Where-Object { $_.PSObject.Properties['InitialPassword'] -and $_.InitialPassword })
        if (-not $rows.Count) { Show-ADTGuiMessage 'No generated passwords to save.' -Icon Warning; return }
        $d = New-Object System.Windows.Forms.SaveFileDialog
        $d.Filter = 'CSV files (*.csv)|*.csv'; $d.FileName = 'InitialPasswords.csv'
        if ($d.ShowDialog($script:ADTGui.Form) -eq 'OK') {
            $rows | Select-Object SamAccountName, UserPrincipalName, InitialPassword | Export-Csv $d.FileName -NoTypeInformation -Encoding UTF8
            Show-ADTGuiMessage "Saved $($rows.Count) passwords to $($d.FileName). Keep the file safe and delete it after hand-over." -Icon Warning
        }
    }

    # INACTIVE USERS ---------------------------------------------------------------
    $p = New-ADTGuiPage 'Inactive' 'Inactive users' 'Find enabled accounts with no sign-in for N days (service accounts and built-in accounts are skipped), tick the ones to disable, and disable them with a report you can undo from.'
    $null = Add-ADTGuiNumber $p 'Days' 'Inactive for (days):' 90 14 3650
    $null = Add-ADTGuiCheck $p 'Never' 'Include never signed in' $false
    $null = Add-ADTGuiText $p 'Exclude' 'Exclude group(s):' 200
    $null = Add-ADTGuiButton $p 'Find' {
        $prm = @{ Days = [int](Get-ADTGuiControl 'Inactive' 'Days').Value; Never = (Get-ADTGuiControl 'Inactive' 'Never').Checked; Exclude = @((Get-ADTGuiText 'Inactive' 'Exclude') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        Start-ADTGuiJob -Title 'Finding inactive users' -Parameters $prm -Script { param($Days, $Never, $Exclude) Get-ADTInactiveUser -Days $Days -IncludeNeverLoggedOn:$Never -ExcludeGroup $Exclude } -OnDone {
            param($out) Set-ADTGuiGrid -Page 'Inactive' -InputObject $out -Columns @('SamAccountName', 'Name', 'LastLogonDate', 'DaysInactive', 'Privileged', 'Reason', 'Description', 'DistinguishedName') -Selectable
        }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiButton $p 'Select all' { Set-ADTGuiSelectAll 'Inactive' $true }
    $null = Add-ADTGuiButton $p 'Select none' { Set-ADTGuiSelectAll 'Inactive' $false }
    $null = Add-ADTGuiText $p 'MoveTo' 'Move to OU (optional):' 260
    $null = Add-ADTGuiButton $p 'Disable selected' {
        $sel = @(Get-ADTGuiSelection 'Inactive')
        if (-not $sel.Count) { Show-ADTGuiMessage 'Tick the accounts to disable first.' -Icon Warning; return }
        if (-not (Confirm-ADTGui "Disable $($sel.Count) account(s)?`n`n$((@($sel | Select-Object -First 15 | ForEach-Object { $_.SamAccountName }) -join ', '))$(if ($sel.Count -gt 15) { ', ...' })")) { return }
        Start-ADTGuiJob -Title 'Disabling accounts' -Parameters @{ Users = $sel; MoveTo = (Get-ADTGuiText 'Inactive' 'MoveTo') } -Script {
            param($Users, $MoveTo)
            $a = @{ InputObject = $Users; Confirm = $false }; if ($MoveTo) { $a['MoveToOU'] = $MoveTo }
            Disable-ADTInactiveUser @a
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'Inactive' -InputObject $out -Columns @('SamAccountName', 'Name', 'DaysInactive', 'Action', 'Detail', 'DistinguishedName') }
    } -Kind Danger

    # TRUSTS ------------------------------------------------------------------------
    $p = New-ADTGuiPage 'Trusts' 'Trusts' 'List domain and forest trusts with their direction and encryption settings, and verify the secure channel of outbound trusts. Create trusts with Active Directory Domains and Trusts or netdom.'
    $null = Add-ADTGuiButton $p 'List trusts' {
        Start-ADTGuiJob -Title 'Reading trusts' -Script { Get-ADTTrust } -OnDone { param($out) Set-ADTGuiGrid -Page 'Trusts' -InputObject $out -Selectable }
    } -Kind Primary
    $null = Add-ADTGuiButton $p 'Verify selected' {
        $sel = @(Get-ADTGuiSelection 'Trusts')
        if (-not $sel.Count) { Show-ADTGuiMessage 'Tick the trusts to verify.' -Icon Warning; return }
        Start-ADTGuiJob -Title 'Verifying trusts' -Parameters @{ Names = @($sel | ForEach-Object { $_.Name }) } -Script { param($Names) $Names | ForEach-Object { Test-ADTTrust -Name $_ } } -OnDone {
            param($out) Set-ADTGuiGrid -Page 'Trusts' -InputObject $out -Columns @('Status', 'Target', 'Detail', 'Fix')
        }
    }

    # DNS HEALTH --------------------------------------------------------------------
    $p = New-ADTGuiPage 'DnsHealth' 'DNS health check' 'Service and port 53, zones (state, secure updates, aging), scavenging, forwarders, recursion, AD locator records, recent errors and stale records. Read-only.'
    $null = Add-ADTGuiCombo $p 'Server' 'DNS server:' @('localhost') 220
    $null = Add-ADTGuiNumber $p 'StaleDays' 'Stale after (days):' 30 1 3650
    $null = Add-ADTGuiButton $p 'Run health check' {
        Start-ADTGuiJob -Title 'DNS health check' -Parameters @{ Server = (Get-ADTGuiText 'DnsHealth' 'Server'); StaleDays = [int](Get-ADTGuiControl 'DnsHealth' 'StaleDays').Value } -Script { param($Server, $StaleDays) Test-ADTDnsHealth -ComputerName $Server -StaleDays $StaleDays } -OnDone {
            param($out)
            $r = $out[0]; $pg = $script:ADTGui.Pages['DnsHealth']; $pg.Report = $r.ReportPath
            Set-ADTGuiGrid -Page 'DnsHealth' -InputObject @($r.Checks) -Columns @('Status', 'Category', 'Check', 'Target', 'Detail', 'Fix')
            $pg.CountLabel.Text = "Overall: $($r.Overall)  -  $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failures"
        }
    } -Kind Primary
    $null = Add-ADTGuiButton $p 'Open report' { Open-ADTGuiPath $script:ADTGui.Pages['DnsHealth'].Report }

    # DNS RECORDS -------------------------------------------------------------------
    $p = New-ADTGuiPage 'DnsRecords' 'DNS records' 'Browse, filter, export, add, import and delete records. Deleting asks first; SOA and NS records are protected.'
    $null = Add-ADTGuiCombo $p 'Server' 'DNS server:' @('localhost') 200
    $null = Add-ADTGuiButton $p 'Load zones' {
        Start-ADTGuiJob -Title 'Loading zones' -Parameters @{ Server = (Get-ADTGuiText 'DnsRecords' 'Server') } -Script { param($Server) Get-ADTDnsZone -ComputerName $Server | ForEach-Object { $_.ZoneName } } -OnDone {
            param($out)
            $cb = Get-ADTGuiControl 'DnsRecords' 'Zone'; $cb.Items.Clear()
            $names = @($out | ForEach-Object { "$_" })
            if ($names.Count) { $cb.Items.AddRange([object[]]$names); $cb.SelectedIndex = 0 }
            Write-ADTGuiLog "  $($names.Count) zones"
        }
    }
    $null = Add-ADTGuiCombo $p 'Zone' 'Zone:' @() 220
    $null = Add-ADTGuiButton $p 'Load records' {
        $zone = Get-ADTGuiText 'DnsRecords' 'Zone'
        if (-not $zone) { Show-ADTGuiMessage 'Load zones and pick one first.' -Icon Warning; return }
        Start-ADTGuiJob -Title "Loading $zone" -Parameters @{ Server = (Get-ADTGuiText 'DnsRecords' 'Server'); Zone = $zone } -Script { param($Server, $Zone) Get-ADTDnsRecord -ZoneName $Zone -ComputerName $Server } -OnDone {
            param($out)
            $script:ADTGui.Pages['DnsRecords'].All = $out
            (Get-ADTGuiControl 'DnsRecords' 'Filter').Text = ''
            Set-ADTGuiGrid -Page 'DnsRecords' -InputObject $out -Columns @('HostName', 'RecordType', 'Data', 'Preference', 'TTL', 'Dynamic', 'Timestamp', 'AgeDays', 'ZoneName') -Selectable
        }
    } -Kind Primary
    $f = Add-ADTGuiText $p 'Filter' 'Filter:' 150
    $f.Add_TextChanged({
            $pg = $script:ADTGui.Pages['DnsRecords']
            if (-not $pg.All) { return }
            $q = $this.Text.Trim()
            $rows = if ($q) { @($pg.All | Where-Object { "$($_.HostName) $($_.RecordType) $($_.Data)" -like "*$q*" }) } else { @($pg.All) }
            Set-ADTGuiGrid -Page 'DnsRecords' -InputObject $rows -Columns @('HostName', 'RecordType', 'Data', 'Preference', 'TTL', 'Dynamic', 'Timestamp', 'AgeDays', 'ZoneName') -Selectable
        })
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiCombo $p 'Type' 'Add:' @('A', 'AAAA', 'CNAME', 'MX', 'TXT', 'PTR') 70 -List
    $null = Add-ADTGuiText $p 'Name' 'Name:' 130
    $null = Add-ADTGuiText $p 'Data' 'Data:' 190
    $null = Add-ADTGuiNumber $p 'Pref' 'MX pref:' 10 0 65535
    $null = Add-ADTGuiNumber $p 'Ttl' 'TTL (s, 0 = zone default):' 0 0 2147483
    $null = Add-ADTGuiCheck $p 'Ptr' 'Create PTR' $false
    $null = Add-ADTGuiButton $p 'Add record' {
        $prm = @{ Server = (Get-ADTGuiText 'DnsRecords' 'Server'); Zone = (Get-ADTGuiText 'DnsRecords' 'Zone'); Type = (Get-ADTGuiText 'DnsRecords' 'Type'); Name = (Get-ADTGuiText 'DnsRecords' 'Name'); Data = (Get-ADTGuiText 'DnsRecords' 'Data')
            Pref = [int](Get-ADTGuiControl 'DnsRecords' 'Pref').Value; Ttl = [int](Get-ADTGuiControl 'DnsRecords' 'Ttl').Value; Ptr = (Get-ADTGuiControl 'DnsRecords' 'Ptr').Checked }
        if (-not $prm.Zone -or -not $prm.Name -or -not $prm.Data) { Show-ADTGuiMessage 'Zone, name and data are required.' -Icon Warning; return }
        Start-ADTGuiJob -Title "Adding $($prm.Type) $($prm.Name)" -Parameters $prm -Script {
            param($Server, $Zone, $Type, $Name, $Data, $Pref, $Ttl, $Ptr)
            Add-ADTDnsRecord -ComputerName $Server -ZoneName $Zone -Type $Type -Name $Name -Data $Data -Preference $Pref -TimeToLiveSeconds $Ttl -CreatePtr:$Ptr -Confirm:$false
        } -OnDone {
            param($out)
            $r = $out[0]
            if ($r.Action -eq 'Failed') { Show-ADTGuiMessage $r.Detail -Title 'Record not added' -Icon Error } else { Write-ADTGuiLog "  Added $($r.RecordType) $($r.HostName) -> $($r.Data)" }
        }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiButton $p 'Delete selected' {
        $sel = @(Get-ADTGuiSelection 'DnsRecords')
        if (-not $sel.Count) { Show-ADTGuiMessage 'Tick the records to delete.' -Icon Warning; return }
        $list = (@($sel | Select-Object -First 12 | ForEach-Object { "$($_.HostName) $($_.RecordType) $($_.Data)" }) -join "`n")
        if (-not (Confirm-ADTGui "Delete $($sel.Count) record(s)?`n`n$list$(if ($sel.Count -gt 12) { "`n..." })")) { return }
        Start-ADTGuiJob -Title 'Deleting records' -Parameters @{ Records = $sel; Server = (Get-ADTGuiText 'DnsRecords' 'Server') } -Script {
            param($Records, $Server)
            foreach ($r in $Records) { Remove-ADTDnsRecord -ZoneName $r.ZoneName -Name $r.HostName -Type $r.RecordType -Data $r.Data -ComputerName $Server -Confirm:$false }
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'DnsRecords' -InputObject $out -Columns @('HostName', 'RecordType', 'Data', 'Action', 'Detail'); $script:ADTGui.Pages['DnsRecords'].All = $null }
    } -Kind Danger
    $null = Add-ADTGuiButton $p 'Export CSV' { Save-ADTGuiGridCsv 'DnsRecords' ("$(Get-ADTGuiText 'DnsRecords' 'Zone')_records.csv") }
    $null = Add-ADTGuiButton $p 'Import CSV...' {
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = 'CSV files (*.csv)|*.csv'
        if ($d.ShowDialog($script:ADTGui.Form) -ne 'OK') { return }
        if (-not (Confirm-ADTGui "Add the records in`n$($d.FileName)`n(rows without a ZoneName go to $(Get-ADTGuiText 'DnsRecords' 'Zone'))? Existing records are skipped.")) { return }
        Start-ADTGuiJob -Title 'Importing records' -Parameters @{ Csv = $d.FileName; Server = (Get-ADTGuiText 'DnsRecords' 'Server'); Zone = (Get-ADTGuiText 'DnsRecords' 'Zone') } -Script {
            param($Csv, $Server, $Zone) Import-ADTDnsRecord -CsvPath $Csv -ZoneName $Zone -ComputerName $Server -Confirm:$false
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'DnsRecords' -InputObject $out -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'Action', 'Detail') }
    }

    # DNS BACKUP / RESTORE ----------------------------------------------------------
    $p = New-ADTGuiPage 'DnsBackup' 'DNS zone backup and restore' 'Backs up every zone as a zone file plus a JSON copy of all records and settings. Restore re-creates missing zones (AD-integrated again) or adds only the missing records to existing ones.'
    $null = Add-ADTGuiCombo $p 'Server' 'DNS server:' @('localhost') 220
    $null = Add-ADTGuiButton $p 'Back up all zones' {
        Start-ADTGuiJob -Title 'DNS zone backup' -Parameters @{ Server = (Get-ADTGuiText 'DnsBackup' 'Server') } -Script { param($Server) Backup-ADTDnsZone -ComputerName $Server } -OnDone {
            param($out)
            if ($out.Count) { (Get-ADTGuiControl 'DnsBackup' 'Path').Text = $out[0].Folder }
            Set-ADTGuiGrid -Page 'DnsBackup' -InputObject $out -Columns @('ZoneName', 'Records', 'ZoneFile', 'Status', 'Detail')
        }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiText $p 'Path' 'Backup folder:' 380
    $null = Add-ADTGuiBrowse $p 'Path' -Mode Folder
    $null = Add-ADTGuiText $p 'Zones' 'Zones (blank = all):' 200
    Add-ADTGuiBreak $p
    $dnsRestore = {
        param([bool]$Preview)
        $path = Get-ADTGuiText 'DnsBackup' 'Path'
        if (-not $path) { Show-ADTGuiMessage 'Choose a backup folder first.' -Icon Warning; return }
        $prm = @{ Path = $path; Server = (Get-ADTGuiText 'DnsBackup' 'Server'); Zones = @((Get-ADTGuiText 'DnsBackup' 'Zones') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); Preview = $Preview }
        if (-not $Preview -and -not (Confirm-ADTGui "Restore DNS zones from`n$path`nto $($prm.Server)?")) { return }
        Start-ADTGuiJob -Title $(if ($Preview) { 'DNS restore preview' } else { 'Restoring DNS zones' }) -Parameters $prm -Script {
            param($Path, $Server, $Zones, $Preview)
            $a = @{ Path = $Path; ComputerName = $Server }; if ($Zones) { $a['ZoneName'] = $Zones }
            if ($Preview) { Restore-ADTDnsZone @a -WhatIf } else { Restore-ADTDnsZone @a -Confirm:$false }
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'DnsBackup' -InputObject $out -Columns @('ZoneName', 'Action', 'Detail') }
    }
    $script:ADTGui.Actions['DnsRestore'] = $dnsRestore
    $null = Add-ADTGuiButton $p 'Preview restore' { & $script:ADTGui.Actions['DnsRestore'] $true }
    $null = Add-ADTGuiButton $p 'Restore' { & $script:ADTGui.Actions['DnsRestore'] $false } -Kind Danger

    # STALE RECORDS -----------------------------------------------------------------
    $p = New-ADTGuiPage 'StaleDns' 'Stale DNS records' 'Dynamic records older than the threshold (0 = each zone''s aging interval, or 30 days). Removed records are saved first and can be re-imported.'
    $null = Add-ADTGuiCombo $p 'Server' 'DNS server:' @('localhost') 200
    $null = Add-ADTGuiText $p 'Zone' 'Zone (blank = all):' 180
    $null = Add-ADTGuiNumber $p 'Days' 'Older than (days):' 0 0 3650
    $null = Add-ADTGuiButton $p 'Find stale records' {
        $prm = @{ Server = (Get-ADTGuiText 'StaleDns' 'Server'); Zone = (Get-ADTGuiText 'StaleDns' 'Zone'); Days = [int](Get-ADTGuiControl 'StaleDns' 'Days').Value }
        Start-ADTGuiJob -Title 'Finding stale records' -Parameters $prm -Script {
            param($Server, $Zone, $Days)
            $a = @{ ComputerName = $Server }; if ($Zone) { $a['ZoneName'] = $Zone }; if ($Days -gt 0) { $a['OlderThanDays'] = $Days }
            Find-ADTStaleDnsRecord @a
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'StaleDns' -InputObject $out -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'Timestamp', 'AgeDays', 'ThresholdDays') -Selectable }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiButton $p 'Select all' { Set-ADTGuiSelectAll 'StaleDns' $true }
    $null = Add-ADTGuiButton $p 'Select none' { Set-ADTGuiSelectAll 'StaleDns' $false }
    $null = Add-ADTGuiCheck $p 'Responding' 'Keep A records whose address still responds' $true
    $null = Add-ADTGuiButton $p 'Remove selected' {
        $sel = @(Get-ADTGuiSelection 'StaleDns')
        if (-not $sel.Count) { Show-ADTGuiMessage 'Tick the records to remove.' -Icon Warning; return }
        if (-not (Confirm-ADTGui "Remove $($sel.Count) stale record(s)? They are saved to a CSV first so you can re-import them.")) { return }
        Start-ADTGuiJob -Title 'Removing stale records' -Parameters @{ Records = $sel; Server = (Get-ADTGuiText 'StaleDns' 'Server'); Skip = (Get-ADTGuiControl 'StaleDns' 'Responding').Checked } -Script {
            param($Records, $Server, $Skip) Remove-ADTStaleDnsRecord -InputObject $Records -ComputerName $Server -SkipIfResponding:$Skip -Confirm:$false
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'StaleDns' -InputObject $out -Columns @('ZoneName', 'HostName', 'RecordType', 'Data', 'AgeDays', 'Action', 'Detail') }
    } -Kind Danger

    # FORWARDERS --------------------------------------------------------------------
    $p = New-ADTGuiPage 'Forwarders' 'Conditional forwarders' 'Forward queries for another domain (a partner forest, a cloud private zone) to its DNS servers.'
    $null = Add-ADTGuiCombo $p 'Server' 'DNS server:' @('localhost') 200
    $null = Add-ADTGuiButton $p 'List' {
        Start-ADTGuiJob -Title 'Reading conditional forwarders' -Parameters @{ Server = (Get-ADTGuiText 'Forwarders' 'Server') } -Script { param($Server) Get-ADTConditionalForwarder -ComputerName $Server } -OnDone { param($out) Set-ADTGuiGrid -Page 'Forwarders' -InputObject $out -Selectable }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiText $p 'Domain' 'Domain:' 180
    $null = Add-ADTGuiText $p 'Ips' 'Server IPs (comma separated):' 200
    $null = Add-ADTGuiCombo $p 'Scope' 'Replicate to:' @('Forest', 'Domain', 'None') 90 -List
    $null = Add-ADTGuiButton $p 'Add forwarder' {
        $prm = @{ Server = (Get-ADTGuiText 'Forwarders' 'Server'); Domain = (Get-ADTGuiText 'Forwarders' 'Domain'); Ips = @((Get-ADTGuiText 'Forwarders' 'Ips') -split '[,; ]+' | Where-Object { $_ }); Scope = (Get-ADTGuiText 'Forwarders' 'Scope') }
        if (-not $prm.Domain -or -not $prm.Ips.Count) { Show-ADTGuiMessage 'Enter the domain and at least one server IP.' -Icon Warning; return }
        Start-ADTGuiJob -Title "Adding forwarder $($prm.Domain)" -Parameters $prm -Script {
            param($Server, $Domain, $Ips, $Scope) Add-ADTConditionalForwarder -ComputerName $Server -Name $Domain -MasterServers $Ips -ReplicationScope $Scope -Confirm:$false; Get-ADTConditionalForwarder -ComputerName $Server
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'Forwarders' -InputObject $out -Selectable }
    }
    $null = Add-ADTGuiButton $p 'Remove selected' {
        $sel = @(Get-ADTGuiSelection 'Forwarders')
        if (-not $sel.Count) { Show-ADTGuiMessage 'Tick the forwarders to remove.' -Icon Warning; return }
        if (-not (Confirm-ADTGui "Remove $((@($sel | ForEach-Object { $_.ZoneName })) -join ', ')?")) { return }
        Start-ADTGuiJob -Title 'Removing forwarders' -Parameters @{ Names = @($sel | ForEach-Object { $_.ZoneName }); Server = (Get-ADTGuiText 'Forwarders' 'Server') } -Script {
            param($Names, $Server) foreach ($n in $Names) { Remove-ADTConditionalForwarder -Name $n -ComputerName $Server -Confirm:$false }; Get-ADTConditionalForwarder -ComputerName $Server
        } -OnDone { param($out) Set-ADTGuiGrid -Page 'Forwarders' -InputObject $out -Selectable }
    } -Kind Danger

    # DIAGNOSTICS -------------------------------------------------------------------
    $p = New-ADTGuiPage 'Diagnostics' 'Diagnostics' 'Ping and test the ports AD and DNS use, or resolve a name against a specific DNS server.'
    $null = Add-ADTGuiText $p 'Host' 'Host or IP:' 200
    $null = Add-ADTGuiText $p 'Ports' 'Ports:' 230 '53, 88, 135, 389, 445, 636, 3268, 3389, 5985'
    $null = Add-ADTGuiButton $p 'Test connection' {
        $h = Get-ADTGuiText 'Diagnostics' 'Host'
        if (-not $h) { Show-ADTGuiMessage 'Enter a host name or IP address.' -Icon Warning; return }
        $ports = @((Get-ADTGuiText 'Diagnostics' 'Ports') -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        Start-ADTGuiJob -Title "Testing $h" -Parameters @{ Host_ = $h; Ports = $ports } -Script { param($Host_, $Ports) Test-ADTConnection -ComputerName $Host_ -Port $Ports } -OnDone { param($out) Set-ADTGuiGrid -Page 'Diagnostics' -InputObject $out }
    } -Kind Primary
    Add-ADTGuiBreak $p
    $null = Add-ADTGuiText $p 'Name' 'Resolve name:' 220
    $null = Add-ADTGuiText $p 'DnsServer' 'Using DNS server (optional):' 150
    $null = Add-ADTGuiCombo $p 'RType' 'Type:' @('A_AAAA', 'A', 'AAAA', 'CNAME', 'MX', 'SRV', 'TXT', 'PTR', 'NS', 'SOA') 90 -List
    $null = Add-ADTGuiButton $p 'Resolve' {
        $n = Get-ADTGuiText 'Diagnostics' 'Name'
        if (-not $n) { Show-ADTGuiMessage 'Enter a name to resolve.' -Icon Warning; return }
        Start-ADTGuiJob -Title "Resolving $n" -Parameters @{ Name = $n; Server = (Get-ADTGuiText 'Diagnostics' 'DnsServer'); Type = (Get-ADTGuiText 'Diagnostics' 'RType') } -Script { param($Name, $Server, $Type) Test-ADTDnsResolution -Name $Name -Server $Server -Type $Type } -OnDone { param($out) Set-ADTGuiGrid -Page 'Diagnostics' -InputObject $out }
    }

    # LOG ---------------------------------------------------------------------------
    $p = New-ADTGuiPage 'Log' 'Activity log' 'Every change the toolkit makes is logged with who, where and when (newest first).'
    $null = Add-ADTGuiButton $p 'Refresh' { Update-ADTGuiLogPage } -Kind Primary
    $null = Add-ADTGuiButton $p 'Open log file' { Open-ADTGuiPath (Get-ADTConfig).LogFile }
}

# ----------------------------------------------------------------------------------
# Main window
# ----------------------------------------------------------------------------------
function Show-ADTGui {
    <#
    .SYNOPSIS
        Opens the AD & DNS Toolkit window.
    .PARAMETER Page
        The page to open on.
    .PARAMETER NoShow
        Builds the window and returns it without showing it (used by tests).
    .EXAMPLE
        Show-ADTGui -Page DnsRecords
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Home', 'ADHealth', 'ADInventory', 'ADBackup', 'BulkUsers', 'Inactive', 'Trusts', 'DnsHealth', 'DnsRecords', 'DnsBackup', 'StaleDns', 'Forwarders', 'Diagnostics', 'Log')]
        [string]$Page = 'Home',
        [switch]$NoShow
    )
    if (-not (Test-ADTGuiAvailable)) { throw 'The graphical interface needs Windows with a desktop session. Use Show-ADTMenu or the cmdlets instead.' }
    if (-not $NoShow -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Windows Forms needs a single-threaded apartment. Start PowerShell with -STA (Start-Toolkit.ps1 and Launch-Toolkit.cmd do this for you).'
    }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { Write-Verbose 'Text rendering already set' }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AD & DNS Toolkit v$script:ADTVersion"
    $form.Size = New-Object System.Drawing.Size(1240, 800)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 640)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $form.AutoScaleMode = 'Dpi'
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 252)
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path) } catch { Write-Verbose 'No icon' }

    $script:ADTGui = @{
        Form = $form; Pages = [ordered]@{}; NavButtons = @{}; Actions = @{}; BrowseInfo = @{}; Job = $null; Queue = [System.Collections.Generic.List[object]]::new(); DnsServers = $null; Current = $null
        NavBack = [System.Drawing.Color]::FromArgb(16, 24, 44); NavFore = [System.Drawing.Color]::FromArgb(205, 214, 232)
    }
    $g = $script:ADTGui

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = 'Fill'
    $g.Content = $content

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'; $logBox.Dock = 'Bottom'; $logBox.Height = 130
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9); $logBox.BackColor = [System.Drawing.Color]::White; $logBox.BorderStyle = 'FixedSingle'
    $g.LogBox = $logBox

    $strip = New-Object System.Windows.Forms.StatusStrip
    $status = New-Object System.Windows.Forms.ToolStripStatusLabel
    $status.Spring = $true; $status.TextAlign = 'MiddleLeft'; $status.Text = 'Ready'
    $prog = New-Object System.Windows.Forms.ToolStripProgressBar
    $prog.Visible = $false; $prog.Width = 160; $prog.MarqueeAnimationSpeed = 30
    $out = New-Object System.Windows.Forms.ToolStripStatusLabel
    $out.Text = "Output: $((Get-ADTConfig).OutputRoot)"; $out.IsLink = $true
    $out.Add_Click({ $r = (Get-ADTConfig).OutputRoot; if (-not (Test-Path $r)) { New-Item -ItemType Directory $r -Force | Out-Null }; Invoke-Item $r })
    [void]$strip.Items.AddRange(@($status, $prog, $out))
    $g.StatusLabel = $status; $g.Progress = $prog; $g.OutputLabel = $out

    # Navigation
    $nav = New-Object System.Windows.Forms.FlowLayoutPanel
    $nav.Dock = 'Left'; $nav.Width = 218; $nav.FlowDirection = 'TopDown'; $nav.WrapContents = $false; $nav.AutoScroll = $true
    $nav.BackColor = $g.NavBack; $nav.Padding = New-Object System.Windows.Forms.Padding(10, 14, 10, 10)
    $g.Nav = $nav
    $brand = New-Object System.Windows.Forms.Label
    $brand.Text = 'AD & DNS Toolkit'; $brand.UseMnemonic = $false; $brand.ForeColor = [System.Drawing.Color]::White; $brand.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
    $brand.AutoSize = $true; $brand.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 2)
    $ver = New-Object System.Windows.Forms.Label
    $ver.Text = "v$script:ADTVersion  -  open source (MIT)"; $ver.ForeColor = $g.NavFore; $ver.AutoSize = $true; $ver.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 10)
    $nav.Controls.AddRange(@($brand, $ver))
    $lastGroup = ''
    foreach ($k in $script:ADTGuiPages.Keys) {
        $info = $script:ADTGuiPages[$k]
        if ($info.Group -ne $lastGroup) {
            $gl = New-Object System.Windows.Forms.Label
            $gl.Text = $info.Group; $gl.ForeColor = [System.Drawing.Color]::FromArgb(120, 136, 168); $gl.AutoSize = $true
            $gl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8); $gl.Margin = New-Object System.Windows.Forms.Padding(5, 12, 0, 4)
            $nav.Controls.Add($gl); $lastGroup = $info.Group
        }
        $b = New-Object System.Windows.Forms.Button
        $b.Text = '  ' + $info.Text; $b.Tag = $k; $b.TextAlign = 'MiddleLeft'; $b.Width = 192; $b.Height = 32
        $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.BackColor = $g.NavBack; $b.ForeColor = $g.NavFore; $b.Cursor = [System.Windows.Forms.Cursors]::Hand
        $b.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 1)
        $b.Add_Click({ Show-ADTGuiPage $this.Tag })
        $nav.Controls.Add($b)
        $g.NavButtons[$k] = $b
    }
    $dark = New-Object System.Windows.Forms.CheckBox
    $dark.Text = 'Dark mode'; $dark.ForeColor = $g.NavFore; $dark.AutoSize = $true; $dark.Margin = New-Object System.Windows.Forms.Padding(6, 18, 0, 0)
    $dark.Add_CheckedChanged({ Set-ADTGuiTheme $this.Checked })
    $nav.Controls.Add($dark)

    # Dock order: the control added last docks first.
    $form.Controls.Add($content)
    $form.Controls.Add($logBox)
    $form.Controls.Add($strip)
    $form.Controls.Add($nav)

    Initialize-ADTGuiPages

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({ Update-ADTGuiJob })
    $g.Timer = $timer

    $form.Add_Shown({
            $script:ADTGui.Timer.Start()
            Write-ADTGuiLog "AD & DNS Toolkit v$script:ADTVersion started by $env:USERDOMAIN\$env:USERNAME on $([Environment]::MachineName)$(if (Test-ADTIsAdmin) { ' (administrator)' })"
            Show-ADTGuiPage $script:ADTGui.StartPage
        })
    $form.Add_FormClosing({
            param($s, $e)
            $j = $script:ADTGui.Job
            if ($j) {
                if (-not (Confirm-ADTGui "'$($j.Title)' is still running. Stop it and close?")) { $e.Cancel = $true; return }
                try { $j.PS.Stop() } catch { Write-Verbose 'Stop failed' }
            }
            $script:ADTGui.Queue.Clear()
            $script:ADTGui.Timer.Stop()
        })
    $g.StartPage = $Page
    if ($NoShow) { return $form }
    [void]$form.ShowDialog()
    $form.Dispose()
}
