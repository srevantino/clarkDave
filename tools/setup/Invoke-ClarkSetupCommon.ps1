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
