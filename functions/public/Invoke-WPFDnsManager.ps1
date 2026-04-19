function Invoke-WPFDnsManager {
    <#
    .SYNOPSIS
        DNS presets per adapter or all adapters, plus DHCP reset.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $providers = @("DHCP") + @($sync.configs.dns.PSObject.Properties.Name | Sort-Object) + @("Custom")

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark - DNS manager"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.StartPosition = "CenterScreen"

    # Use a dedicated name + [int] — a plain $y can collide with outer scopes and become Object[], breaking $y - 2.
    [int]$dnsFormY = 12
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $lbl.Size = New-Object System.Drawing.Size(600, 40)
    $lbl.Text = "Pick a DNS preset first, then select adapters and click Apply. DHCP resets both IPv4 and IPv6 where supported."
    [void]$form.Controls.Add($lbl)
    $dnsFormY = [int]($dnsFormY + 46)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = "DNS preset:"
    $lblP.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $lblP.AutoSize = $true
    [void]$form.Controls.Add($lblP)
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = "DropDownList"
    $combo.Location = New-Object System.Drawing.Point(100, [int]($dnsFormY - 2))
    $combo.Width = 220
    foreach ($p in $providers) { [void]$combo.Items.Add($p) }
    $combo.SelectedIndex = [math]::Max(0, $combo.Items.IndexOf("Cloudflare"))
    if ($combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }
    [void]$form.Controls.Add($combo)
    $combo.Add_DropDown({ $combo.BringToFront() })
    $dnsFormY = [int]($dnsFormY + 32)

    $cbAll = New-Object System.Windows.Forms.CheckBox
    $cbAll.Text = "Select all adapters (including not Up)"
    $cbAll.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $cbAll.Width = 400
    [void]$form.Controls.Add($cbAll)
    $dnsFormY = [int]($dnsFormY + 28)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $list.Size = New-Object System.Drawing.Size(600, 160)
    $ifIndexByRow = [System.Collections.Generic.List[int]]::new()
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $label = "$($a.Name)  [ifIndex $($a.ifIndex)]  $($a.Status)"
        [void]$list.Items.Add($label, ($a.Status -eq 'Up'))
        [void]$ifIndexByRow.Add($a.ifIndex)
    }
    $list.Tag = $ifIndexByRow
    [void]$form.Controls.Add($list)
    $dnsFormY = [int]($dnsFormY + 168)

    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = "Custom IPv4 (primary / secondary):"
    $lblC.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $lblC.Width = 260
    [void]$form.Controls.Add($lblC)
    $dnsFormY = [int]($dnsFormY + 22)
    $tPri = New-Object System.Windows.Forms.TextBox
    $tPri.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $tPri.Width = 120
    [void]$form.Controls.Add($tPri)
    $tSec = New-Object System.Windows.Forms.TextBox
    $tSec.Location = New-Object System.Drawing.Point(140, $dnsFormY)
    $tSec.Width = 120
    [void]$form.Controls.Add($tSec)
    $dnsFormY = [int]($dnsFormY + 34)

    $lbl6 = New-Object System.Windows.Forms.Label
    $lbl6.Text = "Custom IPv6 (optional, primary / secondary):"
    $lbl6.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $lbl6.Width = 360
    [void]$form.Controls.Add($lbl6)
    $dnsFormY = [int]($dnsFormY + 22)
    $t6p = New-Object System.Windows.Forms.TextBox
    $t6p.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $t6p.Width = 240
    [void]$form.Controls.Add($t6p)
    $t6s = New-Object System.Windows.Forms.TextBox
    $t6s.Location = New-Object System.Drawing.Point(260, $dnsFormY)
    $t6s.Width = 240
    [void]$form.Controls.Add($t6s)
    $dnsFormY = [int]($dnsFormY + 44)

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.Location = New-Object System.Drawing.Point(12, $dnsFormY)
    $btnRow.Width = 616
    $btnRow.AutoSize = $true
    $btnRow.WrapContents = $false
    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $btnRow.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Apply to selected adapters"
    $btnApply.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnApply.Add_Click({
        $indexes = [System.Collections.Generic.List[int]]::new()
        $rows = [System.Collections.Generic.List[int]]$list.Tag
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            if ($list.GetItemChecked($i)) {
                [void]$indexes.Add([int]$rows[$i])
            }
        }
        if ($indexes.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Check at least one adapter.", "clark", "OK", "Information")
            return
        }
        $prov = [string]$combo.SelectedItem
        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")
            return
        }
        try {
            if ($prov -eq "Custom") {
                Set-WinUtilDNS -DNSProvider Custom -InterfaceIndex $indexes.ToArray() `
                    -CustomPrimaryV4 $tPri.Text.Trim() -CustomSecondaryV4 $tSec.Text.Trim() `
                    -CustomPrimaryV6 $t6p.Text.Trim() -CustomSecondaryV6 $t6s.Text.Trim()
            } else {
                Set-WinUtilDNS -DNSProvider $prov -InterfaceIndex $indexes.ToArray()
            }
            [System.Windows.Forms.MessageBox]::Show("DNS update finished. See console output for details.", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")
        }
    })
    [void]$btnRow.Controls.Add($btnApply)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "Apply preset to ALL adapters"
    $btnAll.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnAll.Add_Click({
        $prov = [string]$combo.SelectedItem
        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")
            return
        }
        try {
            if ($prov -eq "Custom") {
                Set-WinUtilDNS -DNSProvider Custom -AllAdapters `
                    -CustomPrimaryV4 $tPri.Text.Trim() -CustomSecondaryV4 $tSec.Text.Trim() `
                    -CustomPrimaryV6 $t6p.Text.Trim() -CustomSecondaryV6 $t6s.Text.Trim()
            } else {
                Set-WinUtilDNS -DNSProvider $prov -AllAdapters
            }
            [System.Windows.Forms.MessageBox]::Show("DNS update applied to all adapters.", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")
        }
    })
    [void]$btnRow.Controls.Add($btnAll)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Add_Click({ $form.Close() })
    [void]$btnRow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnApply, $btnAll, $btnClose)
    [void]$form.Controls.Add($btnRow)
    $dnsFormY = [int]($dnsFormY + [math]::Max(44, $btnRow.PreferredSize.Height + 4))

    $cbAll.Add_CheckedChanged({
        if ($cbAll.Checked) {
            for ($i = 0; $i -lt $list.Items.Count; $i++) {
                $list.SetItemChecked($i, $true)
            }
        }
    })

    $form.ClientSize = New-Object System.Drawing.Size(640, [int]($dnsFormY + 48))

    [void]$form.ShowDialog()
}
