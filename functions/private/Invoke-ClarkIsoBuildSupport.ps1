#Requires -Version 5.1
# Clark ISO build: WIM cleanup, ASYS payload, modify stop, work-dir resolution.
# Loaded after Invoke-ClarkISO.ps1 by Compile.ps1 (overrides orphan-mount repair).

function Test-ClarkIsoRunningElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-ClarkIsoMountHolderProcesses {
    param([scriptblock]$Log = { param($m) Write-Output $m })
    $mine = $PID
    $stopped = 0
    foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue)) {
        if ($proc.ProcessId -eq $mine) { continue }
        $cmd = [string]$proc.CommandLine
        if ($cmd -notmatch 'A-SYS_clark|ASYS_WinISO|Invoke-ClarkISO|wim_mount') { continue }
        & $Log "Stopping Clark/ISO PowerShell PID $($proc.ProcessId)..."
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped++
    }
    if ($stopped -gt 0) {
        & $Log "Stopped $stopped process(es). Waiting for file handles to release..."
        Start-Sleep -Seconds 5
    }
}

function Invoke-ClarkIsoDismExeUnmount {
    param(
        [Parameter(Mandatory)][string]$MountPath,
        [switch]$Discard,
        [scriptblock]$Log = { param($m) Write-Output $m }
    )
    $mountPathFull = ($MountPath -replace '/', '\').TrimEnd('\')
    $dismArg = if ($Discard) { '/Discard' } else { '/Commit' }
    & $Log "Running: dism.exe /Unmount-Image /MountDir:$mountPathFull $dismArg"
    try {
        $proc = Start-Process -FilePath 'dism.exe' -ArgumentList @(
            '/English', '/Unmount-Image', "/MountDir:$mountPathFull", $dismArg
        ) -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            & $Log 'DISM.exe unmount succeeded.'
            return $true
        }
        & $Log "DISM.exe exit code: $($proc.ExitCode)"
    } catch {
        & $Log "DISM.exe failed: $($_.Exception.Message)"
    }
    return $false
}

function Dismount-AllClarkIsoMountedImages {
    param(
        [scriptblock]$Log = { param($m) Write-Output $m },
        [switch]$Discard
    )
    $ok = $true
    foreach ($img in @(Get-ClarkIsoMountedImages)) {
        try {
            $p = [System.IO.Path]::GetFullPath($img.Path).TrimEnd('\')
            if ($p -notmatch 'ASYS_WinISO|ASYS_Win11ISO') { continue }
            if (-not (Invoke-ClarkIsoDismExeUnmount -MountPath $p -Discard:$Discard -Log $Log)) { $ok = $false }
        } catch {
            & $Log "Warning: error processing mounted image: $($_.Exception.Message)"
            $ok = $false
        }
    }
    return $ok
}

function Register-ClarkIsoDeleteOnReboot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$Log = { param($m) Write-Output $m }
    )
    if (-not (Test-ClarkIsoRunningElevated)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    if (-not ([System.Management.Automation.PSTypeName]'ClarkNativeDelete').Type) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ClarkNativeDelete {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
    public const int MOVEFILE_DELAY_UNTIL_REBOOT = 4;
}
'@
    }

    $items = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)
    $anyFailed = $false
    foreach ($item in $items) {
        if (-not [ClarkNativeDelete]::MoveFileEx($item.FullName, $null, [ClarkNativeDelete]::MOVEFILE_DELAY_UNTIL_REBOOT)) {
            & $Log "Warning: MoveFileEx failed for child: $($item.FullName)"
            $anyFailed = $true
        }
    }
    if (-not [ClarkNativeDelete]::MoveFileEx($Path, $null, [ClarkNativeDelete]::MOVEFILE_DELAY_UNTIL_REBOOT)) {
        & $Log "Warning: MoveFileEx failed for parent: $Path"
        $anyFailed = $true
    }
    if ($anyFailed) {
        & $Log "Warning: some items could not be scheduled for reboot deletion under: $Path"
    }
    & $Log "Scheduled delete on next reboot: $Path"
    return $true
}

