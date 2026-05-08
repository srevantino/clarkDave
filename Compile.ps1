param (
    [switch]$Run,
    [string]$Arguments
)

$ErrorActionPreference = "Stop"

$outputScriptPath = Join-Path $PSScriptRoot "A-SYS_clark.ps1"

if ((Get-Item $outputScriptPath -ErrorAction SilentlyContinue).IsReadOnly) {
    Remove-Item $outputScriptPath -Force
}

$OFS = "`r`n"
$scriptname = "A-SYS_clark.ps1"
$workingdir = $PSScriptRoot

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

function Write-CompileBanner {
    param([string]$Title)

    $line = ('=' * 72)
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host (" {0}" -f $Title) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor DarkCyan
}

function Write-Stage {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0,100)]
        [int]$Percent,

        [Parameter(Mandatory)]
        [string]$StatusMessage
    )

    $prefix = "[{0,3}%]" -f $Percent
    Write-Host "$prefix $StatusMessage" -ForegroundColor Gray
}

function Write-Check {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [switch]$Pass
    )

    if ($Pass) {
        Write-Host ("[OK ] {0}" -f $Message) -ForegroundColor Green
    } else {
        Write-Host ("[ERR] {0}" -f $Message) -ForegroundColor Red
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Check -Message "$Label not found: $Path"
        throw "$Label missing: $Path"
    }

    Write-Check -Message "$Label found" -Pass
}

Write-CompileBanner "Clark Build Compiler"
Write-Stage -Percent 0 -StatusMessage "Validating prerequisites"
Assert-PathExists -Path (Join-Path $workingdir "tools") -Label "Tools directory"
Assert-PathExists -Path (Join-Path $workingdir "functions") -Label "Functions directory"
Assert-PathExists -Path (Join-Path $workingdir "config") -Label "Config directory"
Assert-PathExists -Path (Join-Path $workingdir "xaml\inputXML.xaml") -Label "XAML input file"
Assert-PathExists -Path (Join-Path $workingdir "tools\autounattend.xml") -Label "Autounattend file"
Assert-PathExists -Path (Join-Path $workingdir "scripts\start.ps1") -Label "Start script"
Assert-PathExists -Path (Join-Path $workingdir "scripts\main.ps1") -Label "Main script"

Write-Stage -Percent 2 -StatusMessage "Running preprocessor"

# Dot source the 'Invoke-Preprocessing' Function from 'tools/Invoke-Preprocessing.ps1' Script
$preprocessingFilePath = Join-Path $workingdir "tools\Invoke-Preprocessing.ps1"
Assert-PathExists -Path $preprocessingFilePath -Label "Preprocessor script"
. $preprocessingFilePath
if (-not (Get-Command -Name Invoke-Preprocessing -ErrorAction SilentlyContinue)) {
    Write-Check -Message "Invoke-Preprocessing function not available after dot-sourcing"
    throw "Failed to import Invoke-Preprocessing"
}
Write-Check -Message "Invoke-Preprocessing loaded" -Pass

$excludedFiles = @()

