#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Force-clear a stuck ASYS WinISO work folder (locked wim_mount / SOFTWARE hive).
.NOTES
    1. Close Clark (A-SYS_clark.ps1) before running this.
    2. If cleanup fails, reboot and run again (-ScheduleRebootOnFailure schedules delete on reboot).
#>
param(
    [string]$WorkDir = '',
    [switch]$ScheduleRebootOnFailure,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

if (-not $WorkDir) {
    $candidates = @(Get-ChildItem -Path (Join-Path $env:TEMP 'ASYS_WinISO*') -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -gt 0) {
        $WorkDir = $candidates[0].FullName
        Write-Host "Auto-detected work directory: $WorkDir" -ForegroundColor Cyan
    } else {
        Write-Host 'No ASYS_WinISO work directory found in %TEMP%. Specify -WorkDir explicitly.' -ForegroundColor Red
        exit 1
    }
}

Write-Host ''
Write-Host 'IMPORTANT: Close Clark (A-SYS_clark.ps1) completely before continuing.' -ForegroundColor Yellow
if (-not $NonInteractive) {
    Write-Host 'Press Enter when Clark is closed, or Ctrl+C to cancel...'
    [void][Console]::ReadLine()
}

$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'functions\private\Invoke-ClarkIsoBuildSupport.ps1')

function Write-Log([string]$m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

$ok = Invoke-ClarkIsoForceClearWorkDir -WorkDir $WorkDir -Log { param($x) Write-Log $x } -ScheduleRebootOnFailure:$ScheduleRebootOnFailure

if ($ok) {
    Write-Host ''
    Write-Host 'Success. Run Compile.ps1 if needed, then start A-SYS_clark.ps1 and build again.' -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host 'Cleanup incomplete.' -ForegroundColor Red
Write-Host 'Try: close Clark, reboot, then run:' -ForegroundColor Yellow
Write-Host "  .\scripts\Force-ClearClarkIsoWorkDir.ps1 -ScheduleRebootOnFailure" -ForegroundColor Cyan
exit 1