function Grant-ClarkIsoPathFullControl {
    param(
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$Log = { param($m) }
    )
    if (-not (Test-ClarkIsoRunningElevated)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        & takeown.exe /F $Path /R /D Y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $Log "Warning: takeown exited with code $LASTEXITCODE for: $Path" }
        & icacls.exe $Path /grant "${env:USERNAME}:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $Log "Warning: icacls exited with code $LASTEXITCODE for: $Path" }
    } catch {
        & $Log "Warning: Grant-ClarkIsoPathFullControl failed for ${Path}: $($_.Exception.Message)"
    }
}

function Get-ClarkIsoMountedImages {
    try { return @(Get-WindowsImage -Mounted -ErrorAction Stop) } catch { return @() }
}

function Get-ClarkIsoMountedImageForPath {
    param([Parameter(Mandatory)][string]$MountPath)
    $target = [System.IO.Path]::GetFullPath($MountPath).TrimEnd('\')
    foreach ($img in @(Get-ClarkIsoMountedImages)) {
        try {
            if ([System.IO.Path]::GetFullPath($img.Path).TrimEnd('\') -ieq $target) { return $img }
        } catch { }
    }
    return $null
}

function Remove-ClarkIsoWimMountFolder {
    param(
        [Parameter(Mandatory)][string]$MountPath,
        [scriptblock]$Log = { param($m) Write-Output $m }
    )
    $mountPathFull = [System.IO.Path]::GetFullPath($MountPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $mountPathFull)) { return $true }

    if (Get-ClarkIsoMountedImageForPath -MountPath $mountPathFull) {
        & $Log 'Cannot delete wim_mount while DISM still has it mounted.'
        return $false
    }

    & $Log "Removing wim_mount folder: $mountPathFull"
    Grant-ClarkIsoPathFullControl -Path $mountPathFull

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Remove-Item -LiteralPath $mountPathFull -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $mountPathFull)) {
                & $Log 'wim_mount folder removed.'
                return $true
            }
        } catch {
            & $Log "Delete attempt $attempt failed: $($_.Exception.Message)"
            Grant-ClarkIsoPathFullControl -Path $mountPathFull
            try {
                $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'rd', '/s', '/q', "`"$mountPathFull`"") -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $mountPathFull)) { return $true }
            } catch { }
            Start-Sleep -Seconds 3
        }
    }
    return -not (Test-Path -LiteralPath $mountPathFull)
}

function Clear-ClarkIsoWimMount {
    param(
        [Parameter(Mandatory)][string]$MountPath,
        [scriptblock]$Log = { param($m) Write-Output $m },
        [switch]$Discard,
        [switch]$StopHolderProcesses
    )
    $mountPathFull = [System.IO.Path]::GetFullPath($MountPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $mountPathFull)) { return $true }

    try {
        if ($StopHolderProcesses) {
            Stop-ClarkIsoMountHolderProcesses -Log $Log
        }

        [void](Dismount-AllClarkIsoMountedImages -Log $Log -Discard:$Discard)

        foreach ($attempt in 1..5) {
            if (-not (Get-ClarkIsoMountedImageForPath -MountPath $mountPathFull)) { break }

            & $Log "Dismount attempt $attempt of 5..."
            if (Invoke-ClarkIsoDismExeUnmount -MountPath $mountPathFull -Discard:$Discard -Log $Log) { break }

            try {
                if ($Discard) {
                    Dismount-WindowsImage -Path $mountPathFull -Discard -ErrorAction Stop | Out-Null
                } else {
                    Dismount-WindowsImage -Path $mountPathFull -Save -ErrorAction Stop | Out-Null
                }
                & $Log "WIM dismounted via cmdlet: $mountPathFull"
                break
            } catch {
                & $Log "Cmdlet dismount failed: $($_.Exception.Message)"
            }
            Start-Sleep -Seconds 4
            if (Test-ClarkIsoRunningElevated) {
                try { & dism /English /Cleanup-Wim 2>&1 | Out-Null } catch { }
            }
        }

        if (Get-ClarkIsoMountedImageForPath -MountPath $mountPathFull) {
            & $Log 'DISM still reports this path as mounted. Close all Clark windows, then run Force-Clear again or reboot.'
            return $false
        }

        $hasContent = @(Get-ChildItem -LiteralPath $mountPathFull -Force -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $hasContent) { return $true }
        return Remove-ClarkIsoWimMountFolder -MountPath $mountPathFull -Log $Log
    } catch {
        & $Log "Error in Clear-ClarkIsoWimMount: $($_.Exception.Message)"
        # Emergency dismount attempt to avoid orphaned WIM mount
        try {
            if (Get-ClarkIsoMountedImageForPath -MountPath $mountPathFull) {
                & $Log "Emergency: attempting DISM dismount after unexpected error..."
                Invoke-ClarkIsoDismExeUnmount -MountPath $mountPathFull -Discard -Log $Log | Out-Null
            }
        } catch { }
        return $false
    }
}

function Invoke-ClarkIsoForceClearWorkDir {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [scriptblock]$Log = { param($m) Write-Output $m },
        [switch]$ScheduleRebootOnFailure
    )

    if (-not (Test-Path -LiteralPath $WorkDir)) {
        & $Log 'Work directory already removed.'
        return $true
    }
    if (-not (Test-ClarkIsoRunningElevated)) {
        throw 'Run this script as Administrator.'
    }

    Stop-ClarkIsoMountHolderProcesses -Log $Log
    $mountDir = Join-Path $WorkDir 'wim_mount'

    if (Test-Path -LiteralPath $mountDir) {
        & $Log "Clearing wim_mount under $WorkDir ..."
        if (-not (Clear-ClarkIsoWimMount -MountPath $mountDir -Discard -Log $Log -StopHolderProcesses)) {
            & $Log 'Could not dismount wim_mount. Close all Clark windows and retry, or reboot then run this script again.'
            if ($ScheduleRebootOnFailure) {
                Register-ClarkIsoDeleteOnReboot -Path $WorkDir -Log $Log | Out-Null
                & $Log 'Work directory scheduled for deletion on next reboot.'
            }
            return $false
        }
    }

    if (Test-Path -LiteralPath $WorkDir) {
        & $Log "Deleting work directory: $WorkDir"
        Grant-ClarkIsoPathFullControl -Path $WorkDir
        try {
            Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction Stop
        } catch {
            & $Log "Delete failed: $($_.Exception.Message)"
            if ($ScheduleRebootOnFailure) {
                Register-ClarkIsoDeleteOnReboot -Path $WorkDir -Log $Log | Out-Null
                & $Log 'Scheduled full work directory delete on next reboot.'
                return $false
            }
            throw
        }
    }

    if (Test-Path -LiteralPath $WorkDir) { return $false }
    & $Log 'Cleanup complete.'
    return $true
}

function Test-ClarkIsoWimMountDirDirty {
    param([Parameter(Mandatory)][string]$WorkDir)
    $mountDir = Join-Path $WorkDir 'wim_mount'
    if (-not (Test-Path -LiteralPath $mountDir)) { return $false }
    if (Get-ClarkIsoMountedImageForPath -MountPath $mountDir) { return $true }
    return @(Get-ChildItem -LiteralPath $mountDir -Force -ErrorAction SilentlyContinue).Count -gt 0
}

function Resolve-ClarkIsoWorkDirectory {
    param(
        [scriptblock]$Log = { param($m) Write-Output $m },
        [scriptblock]$GetCandidates = { @() }
    )
    $existing = @(& $GetCandidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if (-not $existing) {
        return (Join-Path $env:TEMP "ASYS_WinISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')")
    }
    $candidate = $existing.FullName
    if (-not (Test-ClarkIsoWimMountDirDirty -WorkDir $candidate)) {
        & $Log "Reusing existing temp directory: $candidate"
        return $candidate
    }
    & $Log "Stale wim_mount in $candidate - attempting cleanup..."
    $mountDir = Join-Path $candidate 'wim_mount'
    $cleared = Clear-ClarkIsoWimMount -MountPath $mountDir -Log $Log -Discard
    if ($cleared -and -not (Test-ClarkIsoWimMountDirDirty -WorkDir $candidate)) {
        & $Log "Cleanup succeeded; reusing: $candidate"
        return $candidate
    }
    $fresh = Join-Path $env:TEMP "ASYS_WinISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    & $Log "Using new work directory (could not clear old wim_mount): $fresh"
    return $fresh
}

function Reset-ClarkIsoModifyStop { param([hashtable]$Sync); if ($Sync) { $Sync['Win11ISOModifyStopRequested'] = $false } }
function Test-ClarkIsoModifyStopRequested { param([hashtable]$Sync); return [bool]($Sync -and $Sync['Win11ISOModifyStopRequested']) }
function Stop-ClarkIsoModifyIfRequested { param([hashtable]$Sync); if (Test-ClarkIsoModifyStopRequested -Sync $Sync) { throw 'ISO modification stopped by user.' } }

function Invoke-ClarkISOModifyStop {
    param([hashtable]$Sync = $sync)
    if (-not $Sync['Win11ISOModifying']) { return }
    $Sync['Win11ISOModifyStopRequested'] = $true
    Write-Win11ISOLog 'Stop requested for ISO modification (stopping after current step)...'
    if ($Sync['WPFWin11ISOModifyStopButton']) { $Sync['WPFWin11ISOModifyStopButton'].IsEnabled = $false }
}

function Register-ClarkIsoModifyStopUi {
    param([hashtable]$Sync = $sync)
    if (-not $Sync -or $Sync['WPFWin11ISOModifyStopButton']) { return }
    $modifyBtn = $Sync['WPFWin11ISOModifyButton']
    if (-not $modifyBtn) { return }

    $stopBtn = New-Object System.Windows.Controls.Button
    $stopBtn.Name = 'WPFWin11ISOModifyStopButton'
    $stopBtn.Content = 'Stop build'
    $stopBtn.Width = 100
    $stopBtn.Height = 32
    $stopBtn.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $stopBtn.Background = '#8b0000'
    $stopBtn.Foreground = 'White'
    $stopBtn.BorderBrush = '#a04040'
    $stopBtn.IsEnabled = $false
    $stopBtn.ToolTip = 'Stop the running install.wim modification'

    $panel = $modifyBtn.Parent
    if ($panel -is [System.Windows.Controls.Panel]) {
        $idx = $panel.Children.IndexOf($modifyBtn)
        if ($idx -lt 0) { $idx = $panel.Children.Count }
        [void]$panel.Children.Insert($idx + 1, $stopBtn)
    }
    $Sync['WPFWin11ISOModifyStopButton'] = $stopBtn
    [void]$stopBtn.Add_Click({ Invoke-ClarkISOModifyStop -Sync $sync })
}

function Set-ClarkIsoModifyControlState {
    param([hashtable]$Sync = $sync, [bool]$IsRunning)
    if ($Sync['WPFWin11ISOModifyButton']) { $Sync['WPFWin11ISOModifyButton'].IsEnabled = -not $IsRunning }
    if ($Sync['WPFWin11ISOModifyStopButton']) { $Sync['WPFWin11ISOModifyStopButton'].IsEnabled = $IsRunning }
}

function Invoke-ClarkISOCheckExistingWorkMountCleanup {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [scriptblock]$Log = { param($m) Write-Output $m }
    )
    if (-not (Test-ClarkIsoWimMountDirDirty -WorkDir $WorkDir)) { return $false }
    & $Log "Incomplete wim_mount under $WorkDir - attempting cleanup..."
    $mountDir = Join-Path $WorkDir 'wim_mount'
    $ok = Clear-ClarkIsoWimMount -MountPath $mountDir -Discard -Log $Log
    if ($ok -and -not (Test-ClarkIsoWimMountDirDirty -WorkDir $WorkDir)) {
        & $Log 'wim_mount cleared.'
        return $false
    }
    & $Log 'Incomplete modification detected (wim_mount still present). Use Clean and Reset or run scripts\Force-ClearClarkIsoWorkDir.ps1 as Administrator.'
    return $true
}

function Invoke-ClarkISORepairOrphanedMountsCore {
    param([scriptblock]$Log = { param($m) Write-Output $m })

    Stop-ClarkIsoMountHolderProcesses -Log $Log
    $orphanPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($img in @(Get-ClarkIsoMountedImages)) {
        try {
            $p = [System.IO.Path]::GetFullPath($img.Path).TrimEnd('\')
            if ($p -match 'ASYS_WinISO|ASYS_Win11ISO') { [void]$orphanPaths.Add($p) }
        } catch { }
    }
    foreach ($dir in @(Get-ChildItem -Path (Join-Path $env:TEMP 'ASYS_WinISO*') -Directory -ErrorAction SilentlyContinue)) {
        $m = Join-Path $dir.FullName 'wim_mount'
        if (Test-Path -LiteralPath $m) { [void]$orphanPaths.Add([System.IO.Path]::GetFullPath($m).TrimEnd('\')) }
    }
    foreach ($dir in @(Get-ChildItem -Path (Join-Path $env:TEMP 'ASYS_Win11ISO*') -Directory -ErrorAction SilentlyContinue)) {
        $m = Join-Path $dir.FullName 'wim_mount'
        if (Test-Path -LiteralPath $m) { [void]$orphanPaths.Add([System.IO.Path]::GetFullPath($m).TrimEnd('\')) }
    }
    if ($orphanPaths.Count -eq 0) { return $false }

    $incomplete = $false
    foreach ($path in @($orphanPaths)) {
        & $Log "Discarding orphaned mount: $path"
        if (-not (Clear-ClarkIsoWimMount -MountPath $path -Discard -Log $Log)) { $incomplete = $true }
    }
    if (Test-ClarkIsoRunningElevated) {
        try { & dism /English /Cleanup-Wim 2>&1 | ForEach-Object { & $Log $_ } } catch { }
    }
    foreach ($dir in @(Get-ChildItem -Path (Join-Path $env:TEMP 'ASYS_WinISO*') -Directory -ErrorAction SilentlyContinue)) {
        if (Test-ClarkIsoWimMountDirDirty -WorkDir $dir.FullName) { $incomplete = $true }
    }
    if ($incomplete) {
        & $Log 'Some wim_mount folders could not be fully cleared. Run scripts\Force-ClearClarkIsoWorkDir.ps1 as Administrator.'
    } else {
        & $Log 'Orphaned mount(s) discarded.'
    }
    return $incomplete
}

function Invoke-ClarkISORepairOrphanedMounts {
    $orphans = @(Get-ClarkISOOrphanedMounts)
    if ($orphans.Count -eq 0) { return $false }

    $paths = ($orphans | ForEach-Object { $_.MountPath }) -join "`n"
    $answer = [System.Windows.MessageBox]::Show(
        @"
An incomplete WIM mount was found from a previous session:

$paths

Discard the mount and uncommitted changes?
"@,
        'Incomplete ISO Build Detected', 'YesNo', 'Warning')

    if ($answer -ne 'Yes') {
        Write-Win11ISOLog 'Orphaned WIM mount left in place.'
        return $true
    }
    return Invoke-ClarkISORepairOrphanedMountsCore -Log { param($m) Write-Win11ISOLog $m }
}

function Get-ClarkIsoWorkerFunctionDefinitions {
    $names = @(
        'Test-ClarkIsoRunningElevated',
        'Grant-ClarkIsoPathFullControl',
        'Stop-ClarkIsoMountHolderProcesses',
        'Invoke-ClarkIsoDismExeUnmount',
        'Get-ClarkIsoMountedImages',
        'Get-ClarkIsoMountedImageForPath',
        'Dismount-AllClarkIsoMountedImages',
        'Remove-ClarkIsoWimMountFolder',
        'Clear-ClarkIsoWimMount',
        'Copy-ClarkAsysIsoPayload',
        'Test-ClarkIsoModifyStopRequested',
        'Stop-ClarkIsoModifyIfRequested'
    )
    $defs = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        if (-not (Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Warning "Get-ClarkIsoWorkerFunctionDefinitions: function '$name' not found — worker runspace may be incomplete."
            continue
        }
        $body = (Get-Command $name).ScriptBlock.ToString()
        $nl = [Environment]::NewLine
        [void]$defs.Add('function ' + $name + ' {' + $nl + $body + $nl + '}')
    }
    return @($defs)
}
