@{
    RootModule           = 'ADDnsToolkit.psm1'
    ModuleVersion        = '2.0.0'
    GUID                 = '11432ca1-602f-5887-b2e4-1bfea467e537'
    Author               = 'Akhilesh Ayyagari'
    CompanyName          = 'Community'
    Copyright            = '(c) 2024-2026 Akhilesh Ayyagari. MIT License.'
    Description          = 'Open-source Active Directory and DNS administration toolkit: health checks, inventory, backup and restore, bulk users, inactive accounts, DNS records, zones, stale records and forwarders - as cmdlets, a console menu and a Windows GUI. Read-only by default; every change supports -WhatIf.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @(
        'Get-ADTConfig',
        'Set-ADTConfig',
        'Get-ADTEnvironment',
        'Get-ADTCloudProvider',
        'Get-ADTPlatformType',
        'Get-ADTClusterStatus',
        'Install-ADTPrerequisite',
        'Get-ADTInventory',
        'Test-ADTHealth',
        'Backup-ADTObject',
        'Restore-ADTObject',
        'Test-ADTBulkUserCsv',
        'New-ADTBulkUser',
        'Get-ADTInactiveUser',
        'Disable-ADTInactiveUser',
        'Get-ADTTrust',
        'Test-ADTTrust',
        'Get-ADTDnsServer',
        'Get-ADTDnsZone',
        'Get-ADTDnsRecord',
        'Add-ADTDnsRecord',
        'Import-ADTDnsRecord',
        'Remove-ADTDnsRecord',
        'Backup-ADTDnsZone',
        'Restore-ADTDnsZone',
        'Find-ADTStaleDnsRecord',
        'Remove-ADTStaleDnsRecord',
        'Test-ADTDnsHealth',
        'Get-ADTConditionalForwarder',
        'Add-ADTConditionalForwarder',
        'Remove-ADTConditionalForwarder',
        'Test-ADTDnsResolution',
        'Test-ADTConnection',
        'New-ADTPassword',
        'Show-ADTMenu',
        'Show-ADTGui',
        'Test-ADTGuiAvailable'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'DNS', 'AD', 'HealthCheck', 'Inventory', 'Backup', 'Windows', 'WindowsServer', 'Admin', 'GUI', 'RSAT')
            LicenseUri   = 'https://github.com/aayyagar/PS/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/aayyagar/PS'
            ReleaseNotes = 'v2.0.0: rebuilt as a module with a console menu and an asynchronous Windows GUI; safe, previewable changes; fixes for every v1 tool. See CHANGELOG.md.'
        }
    }
}
