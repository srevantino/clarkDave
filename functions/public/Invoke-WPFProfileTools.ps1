function Invoke-WPFAutoReapplyEnable {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "AutoReapply" }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name for scheduled reapply:", "Enable Auto Reapply", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Register-WinUtilAutoReapplyTask -ProfileName $profileName
        [System.Windows.MessageBox]::Show("Auto reapply enabled. Scheduled tasks were created for startup and logon using profile '$profileName'.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to enable auto reapply: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFAutoReapplyDisable {
    try {
        Unregister-WinUtilAutoReapplyTask
        [System.Windows.MessageBox]::Show("Auto reapply scheduled tasks have been removed.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to disable auto reapply: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileExportFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "Clark profile JSON (*.json)|*.json"
    $dlg.FileName = "clark-profile.json"
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    $path = $dlg.FileName
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }
    try {
        Invoke-WinUtilProfileExportToPath -LiteralPath $path
        [System.Windows.MessageBox]::Show("Profile exported to:`n$path", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Export failed: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileImportFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Clark profile JSON (*.json)|*.json|All files (*.*)|*.*"
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    $path = $dlg.FileName
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json
        $sync.selectedApps = [System.Collections.Generic.List[string]]::new()
        $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
        $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()
        $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()
        Invoke-WinUtilProfileImportFromObject -ProfileObject $obj
        if (-not $PARAM_NOUI) {
            $sync.ImportInProgress = $true
            try {
                Reset-WPFCheckBoxes -doToggles $true
            } finally {
                $sync.ImportInProgress = $false
            }
        }
        [System.Windows.MessageBox]::Show("Profile imported from:`n$path", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Import failed: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileSave {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "MyProfile" }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name to save current selections:", "Save Profile", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Save-WinUtilProfile -Name $profileName | Out-Null
        [System.Windows.MessageBox]::Show("Profile '$profileName' saved.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to save profile: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileLoad {
    $profiles = @(Get-WinUtilProfiles)
    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No saved profiles were found.", "clark", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { $profiles[0] }
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to load:", "Load Profile", $defaultName)
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Import-WinUtilProfile -Name $profileName -ApplyToUI
        [System.Windows.MessageBox]::Show("Profile '$profileName' loaded.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to load profile: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileDelete {
    $profiles = @(Get-WinUtilProfiles)
    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No saved profiles were found.", "clark", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to delete:", "Delete Profile", $profiles[0])
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        return
    }

    try {
        Remove-WinUtilProfile -Name $profileName
        [System.Windows.MessageBox]::Show("Profile '$profileName' deleted.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to delete profile: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFRollbackLastTweak {
    try {
        $restored = Invoke-WinUtilRollbackLatest
        if ($restored) {
            [System.Windows.MessageBox]::Show("Last tweak snapshot was restored from rollback journal.", "clark", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("No rollback snapshot could be restored.", "clark", "OK", "Warning")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Rollback failed: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Get-WinUtilActivationScriptsRoot {
    $basePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($sync.PSScriptRoot)) {
        $basePaths += $sync.PSScriptRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $basePaths += $PSScriptRoot
    }
    $cwdPath = (Get-Location).Path
    if (-not [string]::IsNullOrWhiteSpace($cwdPath)) {
        $basePaths += $cwdPath
    }

    $candidateRoots = New-Object System.Collections.Generic.List[string]
    foreach ($basePath in ($basePaths | Select-Object -Unique)) {
        $current = $basePath
        for ($i = 0; $i -lt 5 -and -not [string]::IsNullOrWhiteSpace($current); $i++) {
            $candidateRoots.Add((Join-Path $current "Microsoft-Activation-Scripts-master"))
            $parent = Split-Path -Path $current -Parent
            if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $current)) {
                break
            }
            $current = $parent
        }
    }

    foreach ($candidate in ($candidateRoots | Select-Object -Unique)) {
        $masAioPath = Join-Path $candidate "MAS\All-In-One-Version-KL\MAS_AIO.cmd"
        if (Test-Path $masAioPath) {
            return $candidate
        }
    }

    return $null
}

function Invoke-WPFActivationScriptsMenu {
    try {
        $masRoot = Get-WinUtilActivationScriptsRoot
        if (-not $masRoot) {
            throw "Microsoft-Activation-Scripts-master folder was not found near clark."
        }

        $masAioPath = Join-Path $masRoot "MAS\All-In-One-Version-KL\MAS_AIO.cmd"
        if (-not (Test-Path $masAioPath)) {
            throw "MAS menu script was not found: $masAioPath"
        }

        Start-Process -FilePath $masAioPath
    } catch {
        [System.Windows.MessageBox]::Show("Unable to open MAS menu: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFActivationStatus {
    try {
        # Summary is read from the license service via WMI only. Running MAS Check_Activation_Status.cmd
        # first blocked the UI for a long time and did not affect this dialog.
        $st = Get-WinUtilActivationStatus
        $lines = @(
            "Summary (license service on this PC):",
            "",
            "Windows: $($st.Windows)",
            "Office: $($st.Office)",
            ""
        )

        $needActivate = @()
        if ($st.Windows -eq "Not Activated") {
            $needActivate += "Windows"
        }
        if ($st.OfficeDetected -and ($st.Office -eq "Not Activated")) {
            $needActivate += "Office"
        }

        if ($needActivate.Count -gt 0) {
            $lines += "May need activation: $($needActivate -join ', ')."
            $lines += "If you have a valid license, use the MAS activation menu."
        } else {
            $lines += "Nothing flagged as not activated (Windows activated; Office OK or not installed)."
        }

        [System.Windows.MessageBox]::Show(($lines -join [Environment]::NewLine), "Activation check", "OK", "Information") | Out-Null

        if ($needActivate.Count -gt 0) {
            if (Get-WinUtilActivationScriptsRoot) {
                $openMas = [System.Windows.MessageBox]::Show(
                    "Open the MAS activation menu now?",
                    "Activation",
                    "YesNo",
                    "Question"
                )
                if ($openMas -eq [System.Windows.MessageBoxResult]::Yes) {
                    Invoke-WPFActivationScriptsMenu
                }
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Activation check failed: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}

function Invoke-WPFProfileCreateWithOptions {
    Add-Type -AssemblyName System.Windows.Forms

    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "MyProfile" }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Create profile - choose what to save"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.ClientSize = New-Object System.Drawing.Size(440, 300)
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Profile name:"
    $lblName.Location = New-Object System.Drawing.Point(12, 14)
    $lblName.AutoSize = $true
    [void]$form.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Text = $defaultName
    $txtName.Location = New-Object System.Drawing.Point(12, 34)
    $txtName.Width = 410
    [void]$form.Controls.Add($txtName)

    [int]$profileFormY = 68
    $cbApps = New-Object System.Windows.Forms.CheckBox
    $cbApps.Text = "Include selected Applications (Install tab)"
    $cbApps.Checked = $true
    $cbApps.Location = New-Object System.Drawing.Point(12, $profileFormY)
    $cbApps.Width = 410
    [void]$form.Controls.Add($cbApps)
    $profileFormY = [int]($profileFormY + 28)

    $cbTweaks = New-Object System.Windows.Forms.CheckBox
    $cbTweaks.Text = "Include selected Tweaks"
    $cbTweaks.Checked = $true
    $cbTweaks.Location = New-Object System.Drawing.Point(12, $profileFormY)
    $cbTweaks.Width = 410
    [void]$form.Controls.Add($cbTweaks)
    $profileFormY = [int]($profileFormY + 28)

    $cbToggles = New-Object System.Windows.Forms.CheckBox
    $cbToggles.Text = "Include selected Config toggles"
    $cbToggles.Checked = $true
    $cbToggles.Location = New-Object System.Drawing.Point(12, $profileFormY)
    $cbToggles.Width = 410
    [void]$form.Controls.Add($cbToggles)
    $profileFormY = [int]($profileFormY + 28)

    $cbFeatures = New-Object System.Windows.Forms.CheckBox
    $cbFeatures.Text = "Include selected Config features"
    $cbFeatures.Checked = $true
    $cbFeatures.Location = New-Object System.Drawing.Point(12, $profileFormY)
    $cbFeatures.Width = 410
    [void]$form.Controls.Add($cbFeatures)
    $profileFormY = [int]($profileFormY + 32)

    $cbMerge = New-Object System.Windows.Forms.CheckBox
    $cbMerge.Text = "If this profile already exists, merge (add new entries; keep existing)"
    $cbMerge.Checked = $false
    $cbMerge.Location = New-Object System.Drawing.Point(12, $profileFormY)
    $cbMerge.Width = 410
    [void]$form.Controls.Add($cbMerge)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Save"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = New-Object System.Drawing.Point(268, 258)
    $btnOk.Width = 75
    [void]$form.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = New-Object System.Drawing.Point(347, 258)
    $btnCancel.Width = 75
    [void]$form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $profileName = $txtName.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        [System.Windows.MessageBox]::Show("Profile name cannot be empty.", "clark", "OK", "Warning")
        return
    }

    try {
        Save-WinUtilProfilePartial -Name $profileName `
            -IncludeApps $cbApps.Checked `
            -IncludeTweaks $cbTweaks.Checked `
            -IncludeToggles $cbToggles.Checked `
            -IncludeFeatures $cbFeatures.Checked `
            -MergeExisting:($cbMerge.Checked)
        [System.Windows.MessageBox]::Show("Profile '$profileName' saved.", "clark", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to save profile: $($_.Exception.Message)", "clark", "OK", "Error")
    }
}
