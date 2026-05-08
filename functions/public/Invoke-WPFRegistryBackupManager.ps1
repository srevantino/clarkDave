function Invoke-WPFRegistryBackupManager {
    <#
    .SYNOPSIS
        UI to list pre-tweak .reg backups, open folder, or restore via reg import.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark - Registry backups (pre-tweak)"
    $form.Size = New-Object System.Drawing.Size(720, 420)
    $form.StartPosition = "CenterScreen"

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, 10)
    $lbl.Size = New-Object System.Drawing.Size(680, 40)
    $lbl.Text = "Backups are created automatically before running tweaks (HKCU/HKLM). Restoring merges values from the file into the registry; it does not delete keys added after the backup. Distinct from 'Rollback Last Tweak Snapshot' (rollback journal)."
    [void]$form.Controls.Add($lbl)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 55)
    $list.Size = New-Object System.Drawing.Size(680, 240)
    $list.SelectionMode = "MultiExtended"
    [void]$form.Controls.Add($list)

    foreach ($f in @(Get-WinUtilRegistryBackupFiles)) {
        [void]$list.Items.Add($f.FullName)
    }

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.Location = New-Object System.Drawing.Point(12, 302)
    $btnRow.Width = 696
    $btnRow.AutoSize = $true
    $btnRow.WrapContents = $true
    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight

    $btnFolder = New-Object System.Windows.Forms.Button
    $btnFolder.Text = "Open backups folder"
    $btnFolder.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)
    $btnFolder.Add_Click({
        Start-Process explorer.exe (Get-WinUtilClarkBackupsDirectory)
    })
    [void]$btnRow.Controls.Add($btnFolder)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Refresh"
    $btnRefresh.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)
    $btnRefresh.Add_Click({
        $list.Items.Clear()
        foreach ($f in @(Get-WinUtilRegistryBackupFiles)) {
            [void]$list.Items.Add($f.FullName)
        }
    })
    [void]$btnRow.Controls.Add($btnRefresh)

    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Text = "Restore selected..."
    $btnRestore.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)
    $btnRestore.Add_Click({
        if ($list.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Select one or more .reg files.", "clark", "OK", "Information")
            return
        }
        $msg = @"
reg import merges the selected file(s) into the current registry.

Run Clark as Administrator. Incorrect restores can destabilize Windows.

Continue?
"@
        $c = [System.Windows.Forms.MessageBox]::Show($msg, "Confirm restore", "YesNo", "Warning")
        if ($c -ne 'Yes') { return }
        $paths = @($list.SelectedItems | ForEach-Object { [string]$_ })
        try {
            Invoke-WinUtilRegistryBackupRestore -LiteralPaths $paths
            [System.Windows.Forms.MessageBox]::Show("Restore completed.", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Restore failed: $($_.Exception.Message)", "clark", "OK", "Error")
        }
    })
    [void]$btnRow.Controls.Add($btnRestore)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)
    $btnClose.Add_Click({ $form.Close() })
    [void]$btnRow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnFolder, $btnRefresh, $btnRestore, $btnClose)
    [void]$form.Controls.Add($btnRow)

    [void]$form.ShowDialog()
}
