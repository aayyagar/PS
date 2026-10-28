# ==================================================================================
# AD & DNS Toolkit - module loader
# Copyright (c) 2024-2026 Akhilesh Ayyagari. MIT License.
# ==================================================================================
$script:ADTModuleRoot = $PSScriptRoot
$script:ADTManifestPath = Join-Path $PSScriptRoot 'ADDnsToolkit.psd1'

foreach ($folder in 'Private', 'Public', 'Console', 'GUI') {
    $dir = Join-Path $PSScriptRoot $folder
    if (Test-Path $dir) {
        foreach ($file in Get-ChildItem -Path $dir -Filter '*.ps1' | Sort-Object Name) { . $file.FullName }
    }
}