# Add directories only if they exist
if (Test-Path '.\.git\') { $excludedFiles += '.\.git\' }
if (Test-Path '.\.idea\') { $excludedFiles += '.\.idea\' }
if (Test-Path '.\binary\') { $excludedFiles += '.\binary\' }
# JSON configs must not be run through PowerShell formatting regex (can break valid JSON)
if (Test-Path '.\config\') { $excludedFiles += '.\config\' }

# Add files that should always be excluded
$excludedFiles += @(
    '.\.gitignore',
    '.\.gitattributes',
    '.\.github\CODEOWNERS',
    '.\LICENSE',
    "$preprocessingFilePath",
    '*.png',
    '.\.preprocessor_hashes.json'
)

$msg = "Pre-req: Code Formatting"
Invoke-Preprocessing -WorkingDir "$workingdir" -ExcludedFiles @($excludedFiles) -ProgressStatusMessage $msg

# Create the script in memory.
Write-Stage -Percent 5 -StatusMessage "Allocating script memory"
$script_content = [System.Collections.Generic.List[string]]::new()

Write-Stage -Percent 10 -StatusMessage "Adding version header"
$script_content.Add($(Get-Content (Join-Path $workingdir "scripts\start.ps1")).replace('#{replaceme}',"$(Get-Date -Format yy.MM.dd)"))

Write-Stage -Percent 20 -StatusMessage "Adding functions"
Get-ChildItem (Join-Path $workingdir "functions") -Recurse -File | ForEach-Object {
    $script_content.Add($(Get-Content $psitem.FullName))
    }
Write-Stage -Percent 40 -StatusMessage "Adding JSON config"
Get-ChildItem (Join-Path $workingdir "config") | Where-Object {$psitem.extension -eq ".json"} | ForEach-Object {
    $json = (Get-Content $psitem.FullName -Raw)
    $jsonAsObject = $json | ConvertFrom-Json

    # Add 'WPFInstall' as a prefix to every entry-name in 'applications.json' file
    if ($psitem.Name -eq "applications.json") {
        foreach ($appEntryName in $jsonAsObject.PSObject.Properties.Name) {
            $appEntryContent = $jsonAsObject.$appEntryName
            $jsonAsObject.PSObject.Properties.Remove($appEntryName)
            $jsonAsObject | Add-Member -MemberType NoteProperty -Name "WPFInstall$appEntryName" -Value $appEntryContent
        }
    }

    # Line 90 requires no whitespace inside the here-strings, to keep formatting of the JSON in the final script.
    $json = @"
$($jsonAsObject | ConvertTo-Json -Depth 3)
"@

    $sync.configs.$($psitem.BaseName) = $json | ConvertFrom-Json
    $script_content.Add($(Write-Output "`$sync.configs.$($psitem.BaseName) = @'`r`n$json`r`n'@ `| ConvertFrom-Json" ))
}

# Read the entire XAML file as a single string, preserving line breaks
$xaml = Get-Content "$workingdir\xaml\inputXML.xaml" -Raw

Write-Stage -Percent 90 -StatusMessage "Adding XAML"

# Add the XAML content to $script_content using a here-string
$script_content.Add(@"
`$inputXML = @'
$xaml
'@
"@)

Write-Stage -Percent 95 -StatusMessage "Adding autounattend.xml"
$autounattendRaw = Get-Content "$workingdir\tools\autounattend.xml" -Raw
# Strip XML comments (<!-- ... -->, including multi-line)
$autounattendRaw = [regex]::Replace($autounattendRaw, '<!--.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
# Drop blank lines and trim trailing whitespace per line
$autounattendXml = ($autounattendRaw -split "`r?`n" |
    Where-Object { $_.Trim() -ne '' } |
    ForEach-Object { $_.TrimEnd() }) -join "`r`n"
$script_content.Add(@"
`$WinUtilAutounattendXml = @'
$autounattendXml
'@
"@)

$script_content.Add($(Get-Content (Join-Path $workingdir "scripts\main.ps1")))

Write-Stage -Percent 99 -StatusMessage "Cleaning temporary files"
Remove-Item "xaml\inputApp.xaml" -ErrorAction SilentlyContinue
Remove-Item "xaml\inputTweaks.xaml" -ErrorAction SilentlyContinue
Remove-Item "xaml\inputFeatures.xaml" -ErrorAction SilentlyContinue

Set-Content -Path $outputScriptPath -Value ($script_content -join "`r`n") -Encoding ascii
Write-Check -Message "Compiled script written: $scriptname" -Pass

Write-Stage -Percent 100 -StatusMessage "Validating PowerShell syntax"
try {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($outputScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw ($parseErrors | ForEach-Object { $_.Message } | Select-Object -First 1)
    }
    Write-Check -Message "Syntax validation passed for $scriptname" -Pass
} catch {
    Write-Check -Message "Syntax validation failed for $scriptname"
    Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Cyan

if ($run) {
    Write-Host "Launching $scriptname..." -ForegroundColor Cyan
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    & $outputScriptPath $Arguments
    break
}
