function Invoke-WPFDiskToolsWizard {
    <#
    .SYNOPSIS
        Disk health summary and shortcuts (Disk Management, OS volume read-only scan, diskpart helper).
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-DiskHealthSummaryText {
        $sb = [System.Text.StringBuilder]::new()
        try {
            $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Sort-Object FriendlyName)
            if ($pd.Count -gt 0) {
                [void]$sb.AppendLine('=== Physical disks (SMART / health) ===')
                foreach ($d in $pd) {
                    $h = $d.HealthStatus
                    $op = $d.OperationalStatus
                    $media = $d.MediaType
                    $size = if ($d.Size) { '{0:N0} GB' -f ($d.Size / 1GB) } else { '?' }
                    [void]$sb.AppendLine(('- {0} | {1} | Health: {2} | Op: {3} | {4}' -f $d.FriendlyName, $media, $h, $op, $size))
                }
                [void]$sb.AppendLine('')
            }
        } catch { [void]$sb.AppendLine('PhysicalDisk: ' + $_.Exception.Message) }

        try {
            $disks = @(Get-Disk -ErrorAction SilentlyContinue | Sort-Object Number)
            if ($disks.Count -gt 0) {
                [void]$sb.AppendLine('=== Disks / partitions ===')
                foreach ($dk in $disks) {
                    [void]$sb.AppendLine(('- Disk {0}: {1} | {2:N0} GB | {3}' -f $dk.Number, $dk.FriendlyName, ($dk.Size / 1GB), $dk.OperationalStatus))
                    $parts = @(Get-Partition -DiskId $dk.Path -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
                    foreach ($p in $parts) {
                        $letter = if ($p.DriveLetter) { "$($p.DriveLetter):" } else { '(no letter)' }
                        [void]$sb.AppendLine(('    Part {0} {1} {2:N0} MB' -f $p.PartitionNumber, $letter, ($p.Size / 1MB)))
                    }
                }
            }
        } catch { [void]$sb.AppendLine('Get-Disk: ' + $_.Exception.Message) }

        if ($sb.Length -eq 0) {
            [void]$sb.AppendLine('No disk data returned. Run PowerShell as Administrator for fuller SMART details on some systems.')
        }
        return $sb.ToString()
    }

    function Get-ClarkDiskpartReadmeText {
        @'
================================================================================
Clark - diskpart quick reference (read before typing anything destructive)
================================================================================
diskpart is powerful. Wrong disk/partition = data loss or unbootable PC.
Prefer Disk Management for simple tasks. Run diskpart elevated (Admin) when
Windows says access is denied.

HOW TO RUN A SCRIPT FILE (optional)
  diskpart /s C:\path\to\script.txt

OPEN DISKPART FROM THIS BUTTON
  A separate Command Prompt window opens running diskpart (DISKPART> prompt).
  This README opens in Notepad beside it.

-------------------------------------------------------------------------------
INSPECTION (usually safe)
-------------------------------------------------------------------------------
  list disk
  list volume
  list partition          (after: select disk N)

  select disk N           N = number from "list disk"
  detail disk
  detail volume           (after: select volume N)

  select volume N         N = number from "list volume" (or use drive letter)
  select partition N      (after: select disk N)

-------------------------------------------------------------------------------
ONLINE / OFFLINE / READONLY
-------------------------------------------------------------------------------
  online disk
  offline disk
  attributes disk clear readonly
  attributes volume clear readonly

-------------------------------------------------------------------------------
CREATE / SHRINK / EXTEND (destructive if mis-targeted)
-------------------------------------------------------------------------------
  create partition primary size=50000    size in MB; omit size = use all space
  create partition efi size=260           GPT EFI system partition
  create partition msr size=128         GPT Microsoft Reserved

  shrink desired=10240 minimum=10240    MB free to shrink from end of volume
  extend size=10240                     extend into contiguous free space

-------------------------------------------------------------------------------
FORMAT / LETTERS / ACTIVE (destructive)
-------------------------------------------------------------------------------
  format fs=ntfs quick label=MyDisk
  format fs=fat32 quick label=EFI       often used for small EFI partitions
  assign letter=Z
  remove letter=Z
  active                                sets MBR partition as bootable (legacy)

-------------------------------------------------------------------------------
DELETE PARTITION (VERY destructive)
-------------------------------------------------------------------------------
  select disk N
  select partition N
  delete partition          may fail if Windows is using the partition

  delete partition override          forces deletion (system/recovery/OEM)
  delete partition override noerr    same, no error if already gone

-------------------------------------------------------------------------------
DISK WIPE (EXTREMELY destructive)
-------------------------------------------------------------------------------
  select disk N
  clean                 remove partition table (fast)
  clean all             overwrite entire disk (very slow)

-------------------------------------------------------------------------------
GPT / RECOVERY / SCAN / CONVERT (advanced, often destructive)
-------------------------------------------------------------------------------
  rescan                              refresh disk list after hot-plug
  recover                             try to recover selected volume

  convert mbr                         convert empty disk to MBR (data loss)
  convert gpt                         convert empty disk to GPT (data loss)

  gpt attributes=0x0000000000000000   clear GPT partition attributes (rare)
  (Use only if you know why; recovery partitions use special attributes.)

-------------------------------------------------------------------------------
EXIT
-------------------------------------------------------------------------------
  exit                  leaves diskpart
  exit                  again in cmd closes the window (if /k was used)

================================================================================
'@
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark - Disk health & tools'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $form.MinimumSize = New-Object System.Drawing.Size(520, 380)
    $form.ClientSize = New-Object System.Drawing.Size(760, 480)
    $form.StartPosition = 'CenterScreen'

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = 'Both'
    $txt.Font = New-Object System.Drawing.Font('Consolas', 9)
    $txt.Dock = 'Fill'
    $txt.Text = Get-DiskHealthSummaryText

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Bottom'
    $flow.WrapContents = $true
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flow.AutoSize = $true
    $flow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flow.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 8)

    $btnDiskMgmt = New-Object System.Windows.Forms.Button
    $btnDiskMgmt.Text = 'Disk Management'
    $btnDiskMgmt.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    $btnDiskMgmt.Add_Click({ Start-Process 'diskmgmt.msc' })
    [void]$flow.Controls.Add($btnDiskMgmt)

    $btnChk = New-Object System.Windows.Forms.Button
    $btnChk.Text = 'OS volume health check'
    $btnChk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    $btnChk.Add_Click({
        $sys = $env:SystemDrive
        if ([string]::IsNullOrWhiteSpace($sys)) { $sys = 'C:' }
        if (-not $sys.EndsWith('\')) { $sys = $sys + '\' }
        $r = [System.Windows.Forms.MessageBox]::Show(
            @"
Run a fuller health check for $sys ?

This opens an elevated PowerShell window and runs:
 - Repair-Volume -Scan (filesystem health)
 - chkdsk /scan (filesystem verification pass)
 - SMART reliability counters (reallocated/pending/uncorrectable sectors where available)

After checks complete, it can optionally schedule chkdsk /r for reboot
to perform a deeper bad-sector scan and recovery attempt.
"@,
            'Confirm',
            'YesNo',
            'Question'
        )
        if ($r -ne 'Yes') { return }
        try {
            $drive = $env:SystemDrive
            if ([string]::IsNullOrWhiteSpace($drive)) { $drive = 'C:' }
            $drive = $drive.TrimEnd('\')
            if ($drive -notmatch '^[A-Za-z]:$') {
                throw "Unexpected system drive format: $drive"
            }
            $letter = $drive.Substring(0, 1).ToUpperInvariant()
            $ps1Path = Join-Path $env:TEMP ("clark-repair-volume-{0}.ps1" -f [Guid]::NewGuid().ToString('n'))
            $ps1 = @"
`$Host.UI.RawUI.WindowTitle = 'Clark - Disk health check ($drive)'
Write-Host ''
Write-Host "Clark disk health check for $drive" -ForegroundColor Cyan
Write-Host ''
try {
    Import-Module Storage -ErrorAction SilentlyContinue

    Write-Host '1) Filesystem online scan (Repair-Volume -Scan)...' -ForegroundColor Yellow
    Repair-Volume -DriveLetter '$letter' -Scan -ErrorAction Continue
    Write-Host ''

    Write-Host '2) Filesystem verification (chkdsk /scan)...' -ForegroundColor Yellow
    cmd /c "chkdsk $drive /scan"
    Write-Host ''

    Write-Host '3) Device SMART / reliability counters...' -ForegroundColor Yellow
    `$diskObj = Get-Volume -DriveLetter '$letter' -ErrorAction SilentlyContinue |
        Get-Partition -ErrorAction SilentlyContinue |
        Get-Disk -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (`$null -ne `$diskObj) {
        Write-Host ("Disk: #{0} {1}" -f `$diskObj.Number, `$diskObj.FriendlyName) -ForegroundColor DarkGray
        `$rel = Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { `$_.FriendlyName -eq `$diskObj.FriendlyName } |
            Get-StorageReliabilityCounter -ErrorAction SilentlyContinue

        if (-not `$rel -or `$rel.Count -eq 0) {
            `$rel = Get-PhysicalDisk -ErrorAction SilentlyContinue | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        }

        if (`$rel -and `$rel.Count -gt 0) {
            foreach (`$r in `$rel) {
                Write-Host ("- Temperature: {0}C  Reallocated: {1}  Pending: {2}  Uncorrectable: {3}  Wear: {4}" -f `$r.Temperature, `$r.ReallocatedSectors, `$r.PendingSectors, `$r.UncorrectableSectors, `$r.Wear) -ForegroundColor Gray
            }
        } else {
            Write-Host 'SMART counters not exposed by this storage controller/driver.' -ForegroundColor DarkYellow
        }
    } else {
        Write-Host 'Could not map OS volume to a disk object for SMART counters.' -ForegroundColor DarkYellow
    }

    Write-Host ''
    `$scheduleDeep = Read-Host 'Schedule deep bad-sector check on next reboot? (chkdsk /r) [y/N]'
    if (`$scheduleDeep -match '^(y|yes)$') {
        Write-Host 'Scheduling chkdsk /r on next restart...' -ForegroundColor Yellow
        cmd /c "echo Y|chkdsk $drive /r"
    }

    Write-Host ''
    Write-Host 'Disk health checks completed.' -ForegroundColor Green
} catch {
    Write-Host ('Error: ' + `$_.Exception.Message) -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press Enter to close'
"@
            Set-Content -LiteralPath $ps1Path -Value $ps1 -Encoding UTF8
            $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (-not (Test-Path -LiteralPath $psExe)) {
                $psExe = 'powershell.exe'
            }
            $psArgs = @(
                '-NoProfile',
                '-NoLogo',
                '-ExecutionPolicy', 'Bypass',
                '-File', $ps1Path
            )
            try {
                Start-Process -FilePath $psExe -ArgumentList $psArgs -Verb RunAs -WorkingDirectory $env:SystemRoot -ErrorAction Stop
            } catch {
                Start-Process -FilePath $psExe -ArgumentList $psArgs -WorkingDirectory $env:SystemRoot -ErrorAction Stop
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                @"
Could not start the disk health check:

$($_.Exception.Message)

If you cancelled the UAC prompt, try again and approve it.

Manual (elevated PowerShell):
  Repair-Volume -DriveLetter '$($env:SystemDrive.Substring(0,1))' -Scan
  chkdsk $($env:SystemDrive) /scan
"@,
                'Disk health',
                'OK',
                'Warning'
            )
        }
    })
    [void]$flow.Controls.Add($btnChk)

    $btnDp = New-Object System.Windows.Forms.Button
    $btnDp.Text = 'Diskpart (cmd) + command guide'
    $btnDp.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    $btnDp.Add_Click({
        # Command guide text lives only in this script (not downloaded). Shown in a WinForms window — no readme .txt on disk.
        $readme = Get-ClarkDiskpartReadmeText

        $guideForm = New-Object System.Windows.Forms.Form
        $guideForm.Text = 'Clark - diskpart command guide'
        $guideForm.Size = New-Object System.Drawing.Size(700, 560)
        $guideForm.StartPosition = 'CenterScreen'
        $guideForm.MinimizeBox = $false
        $guideForm.ShowInTaskbar = $false
        $guideForm.Owner = $form

        $guideTb = New-Object System.Windows.Forms.TextBox
        $guideTb.Multiline = $true
        $guideTb.ReadOnly = $true
        $guideTb.ScrollBars = 'Both'
        $guideTb.Dock = 'Fill'
        $guideTb.Font = New-Object System.Drawing.Font('Consolas', 9)
        $guideTb.Text = $readme

        $guideBtn = New-Object System.Windows.Forms.Button
        $guideBtn.Text = 'Close'
        $guideBtn.Dock = 'Bottom'
        $guideBtn.Height = 34
        $guideBtn.Add_Click({
            param($sender, $eventArgs)
            $hostForm = $sender.FindForm()
            if ($null -ne $hostForm) {
                $hostForm.Close()
            }
        })
        Set-WinFormsButtonFullText -Button $guideBtn

        [void]$guideForm.Controls.Add($guideBtn)
        [void]$guideForm.Controls.Add($guideTb)

        # Optional tiny script on disk only if you run diskpart /s "path" (not required for the guide).
        $samplePath = Join-Path $env:TEMP ("clark-diskpart-sample-{0}.txt" -f [Guid]::NewGuid().ToString('n'))
        $sample = @(
            'REM Safe inspection-only script. Run (elevated if needed):',
            ('REM   diskpart /s "{0}"' -f $samplePath),
            'REM Or paste lines into the DISKPART> window Clark opened.',
            'list disk',
            'list volume'
        ) -join "`r`n"
        Set-Content -LiteralPath $samplePath -Value $sample -Encoding UTF8

        # Interactive diskpart in a new console (DISKPART> prompt).
        Start-Process -FilePath cmd.exe -ArgumentList @('/k', 'diskpart') -WorkingDirectory $env:TEMP

        # Readme: shown in this process only (no guide .txt file). Modeless so you can use DISKPART and the guide together.
        [void]$guideForm.Show($form)
    })
    [void]$flow.Controls.Add($btnDp)

    $btnRef = New-Object System.Windows.Forms.Button
    $btnRef.Text = 'Refresh'
    $btnRef.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    $btnRef.Add_Click({ $txt.Text = Get-DiskHealthSummaryText })
    [void]$flow.Controls.Add($btnRef)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 6)
    $btnClose.Add_Click({ $form.Close() })
    [void]$flow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnDiskMgmt, $btnChk, $btnDp, $btnRef, $btnClose)

    [void]$form.Controls.Add($flow)
    [void]$form.Controls.Add($txt)
    [void]$form.ShowDialog()
}
