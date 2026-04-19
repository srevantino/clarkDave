function Get-WinUtilClarkBackupsDirectory {
    $d = Join-Path $env:USERPROFILE "Clark\Backups"
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    return $d
}

function Invoke-WinUtilPreTweakRegistryExport {
    <#
    .SYNOPSIS
        Exports HKCU and HKLM to timestamped .reg files before applying tweaks.
    .NOTES
        Coarse safety net only. Per-tweak undo remains Save-WinUtilRollbackSnapshot / rollback journal.
    #>
    [CmdletBinding()]
    param()

    $dir = Get-WinUtilClarkBackupsDirectory
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $base = Join-Path $dir "pre-tweak-$stamp"
    $hkcuPath = "$base-HKCU.reg"
    $hklmPath = "$base-HKLM.reg"
    $regExe = Join-Path $env:SystemRoot "System32\reg.exe"

    $results = [ordered]@{
        HKCUPath = $hkcuPath
        HKLMPath = $hklmPath
        HKCUOk   = $false
        HKLMOk   = $false
        Messages = [System.Collections.Generic.List[string]]::new()
    }

    $pHKCU = Start-Process -FilePath $regExe -ArgumentList @('export', 'HKCU', $hkcuPath, '/y') -Wait -PassThru -WindowStyle Hidden
    if ($pHKCU.ExitCode -eq 0 -and (Test-Path -LiteralPath $hkcuPath)) {
        $results.HKCUOk = $true
        [void]$results.Messages.Add("HKCU export: $hkcuPath")
    } else {
        [void]$results.Messages.Add("HKCU export failed (exit $($pHKCU.ExitCode)).")
    }

    $pHKLM = Start-Process -FilePath $regExe -ArgumentList @('export', 'HKLM', $hklmPath, '/y') -Wait -PassThru -WindowStyle Hidden
    if ($pHKLM.ExitCode -eq 0 -and (Test-Path -LiteralPath $hklmPath)) {
        $results.HKLMOk = $true
        [void]$results.Messages.Add("HKLM export: $hklmPath")
    } else {
        [void]$results.Messages.Add("HKLM export may require elevation or failed (exit $($pHKLM.ExitCode)).")
    }

    return [pscustomobject]$results
}

function Test-WinUtilRegistryBackupThrottle {
    param(
        [int]$Seconds = 120
    )
    $key = 'LastPreTweakRegistryBackupUtc'
    if (-not $sync.ContainsKey($key) -or $null -eq $sync.$key) {
        return $false
    }
    $elapsed = ([datetime]::UtcNow - [datetime]$sync.$key).TotalSeconds
    return ($elapsed -lt $Seconds)
}

function Invoke-WinUtilPreTweakRegistryExportIfNeeded {
    <#
    .SYNOPSIS
        Exports registry backup unless a recent backup exists (toggle spam guard).
    #>
    param(
        [switch]$Force
    )
    if (-not $Force -and (Test-WinUtilRegistryBackupThrottle -Seconds 120)) {
        return $null
    }
    $out = Invoke-WinUtilPreTweakRegistryExport
    $sync.LastPreTweakRegistryBackupUtc = [datetime]::UtcNow
    return $out
}

function Get-WinUtilRegistryBackupFiles {
    $dir = Get-WinUtilClarkBackupsDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        return @()
    }
    return Get-ChildItem -LiteralPath $dir -Filter "pre-tweak-*.reg" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Invoke-WinUtilRegistryBackupRestore {
    <#
    .SYNOPSIS
        Imports selected .reg files (merges into live registry).
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$LiteralPaths
    )
    $regExe = Join-Path $env:SystemRoot "System32\reg.exe"
    foreach ($p in $LiteralPaths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $proc = Start-Process -FilePath $regExe -ArgumentList @('import', $p) -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -ne 0) {
            throw "reg import failed for '$p' (exit $($proc.ExitCode))."
        }
    }
}
