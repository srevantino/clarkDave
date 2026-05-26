#Requires -Version 5.1
function Find-ClarkAsysRoot {
    foreach ($letter in [char[]](67..90)) {
        $root = '{0}:\asys' -f $letter
        if (Test-Path -LiteralPath $root) { return $root }
    }
    return $null
}

function Get-ClarkSetupLogDir {
    $root = Find-ClarkAsysRoot
    if ($root) { return (Join-Path $root 'logs') }
    return Join-Path $env:TEMP 'clark-asys-logs'
}

function Write-ClarkSetupLog {
    param(
        [string]$Message,
        [string]$LogName = 'setup.log',
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $logDir = Get-ClarkSetupLogDir
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath (Join-Path $logDir $LogName) -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow } else { Write-Host $line }
}

function Show-ClarkSetupError {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [string]$Detail = ''
    )
    $fullText = if ($Detail) { "$Message`n`n$Detail" } else { $Message }
    Write-ClarkSetupLog -Message "$Title | $fullText" -LogName 'errors.log' -Level 'ERROR'

    $shown = $false
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            $fullText, "Clark Setup — $Title",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        $shown = $true
    } catch { }

    if (-not $shown) {
        try {
            $vbs = "MsgBox ""$($fullText -replace '"','""')"", 16, ""Clark Setup - $($Title -replace '"','""')"""
            $vbsPath = Join-Path $env:TEMP 'clark-setup-err.vbs'
            Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII -Force
            Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$vbsPath`"" -Wait -ErrorAction Stop
            $shown = $true
        } catch { }
    }

    if (-not $shown) {
        try {
            Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "msg.exe", '*', "/TIME:0", "${Title}: $Message") -Wait -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Get-ClarkInstallCandidateDisks {
    $minBytes = 100GB
    Get-Disk -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.IsOffline -and -not $_.IsRemovable -and
            $_.BusType -notin @('USB', 'SD') -and $_.Size -gt $minBytes
        } | Sort-Object Size -Descending
}

function Show-ClarkDiskSelectionDialog {
    param([Parameter(Mandatory)]$Disks)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark Setup — Select installation disk'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(560, 320)
    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 16)
    $label.Size = New-Object System.Drawing.Size(520, 48)
    $label.Text = 'Multiple internal disks found. Choose where to install Windows. Only the selected disk will be repartitioned.'
    $form.Controls.Add($label)
    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(20, 72)
    $list.Size = New-Object System.Drawing.Size(520, 180)
    $form.Controls.Add($list)
    $diskMap = @{}
    foreach ($d in $Disks) {
        $display = "Disk {0} — {1} GB — {2}" -f $d.Number, [math]::Round($d.Size / 1GB, 0), $d.FriendlyName
        [void]$list.Items.Add($display)
        $diskMap[$display] = $d
    }
    $list.SelectedIndex = 0
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Install here'; $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(360, 268); $ok.Size = New-Object System.Drawing.Size(90, 28)
    $form.AcceptButton = $ok; $form.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.DialogResult = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(460, 268); $cancel.Size = New-Object System.Drawing.Size(80, 28)
    $form.CancelButton = $cancel; $form.Controls.Add($cancel)
    if ($form.ShowDialog() -ne 'OK') { throw 'Windows installation cancelled — no disk was selected.' }
    $diskMap[[string]$list.SelectedItem]
}

function Select-ClarkTargetDisk {
    $candidates = @(Get-ClarkInstallCandidateDisks)
    if ($candidates.Count -eq 0) { throw 'No internal disk >100 GB found (non-removable). Unplug USB install drives.' }
    if ($candidates.Count -eq 1) { return $candidates[0] }
    Write-ClarkSetupLog -Message ("Multiple disks ({0}); showing picker." -f $candidates.Count) -LogName 'disk-layout.log'
    Show-ClarkDiskSelectionDialog -Disks $candidates
}

function Invoke-ClarkSetupPhase {
    param(
        [Parameter(Mandatory)][string]$PhaseName,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        Write-ClarkSetupLog -Message "Starting: $PhaseName" -LogName 'setup.log'
        & $Action
        Write-ClarkSetupLog -Message "Completed: $PhaseName" -LogName 'setup.log'
    } catch {
        $err = $_.Exception.Message
        if ($_.ScriptStackTrace) { $err += "`n`n$($_.ScriptStackTrace)" }
        Show-ClarkSetupError -Title $PhaseName -Message 'This step failed during Windows setup.' -Detail $err
        exit 1
    }
}
