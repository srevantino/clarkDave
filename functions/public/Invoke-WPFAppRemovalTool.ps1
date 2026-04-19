function Invoke-WPFAppRemovalTool {
    <#
    .SYNOPSIS
        List installed programs from registry uninstall keys; uninstall selected or open Programs and Features.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-InstalledProgramsFromRegistry {
        $list = [System.Collections.Generic.List[object]]::new()
        $roots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if (-not $p) { return }
                $name = [string]$p.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { return }
                if ($p.SystemComponent -eq 1) { return }
                $quiet = [string]$p.QuietUninstallString
                $loud = [string]$p.UninstallString
                if ([string]::IsNullOrWhiteSpace($quiet) -and [string]::IsNullOrWhiteSpace($loud)) { return }
                [void]$list.Add([pscustomobject]@{
                        DisplayName     = $name
                        Publisher       = [string]$p.Publisher
                        Version         = [string]$p.DisplayVersion
                        QuietUninstall  = $quiet
                        UninstallString = $loud
                    })
            }
        }
        return @($list | Sort-Object DisplayName)
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark - Installed programs & deep clean'
    $form.Size = New-Object System.Drawing.Size(920, 560)
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Dock = 'Top'
    $lbl.Height = 40
    $lbl.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)
    $lbl.Text = 'Programs from registry uninstall keys. Uninstall runs the quiet command when available; some installers still show UI. Create a restore point before bulk removals.'

    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Dock = 'Fill'
    $dg.ReadOnly = $true
    $dg.AutoGenerateColumns = $false
    $dg.SelectionMode = 'FullRowSelect'
    $dg.MultiSelect = $false
    $dg.AllowUserToAddRows = $false
    foreach ($colDef in @(
            @{ Name = 'DisplayName'; HeaderText = 'Name'; Width = 280 }
            @{ Name = 'Publisher'; HeaderText = 'Publisher'; Width = 160 }
            @{ Name = 'Version'; HeaderText = 'Version'; Width = 90 }
            @{ Name = 'QuietUninstall'; HeaderText = 'Quiet uninstall'; Width = 200 }
            @{ Name = 'UninstallString'; HeaderText = 'Uninstall command'; Width = 260 }
        )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $colDef.Name
        $c.HeaderText = $colDef.HeaderText
        $c.Width = $colDef.Width
        $c.DataPropertyName = $colDef.Name
        [void]$dg.Columns.Add($c)
    }

    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add('DisplayName', [string])
    [void]$table.Columns.Add('Publisher', [string])
    [void]$table.Columns.Add('Version', [string])
    [void]$table.Columns.Add('QuietUninstall', [string])
    [void]$table.Columns.Add('UninstallString', [string])
    foreach ($row in @(Get-InstalledProgramsFromRegistry)) {
        [void]$table.Rows.Add(@($row.DisplayName, $row.Publisher, $row.Version, $row.QuietUninstall, $row.UninstallString))
    }
    $bs = New-Object System.Windows.Forms.BindingSource
    $bs.DataSource = $table
    $dg.DataSource = $bs

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Bottom'
    $flow.WrapContents = $true
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flow.AutoSize = $true
    $flow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flow.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)

    $btnUn = New-Object System.Windows.Forms.Button
    $btnUn.Text = 'Uninstall selected'
    $btnUn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnUn.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $r = $dg.SelectedRows[0]
        $cmd = [string]$r.Cells['QuietUninstall'].Value
        if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = [string]$r.Cells['UninstallString'].Value }
        $disp = [string]$r.Cells['DisplayName'].Value
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            [System.Windows.Forms.MessageBox]::Show('No uninstall command for this entry.', 'clark', 'OK', 'Information')
            return
        }
        $c = [System.Windows.Forms.MessageBox]::Show(
            "Run uninstall for:`n`n$disp`n`nCommand:`n$cmd",
            'Confirm uninstall',
            'YesNo',
            'Warning'
        )
        if ($c -ne 'Yes') { return }
        try {
            Start-Process cmd.exe -ArgumentList @('/c', $cmd) -Wait
            [System.Windows.Forms.MessageBox]::Show('Uninstall process exited. Click Refresh if the program was removed.', 'clark', 'OK', 'Information')
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Uninstall', 'OK', 'Error')
        }
    })
    [void]$flow.Controls.Add($btnUn)

    $btnAppwiz = New-Object System.Windows.Forms.Button
    $btnAppwiz.Text = 'Programs and Features'
    $btnAppwiz.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnAppwiz.Add_Click({ Start-Process appwiz.cpl })
    [void]$flow.Controls.Add($btnAppwiz)

    $btnRef = New-Object System.Windows.Forms.Button
    $btnRef.Text = 'Refresh'
    $btnRef.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnRef.Add_Click({
        $table.Rows.Clear()
        foreach ($row in @(Get-InstalledProgramsFromRegistry)) {
            [void]$table.Rows.Add(@($row.DisplayName, $row.Publisher, $row.Version, $row.QuietUninstall, $row.UninstallString))
        }
    })
    [void]$flow.Controls.Add($btnRef)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnClose.Add_Click({ $form.Close() })
    [void]$flow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnUn, $btnAppwiz, $btnRef, $btnClose)

    # Dock: add Top and Bottom first, then Fill, so the grid uses remaining client area.
    [void]$form.Controls.Add($lbl)
    [void]$form.Controls.Add($flow)
    [void]$form.Controls.Add($dg)

    [void]$form.ShowDialog()
}
