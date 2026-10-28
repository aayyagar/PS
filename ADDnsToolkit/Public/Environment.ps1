# ==================================================================================
# AD & DNS Toolkit - environment detection and prerequisites
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================

function Get-ADTCloudProvider {
    <#
    .SYNOPSIS
        Detects Azure, AWS or Google Cloud from the instance metadata service (2-second timeouts).
    #>
    [CmdletBinding()]
    param([int]$TimeoutSec = 2)
    $imds = 'http://169.254.169.254'
    if (-not (Test-ADTTcpPort -ComputerName '169.254.169.254' -Port 80 -TimeoutMs 700)) { return 'On-premises' }
    try { if (Invoke-RestMethod -Uri "$imds/metadata/instance?api-version=2021-02-01" -Headers @{ Metadata = 'true' } -TimeoutSec $TimeoutSec -ErrorAction Stop) { return 'Azure' } } catch { Write-Verbose 'Not Azure' }
    try {
        # AWS IMDSv2 needs a session token first; fall back to IMDSv1.
        $tok = $null
        try { $tok = Invoke-RestMethod -Method Put -Uri "$imds/latest/api/token" -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '60' } -TimeoutSec $TimeoutSec -ErrorAction Stop } catch { $tok = $null }
        $h = @{}; if ($tok) { $h['X-aws-ec2-metadata-token'] = $tok }
        if (Invoke-RestMethod -Uri "$imds/latest/meta-data/instance-id" -Headers $h -TimeoutSec $TimeoutSec -ErrorAction Stop) { return 'AWS' }
    }
    catch { Write-Verbose 'Not AWS' }
    try { if (Invoke-RestMethod -Uri "$imds/computeMetadata/v1/instance/id" -Headers @{ 'Metadata-Flavor' = 'Google' } -TimeoutSec $TimeoutSec -ErrorAction Stop) { return 'Google Cloud' } } catch { Write-Verbose 'Not GCP' }
    'On-premises'
}

function Get-ADTPlatformType {
    <#
    .SYNOPSIS
        Physical server or which hypervisor / cloud the machine runs on.
    #>
    [CmdletBinding()]
    param()
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
        $m = "$($cs.Manufacturer) $($cs.Model) $($bios.Manufacturer) $($bios.Version)"
        switch -Regex ($m) {
            'VMware' { return 'VMware virtual machine' }
            'Amazon EC2|amazon' { return 'AWS EC2 instance' }
            'Google' { return 'Google Compute Engine VM' }
            'Nutanix|AHV' { return 'Nutanix AHV virtual machine' }
            'VirtualBox|innotek' { return 'VirtualBox virtual machine' }
            'KVM|QEMU|Red Hat' { return 'KVM/QEMU virtual machine' }
            'Xen' { return 'Xen virtual machine' }
            'Microsoft Corporation Virtual Machine|Hyper-V' { return 'Hyper-V virtual machine' }
            'Parallels' { return 'Parallels virtual machine' }
        }
        if ($cs.HypervisorPresent -and $cs.Model -match 'Virtual') { return 'Virtual machine' }
        'Physical machine'
    }
    catch { 'Unknown' }
}

function Get-ADTClusterStatus {
    <#
    .SYNOPSIS
        Failover cluster membership and health of this machine (Standalone when not clustered).
    #>
    [CmdletBinding()]
    param()
    $r = [ordered]@{ ClusterName = 'N/A'; Node = [Environment]::MachineName; Status = 'Standalone'; Health = 'N/A'; NodesDown = 0; GroupsOffline = 0 }
    if (-not (Test-ADTModule 'FailoverClusters')) { return [pscustomobject]$r }
    try {
        Import-Module FailoverClusters -ErrorAction Stop -Verbose:$false
        $c = Get-Cluster -ErrorAction Stop
        $down = @(Get-ClusterNode -ErrorAction Stop | Where-Object { $_.State -ne 'Up' })
        $off = @(Get-ClusterGroup -ErrorAction Stop | Where-Object { $_.State -ne 'Online' })
        $r.ClusterName = $c.Name; $r.Status = 'Clustered node'; $r.NodesDown = $down.Count; $r.GroupsOffline = $off.Count
        $r.Health = if ($down.Count -or $off.Count) { 'Warning' } else { 'Healthy' }
    }
    catch { Write-Verbose "No cluster: $($_.Exception.Message)" }
    [pscustomobject]$r
}

