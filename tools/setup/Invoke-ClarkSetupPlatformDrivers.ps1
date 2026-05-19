#Requires -Version 5.1
$here = $PSScriptRoot
. (Join-Path $here 'Invoke-ClarkSetupCommon.ps1')

function Get-IntelProcessorGeneration {
    param([string]$CpuName)

    if ([string]::IsNullOrWhiteSpace($CpuName)) { return $null }

    if ($CpuName -match '(?i)(\d+)(?:st|nd|rd|th)\s+Gen') {
        return [int]$Matches[1]
    }

    # Core i3/i5/i7/i9 — leading digits of model number (e.g. i5-12400 → 12, i7-9750 → 9)
    if ($CpuName -match '(?i)\bi[3579]-(\d{2})\d{2,3}[A-Z]*\b') {
        return [int]$Matches[1]
    }
    if ($CpuName -match '(?i)\bi[3579]-(\d)\d{3}[A-Z]*\b') {
        return [int]$Matches[1]
    }

    return $null
}

function Get-IntelGenRangeSubfolders {
    <#
    .SYNOPSIS
        Finds IRST_* subfolders whose name range (e.g. 8-9 in IRST_8-9G) contains $Generation.
        When multiple match, returns the narrowest range (most specific).
    #>
    param(
        [Parameter(Mandatory)][string]$PackRoot,
        [Parameter(Mandatory)][int]$Generation
    )

    $candidates = @()
    foreach ($dir in Get-ChildItem -LiteralPath $PackRoot -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -match '(?i)(\d+)\s*-\s*(\d+)') {
            $minGen = [int]$Matches[1]
            $maxGen = [int]$Matches[2]
            if ($Generation -ge $minGen -and $Generation -le $maxGen) {
                $candidates += [PSCustomObject]@{
                    Path = $dir.FullName
                    Name = $dir.Name
                    Min  = $minGen
                    Max  = $maxGen
                    Span = $maxGen - $minGen
                }
            }
        }
    }

    if (-not $candidates) { return @() }

    $narrowest = ($candidates | Sort-Object -Property Span, Min | Select-Object -First 1).Span
    @($candidates | Where-Object { $_.Span -eq $narrowest })
}

function Install-ClarkDriverFolder {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [Parameter(Mandatory)][string]$Label
    )

    $infs = Get-ChildItem -LiteralPath $FolderPath -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
    if (-not $infs) {
        Write-ClarkSetupLog -Message "No .inf files in $Label ($FolderPath)" -LogName 'platform-drivers.log' -Level 'WARN'
        return
    }

    Write-ClarkSetupLog -Message "pnputil: $Label <- $FolderPath" -LogName 'platform-drivers.log'
    $out = & pnputil.exe '/add-driver', (Join-Path $FolderPath '*.inf'), '/subdirs', '/install' 2>&1
    $out | ForEach-Object { Write-ClarkSetupLog -Message "  $_" -LogName 'platform-drivers.log' }
    if ($LASTEXITCODE -ne 0) {
        throw "pnputil failed for $Label (exit $LASTEXITCODE)"
    }
}

$asysRoot = Find-ClarkAsysRoot
if (-not $asysRoot) { return }

$manifestPath = Join-Path (Join-Path $asysRoot 'drivers') 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-ClarkSetupLog -Message 'No drivers manifest; skipping.' -LogName 'platform-drivers.log'
    return
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$cpuName = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
Write-ClarkSetupLog -Message "CPU: $cpuName" -LogName 'platform-drivers.log'

$intelGen = Get-IntelProcessorGeneration -CpuName $cpuName
if ($null -ne $intelGen) {
    Write-ClarkSetupLog -Message "Detected Intel generation: $intelGen" -LogName 'platform-drivers.log'
} else {
    Write-ClarkSetupLog -Message 'Could not parse Intel CPU generation from processor name.' -LogName 'platform-drivers.log' -Level 'WARN'
}

if (-not (Get-Command pnputil.exe -ErrorAction SilentlyContinue)) {
    Write-ClarkSetupLog -Message 'pnputil unavailable in WinPE.' -LogName 'platform-drivers.log' -Level 'WARN'
    return
}

$driversRoot = Join-Path $asysRoot 'drivers'
$anyInstalled = $false

foreach ($entry in $manifest.entries) {
    $packRoot = Join-Path $driversRoot $entry.folder
    if (-not (Test-Path -LiteralPath $packRoot)) {
        Write-ClarkSetupLog -Message "Pack missing: $packRoot" -LogName 'platform-drivers.log' -Level 'WARN'
        continue
    }

    $vendorMatch = $false
    foreach ($pattern in $entry.patterns) {
        if ($cpuName -like "*$pattern*") { $vendorMatch = $true; break }
    }
    if (-not $vendorMatch) {
        Write-ClarkSetupLog -Message "Skipping '$($entry.id)' (CPU name does not match vendor patterns)." -LogName 'platform-drivers.log'
        continue
    }

    $entryType = if ($entry.PSObject.Properties['type']) { [string]$entry.type } else { '' }

    if ($entryType -eq 'intel-gen-subfolders') {
        if ($null -eq $intelGen) {
            Write-ClarkSetupLog -Message "Skipping '$($entry.id)' (Intel generation unknown)." -LogName 'platform-drivers.log' -Level 'WARN'
            continue
        }

        $minG = if ($entry.PSObject.Properties['minGeneration']) { [int]$entry.minGeneration } else { 0 }
        $maxG = if ($entry.PSObject.Properties['maxGeneration']) { [int]$entry.maxGeneration } else { 99 }
        if ($intelGen -lt $minG -or $intelGen -gt $maxG) {
            Write-ClarkSetupLog -Message "Skipping '$($entry.id)' (gen $intelGen outside pack range $minG-$maxG)." -LogName 'platform-drivers.log'
            continue
        }

        $subfolders = Get-IntelGenRangeSubfolders -PackRoot $packRoot -Generation $intelGen
        if (-not $subfolders) {
            Write-ClarkSetupLog -Message "No subfolder for Intel gen $intelGen under $packRoot" -LogName 'platform-drivers.log' -Level 'WARN'
            continue
        }

        foreach ($sub in $subfolders) {
            Write-ClarkSetupLog -Message "Matched $($sub.Name) for generation $intelGen (range $($sub.Min)-$($sub.Max))" -LogName 'platform-drivers.log'
            Install-ClarkDriverFolder -FolderPath $sub.Path -Label "$($entry.id)\$($sub.Name)"
            $anyInstalled = $true
        }
        continue
    }

    # Legacy: flat pack folder (all .inf under pack root)
    if ($entryType -ne 'intel-gen-subfolders') {
        if (Get-ChildItem -LiteralPath $packRoot -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue) {
            Install-ClarkDriverFolder -FolderPath $packRoot -Label $entry.id
            $anyInstalled = $true
        }
    }
}

if (-not $anyInstalled) {
    Write-ClarkSetupLog -Message 'No platform driver pack was installed (non-fatal if storage already visible).' -LogName 'platform-drivers.log' -Level 'WARN'
} else {
    Write-ClarkSetupLog -Message 'Platform driver pass complete.' -LogName 'platform-drivers.log'
}
