function Invoke-WPFWindowsUpdatePolicy {
    <#
    .SYNOPSIS
        Configure Windows Update policy (defer / disable automatic updates) or remove policy keys.
        HKLM paths require Administrator.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $clark = 'HKCU:\Software\Clark\WindowsUpdatePolicy'

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark - Windows Update policy'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(480, 48)
    $lbl.Text = 'Policy values are written under HKLM\SOFTWARE\Policies (requires Administrator). Use Remove policy keys to clear defer/disable settings Clark applied.'
    [void]$form.Controls.Add($lbl)

    [int]$wuFormY = 68
    $chkDeferFeat = New-Object System.Windows.Forms.CheckBox
    $chkDeferFeat.Text = 'Defer feature updates (enable policy)'
    $chkDeferFeat.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkDeferFeat.Width = 280
    [void]$form.Controls.Add($chkDeferFeat)
    $wuFormY = [int]($wuFormY + 28)

    $lblDf = New-Object System.Windows.Forms.Label
    $lblDf.Text = 'Feature defer (days, 0-365):'
    $lblDf.Location = New-Object System.Drawing.Point(28, $wuFormY)
    $lblDf.AutoSize = $true
    [void]$form.Controls.Add($lblDf)
    $numFeat = New-Object System.Windows.Forms.NumericUpDown
    $numFeat.Location = New-Object System.Drawing.Point(220, [int]($wuFormY - 2))
    $numFeat.Width = 80
    $numFeat.Minimum = 0
    $numFeat.Maximum = 365
    $numFeat.Value = 120
    [void]$form.Controls.Add($numFeat)
    $wuFormY = [int]($wuFormY + 32)

    $chkDeferQual = New-Object System.Windows.Forms.CheckBox
    $chkDeferQual.Text = 'Defer quality updates (enable policy)'
    $chkDeferQual.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkDeferQual.Width = 280
    [void]$form.Controls.Add($chkDeferQual)
    $wuFormY = [int]($wuFormY + 28)

    $lblDq = New-Object System.Windows.Forms.Label
    $lblDq.Text = 'Quality defer (days, 0-30):'
    $lblDq.Location = New-Object System.Drawing.Point(28, $wuFormY)
    $lblDq.AutoSize = $true
    [void]$form.Controls.Add($lblDq)
    $numQual = New-Object System.Windows.Forms.NumericUpDown
    $numQual.Location = New-Object System.Drawing.Point(220, [int]($wuFormY - 2))
    $numQual.Width = 80
    $numQual.Minimum = 0
    $numQual.Maximum = 30
    $numQual.Value = 7
    [void]$form.Controls.Add($numQual)
    $wuFormY = [int]($wuFormY + 36)

    $chkNoAuto = New-Object System.Windows.Forms.CheckBox
    $chkNoAuto.Text = 'Disable automatic updates (NoAutoUpdate = 1) - use with caution'
    $chkNoAuto.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkNoAuto.Width = 440
    [void]$form.Controls.Add($chkNoAuto)
    $wuFormY = [int]($wuFormY + 40)

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $btnRow.Width = 496
    $btnRow.AutoSize = $true
    $btnRow.WrapContents = $false
    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Apply policy'
    $btnApply.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnApply.Add_Click({
        try {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
                [System.Windows.Forms.MessageBox]::Show('Applying HKLM policies requires running Clark as Administrator.', 'clark', 'OK', 'Warning')
                return
            }
            New-Item -Path $wu -Force | Out-Null
            New-Item -Path $au -Force | Out-Null

            if ($chkDeferFeat.Checked) {
                Set-ItemProperty -Path $wu -Name 'DeferFeatureUpdates' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -Type DWord -Value ([int]$numFeat.Value) -Force
            } else {
                Remove-ItemProperty -Path $wu -Name 'DeferFeatureUpdates' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -ErrorAction SilentlyContinue
            }

            if ($chkDeferQual.Checked) {
                Set-ItemProperty -Path $wu -Name 'DeferQualityUpdates' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -Type DWord -Value ([int]$numQual.Value) -Force
            } else {
                Remove-ItemProperty -Path $wu -Name 'DeferQualityUpdates' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -ErrorAction SilentlyContinue
            }

            if ($chkNoAuto.Checked) {
                Set-ItemProperty -Path $au -Name 'NoAutoUpdate' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $au -Name 'AUOptions' -Type DWord -Value 1 -Force
            } else {
                Remove-ItemProperty -Path $au -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $au -Name 'AUOptions' -ErrorAction SilentlyContinue
            }

            if (-not (Test-Path -LiteralPath $clark)) {
                New-Item -Path $clark -Force | Out-Null
            }
            Set-ItemProperty -Path $clark -Name 'LastApplied' -Type String -Value (Get-Date -Format 's') -Force

            [System.Windows.Forms.MessageBox]::Show('Policy values written. Reboot or gpupdate may be required for all components to respect policy.', 'clark', 'OK', 'Information')
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Apply failed', 'OK', 'Error')
        }
    })
    [void]$btnRow.Controls.Add($btnApply)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = 'Remove policy keys'
    $btnClear.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnClear.Add_Click({
        try {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
                [System.Windows.Forms.MessageBox]::Show('Removing HKLM policy values requires Administrator.', 'clark', 'OK', 'Warning')
                return
            }
            if (Test-Path -LiteralPath $wu) {
                foreach ($n in @('DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays')) {
                    Remove-ItemProperty -LiteralPath $wu -Name $n -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -LiteralPath $au) {
                foreach ($n in @('NoAutoUpdate', 'AUOptions')) {
                    Remove-ItemProperty -LiteralPath $au -Name $n -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -Path $clark -Recurse -Force -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show('Removed defer / NoAutoUpdate policy values Clark uses, and the Clark marker under HKCU.', 'clark', 'OK', 'Information')
            $chkDeferFeat.Checked = $false
            $chkDeferQual.Checked = $false
            $chkNoAuto.Checked = $false
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Remove failed', 'OK', 'Error')
        }
    })
    [void]$btnRow.Controls.Add($btnClear)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Add_Click({ $form.Close() })
    [void]$btnRow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnApply, $btnClear, $btnClose)
    [void]$form.Controls.Add($btnRow)
    $wuFormY = [int]($wuFormY + [math]::Max(44, $btnRow.PreferredSize.Height + 4))

    $form.ClientSize = New-Object System.Drawing.Size(520, [int]($wuFormY + 44))

    [void]$form.ShowDialog()
}
