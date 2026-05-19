#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$setupRoot = 'C:\Setup'
$logFile = Join-Path $setupRoot 'firstlogon-errors.log'

function Write-FirstLogonLog([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        if (-not (Test-Path $setupRoot)) { New-Item -ItemType Directory -Path $setupRoot -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch { }
}

function Show-FirstLogonError([string]$Title, [string]$Message) {
    Write-FirstLogonLog "$Title : $Message"
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($Message, "Clark — $Title", 'OK', 'Error')
    } catch {
        $vbs = "MsgBox ""$($Message -replace '"','""')"", 16, ""Clark - $Title"""
        $p = Join-Path $env:TEMP 'clark-fl-err.vbs'
        Set-Content -LiteralPath $p -Value $vbs -Encoding ASCII
        Start-Process wscript.exe -ArgumentList "`"$p`"" -Wait
    }
}

$master = Join-Path $setupRoot 'master.ps1'
if (-not (Test-Path -LiteralPath $master)) {
    Show-FirstLogonError 'master.ps1 missing' "Expected: $master`nRebuild with Full ASYS Deployment."
    exit 1
}

try {
    Write-FirstLogonLog 'Running master.ps1'
    & $master
} catch {
    Show-FirstLogonError 'Post-install setup failed' $_.Exception.Message
    exit 1
}