function Get-ADTEnvironment {
    <#
    .SYNOPSIS
        Describes the machine the toolkit runs on: OS, PowerShell, domain, cloud, hypervisor,
        cluster and which management modules are installed.
    .EXAMPLE
        Get-ADTEnvironment | Format-List
    #>
    [CmdletBinding()]
    param([switch]$SkipCloud)
    $isWin = ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows)
    $os = $null
    if ($isWin) { try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $os = $null } }
    $domain = $null
    if ($isWin) { try { $domain = ([DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name } catch { $domain = $null } }
    [pscustomobject][ordered]@{
        ComputerName        = [Environment]::MachineName
        OperatingSystem     = $(if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString })
        OSVersion           = $(if ($os) { $os.Version } else { "$([Environment]::OSVersion.Version)" })
        Architecture        = $(if ($os) { $os.OSArchitecture } elseif ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' })
        IsServer            = [bool]($os -and $os.ProductType -ne 1)
        IsDomainController  = [bool]($os -and $os.ProductType -eq 2)
        PowerShell          = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
        Domain              = $(if ($domain) { $domain } else { 'Not domain-joined' })
        RunningAsAdmin      = Test-ADTIsAdmin
        CloudProvider       = $(if ($SkipCloud) { 'Not checked' } else { Get-ADTCloudProvider })
        Platform            = $(if ($isWin) { Get-ADTPlatformType } else { 'Unknown' })
        Cluster             = $(if ($isWin) { (Get-ADTClusterStatus).Status } else { 'N/A' })
        ActiveDirectoryRsat = Test-ADTModule 'ActiveDirectory'
        DnsServerRsat       = Test-ADTModule 'DnsServer'
        FailoverClusterRsat = Test-ADTModule 'FailoverClusters'
        ToolkitVersion      = $script:ADTVersion
        OutputRoot          = (Get-ADTConfig).OutputRoot
    }
}

function Install-ADTPrerequisite {
    <#
    .SYNOPSIS
        Installs the RSAT management tools the toolkit needs (only the tools - never server roles).
    .DESCRIPTION
        On Windows Server it uses Install-WindowsFeature; on Windows 10/11 it adds the RSAT
        Features on Demand. Needs an elevated session and, for Windows 10/11, access to Windows Update.
    .EXAMPLE
        Install-ADTPrerequisite -Component ActiveDirectory, DnsServer -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([ValidateSet('ActiveDirectory', 'DnsServer', 'FailoverClusters')][string[]]$Component = @('ActiveDirectory', 'DnsServer'))
    if (-not (Test-ADTIsAdmin)) { throw 'Run PowerShell as Administrator to install RSAT tools.' }
    $os = Get-CimInstance Win32_OperatingSystem
    $server = $os.ProductType -ne 1
    $feature = @{ ActiveDirectory = 'RSAT-AD-PowerShell'; DnsServer = 'RSAT-DNS-Server'; FailoverClusters = 'RSAT-Clustering-PowerShell' }
    $capability = @{ ActiveDirectory = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'; DnsServer = 'Rsat.Dns.Tools~~~~0.0.1.0'; FailoverClusters = 'Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0' }
    foreach ($c in $Component) {
        if (Test-ADTModule $c) { Write-ADTStatus "$c tools are already installed." Ok; continue }
        $name = if ($server) { $feature[$c] } else { $capability[$c] }
        if ($PSCmdlet.ShouldProcess($name, 'Install')) {
            Write-ADTStatus "Installing $name..." Step
            try {
                if ($server) { Install-WindowsFeature -Name $name -ErrorAction Stop | Out-Null }
                else { Add-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null }
                Write-ADTLog "Installed $name" Change
                Write-ADTStatus "Installed $name." Ok
            }
            catch { Write-ADTStatus "Could not install $($name): $($_.Exception.Message)" Error; Write-ADTLog "Failed to install $($name): $($_.Exception.Message)" Error }
        }
    }
}
