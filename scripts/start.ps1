<#
.NOTES
    Product        : clark
    Organization   : Advance Systems 4042 (developed & managed)
    Version        : #{replaceme}
#>

param (
    [string]$Config,
    [switch]$Run,
    [switch]$Noui,
    [switch]$Offline
)

$PARAM_CONFIG = $null
if ($Config) {
    $PARAM_CONFIG = $Config
}

$PARAM_RUN = $false
# Handle the -Run switch
if ($Run) {
    $PARAM_RUN = $true
}

$PARAM_NOUI = $false
if ($Noui) {
    $PARAM_NOUI = $true
}

$PARAM_OFFLINE = $false
if ($Offline) {
    $PARAM_OFFLINE = $true
}


if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "clark needs to be run as Administrator. Attempting to relaunch."
    $argList = @()

    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    # Prefer local script path so dev/testing works; optional remote fallback when path is unknown (e.g. pasted into console).
    $localScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
    $deployUrl = if ($env:ASYS_DEPLOY_URL) { $env:ASYS_DEPLOY_URL } else { 'https://clark.advancesystems4042.com/?token=covxo5-nyrmUh-rodgac' }
    $script = if ($localScriptPath) {
        "& { & `'$($localScriptPath)`' $($argList -join ' ') }"
    } else {
        "irm '$deployUrl' | iex"
    }

    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { "$powershellCmd" }

    if ($processCmd -eq "wt.exe") {
        Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    } else {
        Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    }

    exit
}

# Load DLLs
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})

# Resolve script root for file and in-memory executions (e.g. irm | iex).
$resolvedScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($resolvedScriptRoot) -and $PSCommandPath) {
    $resolvedScriptRoot = Split-Path -Parent $PSCommandPath
}
if ([string]::IsNullOrWhiteSpace($resolvedScriptRoot)) {
    $resolvedScriptRoot = (Get-Location).Path
}

# Repo root: compiled script lives in repo root (.\config exists); dev start.ps1 lives in scripts\ (use parent).
$repoRoot = $null
if (Test-Path -LiteralPath (Join-Path $resolvedScriptRoot "config")) {
    $repoRoot = $resolvedScriptRoot
} else {
    $parent = Split-Path -Parent $resolvedScriptRoot
    if ($parent -and (Test-Path -LiteralPath (Join-Path $parent "config"))) {
        $repoRoot = $parent
    }
}

# In deployed/irm mode, config is bundled in-script, so missing disk config should not block startup.
$sync.PSScriptRoot = if ($repoRoot) { $repoRoot } else { $resolvedScriptRoot }
$sync.version = "#{replaceme}"
$sync.configs = @{}
$sync.Buttons = [System.Collections.Generic.List[PSObject]]::new()
$sync.preferences = @{}
$sync.ProcessRunning = $false
$sync.selectedApps = [System.Collections.Generic.List[string]]::new()
$sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()
$sync.selectedToggles = [System.Collections.Generic.List[string]]::new()
$sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()
$sync.currentTab = "Install"
$sync.selectedAppsStackPanel
$sync.selectedAppsPopup

$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# App data and logs (clark / Advance Systems 4042)
$asysdir = "$env:LocalAppData\asys"
New-Item $asysdir -ItemType Directory -Force | Out-Null
$sync.asysdir = $asysdir

$profilesDir = "$asysdir\profiles"
New-Item $profilesDir -ItemType Directory -Force | Out-Null
$sync.profilesDir = $profilesDir

$rollbackDir = "$asysdir\rollback"
New-Item $rollbackDir -ItemType Directory -Force | Out-Null
$sync.rollbackDir = $rollbackDir

$logdir = "$asysdir\logs"
New-Item $logdir -ItemType Directory -Force | Out-Null
Start-Transcript -Path "$logdir\asys_$dateTime.log" -Append -NoClobber | Out-Null

# Set PowerShell window title
$Host.UI.RawUI.WindowTitle = "clark (Admin)"
clear-host

# Dev only: Compile.ps1 concatenates functions, configs, XAML, and main.ps1 after this file — do not load from disk then.
$devMainPath = Join-Path $resolvedScriptRoot "main.ps1"
if (Test-Path -LiteralPath $devMainPath) {
    $repoRoot = $sync.PSScriptRoot
    $configDir = Join-Path $repoRoot "config"
    if (-not (Test-Path -LiteralPath $configDir)) {
        throw "Config directory not found: $configDir"
    }

    Get-ChildItem -LiteralPath $configDir -File -Filter "*.json" | ForEach-Object {
        $json = Get-Content -LiteralPath $_.FullName -Raw
        $jsonAsObject = $json | ConvertFrom-Json
        if ($_.Name -eq "applications.json") {
            foreach ($appEntryName in @($jsonAsObject.PSObject.Properties.Name)) {
                $appEntryContent = $jsonAsObject.$appEntryName
                [void]$jsonAsObject.PSObject.Properties.Remove($appEntryName)
                $jsonAsObject | Add-Member -MemberType NoteProperty -Name "WPFInstall$appEntryName" -Value $appEntryContent
            }
        }
        $json = @"
$($jsonAsObject | ConvertTo-Json -Depth 3)
"@
        $sync.configs[$_.BaseName] = $json | ConvertFrom-Json
    }

    $xamlPath = Join-Path $repoRoot "xaml\inputXML.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "XAML not found: $xamlPath"
    }
    $inputXML = Get-Content -LiteralPath $xamlPath -Raw

    $autopath = Join-Path $repoRoot "tools\autounattend.xml"
    if (Test-Path -LiteralPath $autopath) {
        $autounattendRaw = Get-Content -LiteralPath $autopath -Raw
        $autounattendRaw = [regex]::Replace($autounattendRaw, "<!--.*?-->", "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $WinUtilAutounattendXml = ($autounattendRaw -split "`r?`n" |
            Where-Object { $_.Trim() -ne "" } |
            ForEach-Object { $_.TrimEnd() }) -join "`r`n"
    } else {
        $WinUtilAutounattendXml = ""
    }

    $functionsRoot = Join-Path $repoRoot "functions"
    Get-ChildItem -LiteralPath $functionsRoot -Recurse -File -Filter "*.ps1" | ForEach-Object { . $_.FullName }

    . $devMainPath
}
