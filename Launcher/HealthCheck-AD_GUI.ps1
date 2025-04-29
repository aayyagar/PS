<#
==================================================================================
Title        : Active Directory Health Check (GUI)
Module       : HealthCheck-AD_GUI.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
Description  : 
    Simple WinForms-based GUI to run Active Directory Health Check,
    view live status, and open report folder easily.
==================================================================================
#>

# Step 1: Load WinForms Assembly
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# Step 2: Define Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Active Directory Health Check Toolkit"
$form.Size = New-Object System.Drawing.Size(500,300)
$form.StartPosition = "CenterScreen"

# Step 3: Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(30,30)
$statusLabel.Size = New-Object System.Drawing.Size(420,40)
$statusLabel.Text = "Ready to run Health Check..."
$form.Controls.Add($statusLabel)

# Step 4: Run Health Check Button
$runButton = New-Object System.Windows.Forms.Button
$runButton.Location = New-Object System.Drawing.Point(50,100)
$runButton.Size = New-Object System.Drawing.Size(180,40)
$runButton.Text = "Run Health Check"
$form.Controls.Add($runButton)

# Step 5: Open Report Folder Button
$openButton = New-Object System.Windows.Forms.Button
$openButton.Location = New-Object System.Drawing.Point(260,100)
$openButton.Size = New-Object System.Drawing.Size(180,40)
$openButton.Text = "Open Reports Folder"
$form.Controls.Add($openButton)

# Step 6: Exit Button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(180,170)
$exitButton.Size = New-Object System.Drawing.Size(120,30)
$exitButton.Text = "Exit"
$form.Controls.Add($exitButton)

# Step 7: Define Actions
$runButton.Add_Click({
    $statusLabel.Text = "Running Health Check... Please wait..."

    # Call your original HealthCheck-AD.ps1 script
    try {
        $scriptPath = "$PSScriptRoot\..\AD_Tools\HealthCheck-AD.ps1"
        if (Test-Path $scriptPath) {
            powershell.exe -ExecutionPolicy Bypass -File $scriptPath
            $statusLabel.Text = "✅ Health Check completed successfully!"
        }
        else {
            $statusLabel.Text = "❌ HealthCheck-AD.ps1 not found!"
        }
    }
    catch {
        $statusLabel.Text = "❌ Error running Health Check!"
    }
})

$openButton.Add_Click({
    $UserDocuments = [Environment]::GetFolderPath('MyDocuments')
    $HealthCheckPath = Join-Path $UserDocuments "AD_HealthCheck"
    if (Test-Path $HealthCheckPath) {
        Start-Process $HealthCheckPath
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Reports folder not found!","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$exitButton.Add_Click({
    $form.Close()
})

# Step 8: Show Form
$form.Topmost = $true
[void]$form.ShowDialog()
