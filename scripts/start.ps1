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

$global:ClarkStartupLog = Join-Path ([System.IO.Path]::GetTempPath()) "clark_startup.log"
try {
    Add-Content -LiteralPath $global:ClarkStartupLog -Value ("[{0}] Launch: User={1} Admin={2} PWD={3} Script={4}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $env:USERNAME, ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator), (Get-Location).Path, $PSCommandPath)
} catch {}

trap {
    $errText = $_ | Out-String
    try { Add-Content -LiteralPath $global:ClarkStartupLog -Value ("[{0}] FATAL:`r`n{1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $errText) } catch {}
    Write-Host $errText -ForegroundColor Red
    Write-Host "Startup failed. Log file: $global:ClarkStartupLog" -ForegroundColor Yellow
    if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to close" | Out-Null }
    break
}



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

    $argList = New-Object System.Collections.Generic.List[string]



    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [switch] -and $_.Value) {
            $argList.Add("-$($_.Key)")
        } elseif ($_.Value -is [array]) {
            $argList.Add("-$($_.Key)")
            $argList.Add(($_.Value -join ','))
        } elseif ($_.Value) {
            $argList.Add("-$($_.Key)")
            $argList.Add("$($_.Value)")
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



    $powershellCmd = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    # Launch directly with Windows PowerShell for elevation.
    # Use -EncodedCommand to avoid argument quoting issues with paths that contain spaces.
    if ($localScriptPath) {
        $bootstrapLog = Join-Path ([System.IO.Path]::GetTempPath()) "clark_elevated_bootstrap.log"
        $quotedScriptPath = "'" + ($localScriptPath -replace "'", "''") + "'"
        $forwardedArgsLiteral = ($argList | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join " "
        $bootstrapCommand = @"
`$ErrorActionPreference = 'Stop'
`$log = '$($bootstrapLog -replace "'", "''")'
Add-Content -LiteralPath `$log -Value ('[{0}] Elevated bootstrap start. Script={1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $quotedScriptPath)
try {
    & $quotedScriptPath $forwardedArgsLiteral
    Add-Content -LiteralPath `$log -Value ('[{0}] Elevated bootstrap exit code 0' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
} catch {
    Add-Content -LiteralPath `$log -Value ('[{0}] Elevated bootstrap failure:`r`n{1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), (`$_ | Out-String))
    throw
}
"@
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrapCommand))
        try {
            Start-Process -FilePath $powershellCmd -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-EncodedCommand', $encodedCommand) -Verb RunAs -ErrorAction Stop
        } catch {
            Write-Host ""
            Write-Host "clark requires Administrator privileges to run." -ForegroundColor Yellow
            Write-Host "Please accept the UAC prompt, or right-click the script and select 'Run as administrator'." -ForegroundColor Yellow
            Write-Host ""
            if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to close" | Out-Null }
            exit 1
        }

    } else {

        try {
            Start-Process -FilePath $powershellCmd -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-Command', $script) -Verb RunAs -ErrorAction Stop
        } catch {
            Write-Host ""
            Write-Host "clark requires Administrator privileges to run." -ForegroundColor Yellow
            Write-Host "Please accept the UAC prompt, or right-click the script and select 'Run as administrator'." -ForegroundColor Yellow
            Write-Host ""
            if ($Host.Name -eq 'ConsoleHost') { Read-Host "Press Enter to close" | Out-Null }
            exit 1
        }

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



    function ConvertTo-ClarkAutounattendEmbedded {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return "" }
        $raw = Get-Content -LiteralPath $Path -Raw
        $raw = [regex]::Replace($raw, "<!--.*?-->", "", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        return ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.TrimEnd() }) -join "`r`n"
    }

    $ClarkAutounattendXml = ConvertTo-ClarkAutounattendEmbedded -Path (Join-Path $repoRoot "tools\autounattend.xml")
    $ClarkAutounattendLegacyXml = ConvertTo-ClarkAutounattendEmbedded -Path (Join-Path $repoRoot "tools\autounattend-legacy.xml")



    $functionsRoot = Join-Path $repoRoot "functions"

    Get-ChildItem -LiteralPath $functionsRoot -Recurse -File -Filter "*.ps1" | ForEach-Object { . $_.FullName }



    . $devMainPath

}

