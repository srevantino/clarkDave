<#

.NOTES

    Product        : clark

    Organization   : Advance Systems 4042 (developed & managed)

    Version        : 26.05.16

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
        Start-Process -FilePath $powershellCmd -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-EncodedCommand', $encodedCommand) -Verb RunAs -ErrorAction Stop

    } else {

        Start-Process -FilePath $powershellCmd -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-NoProfile', '-Command', $script) -Verb RunAs -ErrorAction Stop

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

$sync.version = "26.05.16"

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



# Dev only: Compile.ps1 concatenates functions, configs, XAML, and main.ps1 after this file ??? do not load from disk then.

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

        $ClarkAutounattendXml = ($autounattendRaw -split "`r?`n" |

            Where-Object { $_.Trim() -ne "" } |

            ForEach-Object { $_.TrimEnd() }) -join "`r`n"

    } else {

        $ClarkAutounattendXml = ""

    }



    $functionsRoot = Join-Path $repoRoot "functions"

    Get-ChildItem -LiteralPath $functionsRoot -Recurse -File -Filter "*.ps1" | ForEach-Object { . $_.FullName }



    . $devMainPath

}

    function Add-SelectedAppsMenuItem {
        <#
        .SYNOPSIS
            This is a helper function that generates and adds the Menu Items to the Selected Apps Popup.

        .Parameter name
            The actual Name of an App like "Chrome" or "Brave"
            This name is contained in the "Content" property inside the applications.json
        .PARAMETER key
            The key which identifies an app object in applications.json
            For Chrome this would be "WPFInstallchrome" because "WPFInstall" is prepended automatically for each key in applications.json
        #>

        param ([string]$name, [string]$key)

        $selectedAppGrid = New-Object Windows.Controls.Grid

        $selectedAppGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "*"}))
        $selectedAppGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width = "30"}))

        # Sets the name to the Content as well as the Tooltip, because the parent Popup Border has a fixed width and text could "overflow".
        # With the tooltip, you can still read the whole entry on hover
        $selectedAppLabel = New-Object Windows.Controls.Label
        $selectedAppLabel.Content = $name
        $selectedAppLabel.ToolTip = $name
        $selectedAppLabel.HorizontalAlignment = "Left"
        $selectedAppLabel.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
        [System.Windows.Controls.Grid]::SetColumn($selectedAppLabel, 0)
        $selectedAppGrid.Children.Add($selectedAppLabel)

        $selectedAppRemoveButton = New-Object Windows.Controls.Button
        $selectedAppRemoveButton.FontFamily = "Segoe MDL2 Assets"
        $selectedAppRemoveButton.Content = [string]([char]0xE711)
        $selectedAppRemoveButton.HorizontalAlignment = "Center"
        $selectedAppRemoveButton.Tag = $key
        $selectedAppRemoveButton.ToolTip = "Remove the App from Selection"
        $selectedAppRemoveButton.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")
        $selectedAppRemoveButton.SetResourceReference([Windows.Controls.Control]::StyleProperty, "HoverButtonStyle")

        # Highlight the Remove icon on Hover
        $selectedAppRemoveButton.Add_MouseEnter({ $this.Foreground = "Red" })
        $selectedAppRemoveButton.Add_MouseLeave({ $this.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor") })
        $selectedAppRemoveButton.Add_Click({
            $sync.($this.Tag).isChecked = $false # On click of the remove button, we only have to uncheck the corresponding checkbox. This will kick of all necessary changes to update the UI
        })
        [System.Windows.Controls.Grid]::SetColumn($selectedAppRemoveButton, 1)
        $selectedAppGrid.Children.Add($selectedAppRemoveButton)
        # Add new Element to Popup
        $sync.selectedAppsstackPanel.Children.Add($selectedAppGrid)
    }
function Convert-ClarkProfileInputToList {

    <#

    .SYNOPSIS

        Normalizes profile import JSON to a flat list of checkbox IDs.

    #>

    param(

        [Parameter(Mandatory)]

        $InputObject

    )



    if ($null -eq $InputObject) {

        return @()

    }



    if ($InputObject -is [string]) {

        return @($InputObject)

    }



    if ($InputObject -is [System.Collections.IDictionary]) {

        $keys = @($InputObject.Keys)

        if ($keys -contains 'apps' -or $keys -contains 'tweaks' -or $keys -contains 'toggles' -or $keys -contains 'features' -or $keys -contains 'schema') {

            $out = [System.Collections.Generic.List[string]]::new()

            foreach ($k in @('apps', 'tweaks', 'toggles', 'features')) {

                if (-not ($InputObject.ContainsKey($k))) { continue }

                foreach ($x in @($InputObject[$k])) {

                    $sx = [string]$x

                    if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$out.Add($sx) }

                }

            }

            return $out

        }

    }



    $propNames = @($InputObject.PSObject.Properties.Name)

    if ($propNames -contains 'apps' -or $propNames -contains 'tweaks' -or $propNames -contains 'toggles' -or $propNames -contains 'features' -or $propNames -contains 'schema') {

        $out = [System.Collections.Generic.List[string]]::new()

        foreach ($k in @('apps', 'tweaks', 'toggles', 'features')) {

            if (-not ($propNames -contains $k)) { continue }

            foreach ($x in @($InputObject.$k)) {

                $sx = [string]$x

                if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$out.Add($sx) }

            }

        }

        return $out

    }



    return @($InputObject)

}

function Find-AppsByNameOrDescription {
    <#
        .SYNOPSIS
            Searches through the Apps on the Install Tab and hides all entries that do not match the string

        .PARAMETER SearchString
            The string to be searched for
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$SearchString = ""
    )
    # Reset the visibility if the search string is empty or the search is cleared
    if ([string]::IsNullOrWhiteSpace($SearchString)) {
        $sync.ItemsControl.Items | ForEach-Object {
            # Each item is a StackPanel container
            $_.Visibility = [Windows.Visibility]::Visible

            if ($_.Children.Count -ge 2) {
                $categoryLabel = $_.Children[0]
                $wrapPanel = $_.Children[1]

                # Keep category label visible
                $categoryLabel.Visibility = [Windows.Visibility]::Visible

                # Respect the collapsed state of categories (indicated by + prefix)
                if ($categoryLabel.Content -like "+*") {
                    $wrapPanel.Visibility = [Windows.Visibility]::Collapsed
                } else {
                    $wrapPanel.Visibility = [Windows.Visibility]::Visible
                }

                # Show all apps within the category
                $wrapPanel.Children | ForEach-Object {
                    $_.Visibility = [Windows.Visibility]::Visible
                }
            }
        }
        return
    }

    # Perform search
    $sync.ItemsControl.Items | ForEach-Object {
        # Each item is a StackPanel container with Children[0] = label, Children[1] = WrapPanel
        if ($_.Children.Count -ge 2) {
            $categoryLabel = $_.Children[0]
            $wrapPanel = $_.Children[1]
            $categoryHasMatch = $false

            # Keep category label visible
            $categoryLabel.Visibility = [Windows.Visibility]::Visible

            # Search through apps in this category
            $wrapPanel.Children | ForEach-Object {
                $appEntry = $sync.configs.applicationsHashtable.$($_.Tag)
                if ($appEntry.Content -like "*$SearchString*" -or $appEntry.Description -like "*$SearchString*") {
                    # Show the App and mark that this category has a match
                    $_.Visibility = [Windows.Visibility]::Visible
                    $categoryHasMatch = $true
                } else {
                    $_.Visibility = [Windows.Visibility]::Collapsed
                }
            }

            # If category has matches, show the WrapPanel and update the category label to expanded state
            if ($categoryHasMatch) {
                $wrapPanel.Visibility = [Windows.Visibility]::Visible
                $_.Visibility = [Windows.Visibility]::Visible
                # Update category label to show expanded state (-)
                if ($categoryLabel.Content -like "+*") {
                    $categoryLabel.Content = $categoryLabel.Content -replace "^\+ ", "- "
                }
            } else {
                # Hide the entire category container if no matches
                $_.Visibility = [Windows.Visibility]::Collapsed
            }
        }
    }
}
function Find-TweaksByNameOrDescription {
    <#
        .SYNOPSIS
            Searches through the Tweaks on the Tweaks Tab and hides all entries that do not match the search string

        .PARAMETER SearchString
            The string to be searched for
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$SearchString = ""
    )

    # Reset the visibility if the search string is empty or the search is cleared
    if ([string]::IsNullOrWhiteSpace($SearchString)) {
        # Show all categories
        $tweakspanel = $sync.Form.FindName("tweakspanel")
        $tweakspanel.Children | ForEach-Object {
            $_.Visibility = [Windows.Visibility]::Visible

            # Foreach category section, show all items
            if ($_ -is [Windows.Controls.Border]) {
                $_.Visibility = [Windows.Visibility]::Visible

                # Find ItemsControl
                $dockPanel = $_.Child
                if ($dockPanel -is [Windows.Controls.DockPanel]) {
                    $itemsControl = $dockPanel.Children | Where-Object { $_ -is [Windows.Controls.ItemsControl] }
                    if ($itemsControl) {
                        # Show items in the category
                        foreach ($item in $itemsControl.Items) {
                            if ($item -is [Windows.Controls.Label]) {
                                $item.Visibility = [Windows.Visibility]::Visible
                            } elseif ($item -is [Windows.Controls.DockPanel] -or
                                      $item -is [Windows.Controls.StackPanel]) {
                                $item.Visibility = [Windows.Visibility]::Visible
                            }
                        }
                    }
                }
            }
        }
        return
    }

    # Search for matching tweaks when search string is not null
    $tweakspanel = $sync.Form.FindName("tweakspanel")

    $tweakspanel.Children | ForEach-Object {
        $categoryBorder = $_
        $categoryVisible = $false

        if ($_ -is [Windows.Controls.Border]) {
            # Find the ItemsControl
            $dockPanel = $_.Child
            if ($dockPanel -is [Windows.Controls.DockPanel]) {
                $itemsControl = $dockPanel.Children | Where-Object { $_ -is [Windows.Controls.ItemsControl] }
                if ($itemsControl) {
                    $categoryLabel = $null

                    # Process all items in the ItemsControl
                    for ($i = 0; $i -lt $itemsControl.Items.Count; $i++) {
                        $item = $itemsControl.Items[$i]

                        if ($item -is [Windows.Controls.Label]) {
                            $categoryLabel = $item
                            $item.Visibility = [Windows.Visibility]::Collapsed
                        } elseif ($item -is [Windows.Controls.DockPanel]) {
                            $checkbox = $item.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] } | Select-Object -First 1
                            $label = $item.Children | Where-Object { $_ -is [Windows.Controls.Label] } | Select-Object -First 1

                            if ($label -and ($label.Content -like "*$SearchString*" -or $label.ToolTip -like "*$SearchString*")) {
                                $item.Visibility = [Windows.Visibility]::Visible
                                if ($categoryLabel) { $categoryLabel.Visibility = [Windows.Visibility]::Visible }
                                $categoryVisible = $true
                            } else {
                                $item.Visibility = [Windows.Visibility]::Collapsed
                            }
                        } elseif ($item -is [Windows.Controls.StackPanel]) {
                            # StackPanel which contain checkboxes or other elements
                            $checkbox = $item.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] } | Select-Object -First 1

                            if ($checkbox -and ($checkbox.Content -like "*$SearchString*" -or $checkbox.ToolTip -like "*$SearchString*")) {
                                $item.Visibility = [Windows.Visibility]::Visible
                                if ($categoryLabel) { $categoryLabel.Visibility = [Windows.Visibility]::Visible }
                                $categoryVisible = $true
                            } else {
                                $item.Visibility = [Windows.Visibility]::Collapsed
                            }
                        }
                    }
                }
            }

            # Set the visibility based on if any item matched
            $categoryBorder.Visibility = if ($categoryVisible) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }

        }
    }
}
function Get-ClarkHardwareSummaryData {

    <#

    .SYNOPSIS

        Collects hardware strings for UI / export via CIM.

    #>

    $sb = [System.Text.StringBuilder]::new()



    $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)

    [void]$sb.AppendLine("=== CPU ===")

    foreach ($c in $cpu) {

        [void]$sb.AppendLine("$($c.Name)")

        [void]$sb.AppendLine("  Manufacturer: $($c.Manufacturer)  Cores: $($c.NumberOfCores)  Logical: $($c.NumberOfLogicalProcessors)")

    }



    $ram = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue

    $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue)

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("=== Memory ===")

    if ($ram) {

        $totalGb = [math]::Round($ram.TotalPhysicalMemory / 1GB, 2)

        [void]$sb.AppendLine("Total visible: $totalGb GB")

    }

    foreach ($m in $modules) {

        $cap = [math]::Round($m.Capacity / 1GB, 2)

        [void]$sb.AppendLine("  $cap GB @ $($m.Speed) MHz  $($m.Manufacturer)  $($m.PartNumber)".Trim())

    }



    $gpu = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("=== Display adapters ===")

    foreach ($g in $gpu) {

        if ([string]::IsNullOrWhiteSpace($g.Name)) { continue }

        [void]$sb.AppendLine("$($g.Name)")

        [void]$sb.AppendLine("  Driver: $($g.DriverVersion)  RAM: $($g.AdapterRAM)  Status: $($g.Status)")

    }



    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("=== Motherboard ===")

    if ($board) {

        [void]$sb.AppendLine("$($board.Manufacturer) $($board.Product)  ($($board.Version))")

        [void]$sb.AppendLine("  Serial: $($board.SerialNumber)")

    }



    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue

    if ($bios) {

        [void]$sb.AppendLine("BIOS: $($bios.SMBIOSBIOSVersion)  $($bios.ReleaseDate)")

    }



    $disks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue)

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("=== Disk drives ===")

    foreach ($d in $disks) {

        $sizeGb = if ($d.Size) { [math]::Round([double]$d.Size / 1GB, 0) } else { "?" }

        [void]$sb.AppendLine("$($d.Model)  $($sizeGb) GB  [$($d.InterfaceType)]  $($d.MediaType)")

    }



    $vols = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 3 })

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("=== Logical volumes ===")

    foreach ($v in $vols) {

        $free = [math]::Round($v.FreeSpace / 1GB, 1)

        $tot = [math]::Round($v.Size / 1GB, 1)

        [void]$sb.AppendLine("$($v.DeviceID)  $free / $tot GB free  $($v.VolumeName)  [$($v.FileSystem)]")

    }



    try {

        $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)

        if ($pd.Count -gt 0) {

            [void]$sb.AppendLine("")

            [void]$sb.AppendLine("=== PhysicalDisk (health) ===")

            foreach ($p in $pd) {

                [void]$sb.AppendLine("$($p.FriendlyName)  Health: $($p.HealthStatus)  Op: $($p.OperationalStatus)  Media: $($p.MediaType)")

            }

        }

    } catch { }



    return $sb.ToString()

}

function Get-ClarkInstallerProcess {

    <#



    .SYNOPSIS

        Checks if the given process is running



    .PARAMETER Process

        The process to check



    .OUTPUTS

        Boolean - True if the process is running



    #>



    param($Process)



    if ($Null -eq $Process) {

        return $false

    }

    if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) {

        return $true

    }

    return $false

}

function Get-ClarkSelectedPackages

{

     <#

    .SYNOPSIS

        Sorts given packages based on installer preference and availability.



    .OUTPUTS

        Hashtable. Key = Package Manager, Value = ArrayList of packages to install

    #>

    param (

        [Parameter(Mandatory=$true)]

        $PackageList,

        [Parameter(Mandatory=$true)]

        [PackageManagers]$Preference

    )



    if ($PackageList.count -eq 1) {

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" -value 0.01 -overlay "logo" }

    } else {

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo" }

    }



    $packages = [System.Collections.Hashtable]::new()

    $packagesWinget = [System.Collections.ArrayList]::new()

    $packagesChoco = [System.Collections.ArrayList]::new()

    $packages[[PackageManagers]::Winget] = $packagesWinget

    $packages[[PackageManagers]::Choco] = $packagesChoco



    Write-Debug "Checking packages using Preference '$($Preference)'"



    foreach ($package in $PackageList) {

        if ($package.winget -eq "na" -and $package.choco -eq "na") {

            Write-Warning "[clark / Advance Systems 4042] $($package.content) has no WinGet or Chocolatey package. Download or install from: $($package.link)"

            continue

        }

        switch ($Preference) {

            "Choco" {

                if ($package.choco -eq "na") {

                    Write-Debug "$($package.content) has no Choco value."

                    $null = $packagesWinget.add($($package.winget))

                    Write-Host "Queueing $($package.winget) for WinGet..."

                } else {

                    $null = $packagesChoco.add($package.choco)

                    Write-Host "Queueing $($package.choco) for Chocolatey..."

                }

                break

            }

            "Winget" {

                if ($package.winget -eq "na") {

                    Write-Debug "$($package.content) has no WinGet value."

                    $null = $packagesChoco.add($package.choco)

                    Write-Host "Queueing $($package.choco) for Chocolatey..."

                } else {

                    $null = $packagesWinget.add($($package.winget))

                    Write-Host "Queueing $($package.winget) for WinGet..."

                }

                break

            }

        }

    }



    return $packages

}

Function Get-ClarkToggleStatus {

    <#



    .SYNOPSIS

        Pulls the registry keys for the given toggle switch and checks whether the toggle should be checked or unchecked



    .PARAMETER ToggleSwitch

        The name of the toggle to check



    .OUTPUTS

        Boolean to set the toggle's status to



    #>



    Param($ToggleSwitch)



    $ToggleSwitchReg = $sync.configs.tweaks.$ToggleSwitch.registry



    try {

        if (($ToggleSwitchReg.path -imatch "hku") -and !(Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {

            $null = (New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS)

            if (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue) {

                Write-Debug "HKU drive created successfully."

            } else {

                Write-Debug "Failed to create HKU drive."

            }

        }

    } catch {

        Write-Error "An error occurred regarding the HKU Drive: $_"

        return $false

    }



    if ($ToggleSwitchReg) {

        $count = 0



        foreach ($regentry in $ToggleSwitchReg) {

            try {

                if (!(Test-Path $regentry.Path)) {

                    New-Item -Path $regentry.Path -Force | Out-Null

                }

                $regstate = (Get-ItemProperty -path $regentry.Path).$($regentry.Name)

                if ($regstate -eq $regentry.Value) {

                    $count += 1

                    Write-Debug "$($regentry.Name) is true (state: $regstate, value: $($regentry.Value), original: $($regentry.OriginalValue))"

                } else {

                    Write-Debug "$($regentry.Name) is false (state: $regstate, value: $($regentry.Value), original: $($regentry.OriginalValue))"

                }

                if ($null -eq $regstate) {

                    switch ($regentry.DefaultState) {

                        "true" {

                            $regstate = $regentry.Value

                            $count += 1

                        }

                        "false" {

                            $regstate = $regentry.OriginalValue

                        }

                        default {

                            Write-Error "Entry for $($regentry.Name) does not exist and no DefaultState is defined."

                            $regstate = $regentry.OriginalValue

                        }

                    }

                }

            } catch {

                Write-Error "An unexpected error occurred: $_"

            }

        }



        if ($count -eq $ToggleSwitchReg.Count) {

            Write-Debug "$($ToggleSwitchReg.Name) is true (count: $count)"

            return $true

        } else {

            Write-Debug "$($ToggleSwitchReg.Name) is false (count: $count)"

            return $false

        }

    } else {

        return $false

    }

}

function Get-ClarkVariables {



    <#

    .SYNOPSIS

        Gets every form object of the provided type



    .OUTPUTS

        List containing every object that matches the provided type

    #>

    param (

        [Parameter()]

        [string[]]$Type

    )

    $keys = ($sync.keys).where{ $_ -like "WPF*" }

    if ($Type) {

        $output = $keys | ForEach-Object {

            try {

                $objType = $sync["$psitem"].GetType().Name

                if ($Type -contains $objType) {

                    Write-Output $psitem

                }

            } catch {

                <#I am here so errors don't get outputted for a couple variables that don't have the .GetType() attribute#>

            }

        }

        return $output

    }

    return $keys

}

function Get-LocalizedYesNo {
    <#
    .SYNOPSIS
    This function runs choice.exe and captures its output to extract yes no in a localized Windows

    .DESCRIPTION
    The function retrieves the output of the command 'cmd /c "choice <nul 2>nul"' and converts the default output for Yes and No
    in the localized format, such as "Yes=<first character>, No=<second character>".

    .EXAMPLE
    $yesNoArray = Get-LocalizedYesNo
    Write-Host "Yes=$($yesNoArray[0]), No=$($yesNoArray[1])"
    #>

    # Run choice and capture its options as output
    # The output shows the options for Yes and No as "[Y,N]?" in the (partially) localized format.
    # eg. English: [Y,N]?
    # Dutch: [Y,N]?
    # German: [J,N]?
    # French: [O,N]?
    # Spanish: [S,N]?
    # Italian: [S,N]?
    # Russian: [Y,N]?

    $line = cmd /c "choice <nul 2>nul"
    $charactersArray = @()
    $regexPattern = '([a-zA-Z])'
    $charactersArray = [regex]::Matches($line, $regexPattern) | ForEach-Object { $_.Groups[1].Value }

    Write-Debug "According to takeown.exe local Yes is $charactersArray[0]"
    # Return the array of characters
    return $charactersArray

  }
function Get-WPFObjectName {
    <#
        .SYNOPSIS
            This is a helper function that generates an objectname with the prefix WPF that can be used as a Powershell Variable after compilation.
            To achieve this, all characters that are not a-z, A-Z or 0-9 are simply removed from the name.

        .PARAMETER type
            The type of object for which the name should be generated. (e.g. Label, Button, CheckBox...)

        .PARAMETER name
            The name or description to be used for the object. (invalid characters are removed)

        .OUTPUTS
            A string that can be used as a object/variable name in powershell.
            For example: WPFLabelMicrosoftTools

        .EXAMPLE
            Get-WPFObjectName -type Label -name "Microsoft Tools"
    #>

    param(
        [Parameter(Mandatory, position=0)]
        [string]$type,

        [Parameter(position=1)]
        [string]$name
    )

    $Output = $("WPF"+$type+$name) -replace '[^a-zA-Z0-9]', ''
    return $Output
}
function Hide-WPFInstallAppBusy {
    <#
    .SYNOPSIS
        Hides the busy overlay in the install app area of the WPF form.
        This is used to indicate that an install or uninstall has finished.
    #>
    Invoke-WPFUIThread -ScriptBlock {
        $sync.InstallAppAreaOverlay.Visibility = [Windows.Visibility]::Collapsed
        $sync.InstallAppAreaBorder.IsEnabled = $true
        $sync.InstallAppAreaScrollViewer.Effect.Radius = 0
    }
}
    function Initialize-InstallAppArea {
        <#
            .SYNOPSIS
                Creates a [Windows.Controls.ScrollViewer] containing a [Windows.Controls.ItemsControl] which is setup to use Virtualization to only load the visible elements for performance reasons.
                This is used as the parent object for all category and app entries on the install tab
                Used to as part of the Install Tab UI generation

                Also creates an overlay with a progress bar and text to indicate that an install or uninstall is in progress

            .PARAMETER TargetElement
                The element to which the AppArea should be added

        #>
        param($TargetElement)
        $targetGrid = $sync.Form.FindName($TargetElement)
        $null = $targetGrid.Children.Clear()

        # Create the outer Border for the aren where the apps will be placed
        $Border = New-Object Windows.Controls.Border
        $Border.VerticalAlignment = "Stretch"
        $Border.SetResourceReference([Windows.Controls.Control]::StyleProperty, "BorderStyle")
        $sync.InstallAppAreaBorder = $Border

        # Add a ScrollViewer, because the ItemsControl does not support scrolling by itself
        $scrollViewer = New-Object Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = 'Auto'
        $scrollViewer.HorizontalAlignment = 'Stretch'
        $scrollViewer.VerticalAlignment = 'Stretch'
        $scrollViewer.CanContentScroll = $true
        $sync.InstallAppAreaScrollViewer = $scrollViewer
        $Border.Child = $scrollViewer

        # Initialize the Blur Effect for the ScrollViewer, which will be used to indicate that an install/uninstall is in progress
        $blurEffect = New-Object Windows.Media.Effects.BlurEffect
        $blurEffect.Radius = 0
        $scrollViewer.Effect = $blurEffect

        ## Create the ItemsControl, which will be the parent of all the app entries
        $itemsControl = New-Object Windows.Controls.ItemsControl
        $itemsControl.HorizontalAlignment = 'Stretch'
        $itemsControl.VerticalAlignment = 'Stretch'
        $scrollViewer.Content = $itemsControl

        # Use WrapPanel to create dynamic columns based on AppEntryWidth and window width
        $itemsPanelTemplate = New-Object Windows.Controls.ItemsPanelTemplate
        $factory = New-Object Windows.FrameworkElementFactory ([Windows.Controls.WrapPanel])
        $factory.SetValue([Windows.Controls.WrapPanel]::OrientationProperty, [Windows.Controls.Orientation]::Horizontal)
        $factory.SetValue([Windows.Controls.WrapPanel]::HorizontalAlignmentProperty, [Windows.HorizontalAlignment]::Left)
        $itemsPanelTemplate.VisualTree = $factory
        $itemsControl.ItemsPanel = $itemsPanelTemplate

        # Add the Border containing the App Area to the target Grid
        $targetGrid.Children.Add($Border) | Out-Null

        $overlay = New-Object Windows.Controls.Border
        $overlay.CornerRadius = New-Object Windows.CornerRadius(10)
        $overlay.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "AppInstallOverlayBackgroundColor")
        $overlay.Visibility = [Windows.Visibility]::Collapsed

        # Also add the overlay to the target Grid on top of the App Area
        $targetGrid.Children.Add($overlay) | Out-Null
        $sync.InstallAppAreaOverlay = $overlay

        $overlayText = New-Object Windows.Controls.TextBlock
        $overlayText.Text = "Installing apps..."
        $overlayText.HorizontalAlignment = 'Center'
        $overlayText.VerticalAlignment = 'Center'
        $overlayText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")
        $overlayText.Background = "Transparent"
        $overlayText.SetResourceReference([Windows.Controls.TextBlock]::FontSizeProperty, "HeaderFontSize")
        $overlayText.SetResourceReference([Windows.Controls.TextBlock]::FontFamilyProperty, "MainFontFamily")
        $overlayText.SetResourceReference([Windows.Controls.TextBlock]::FontWeightProperty, "MainFontWeight")
        $overlayText.SetResourceReference([Windows.Controls.TextBlock]::MarginProperty, "MainMargin")
        $sync.InstallAppAreaOverlayText = $overlayText

        $progressbar = New-Object Windows.Controls.ProgressBar
        $progressbar.Name = "ProgressBar"
        $progressbar.Width = 250
        $progressbar.Height = 50
        $sync.ProgressBar = $progressbar

        # Add a TextBlock overlay for the progress bar text
        $progressBarTextBlock = New-Object Windows.Controls.TextBlock
        $progressBarTextBlock.Name = "progressBarTextBlock"
        $progressBarTextBlock.FontWeight = [Windows.FontWeights]::Bold
        $progressBarTextBlock.FontSize = 16
        $progressBarTextBlock.Width = $progressbar.Width
        $progressBarTextBlock.Height = $progressbar.Height
        $progressBarTextBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "ProgressBarTextColor")
        $progressBarTextBlock.TextTrimming = "CharacterEllipsis"
        $progressBarTextBlock.Background = "Transparent"
        $sync.progressBarTextBlock = $progressBarTextBlock

        # Create a Grid to overlay the text on the progress bar
        $progressGrid = New-Object Windows.Controls.Grid
        $progressGrid.Width = $progressbar.Width
        $progressGrid.Height = $progressbar.Height
        $progressGrid.Margin = "0,10,0,10"
        $progressGrid.Children.Add($progressbar) | Out-Null
        $progressGrid.Children.Add($progressBarTextBlock) | Out-Null

        $overlayStackPanel = New-Object Windows.Controls.StackPanel
        $overlayStackPanel.Orientation = "Vertical"
        $overlayStackPanel.HorizontalAlignment = 'Center'
        $overlayStackPanel.VerticalAlignment = 'Center'
        $overlayStackPanel.Children.Add($overlayText) | Out-Null
        $overlayStackPanel.Children.Add($progressGrid) | Out-Null

        $overlay.Child = $overlayStackPanel

        return $itemsControl
    }
function Initialize-InstallAppEntry {
    <#
        .SYNOPSIS
            Creates the app entry to be placed on the install tab for a given app
            Used to as part of the Install Tab UI generation
        .PARAMETER TargetElement
            The Element into which the Apps should be placed
        .PARAMETER appKey
            The Key of the app inside the $sync.configs.applicationsHashtable
    #>
        param(
            [Windows.Controls.WrapPanel]$TargetElement,
            $appKey
        )

        # Create the outer Border for the application type
        $border = New-Object Windows.Controls.Border
        $border.Style = $sync.Form.Resources.AppEntryBorderStyle
        $border.Tag = $appKey
        $border.ToolTip = $Apps.$appKey.description
        $border.Add_MouseLeftButtonUp({
            $childCheckbox = ($this.Child | Where-Object {$_.Template.TargetType -eq [System.Windows.Controls.Checkbox]})[0]
            $childCheckBox.isChecked = -not $childCheckbox.IsChecked
        })
        $border.Add_MouseEnter({
            if (($sync.$($this.Tag).IsChecked) -eq $false) {
                $this.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "AppInstallHighlightedColor")
            }
        })
        $border.Add_MouseLeave({
            if (($sync.$($this.Tag).IsChecked) -eq $false) {
                $this.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "AppInstallUnselectedColor")
            }
        })
        $border.Add_MouseRightButtonUp({
            # Store the selected app in a global variable so it can be used in the popup
            $sync.appPopupSelectedApp = $this.Tag
            # Set the popup position to the current mouse position
            $sync.appPopup.PlacementTarget = $this
            $sync.appPopup.IsOpen = $true
        })

        $checkBox = New-Object Windows.Controls.CheckBox
        # Sanitize the name for WPF
        $checkBox.Name = $appKey -replace '-', '_'
        # Store the original appKey in Tag
        $checkBox.Tag = $appKey
        $checkbox.Style = $sync.Form.Resources.AppEntryCheckboxStyle
        $checkbox.Add_Checked({
            Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $this.Parent.Tag
            $borderElement = $this.Parent
            $borderElement.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "AppInstallSelectedColor")
        })

        $checkbox.Add_Unchecked({
            Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $this.Parent.Tag
            $borderElement = $this.Parent
            $borderElement.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "AppInstallUnselectedColor")
        })

        # Create the TextBlock for the application name
        $appName = New-Object Windows.Controls.TextBlock
        $appName.Style = $sync.Form.Resources.AppEntryNameStyle
        $appName.Text = $Apps.$appKey.content

        # Change color to Green if FOSS
        if ($Apps.$appKey.foss -eq $true) {
            $appName.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "FOSSColor")
            $appName.FontWeight = "Bold"
        }

        # Add the name to the Checkbox
        $checkBox.Content = $appName

        # Add accessibility properties to make the elements screen reader friendly
        $checkBox.SetValue([Windows.Automation.AutomationProperties]::NameProperty, $Apps.$appKey.content)
        $border.SetValue([Windows.Automation.AutomationProperties]::NameProperty, $Apps.$appKey.content)

        $border.Child = $checkBox
        # Add the border to the corresponding Category
        $TargetElement.Children.Add($border) | Out-Null
        return $checkbox
    }
function Initialize-InstallCategoryAppList {
    <#
        .SYNOPSIS
            Clears the Target Element and sets up a "Loading" message. This is done, because loading of all apps can take a bit of time in some scenarios
            Iterates through all Categories and Apps and adds them to the UI
            Used to as part of the Install Tab UI generation
        .PARAMETER TargetElement
            The Element into which the Categories and Apps should be placed
        .PARAMETER Apps
            The Hashtable of Apps to be added to the UI
            The Categories are also extracted from the Apps Hashtable

    #>
    param(
        $TargetElement,
        $Apps
    )

    function Add-InstallCategoryBlocks {
        param([hashtable]$AppsByCategory)

        foreach ($category in ($AppsByCategory.Keys | Sort-Object)) {
            # Create a container for category label + apps
            $categoryContainer = New-Object Windows.Controls.StackPanel
            $categoryContainer.Orientation = "Vertical"
            $categoryContainer.Margin = New-Object Windows.Thickness(0, 0, 0, 0)
            $categoryContainer.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
            [System.Windows.Automation.AutomationProperties]::SetName($categoryContainer, $Category)

            # Bind Width to the ItemsControl's ActualWidth to force full-row layout in WrapPanel
            $binding = New-Object Windows.Data.Binding
            $binding.Path = New-Object Windows.PropertyPath("ActualWidth")
            $binding.RelativeSource = New-Object Windows.Data.RelativeSource([Windows.Data.RelativeSourceMode]::FindAncestor, [Windows.Controls.ItemsControl], 1)
            [void][Windows.Data.BindingOperations]::SetBinding($categoryContainer, [Windows.FrameworkElement]::WidthProperty, $binding)

            # Add category label to container
            $toggleButton = New-Object Windows.Controls.Label
            $toggleButton.Content = "- $Category"
            $toggleButton.Tag = "CategoryToggleButton"
            $toggleButton.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")
            $toggleButton.SetResourceReference([Windows.Controls.Control]::FontFamilyProperty, "HeaderFontFamily")
            $toggleButton.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "LabelboxForegroundColor")
            $toggleButton.Cursor = [System.Windows.Input.Cursors]::Hand
            $toggleButton.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
            $sync.$Category = $toggleButton

            # Add click handler to toggle category visibility
            $toggleButton.Add_MouseLeftButtonUp({
                param($sender, $e)

                # Find the parent StackPanel (categoryContainer)
                $categoryContainer = $sender.Parent
                if ($categoryContainer -and $categoryContainer.Children.Count -ge 2) {
                    # The WrapPanel is the second child
                    $wrapPanel = $categoryContainer.Children[1]

                    # Toggle visibility
                    if ($wrapPanel.Visibility -eq [Windows.Visibility]::Visible) {
                        $wrapPanel.Visibility = [Windows.Visibility]::Collapsed
                        # Change - to +
                        $sender.Content = $sender.Content -replace "^- ", "+ "
                    } else {
                        $wrapPanel.Visibility = [Windows.Visibility]::Visible
                        # Change + to -
                        $sender.Content = $sender.Content -replace "^\+ ", "- "
                    }
                }
            })

            $null = $categoryContainer.Children.Add($toggleButton)

            # Add wrap panel for apps to container
            $wrapPanel = New-Object Windows.Controls.WrapPanel
            $wrapPanel.Orientation = "Horizontal"
            $wrapPanel.HorizontalAlignment = "Left"
            $wrapPanel.VerticalAlignment = "Top"
            $wrapPanel.Margin = New-Object Windows.Thickness(0, 0, 0, 0)
            $wrapPanel.Visibility = [Windows.Visibility]::Visible
            $wrapPanel.Tag = "CategoryWrapPanel_$category"

            $null = $categoryContainer.Children.Add($wrapPanel)

            # Add the entire category container to the target element
            $null = $TargetElement.Items.Add($categoryContainer)

            # Add apps to the wrap panel
            $AppsByCategory[$category] | Sort-Object | ForEach-Object {
                $sync.$_ = $(Initialize-InstallAppEntry -TargetElement $wrapPanel -AppKey $_)
            }
        }
    }

    function Add-InstallSectionHeader {
        param([string]$Title)

        $sectionHeader = New-Object Windows.Controls.Label
        $sectionHeader.Content = $Title
        $sectionHeader.Tag = "InstallSectionHeader"
        $sectionHeader.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")
        $sectionHeader.SetResourceReference([Windows.Controls.Control]::FontFamilyProperty, "HeaderFontFamily")
        $sectionHeader.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "LabelboxForegroundColor")
        $sectionHeader.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
        $sectionHeader.Margin = New-Object Windows.Thickness(0, 8, 0, 2)
        $null = $TargetElement.Items.Add($sectionHeader)
    }

    # Categories listed here appear under the "Others" section.
    $installUiOtherCategories = @('Media')

    # Pre-group apps by category
    $appsByCategory = @{}
    foreach ($appKey in $Apps.Keys) {
        $category = $Apps.$appKey.Category
        if (-not $appsByCategory.ContainsKey($category)) {
            $appsByCategory[$category] = @()
        }
        $appsByCategory[$category] += $appKey
    }

    $essentialsByCategory = @{}
    $othersByCategory = @{}
    foreach ($cat in $appsByCategory.Keys) {
        if ($installUiOtherCategories -contains $cat) {
            $othersByCategory[$cat] = $appsByCategory[$cat]
        } else {
            $essentialsByCategory[$cat] = $appsByCategory[$cat]
        }
    }

    if ($essentialsByCategory.Count -gt 0) {
        Add-InstallSectionHeader -Title "Technical"
        Add-InstallCategoryBlocks -AppsByCategory $essentialsByCategory
    }

    if ($othersByCategory.Count -gt 0) {
        Add-InstallSectionHeader -Title "Others"
        Add-InstallCategoryBlocks -AppsByCategory $othersByCategory
    }
}
function Install-ClarkChoco {



    <#



    .SYNOPSIS

        Installs Chocolatey if it is not already installed



    #>

    if ((Test-ClarkPackageManager -choco) -eq "installed") {

        return

    }



    Write-Host "Chocolatey is not installed. Installing now..."

    Invoke-WebRequest -Uri https://community.chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression

}

function Install-ClarkProgramChoco {

    <#

    .SYNOPSIS

    Manages the installation or uninstallation of a list of Chocolatey packages.



    .PARAMETER Programs

    A string array containing the programs to be installed or uninstalled.



    .PARAMETER Action

    Specifies the action to perform: "Install" or "Uninstall". The default value is "Install".



    .DESCRIPTION

    This function processes a list of programs to be managed using Chocolatey. Depending on the specified action, it either installs or uninstalls each program in the list, updating the taskbar progress accordingly. After all operations are completed, temporary output files are cleaned up.



    .EXAMPLE

    Install-ClarkProgramChoco -Programs @("7zip","chrome") -Action "Uninstall"

    #>



    param(

        [Parameter(Mandatory, Position = 0)]

        [string[]]$Programs,



        [Parameter(Position = 1)]

        [String]$Action = "Install"

    )



    function Initialize-OutputFile {

        <#

        .SYNOPSIS

        Initializes an output file by removing any existing file and creating a new, empty file at the specified path.



        .PARAMETER filePath

        The full path to the file to be initialized.



        .DESCRIPTION

        This function ensures that the specified file is reset by removing any existing file at the provided path and then creating a new, empty file. It is useful when preparing a log or output file for subsequent operations.



        .EXAMPLE

        Initialize-OutputFile -filePath "C:\temp\output.txt"

        #>



        param ($filePath)

        Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue

        New-Item -ItemType File -Path $filePath | Out-Null

    }



    function Invoke-ChocoCommand {

        <#

        .SYNOPSIS

        Executes a Chocolatey command with the specified arguments and returns the exit code.



        .PARAMETER arguments

        The arguments to be passed to the Chocolatey command.



        .DESCRIPTION

        This function runs a specified Chocolatey command by passing the provided arguments to the `choco` executable. It waits for the process to complete and then returns the exit code, allowing the caller to determine success or failure based on the exit code.



        .RETURNS

        [int]

        The exit code of the Chocolatey command.



        .EXAMPLE

        $exitCode = Invoke-ChocoCommand -arguments "install 7zip -y"

        #>



        param ($arguments)

        return (Start-Process -FilePath "choco" -ArgumentList $arguments -Wait -PassThru).ExitCode

    }



    function Test-UpgradeNeeded {

        <#

        .SYNOPSIS

        Checks if an upgrade is needed for a Chocolatey package based on the content of a log file.



        .PARAMETER filePath

        The path to the log file that contains the output of a Chocolatey install command.



        .DESCRIPTION

        This function reads the specified log file and checks for keywords that indicate whether an upgrade is needed. It returns a boolean value indicating whether the terms "reinstall" or "already installed" are present, which suggests that the package might need an upgrade.



        .RETURNS

        [bool]

        True if the log file indicates that an upgrade is needed; otherwise, false.



        .EXAMPLE

        $isUpgradeNeeded = Test-UpgradeNeeded -filePath "C:\temp\install-output.txt"

        #>



        param ($filePath)

        return Get-Content -Path $filePath | Select-String -Pattern "reinstall|already installed" -Quiet

    }



    function Update-TaskbarProgress {

        <#

        .SYNOPSIS

        Updates the taskbar progress based on the current installation progress.



        .PARAMETER currentIndex

        The current index of the program being installed or uninstalled.



        .PARAMETER totalPrograms

        The total number of programs to be installed or uninstalled.



        .DESCRIPTION

        This function calculates the progress of the installation or uninstallation process and updates the taskbar accordingly. The taskbar is set to "Normal" if all programs have been processed, otherwise, it is set to "Error" as a placeholder.



        .EXAMPLE

        Update-TaskbarProgress -currentIndex 3 -totalPrograms 10

        #>



        param (

            [int]$currentIndex,

            [int]$totalPrograms

        )

        $progressState = if ($currentIndex -eq $totalPrograms) { "Normal" } else { "Error" }

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state $progressState -value ($currentIndex / $totalPrograms) }

    }



    function Install-ChocoPackage {

        <#

        .SYNOPSIS

        Installs a Chocolatey package and optionally upgrades it if needed.



        .PARAMETER Program

        A string containing the name of the Chocolatey package to be installed.



        .PARAMETER currentIndex

        The current index of the program in the list of programs to be managed.



        .PARAMETER totalPrograms

        The total number of programs to be installed.



        .DESCRIPTION

        This function installs a Chocolatey package by running the `choco install` command. If the installation output indicates that an upgrade might be needed, the function will attempt to upgrade the package. The taskbar progress is updated after each package is processed.



        .EXAMPLE

        Install-ChocoPackage -Program $Program -currentIndex 0 -totalPrograms 5

        #>



        param (

            [string]$Program,

            [int]$currentIndex,

            [int]$totalPrograms

        )



        $installOutputFile = "$env:TEMP\Install-ClarkProgramChoco.install-command.output.txt"

        Initialize-OutputFile $installOutputFile



        Write-Host "Starting installation of $Program with Chocolatey."



        try {

            $installStatusCode = Invoke-ChocoCommand "install $Program -y --log-file $installOutputFile"

            if ($installStatusCode -eq 0) {



                if (Test-UpgradeNeeded $installOutputFile) {

                    $upgradeStatusCode = Invoke-ChocoCommand "upgrade $Program -y"

                    Write-Host "$Program was" $(if ($upgradeStatusCode -eq 0) { "upgraded successfully." } else { "not upgraded." })

                } else {

                    Write-Host "$Program installed successfully."

                }

            } else {

                Write-Host "Failed to install $Program."

            }

        } catch {

            Write-Host "Failed to install $Program due to an error: $_"

        }

        finally {

            Update-TaskbarProgress $currentIndex $totalPrograms

        }

    }



    function Uninstall-ChocoPackage {

        <#

        .SYNOPSIS

        Uninstalls a Chocolatey package and any related metapackages.



        .PARAMETER Program

        A string containing the name of the Chocolatey package to be uninstalled.



        .PARAMETER currentIndex

        The current index of the program in the list of programs to be managed.



        .PARAMETER totalPrograms

        The total number of programs to be uninstalled.



        .DESCRIPTION

        This function uninstalls a Chocolatey package and any related metapackages (e.g., .install or .portable variants). It updates the taskbar progress after processing each package.



        .EXAMPLE

        Uninstall-ChocoPackage -Program $Program -currentIndex 0 -totalPrograms 5

        #>



        param (

            [string]$Program,

            [int]$currentIndex,

            [int]$totalPrograms

        )



        $uninstallOutputFile = "$env:TEMP\Install-ClarkProgramChoco.uninstall-command.output.txt"

        Initialize-OutputFile $uninstallOutputFile



        Write-Host "Searching for metapackages of $Program (.install or .portable)"

        $chocoPackages = ((choco list | Select-String -Pattern "$Program(\.install|\.portable)?").Matches.Value) -join " "

        if ($chocoPackages) {

            Write-Host "Starting uninstallation of $chocoPackages with Chocolatey..."

            try {

                $uninstallStatusCode = Invoke-ChocoCommand "uninstall $chocoPackages -y"

                Write-Host "$Program" $(if ($uninstallStatusCode -eq 0) { "uninstalled successfully." } else { "failed to uninstall." })

            } catch {

                Write-Host "Failed to uninstall $Program due to an error: $_"

            }

            finally {

                Update-TaskbarProgress $currentIndex $totalPrograms

            }

        } else {

            Write-Host "$Program is not installed."

        }

    }



    $totalPrograms = $Programs.Count

    if ($totalPrograms -le 0) {

        throw "Parameter 'Programs' must have at least one item."

    }



    Write-Host "==========================================="

    Write-Host "--   Configuring Chocolatey packages   ---"

    Write-Host "==========================================="



    for ($currentIndex = 0; $currentIndex -lt $totalPrograms; $currentIndex++) {

        $Program = $Programs[$currentIndex]

        Set-ClarkProgressBar -label "$Action $($Program)" -percent ($currentIndex / $totalPrograms * 100)

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -value ($currentIndex / $totalPrograms)}



        switch ($Action) {

            "Install" {

                Install-ChocoPackage -Program $Program -currentIndex $currentIndex -totalPrograms $totalPrograms

            }

            "Uninstall" {

                Uninstall-ChocoPackage -Program $Program -currentIndex $currentIndex -totalPrograms $totalPrograms

            }

            default {

                throw "Invalid action parameter value: '$Action'."

            }

        }

    }

    Set-ClarkProgressBar -label "$($Action)ation done" -percent 100

    # Cleanup Output Files

    $outputFiles = @("$env:TEMP\Install-ClarkProgramChoco.install-command.output.txt", "$env:TEMP\Install-ClarkProgramChoco.uninstall-command.output.txt")

    foreach ($filePath in $outputFiles) {

        Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue

    }

}



Function Install-ClarkProgramWinget {

    <#

    .SYNOPSIS

    Runs the designated action on the provided programs using Winget



    .PARAMETER Programs

    A list of programs to process



    .PARAMETER action

    The action to perform on the programs, can be either 'Install' or 'Uninstall'



    .NOTES

    The triple quotes are required any time you need a " in a normal script block.

    The winget Return codes are documented here: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-actionr/winget/returnCodes.md

    #>



    param(

        [Parameter(Mandatory, Position=0)]$Programs,



        [Parameter(Mandatory, Position=1)]

        [ValidateSet("Install", "Uninstall")]

        [String]$Action

    )



    Function Invoke-Winget {

    <#

    .SYNOPSIS

    Invokes the winget.exe with the provided arguments and return the exit code



    .PARAMETER wingetId

    The Id of the Program that WinGet should Install/Uninstall



    .NOTES

    Invoke WinGet uses the public variable $Action defined outside the function to determine if a Program should be installed or removed

    #>

        param (

            [string]$wingetId

        )



        $commonArguments = "--id $wingetId --silent"

        $arguments = if ($Action -eq "Install") {

            "install $commonArguments --accept-source-agreements --accept-package-agreements --source winget"

        } else {

            "uninstall $commonArguments --source winget"

        }



        $processParams = @{

            FilePath = "winget"

            ArgumentList = $arguments

            Wait = $true

            PassThru = $true

            NoNewWindow = $true

        }



        return (Start-Process @processParams).ExitCode

    }



    Function Invoke-Install {

    <#

    .SYNOPSIS

    Contains the Install Logic and return code handling from winget



    .PARAMETER Program

    The WinGet ID of the Program that should be installed

    #>

        param (

            [string]$Program

        )

        $status = Invoke-Winget -wingetId $Program

        if ($status -eq 0) {

            Write-Host "$($Program) installed successfully."

            return $true

        } elseif ($status -eq -1978335189) {

            Write-Host "No applicable update found for $($Program)."

            return $true

        }



        Write-Host "Failed to install $($Program)."

        return $false

    }



    Function Invoke-Uninstall {

        <#

        .SYNOPSIS

        Contains the Uninstall Logic and return code handling from WinGet



        .PARAMETER Program

        The WinGet ID of the Program that should be uninstalled

        #>

        param (

            [string]$Program

        )



        try {

            $status = Invoke-Winget -wingetId $Program

            if ($status -eq 0) {

                Write-Host "$($Program) uninstalled successfully."

                return $true

            } else {

                Write-Host "Failed to uninstall $($Program)."

                return $false

            }

        } catch {

            Write-Host "Failed to uninstall $($Program) due to an error: $_"

            return $false

        }

    }



    $count = $Programs.Count

    $failedPackages = @()



    Write-Host "==========================================="

    Write-Host "--    Configuring WinGet packages       ---"

    Write-Host "==========================================="



    for ($i = 0; $i -lt $count; $i++) {

        $Program = $Programs[$i]

        $result = $false

        Set-ClarkProgressBar -label "$Action $($Program)" -percent ($i / $count * 100)

        Invoke-WPFUIThread -ScriptBlock{ Set-ClarkTaskbaritem -value ($i / $count)}



        $result = switch ($Action) {

            "Install" {Invoke-Install -Program $Program}

            "Uninstall" {Invoke-Uninstall -Program $Program}

            default {throw "[Install-ClarkProgramWinget] Invalid action: $Action"}

        }



        if (-not $result) {

            $failedPackages += $Program

        }

    }



    Set-ClarkProgressBar -label "$($Action) action done." -percent 100

    return $failedPackages

}

function Install-ClarkWinget {

    <#



    .SYNOPSIS

        Installs WinGet if not already installed.



    .DESCRIPTION

        installs winGet if needed

    #>

    if ((Test-ClarkPackageManager -winget) -eq "installed") {

        return

    }



    Write-Host "WinGet is not installed. Installing now..." -ForegroundColor Red



    Install-PackageProvider -Name NuGet -Force

    Install-Module -Name Microsoft.WinGet.Client -Force

    Repair-WinGetPackageManager -AllUsers

}

function Invoke-ClarkAssets {

  param (

      $type,

      $Size,

      [switch]$render

  )



  # Create the Viewbox and set its size

  $LogoViewbox = New-Object Windows.Controls.Viewbox

  $LogoViewbox.Width = $Size

  $LogoViewbox.Height = $Size



  # Create a Canvas to hold the paths

  $canvas = New-Object Windows.Controls.Canvas

  $canvas.Width = 100

  $canvas.Height = 100



  # Define a scale factor for the content inside the Canvas

  $scaleFactor = $Size / 100



  # Apply a scale transform to the Canvas content

  $scaleTransform = New-Object Windows.Media.ScaleTransform($scaleFactor, $scaleFactor)

  $canvas.LayoutTransform = $scaleTransform



  switch ($type) {

      'logo' {

          $LogoPathData1 = @"

M 18.00,14.00

C 18.00,14.00 45.00,27.74 45.00,27.74

45.00,27.74 57.40,34.63 57.40,34.63

57.40,34.63 59.00,43.00 59.00,43.00

59.00,43.00 59.00,83.00 59.00,83.00

55.35,81.66 46.99,77.79 44.72,74.79

41.17,70.10 42.01,59.80 42.00,54.00

42.00,51.62 42.20,48.29 40.98,46.21

38.34,41.74 25.78,38.60 21.28,33.79

16.81,29.02 18.00,20.20 18.00,14.00 Z

"@

          $LogoPath1 = New-Object Windows.Shapes.Path

          $LogoPath1.Data = [Windows.Media.Geometry]::Parse($LogoPathData1)

          $LogoPath1.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0567ff")



          $LogoPathData2 = @"

M 107.00,14.00

C 109.01,19.06 108.93,30.37 104.66,34.21

100.47,37.98 86.38,43.10 84.60,47.21

83.94,48.74 84.01,51.32 84.00,53.00

83.97,57.04 84.46,68.90 83.26,72.00

81.06,77.70 72.54,81.42 67.00,83.00

67.00,83.00 67.00,43.00 67.00,43.00

67.00,43.00 67.99,35.63 67.99,35.63

67.99,35.63 80.00,28.26 80.00,28.26

80.00,28.26 107.00,14.00 107.00,14.00 Z

"@

          $LogoPath2 = New-Object Windows.Shapes.Path

          $LogoPath2.Data = [Windows.Media.Geometry]::Parse($LogoPathData2)

          $LogoPath2.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0567ff")



          $LogoPathData3 = @"

M 19.00,46.00

C 21.36,47.14 28.67,50.71 30.01,52.63

31.17,54.30 30.99,57.04 31.00,59.00

31.04,65.41 30.35,72.16 33.56,78.00

38.19,86.45 46.10,89.04 54.00,93.31

56.55,94.69 60.10,97.20 63.00,97.22

65.50,97.24 68.77,95.36 71.00,94.25

76.42,91.55 84.51,87.78 88.82,83.68

94.56,78.20 95.96,70.59 96.00,63.00

96.01,60.24 95.59,54.63 97.02,52.39

98.80,49.60 103.95,47.87 107.00,47.00

107.00,47.00 107.00,67.00 107.00,67.00

106.90,87.69 96.10,93.85 80.00,103.00

76.51,104.98 66.66,110.67 63.00,110.52

60.33,110.41 55.55,107.53 53.00,106.25

46.21,102.83 36.63,98.57 31.04,93.68

16.88,81.28 19.00,62.88 19.00,46.00 Z

"@

          $LogoPath3 = New-Object Windows.Shapes.Path

          $LogoPath3.Data = [Windows.Media.Geometry]::Parse($LogoPathData3)

          $LogoPath3.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a3a4a6")



          $canvas.Children.Add($LogoPath1) | Out-Null

          $canvas.Children.Add($LogoPath2) | Out-Null

          $canvas.Children.Add($LogoPath3) | Out-Null

      }

      'checkmark' {

          $canvas.Width = 512

          $canvas.Height = 512



          $scaleFactor = $Size / 2.54

          $scaleTransform = New-Object Windows.Media.ScaleTransform($scaleFactor, $scaleFactor)

          $canvas.LayoutTransform = $scaleTransform



          # Define the circle path

          $circlePathData = "M 1.27,0 A 1.27,1.27 0 1,0 1.27,2.54 A 1.27,1.27 0 1,0 1.27,0"

          $circlePath = New-Object Windows.Shapes.Path

          $circlePath.Data = [Windows.Media.Geometry]::Parse($circlePathData)

          $circlePath.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#39ba00")



          # Define the checkmark path

          $checkmarkPathData = "M 0.873 1.89 L 0.41 1.391 A 0.17 0.17 0 0 1 0.418 1.151 A 0.17 0.17 0 0 1 0.658 1.16 L 1.016 1.543 L 1.583 1.013 A 0.17 0.17 0 0 1 1.599 1 L 1.865 0.751 A 0.17 0.17 0 0 1 2.105 0.759 A 0.17 0.17 0 0 1 2.097 0.999 L 1.282 1.759 L 0.999 2.022 L 0.874 1.888 Z"

          $checkmarkPath = New-Object Windows.Shapes.Path

          $checkmarkPath.Data = [Windows.Media.Geometry]::Parse($checkmarkPathData)

          $checkmarkPath.Fill = [Windows.Media.Brushes]::White



          # Add the paths to the Canvas

          $canvas.Children.Add($circlePath) | Out-Null

          $canvas.Children.Add($checkmarkPath) | Out-Null

      }

      'warning' {

          $canvas.Width = 512

          $canvas.Height = 512



          # Define a scale factor for the content inside the Canvas

          $scaleFactor = $Size / 512  # Adjust scaling based on the canvas size

          $scaleTransform = New-Object Windows.Media.ScaleTransform($scaleFactor, $scaleFactor)

          $canvas.LayoutTransform = $scaleTransform



          # Define the circle path

          $circlePathData = "M 256,0 A 256,256 0 1,0 256,512 A 256,256 0 1,0 256,0"

          $circlePath = New-Object Windows.Shapes.Path

          $circlePath.Data = [Windows.Media.Geometry]::Parse($circlePathData)

          $circlePath.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f41b43")



          # Define the exclamation mark path

          $exclamationPathData = "M 256 307.2 A 35.89 35.89 0 0 1 220.14 272.74 L 215.41 153.3 A 35.89 35.89 0 0 1 251.27 116 H 260.73 A 35.89 35.89 0 0 1 296.59 153.3 L 291.86 272.74 A 35.89 35.89 0 0 1 256 307.2 Z"

          $exclamationPath = New-Object Windows.Shapes.Path

          $exclamationPath.Data = [Windows.Media.Geometry]::Parse($exclamationPathData)

          $exclamationPath.Fill = [Windows.Media.Brushes]::White



          # Get the bounds of the exclamation mark path

          $exclamationBounds = $exclamationPath.Data.Bounds



          # Calculate the center position for the exclamation mark path

          $exclamationCenterX = ($canvas.Width - $exclamationBounds.Width) / 2 - $exclamationBounds.X

          $exclamationPath.SetValue([Windows.Controls.Canvas]::LeftProperty, $exclamationCenterX)



          # Define the rounded rectangle at the bottom (dot of exclamation mark)

          $roundedRectangle = New-Object Windows.Shapes.Rectangle

          $roundedRectangle.Width = 80

          $roundedRectangle.Height = 80

          $roundedRectangle.RadiusX = 30

          $roundedRectangle.RadiusY = 30

          $roundedRectangle.Fill = [Windows.Media.Brushes]::White



          # Calculate the center position for the rounded rectangle

          $centerX = ($canvas.Width - $roundedRectangle.Width) / 2

          $roundedRectangle.SetValue([Windows.Controls.Canvas]::LeftProperty, $centerX)

          $roundedRectangle.SetValue([Windows.Controls.Canvas]::TopProperty, 324.34)



          # Add the paths to the Canvas

          $canvas.Children.Add($circlePath) | Out-Null

          $canvas.Children.Add($exclamationPath) | Out-Null

          $canvas.Children.Add($roundedRectangle) | Out-Null

      }

      default {

          Write-Host "Invalid type: $type"

      }

  }



  # Add the Canvas to the Viewbox

  $LogoViewbox.Child = $canvas



  if ($render) {

      # Measure and arrange the canvas to ensure proper rendering

      $canvas.Measure([Windows.Size]::new($canvas.Width, $canvas.Height))

      $canvas.Arrange([Windows.Rect]::new(0, 0, $canvas.Width, $canvas.Height))

      $canvas.UpdateLayout()



      # Initialize RenderTargetBitmap correctly with dimensions

      $renderTargetBitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($canvas.Width, $canvas.Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)



      # Render the canvas to the bitmap

      $renderTargetBitmap.Render($canvas)



      # Create a BitmapFrame from the RenderTargetBitmap

      $bitmapFrame = [Windows.Media.Imaging.BitmapFrame]::Create($renderTargetBitmap)



      # Create a PngBitmapEncoder and add the frame

      $bitmapEncoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()

      $bitmapEncoder.Frames.Add($bitmapFrame)



      # Save to a memory stream

      $imageStream = New-Object System.IO.MemoryStream

      $bitmapEncoder.Save($imageStream)

      $imageStream.Position = 0



      # Load the stream into a BitmapImage

      $bitmapImage = [Windows.Media.Imaging.BitmapImage]::new()

      $bitmapImage.BeginInit()

      $bitmapImage.StreamSource = $imageStream

      $bitmapImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad

      $bitmapImage.EndInit()



      return $bitmapImage

  } else {

      return $LogoViewbox

  }

}

function Get-ClarkProfilesDirectory {

    if (-not $sync.asysdir) {

        $sync.asysdir = Join-Path $env:LocalAppData "asys"

    }



    $profilesDir = Join-Path $sync.asysdir "profiles"

    if (-not (Test-Path $profilesDir)) {

        New-Item -Path $profilesDir -ItemType Directory -Force | Out-Null

    }



    return $profilesDir

}



function Get-ClarkRollbackJournalPath {

    if (-not $sync.asysdir) {

        $sync.asysdir = Join-Path $env:LocalAppData "asys"

    }



    $rollbackDir = Join-Path $sync.asysdir "rollback"

    if (-not (Test-Path $rollbackDir)) {

        New-Item -Path $rollbackDir -ItemType Directory -Force | Out-Null

    }



    return (Join-Path $rollbackDir "journal.jsonl")

}



function Get-ClarkProfilePath {

    param(

        [Parameter(Mandatory)]

        [string]$Name

    )



    $safeName = ($Name -replace '[^\w\.-]', "_").Trim()

    if ([string]::IsNullOrWhiteSpace($safeName)) {

        throw "Profile name cannot be empty."

    }



    return (Join-Path (Get-ClarkProfilesDirectory) "$safeName.json")

}



function Get-ClarkProfiles {

    $profilesDir = Get-ClarkProfilesDirectory

    return Get-ChildItem -Path $profilesDir -Filter "*.json" -File -ErrorAction SilentlyContinue |

        Select-Object -ExpandProperty BaseName |

        Sort-Object

}



function Save-ClarkProfile {

    param(

        [Parameter(Mandatory)]

        [string]$Name

    )



    $profilePath = Get-ClarkProfilePath -Name $Name

    $selection = @(

        @($sync.selectedApps),

        @($sync.selectedTweaks),

        @($sync.selectedToggles),

        @($sync.selectedFeatures)

    ) | ForEach-Object { $_ } | ForEach-Object { [string]$_ }



    $selection | ConvertTo-Json | Out-File -Path $profilePath -Encoding ascii -Force

    $sync.preferences.activeprofile = $Name

    Set-Preferences -save

    return $profilePath

}



function Save-ClarkProfilePartial {

    <#

        .SYNOPSIS

            Saves only chosen selection lists (and optionally merges with an existing profile JSON).

    #>

    param(

        [Parameter(Mandatory)]

        [string]$Name,

        [bool]$IncludeApps = $false,

        [bool]$IncludeTweaks = $false,

        [bool]$IncludeToggles = $false,

        [bool]$IncludeFeatures = $false,

        [switch]$MergeExisting

    )



    if (-not ($IncludeApps -or $IncludeTweaks -or $IncludeToggles -or $IncludeFeatures)) {

        throw "Select at least one category to include in the profile."

    }



    $profilePath = Get-ClarkProfilePath -Name $Name

    $newItems = [System.Collections.Generic.List[string]]::new()



    if ($IncludeApps) {

        foreach ($x in @($sync.selectedApps)) {

            $sx = [string]$x

            if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$newItems.Add($sx) }

        }

    }

    if ($IncludeTweaks) {

        foreach ($x in @($sync.selectedTweaks)) {

            $sx = [string]$x

            if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$newItems.Add($sx) }

        }

    }

    if ($IncludeToggles) {

        foreach ($x in @($sync.selectedToggles)) {

            $sx = [string]$x

            if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$newItems.Add($sx) }

        }

    }

    if ($IncludeFeatures) {

        foreach ($x in @($sync.selectedFeatures)) {

            $sx = [string]$x

            if (-not [string]::IsNullOrWhiteSpace($sx)) { [void]$newItems.Add($sx) }

        }

    }



    if ($newItems.Count -eq 0) {

        throw "No selections in the chosen categories. Select items on Install / Tweaks / Config tabs first."

    }



    $combined = [System.Collections.Generic.List[string]]::new()

    if ($MergeExisting -and (Test-Path -LiteralPath $profilePath)) {

        try {

            $existing = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json

            foreach ($x in @($existing)) {

                $sx = [string]$x

                if (-not [string]::IsNullOrWhiteSpace($sx) -and -not $combined.Contains($sx)) {

                    [void]$combined.Add($sx)

                }

            }

        } catch {

            throw "Could not read existing profile for merge: $($_.Exception.Message)"

        }

    }



    foreach ($x in $newItems) {

        if (-not $combined.Contains($x)) {

            [void]$combined.Add($x)

        }

    }



    $combined | ConvertTo-Json | Out-File -LiteralPath $profilePath -Encoding ascii -Force

    $sync.preferences.activeprofile = $Name

    Set-Preferences -save

    return $profilePath

}



function Import-ClarkProfile {

    param(

        [Parameter(Mandatory)]

        [string]$Name,

        [switch]$ApplyToUI

    )



    $profilePath = Get-ClarkProfilePath -Name $Name

    if (-not (Test-Path $profilePath)) {

        throw "Profile '$Name' does not exist."

    }



    $profileData = Get-Content -Path $profilePath -Raw | ConvertFrom-Json

    $sync.selectedApps = [System.Collections.Generic.List[string]]::new()

    $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()

    $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()

    $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()



    Update-ClarkSelections -flatJson $profileData



    if ($ApplyToUI -and -not $PARAM_NOUI) {

        $sync.ImportInProgress = $true

        try {

            Reset-WPFCheckBoxes -doToggles $true

        } finally {

            $sync.ImportInProgress = $false

        }

    }



    $sync.preferences.activeprofile = $Name

    Set-Preferences -save

}



function Remove-ClarkProfile {

    param(

        [Parameter(Mandatory)]

        [string]$Name

    )



    $profilePath = Get-ClarkProfilePath -Name $Name

    if (Test-Path $profilePath) {

        Remove-Item -Path $profilePath -Force

    }



    if ($sync.preferences.activeprofile -eq $Name) {

        $sync.preferences.activeprofile = ""

        Set-Preferences -save

    }

}



function Save-ClarkRollbackSnapshot {

    param(

        [Parameter(Mandatory)]

        [string]$CheckBox

    )



    $tweakConfig = $sync.configs.tweaks.$CheckBox

    if (-not $tweakConfig) {

        return

    }



    $entry = [ordered]@{

        Timestamp = (Get-Date).ToString("o")

        CheckBox = $CheckBox

        Registry = @()

        Service = @()

        ScheduledTask = @()

    }



    foreach ($registryItem in @($tweakConfig.registry)) {

        if (-not $registryItem) { continue }

        $exists = $false

        $currentValue = $null

        try {

            $item = Get-ItemProperty -Path $registryItem.Path -Name $registryItem.Name -ErrorAction Stop

            $currentValue = $item.($registryItem.Name)

            $exists = $true

        } catch {

            $exists = $false

        }



        $entry.Registry += [ordered]@{

            Path = $registryItem.Path

            Name = $registryItem.Name

            Type = $registryItem.Type

            Exists = $exists

            Value = if ($exists) { [string]$currentValue } else { $null }

        }

    }



    foreach ($serviceItem in @($tweakConfig.service)) {

        if (-not $serviceItem) { continue }

        try {

            $service = Get-Service -Name $serviceItem.Name -ErrorAction Stop

            $entry.Service += [ordered]@{

                Name = $serviceItem.Name

                StartupType = [string]$service.StartType

            }

        } catch {

            $entry.Service += [ordered]@{

                Name = $serviceItem.Name

                StartupType = "<NotFound>"

            }

        }

    }



    foreach ($taskItem in @($tweakConfig.ScheduledTask)) {

        if (-not $taskItem) { continue }

        $taskState = "<NotFound>"

        try {

            $task = Get-ScheduledTask -TaskName $taskItem.Name -ErrorAction Stop

            $taskState = if ($task.State -eq "Disabled") { "Disabled" } else { "Enabled" }

        } catch {

            $taskState = "<NotFound>"

        }



        $entry.ScheduledTask += [ordered]@{

            Name = $taskItem.Name

            OriginalState = $taskState

        }

    }



    $journalPath = Get-ClarkRollbackJournalPath

    ($entry | ConvertTo-Json -Depth 5 -Compress) | Add-Content -Path $journalPath -Encoding ascii

}



function Invoke-ClarkRollbackLatest {

    param(

        [string]$CheckBox

    )



    $journalPath = Get-ClarkRollbackJournalPath

    if (-not (Test-Path $journalPath)) {

        Write-Warning "No rollback journal exists."

        return $false

    }



    $entries = Get-Content -Path $journalPath -ErrorAction SilentlyContinue

    if (-not $entries -or $entries.Count -eq 0) {

        Write-Warning "Rollback journal is empty."

        return $false

    }



    $parsedEntries = $entries | ForEach-Object { $_ | ConvertFrom-Json }

    $target = if ([string]::IsNullOrWhiteSpace($CheckBox)) {

        $parsedEntries | Select-Object -Last 1

    } else {

        $parsedEntries | Where-Object { $_.CheckBox -eq $CheckBox } | Select-Object -Last 1

    }



    if (-not $target) {

        Write-Warning "No rollback snapshot found for '$CheckBox'."

        return $false

    }



    foreach ($registryItem in @($target.Registry)) {

        $value = if ($registryItem.Exists) { $registryItem.Value } else { "<RemoveEntry>" }

        Set-ClarkRegistry -Name $registryItem.Name -Path $registryItem.Path -Type $registryItem.Type -Value $value

    }



    foreach ($serviceItem in @($target.Service)) {

        if ($serviceItem.StartupType -and $serviceItem.StartupType -ne "<NotFound>") {

            Set-ClarkService -Name $serviceItem.Name -StartupType $serviceItem.StartupType

        }

    }



    foreach ($taskItem in @($target.ScheduledTask)) {

        if ($taskItem.OriginalState -and $taskItem.OriginalState -ne "<NotFound>") {

            Set-ClarkScheduledTask -Name $taskItem.Name -State $taskItem.OriginalState

        }

    }



    Write-Host "Rollback restored state for $($target.CheckBox)"

    return $true

}



function Get-ClarkAutoReapplyScriptPath {

    if (-not $sync.asysdir) {

        $sync.asysdir = Join-Path $env:LocalAppData "asys"

    }



    return (Join-Path $sync.asysdir "auto-reapply.ps1")

}



function Register-ClarkAutoReapplyTask {

    param(

        [Parameter(Mandatory)]

        [string]$ProfileName

    )



    $profilePath = Save-ClarkProfile -Name $ProfileName

    $bootstrapScriptPath = Get-ClarkAutoReapplyScriptPath

    $deployUrl = if ($env:ASYS_DEPLOY_URL) { $env:ASYS_DEPLOY_URL } else { "https://clark.advancesystems4042.com/?token=covxo5-nyrmUh-rodgac" }

    $escapedProfilePath = $profilePath.Replace("'", "''")

    $escapedUrl = $deployUrl.Replace("'", "''")



    @(

        "`$ErrorActionPreference = 'Stop'"

        "`$scriptText = Invoke-RestMethod -Uri '$escapedUrl'"

        "`$runner = [scriptblock]::Create(`$scriptText)"

        "& `$runner -Config '$escapedProfilePath' -Run -NoUI"

    ) | Out-File -Path $bootstrapScriptPath -Encoding ascii -Force



    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$bootstrapScriptPath`""

    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries



    Register-ScheduledTask -TaskName "ASYS_AutoReapply_Logon" -Action $action -Trigger $logonTrigger -Settings $settings -RunLevel Highest -Force | Out-Null

    Register-ScheduledTask -TaskName "ASYS_AutoReapply_Startup" -Action $action -Trigger $startupTrigger -Settings $settings -RunLevel Highest -Force | Out-Null

}



function Unregister-ClarkAutoReapplyTask {

    $taskNames = @("ASYS_AutoReapply_Logon", "ASYS_AutoReapply_Startup")

    foreach ($taskName in $taskNames) {

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    }



    $bootstrapScriptPath = Get-ClarkAutoReapplyScriptPath

    if (Test-Path $bootstrapScriptPath) {

        Remove-Item -Path $bootstrapScriptPath -Force

    }

}



function Get-ClarkActivationStatus {

    # Same ApplicationID values as MAS (Check_Activation_Status.cmd). Filtering by Name misses

    # e.g. "Microsoft 365 Apps ..." and enumerating all SoftwareLicensingProduct rows is slow.

    $winAppId = "55c92734-d682-4d71-983e-d6ec3f16059f"

    $officeApp15 = "0ff1ce15-a989-479d-af46-f275c6370663"

    $officeApp14 = "59a52881-a989-479d-af46-f275c6370663"



    $windowsProducts = @(

        Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$winAppId'" -ErrorAction SilentlyContinue

    )



    $officeProducts = [System.Collections.Generic.List[object]]::new()

    foreach ($row in @(

            Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$officeApp15'" -ErrorAction SilentlyContinue

            Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='$officeApp14'" -ErrorAction SilentlyContinue

        )) {

        if ($null -ne $row) {

            $officeProducts.Add($row)

        }

    }



    # Volume Office (older) may only register under OSPP; keep a narrow query.

    try {

        foreach ($r in @(Get-CimInstance -ClassName OfficeSoftwareProtectionProduct -ErrorAction SilentlyContinue)) {

            $aid = [string]$r.ApplicationID

            if ($aid -eq $officeApp15 -or $aid -eq $officeApp14) {

                $officeProducts.Add($r)

            }

        }

    } catch {

    }



    # LicenseStatus 1 = licensed. Do not require PartialProductKey ??? it is often blank in WMI for

    # Office/365 even when Settings shows a valid subscription or key.

    $windowsLicensed = @($windowsProducts | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0

    $officeLicensed = @($officeProducts | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0

    $officeDetected = $officeProducts.Count -gt 0



    $windowsLabel = if ($windowsLicensed) { "Activated" } else { "Not Activated" }

    $officeLabel = if (-not $officeDetected) {

        "Not detected"

    } elseif ($officeLicensed) {

        "Activated"

    } else {

        "Not Activated"

    }



    [PSCustomObject]@{

        CheckedAt = (Get-Date).ToString("s")

        Windows = $windowsLabel

        Office = $officeLabel

        OfficeDetected = $officeDetected

        WindowsProducts = @($windowsProducts | Select-Object -First 3 -ExpandProperty Name)

        OfficeProducts = @($officeProducts | Select-Object -First 3 -ExpandProperty Name)

    }

}

Function Invoke-ClarkCurrentSystem {



    <#



    .SYNOPSIS

        Checks to see what tweaks have already been applied and what programs are installed, and checks the according boxes



    .EXAMPLE

        InvokeClarkCurrentSystem -Checkbox "winget"



    #>



    param(

        $CheckBox

    )

    if ($CheckBox -eq "choco") {

        $apps = (choco list | Select-String -Pattern "^\S+").Matches.Value

        $filter = Get-ClarkVariables -Type Checkbox | Where-Object {$psitem -like "WPFInstall*"}

        $sync.GetEnumerator() | Where-Object {$psitem.Key -in $filter} | ForEach-Object {

            $dependencies = @($sync.configs.applications.$($psitem.Key).choco -split ";")

            if ($dependencies -in $apps) {

                Write-Output $psitem.name

            }

        }

    }



    if ($checkbox -eq "winget") {



        $originalEncoding = [Console]::OutputEncoding

        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

        $Sync.InstalledPrograms = winget list -s winget | Select-Object -skip 3 | ConvertFrom-String -PropertyNames "Name", "Id", "Version", "Available" -Delimiter '\s{2,}'

        [Console]::OutputEncoding = $originalEncoding



        $filter = Get-ClarkVariables -Type Checkbox | Where-Object {$psitem -like "WPFInstall*"}

        $sync.GetEnumerator() | Where-Object {$psitem.Key -in $filter} | ForEach-Object {

            $dependencies = @($sync.configs.applications.$($psitem.Key).winget -split ";")



            if ($dependencies[-1] -in $sync.InstalledPrograms.Id) {

                Write-Output $psitem.name

            }

        }

    }



    if ($CheckBox -eq "tweaks") {



        if (!(Test-Path 'HKU:\')) {$null = (New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS)}

        $ScheduledTasks = Get-ScheduledTask



        $sync.configs.tweaks | Get-Member -MemberType NoteProperty | ForEach-Object {



            $Config = $psitem.Name

            #WPFEssTweaksTele

            $entry = $sync.configs.tweaks.$Config

            $registryKeys = $entry.registry

            $scheduledtaskKeys = $entry.scheduledtask

            $serviceKeys = $entry.service

            $appxKeys = $entry.appx

            $invokeScript = $entry.InvokeScript

            $entryType = $entry.Type



            if ($registryKeys -or $scheduledtaskKeys -or $serviceKeys) {

                $Values = @()



                if ($entryType -eq "Toggle") {

                    if (-not (Get-ClarkToggleStatus $Config)) {

                        $values += $False

                    }

                } else {

                    $registryMatchCount = 0

                    $registryTotal = 0



                    Foreach ($tweaks in $registryKeys) {

                        Foreach ($tweak in $tweaks) {

                            $registryTotal++

                            $regstate = $null



                            if (Test-Path $tweak.Path) {

                                $regstate = Get-ItemProperty -Name $tweak.Name -Path $tweak.Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $($tweak.Name)

                            }



                            if ($null -eq $regstate) {

                                switch ($tweak.DefaultState) {

                                    "true" {

                                        $regstate = $tweak.Value

                                    }

                                    "false" {

                                        $regstate = $tweak.OriginalValue

                                    }

                                    default {

                                        $regstate = $tweak.OriginalValue

                                    }

                                }

                            }



                            if ($regstate -eq $tweak.Value) {

                                $registryMatchCount++

                            }

                        }

                    }



                    if ($registryTotal -gt 0 -and $registryMatchCount -ne $registryTotal) {

                        $values += $False

                    }

                }



                Foreach ($tweaks in $scheduledtaskKeys) {

                    Foreach ($tweak in $tweaks) {

                        $task = $ScheduledTasks | Where-Object {$($psitem.TaskPath + $psitem.TaskName) -like "\$($tweak.name)"}



                        if ($task) {

                            $actualValue = $task.State

                            $expectedValue = $tweak.State

                            if ($expectedValue -ne $actualValue) {

                                $values += $False

                            }

                        }

                    }

                }



                Foreach ($tweaks in $serviceKeys) {

                    Foreach ($tweak in $tweaks) {

                        $Service = Get-Service -Name $tweak.Name



                        if ($Service) {

                            $actualValue = $Service.StartType

                            $expectedValue = $tweak.StartupType

                            if ($expectedValue -ne $actualValue) {

                                $values += $False

                            }

                        }

                    }

                }



                if ($values -notcontains $false) {

                    Write-Output $Config

                }

            } else {

                if ($invokeScript -or $appxKeys) {

                    Write-Debug "Skipping $Config in Get Installed: no detectable registry, scheduled task, or service state."

                }

            }

        }

    }

}

function Invoke-ClarkExplorerUpdate {

     <#

    .SYNOPSIS

        Refreshes the Windows Explorer

    #>

    param (

        [string]$action = "refresh"

    )



    if ($action -eq "refresh") {

        Invoke-WPFRunspace -ScriptBlock {

            # Define the Win32 type only if it doesn't exist

            if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {

                Add-Type -TypeDefinition @"

using System;

using System.Runtime.InteropServices;

public class Win32 {

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]

    public static extern IntPtr SendMessageTimeout(

        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,

        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

}

"@

            }



            $HWND_BROADCAST = [IntPtr]0xffff

            $WM_SETTINGCHANGE = 0x1A

            $SMTO_ABORTIFHUNG = 0x2



            [Win32]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE,

                [IntPtr]::Zero, "ImmersiveColorSet", $SMTO_ABORTIFHUNG, 100,

                [ref]([IntPtr]::Zero))

        }

    } elseif ($action -eq "restart") {

        taskkill.exe /F /IM "explorer.exe"

        Start-Process "explorer.exe"

    }

}

function Invoke-ClarkFeatureInstall {

    <#



    .SYNOPSIS

        Converts all the values from the tweaks.json and routes them to the appropriate function



    #>



    param(

        $CheckBox

    )



    if($sync.configs.feature.$CheckBox.feature) {

        Foreach( $feature in $sync.configs.feature.$CheckBox.feature ) {

            try {

                Write-Host "Installing $feature"

                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart

            } catch {

                if ($CheckBox.Exception.Message -like "*requires elevation*") {

                    Write-Warning "Unable to Install $feature due to permissions. Are you running as admin?"

                    Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Error" }

                } else {



                    Write-Warning "Unable to Install $feature due to unhandled exception."

                    Write-Warning $CheckBox.Exception.StackTrace

                }

            }

        }

    }

    if($sync.configs.feature.$CheckBox.InvokeScript) {

        Foreach( $script in $sync.configs.feature.$CheckBox.InvokeScript ) {

            try {

                $Scriptblock = [scriptblock]::Create($script)



                Write-Host "Running Script for $CheckBox"

                Invoke-Command $scriptblock -ErrorAction stop

            } catch {

                if ($CheckBox.Exception.Message -like "*requires elevation*") {

                    Write-Warning "Unable to Install $feature due to permissions. Are you running as admin?"

                    Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Error" }

                } else {

                    Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Error" }

                    Write-Warning "Unable to Install $feature due to unhandled exception."

                    Write-Warning $CheckBox.Exception.StackTrace

                }

            }

        }

    }

}

function Invoke-ClarkFontScaling {

    <#



    .SYNOPSIS

        Applies UI and font scaling for accessibility



    .PARAMETER ScaleFactor

        Sets the scaling from 0.75 and 2.0.

        Default is 1.0 (100% - no scaling)



    .EXAMPLE

        Invoke-ClarkFontScaling -ScaleFactor 1.25

        # Applies 125% scaling

    #>



    param (

        [double]$ScaleFactor = 1.0

    )



    # Validate if scale factor is within the range

    if ($ScaleFactor -lt 0.75 -or $ScaleFactor -gt 2.0) {

        Write-Warning "Scale factor must be between 0.75 and 2.0. Using 1.0 instead."

        $ScaleFactor = 1.0

    }



    # Define an array for resources to be scaled

    $fontResources = @(

        # Fonts

        "FontSize",

        "ButtonFontSize",

        "HeaderFontSize",

        "TabButtonFontSize",

        "ConfigTabButtonFontSize",

        "IconFontSize",

        "SettingsIconFontSize",

        "AppEntryFontSize",

        "SearchBarTextBoxFontSize",

        "SearchBarClearButtonFontSize",

        "CustomDialogFontSize",

        "CustomDialogFontSizeHeader",

        "ToolTipFontSize",

        "ConfigUpdateButtonFontSize",

        # Buttons and UI

        "CheckBoxBulletDecoratorSize",

        "ButtonWidth",

        "ButtonHeight",

        "TabButtonWidth",

        "TabButtonHeight",

        "IconButtonSize",

        "AppEntryWidth",

        "SearchBarWidth",

        "SearchBarHeight",

        "CustomDialogWidth",

        "CustomDialogHeight",

        "CustomDialogLogoSize",

        "ToolTipWidth"

    )



    # Apply scaling to each resource

    foreach ($resourceName in $fontResources) {

        try {

            # Get the default font size from the theme configuration

            $originalValue = $sync.configs.themes.shared.$resourceName

            if ($originalValue) {

                # Convert string to double since values are stored as strings

                $originalValue = [double]$originalValue

                # Calculates and applies the new font size

                $newValue = [math]::Round($originalValue * $ScaleFactor, 1)

                $sync.Form.Resources[$resourceName] = $newValue

                Write-Debug "Scaled $resourceName from original $originalValue to $newValue (factor: $ScaleFactor)"

            }

        } catch {

            Write-Warning "Failed to scale resource $resourceName : $_"

        }

    }



    # Update the font scaling percentage displayed on the UI

    if ($sync.FontScalingValue) {

        $percentage = [math]::Round($ScaleFactor * 100)

        $sync.FontScalingValue.Text = "$percentage%"

    }



    Write-Debug "Font scaling applied with factor: $ScaleFactor"

}





function Invoke-ClarkInstallPSProfile {



    if (Test-Path $Profile) {

        Rename-Item $Profile -NewName ($Profile + '.bak')

    }



    Start-Process pwsh -ArgumentList '-Command "irm https://github.com/ChrisTitusTech/powershell-profile/raw/main/setup.ps1 | iex"'

}

# ISO Creator supports Windows 10 and Windows 11; paths use WinISO (legacy identifiers still say Win11ISO in code/UI).
function Get-Win11ISOLogFilePath {
    if (-not $sync["Win11ISOGlobalLogPath"]) {
        $logDir = Join-Path $env:TEMP "ASYS_WinISO_Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $sync["Win11ISOGlobalLogPath"] = Join-Path $logDir ("ASYS_WinISO_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    }

    return $sync["Win11ISOGlobalLogPath"]
}

function Write-Win11ISOLogCore {
    <#
        .SYNOPSIS
            Append one ISO status line to file + WPF log. Safe from any thread (uses Form.Dispatcher.Invoke).
            Does not depend on Invoke-WPFUIThread so it can be dot-sourced into ISO worker runspaces.
        .NOTES
            Uses DispatcherOperationCallback + state argument so the line text is not lost when PowerShell
            converts scriptblocks to delegates (broken closure capture with [System.Action]).
    #>
    param([string]$Line)

    try {
        $logPath = Get-Win11ISOLogFilePath
        Add-Content -LiteralPath $logPath -Value $Line -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}

    if ($PARAM_NOUI) {
        Write-Host $Line
        return
    }

    $win = $sync["Form"]
    if (-not $win) {
        Write-Host $Line
        return
    }

    try {
        [void]$win.Dispatcher.Invoke(
            [System.Windows.Threading.DispatcherPriority]::Normal,
            [System.Windows.Threading.DispatcherOperationCallback]{
                param($state)
                $appendLine = [string]$state
                $tb = $sync["WPFWin11ISOStatusLog"]
                if (-not $tb) { return $null }
                $current = [string]$tb.Text
                if ($current -eq "Ready. Please select a Windows 10 or Windows 11 ISO to begin.") {
                    $tb.Text = $appendLine
                } else {
                    $tb.Text += "`n$appendLine"
                }
                $tb.CaretIndex = $tb.Text.Length
                $tb.ScrollToEnd()
                return $null
            },
            $Line
        )
    } catch {
        Write-Host $Line
    }
}

function Add-Win11ISOStatusLogLineUIThread {
    <#
        .SYNOPSIS
            Append a line to the ISO status TextBox on the UI thread only. Call from click handlers (already on UI thread).
    #>
    param([string]$Line)

    $tb = $sync["WPFWin11ISOStatusLog"]
    if (-not $tb) { return }
    $current = [string]$tb.Text
    if ($current -eq "Ready. Please select a Windows 10 or Windows 11 ISO to begin.") {
        $tb.Text = $Line
    } else {
        $tb.Text += "`n$Line"
    }
    $tb.CaretIndex = $tb.Text.Length
    $tb.ScrollToEnd()
}

function Write-Win11ISOLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $line = "[$ts] $Message"
    Write-Win11ISOLogCore -Line $line
}

function Set-ClarkISODownloadProgress {
    param(
        [int]$Percent,
        [string]$Text,
        [switch]$Hide
    )

    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $sync["WinISODownloadLastPercent"] = $safePercent

    Invoke-WPFUIThread -ScriptBlock {
        if (-not $sync["WPFWinISODownloadProgressBar"] -or -not $sync["WPFWinISODownloadProgressText"]) {
            return
        }

        if ($Hide) {
            $sync["WPFWinISODownloadProgressBar"].Visibility = "Collapsed"
            $sync["WPFWinISODownloadProgressText"].Visibility = "Collapsed"
            $sync["WPFWinISODownloadProgressBar"].Value = 0
            $sync["WPFWinISODownloadProgressText"].Text = ""
            return
        }

        $sync["WPFWinISODownloadProgressBar"].Visibility = "Visible"
        $sync["WPFWinISODownloadProgressText"].Visibility = "Visible"
        $sync["WPFWinISODownloadProgressBar"].Value = $safePercent
        $sync["WPFWinISODownloadProgressText"].Text = $Text
    }
}

function Set-ClarkISODownloadControlState {
    param(
        [bool]$IsRunning,
        [bool]$IsPaused = $false
    )

    Invoke-WPFUIThread -ScriptBlock {
        if ($sync["WPFWinISODownloadDirectButton"]) {
            $sync["WPFWinISODownloadDirectButton"].IsEnabled = -not $IsRunning
        }
        if ($sync["WPFWinISODownloadPauseButton"]) {
            $sync["WPFWinISODownloadPauseButton"].IsEnabled = $IsRunning
            $sync["WPFWinISODownloadPauseButton"].Content = if ($IsPaused) { "Resume" } else { "Pause" }
        }
        if ($sync["WPFWinISODownloadStopButton"]) {
            $sync["WPFWinISODownloadStopButton"].IsEnabled = $IsRunning
        }
    }
}

function Test-ClarkISODownloadStopRequested {
    if ($sync["WinISODownloadStopRequested"]) {
        throw "ISO download stopped by user."
    }
}

function Resume-ClarkISOBitsJob {
    <#
        .SYNOPSIS
            Resumes a suspended BITS job without blocking indefinitely (sync Resume-BitsTransfer can hang after Suspend).
        Uses -Asynchronous then polls until the job leaves Suspended or times out.
    #>
    param(
        [Parameter(Mandatory)][string]$BitsJobId,
        [int]$WaitSeconds = 45
    )

    $job = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
    if (-not $job -or $job.JobState -ne "Suspended") {
        return $job
    }

    try {
        Resume-BitsTransfer -BitsJob $job -Asynchronous -ErrorAction Stop
    } catch {
        Write-Win11ISOLog "BITS Resume-BitsTransfer failed: $($_.Exception.Message)"
        try {
            $job2 = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
            if ($job2 -and $job2.JobState -eq "Suspended") {
                Resume-BitsTransfer -BitsJob $job2 -Asynchronous -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Milliseconds 250
        Test-ClarkISODownloadStopRequested
        $job = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
        if (-not $job) {
            return $null
        }
    } while ($job.JobState -eq "Suspended" -and (Get-Date) -lt $deadline)

    return $job
}

function Invoke-ClarkISODirectDownloadPauseToggle {
    if (-not $sync["WinISODownloadRunning"]) {
        return
    }

    $isPaused = [bool]$sync["WinISODownloadPauseRequested"]
    $newPausedState = -not $isPaused
    $sync["WinISODownloadPauseRequested"] = $newPausedState
    $sync["WinISODownloadIsPaused"] = $newPausedState

    if ($newPausedState) {
        Write-Win11ISOLog "ISO download paused."
        Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
    } else {
        Write-Win11ISOLog "ISO download resumed."
    }
    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $newPausedState
}

function Invoke-ClarkISODirectDownloadStop {
    if (-not $sync["WinISODownloadRunning"]) {
        return
    }

    $sync["WinISODownloadStopRequested"] = $true
    $sync["WinISODownloadPauseRequested"] = $false
    $sync["WinISODownloadIsPaused"] = $false
    Write-Win11ISOLog "Stop requested for ISO download..."

    $bitsJobId = [string]$sync["WinISODownloadBitsJobId"]
    if (-not [string]::IsNullOrWhiteSpace($bitsJobId)) {
        try {
            $bitsJob = Get-BitsTransfer -Id $bitsJobId -ErrorAction SilentlyContinue
            if ($bitsJob) {
                Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Show-ClarkISOMessageBox {
    <#
        .SYNOPSIS
            Shows a WPF MessageBox on the UI thread. Required when calling from ISO worker runspaces;
            MessageBox from a pool thread can deadlock or freeze the app after the dialog closes.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.MessageBoxButton]$Button = 'OK',
        [System.Windows.MessageBoxImage]$Image = 'Information'
    )

    if ($PARAM_NOUI) {
        return [System.Windows.MessageBoxResult]::None
    }

    $win = $sync["Form"]
    if (-not $win) {
        return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Image)
    }

    $state = [pscustomobject]@{
        Body   = $Message
        Title  = $Title
        Button = $Button
        Image  = $Image
        Result = [System.Windows.MessageBoxResult]::None
    }
    [void]$win.Dispatcher.Invoke(
        [System.Windows.Threading.DispatcherPriority]::Normal,
        [System.Windows.Threading.DispatcherOperationCallback]{
            param($s)
            $o = $s
            $o.Result = [System.Windows.MessageBox]::Show($o.Body, $o.Title, $o.Button, $o.Image)
            return $null
        },
        $state
    )
    return $state.Result
}

function Get-ClarkDefaultFileDialogDirectory {
    # Prefer Downloads for ISO workflows; fallback to Desktop, then USERPROFILE.
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    if (-not [string]::IsNullOrWhiteSpace($downloads) -and (Test-Path -LiteralPath $downloads)) {
        return $downloads
    }

    $desktop = [System.Environment]::GetFolderPath("Desktop")
    if (-not [string]::IsNullOrWhiteSpace($desktop) -and (Test-Path -LiteralPath $desktop)) {
        return $desktop
    }

    return $env:USERPROFILE
}

function Get-ClarkISODirectDownloadCatalog {
    # Passed to Fido.ps1 as -Rel. Fido matches with release.StartsWith(Rel) or Rel eq 'Latest'.
    # Microsoft/Fido refresh often drops older builds; stale labels (e.g. 24H2) make Fido exit before any URL is returned.
    return @{
        "Windows 11" = @("Latest", "25H2")
        "Windows 10" = @("Latest", "22H2")
    }
}

function Set-ClarkISODirectDownloadVersions {
    if (-not $sync["WPFWinISODownloadProductComboBox"] -or -not $sync["WPFWinISODownloadVersionComboBox"]) {
        return
    }

    $catalog = Get-ClarkISODirectDownloadCatalog
    $selectedProduct = [string]$sync["WPFWinISODownloadProductComboBox"].SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedProduct)) {
        $selectedProduct = "Windows 11"
    }

    $versions = @($catalog[$selectedProduct])
    if (-not $versions -or $versions.Count -eq 0) {
        $versions = @("Latest")
    }

    $sync["WPFWinISODownloadVersionComboBox"].Items.Clear()
    foreach ($version in $versions) {
        [void]$sync["WPFWinISODownloadVersionComboBox"].Items.Add($version)
    }
    $sync["WPFWinISODownloadVersionComboBox"].SelectedIndex = 0
}

function Get-ClarkISODirectDownloadLanguageCatalog {
    # Label shown to user + Fido language token.
    # Keep only US English to avoid locale confusion in downloads.
    return @(
        @{ Label = "English (US)"; FidoLanguage = "English" }
    )
}

function Set-ClarkISODirectDownloadLanguages {
    if (-not $sync["WPFWinISODownloadLanguageComboBox"]) {
        return
    }

    $languageCombo = $sync["WPFWinISODownloadLanguageComboBox"]
    $languageCombo.Items.Clear()

    $catalog = Get-ClarkISODirectDownloadLanguageCatalog
    foreach ($entry in $catalog) {
        [void]$languageCombo.Items.Add([string]$entry.Label)
    }

    # Default to US to avoid accidental UK/international downloads.
    $defaultLabel = "English (US)"
    $defaultIndex = [Array]::IndexOf(@($catalog | ForEach-Object { [string]$_.Label }), $defaultLabel)
    if ($defaultIndex -lt 0) { $defaultIndex = 0 }
    $languageCombo.SelectedIndex = $defaultIndex
}

function Get-ClarkSelectedISODirectDownloadLanguage {
    $selectedLabel = [string]$sync["WPFWinISODownloadLanguageComboBox"].SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedLabel)) {
        return "English"
    }

    $catalog = Get-ClarkISODirectDownloadLanguageCatalog
    $match = $catalog | Where-Object { [string]$_.Label -eq $selectedLabel } | Select-Object -First 1
    if ($match -and -not [string]::IsNullOrWhiteSpace([string]$match.FidoLanguage)) {
        return [string]$match.FidoLanguage
    }

    return "English"
}

function Get-ClarkFidoScriptPath {
    # Prefer repo-shipped Fido (works offline / when GitHub is blocked); else cache under LocalAppData\asys\tools.
    if ($sync.PSScriptRoot) {
        $bundledFido = Join-Path $sync.PSScriptRoot "tools\Fido.ps1"
        if (Test-Path -LiteralPath $bundledFido) {
            return $bundledFido
        }
    }

    $toolsDir = Join-Path $sync.asysdir "tools"
    if (-not (Test-Path $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    }

    $fidoPath = Join-Path $toolsDir "Fido.ps1"
    if (-not (Test-Path $fidoPath)) {
        Write-Win11ISOLog "Downloading Fido helper script from GitHub..."
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1" -OutFile $fidoPath -UseBasicParsing
        Write-Win11ISOLog "Fido helper script downloaded."
    }

    return $fidoPath
}

function Get-ClarkInternetArchiveIsoUrlFromConfig {
    param(
        [Parameter(Mandatory)][string]$WindowsProduct,
        [Parameter(Mandatory)][string]$WindowsRelease
    )

    try {
        $root = $sync.configs.isomirrors
        if (-not $root) { return $null }
        $urls = $root.internetArchiveIsoUrls
        if (-not $urls) { return $null }

        $prodNode = $null
        foreach ($p in $urls.PSObject.Properties) {
            if ($p.Name -eq $WindowsProduct) {
                $prodNode = $p.Value
                break
            }
        }
        if (-not $prodNode) { return $null }

        foreach ($r in $prodNode.PSObject.Properties) {
            if ($r.Name -eq $WindowsRelease) {
                $cand = [string]$r.Value
                if ([string]::IsNullOrWhiteSpace($cand)) { return $null }
                $cand = $cand.Trim()
                if ($cand -match '^https?://') { return $cand }
                return $null
            }
        }
    } catch {}

    return $null
}

function Initialize-ClarkISODownloadTls {
    try {
        $p = [Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [Net.SecurityProtocolType]::Tls13 } catch {}
        [Net.ServicePointManager]::SecurityProtocol = $p
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }
}

function New-ClarkISODownloadHttpClient {
    <#
        .SYNOPSIS
            HttpClient configured for large ISO downloads (not default 100s timeout), TLS 1.2+, redirects, and a normal browser User-Agent.
    #>
    Initialize-ClarkISODownloadTls
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 16
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $handler.UseDefaultCredentials = $true

    $client = [System.Net.Http.HttpClient]::new($handler)
    try {
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    } catch {
        $client.Timeout = [TimeSpan]::FromDays(7)
    }
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    )
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept', '*/*')
    return $client
}

function Invoke-ClarkISOBitsOrHttpDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$WindowsProduct = "",
        [string]$WindowsRelease = ""
    )

    $bitsDescription = if ($WindowsProduct) { "$WindowsProduct $WindowsRelease" } else { "ISO download" }

    try {
        Import-Module BitsTransfer -ErrorAction Stop
        $bitsJob = Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName "clark ISO Download" -Description $bitsDescription -Asynchronous
        if (-not $bitsJob -or [string]::IsNullOrWhiteSpace([string]$bitsJob.JobId)) {
            throw "BITS did not return a transfer job (JobId empty)."
        }
        $bitsJobId = $bitsJob.JobId
        $sync["WinISODownloadBitsJobId"] = [string]$bitsJobId
        $downloadStart = Get-Date

        do {
            Start-Sleep -Seconds 1
            Test-ClarkISODownloadStopRequested

            $bitsJob = Get-BitsTransfer -Id $bitsJobId -ErrorAction SilentlyContinue
            if (-not $bitsJob) {
                Test-ClarkISODownloadStopRequested
                throw "BITS job was not found (it may have been cancelled or cleared). JobId: $bitsJobId"
            }

            if ($sync["WinISODownloadPauseRequested"] -eq $true) {
                if ($bitsJob.JobState -ne "Suspended") {
                    Suspend-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                }
                $sync["WinISODownloadIsPaused"] = $true
                Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $true
                Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    Start-Sleep -Milliseconds 500
                    Test-ClarkISODownloadStopRequested
                }

                $bitsJob = Resume-ClarkISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-ClarkISODownloadStopRequested
                    throw "BITS job was not found after resume (it may have been cancelled). JobId: $bitsJobId"
                }
                $sync["WinISODownloadIsPaused"] = $false
                Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
            }

            if ($bitsJob -and $bitsJob.JobState -eq "Suspended" -and $sync["WinISODownloadPauseRequested"] -ne $true) {
                $bitsJob = Resume-ClarkISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-ClarkISODownloadStopRequested
                    throw "BITS job was not found while resuming. JobId: $bitsJobId"
                }
                if ($bitsJob.JobState -eq "Suspended") {
                    throw "Download resume did not complete (BITS remained suspended)."
                }
            }

            $bytesTotal = [double]$bitsJob.BytesTotal
            $bytesTransferred = [double]$bitsJob.BytesTransferred
            $percent = if ($bytesTotal -gt 0) { [int][Math]::Round(($bytesTransferred / $bytesTotal) * 100, 0) } else { 0 }

            $elapsedSeconds = [Math]::Max(1.0, ((Get-Date) - $downloadStart).TotalSeconds)
            $speedBps = if ($bytesTransferred -gt 0) { $bytesTransferred / $elapsedSeconds } else { 0.0 }
            $remainingBytes = [Math]::Max(0.0, $bytesTotal - $bytesTransferred)
            $etaText = if ($speedBps -gt 0 -and $bytesTotal -gt 0) {
                $etaSeconds = [int][Math]::Ceiling($remainingBytes / $speedBps)
                [TimeSpan]::FromSeconds($etaSeconds).ToString("hh\:mm\:ss")
            } else {
                "estimating..."
            }

            $downloadedMb = [Math]::Round($bytesTransferred / 1MB, 1)
            $totalMb = if ($bytesTotal -gt 0) { [Math]::Round($bytesTotal / 1MB, 1) } else { 0 }
            $label = if ($bytesTotal -gt 0) {
                "Downloading ISO... $percent% ($downloadedMb MB / $totalMb MB, ETA $etaText)"
            } else {
                "Downloading ISO... $percent% (ETA $etaText)"
            }

            Set-ClarkProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
            Set-ClarkISODownloadProgress -Percent $percent -Text $label
        } while ($bitsJob.JobState -in @("Queued", "Connecting", "Transferring", "Suspended"))

        Test-ClarkISODownloadStopRequested
        if ($bitsJob.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $bitsJob -ErrorAction Stop
        } elseif ($bitsJob.JobState -eq "Error") {
            $errorText = if ($bitsJob.ErrorDescription) { $bitsJob.ErrorDescription } else { "BITS download failed." }
            throw $errorText
        } else {
            throw "BITS download did not complete successfully. Final state: $($bitsJob.JobState)"
        }
    } catch {
        if ($sync["WinISODownloadStopRequested"] -or $_.Exception.Message -match "stopped by user") {
            try { Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "clark ISO Download" } | Remove-BitsTransfer -ErrorAction SilentlyContinue } catch {}
            if (Test-Path -LiteralPath $Destination) {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            }
            throw "ISO download stopped by user."
        }

        Write-Win11ISOLog "BITS path failed ($($_.Exception.Message)); using HTTP fallback."
        try { Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "clark ISO Download" } | Remove-BitsTransfer -ErrorAction SilentlyContinue } catch {}
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }

        Set-ClarkProgressBar -Label "Downloading ISO via HTTP..." -Percent 15
        Set-ClarkISODownloadProgress -Percent 5 -Text "Downloading ISO via HTTP..."

        $client = $null
        $response = $null
        $sourceStream = $null
        $targetStream = $null

        try {
            $client = New-ClarkISODownloadHttpClient
            $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode()
            $totalBytes = [double]($response.Content.Headers.ContentLength | ForEach-Object { $_ })
            if (-not $totalBytes) { $totalBytes = 0.0 }

            $sourceStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $targetStream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = New-Object byte[] (1024 * 1024)
            $downloadedBytes = 0.0
            $lastUpdate = Get-Date
            $httpStart = Get-Date

            while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                Test-ClarkISODownloadStopRequested

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    $sync["WinISODownloadIsPaused"] = $true
                    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $true
                    Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
                    Start-Sleep -Milliseconds 500
                    Test-ClarkISODownloadStopRequested
                }

                if ($sync["WinISODownloadIsPaused"]) {
                    $sync["WinISODownloadIsPaused"] = $false
                    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
                }

                $targetStream.Write($buffer, 0, $read)
                $downloadedBytes += $read

                if (((Get-Date) - $lastUpdate).TotalMilliseconds -ge 1000) {
                    $percent = if ($totalBytes -gt 0) { [int][Math]::Round(($downloadedBytes / $totalBytes) * 100, 0) } else { 0 }
                    $elapsedSeconds = [Math]::Max(1.0, ((Get-Date) - $httpStart).TotalSeconds)
                    $speedBps = if ($downloadedBytes -gt 0) { $downloadedBytes / $elapsedSeconds } else { 0.0 }
                    $remainingBytes = [Math]::Max(0.0, $totalBytes - $downloadedBytes)
                    $etaText = if ($speedBps -gt 0 -and $totalBytes -gt 0) {
                        $etaSeconds = [int][Math]::Ceiling($remainingBytes / $speedBps)
                        [TimeSpan]::FromSeconds($etaSeconds).ToString("hh\:mm\:ss")
                    } else {
                        "estimating..."
                    }
                    $downloadedMb = [Math]::Round($downloadedBytes / 1MB, 1)
                    $totalMb = if ($totalBytes -gt 0) { [Math]::Round($totalBytes / 1MB, 1) } else { 0 }
                    $label = if ($totalBytes -gt 0) {
                        "Downloading ISO... $percent% ($downloadedMb MB / $totalMb MB, ETA $etaText)"
                    } else {
                        "Downloading ISO... $downloadedMb MB downloaded"
                    }
                    Set-ClarkProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
                    Set-ClarkISODownloadProgress -Percent $percent -Text $label
                    $lastUpdate = Get-Date
                }
            }
        } catch {
            if ($sync["WinISODownloadStopRequested"] -or $_.Exception.Message -match "stopped by user") {
                if (Test-Path -LiteralPath $Destination) {
                    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                }
                throw "ISO download stopped by user."
            }
            throw
        } finally {
            if ($targetStream) { $targetStream.Dispose() }
            if ($sourceStream) { $sourceStream.Dispose() }
            if ($response) { $response.Dispose() }
            if ($client) { $client.Dispose() }
        }
    } finally {
        $sync["WinISODownloadBitsJobId"] = $null
    }
}

function Test-ClarkFidoMicrosoftAccessDenied {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '715-123130' -or
        $Text -match 'banned from using this service' -or
        $Text -match 'location hiding technologies' -or
        $Text -match 'unable to complete your request at this time'
}

function Get-ClarkMicrosoftSoftwareDownloadUrl {
    param([string]$WindowsProduct)
    if ($WindowsProduct -match '11') {
        return 'https://www.microsoft.com/software-download/windows11'
    }
    return 'https://www.microsoft.com/software-download/windows10'
}

function Get-ClarkDirectISODownloadUrl {
    param(
        [Parameter(Mandatory)]
        [string]$WindowsProduct,
        [Parameter(Mandatory)]
        [string]$WindowsRelease,
        [string]$WindowsLanguage = "English"
    )

    $fidoPath = Get-ClarkFidoScriptPath
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$fidoPath`"",
        "-Win", "`"$WindowsProduct`"",
        "-Rel", "`"$WindowsRelease`"",
        "-Lang", "`"$WindowsLanguage`"",
        "-GetUrl"
    )

    $output = & powershell.exe @arguments 2>&1
    $outputText = ($output | ForEach-Object { "$_" }) -join ' '

    if ($LASTEXITCODE -ne 0) {
        if (Test-ClarkFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request (message often includes 715-123130). " +
                "This usually happens with VPN/proxy/Tor, some datacenter or restricted networks, or regional limits - not a bug in clark.`n`n" +
                "What to try: disconnect VPN/proxy, use another network (e.g. home ISP or phone hotspot), wait and retry, or download the ISO in a browser from:`n$official"
            )
        }
        throw "Unable to get Microsoft ISO link for $WindowsProduct $WindowsRelease ($WindowsLanguage). Fido output: $outputText"
    }

    $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://.+\.iso(\?.*)?$' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)
    }

    if ([string]::IsNullOrWhiteSpace($url) -or $url -notmatch '^https?://') {
        if (Test-ClarkFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request. " +
                "Try without VPN/proxy or use another network, or download from:`n$official"
            )
        }
        throw "No valid ISO URL was returned for $WindowsProduct $WindowsRelease ($WindowsLanguage)."
    }

    return [string]$url.Trim()
}

function Invoke-ClarkISODirectDownload {
    Add-Type -AssemblyName System.Windows.Forms

    $windowsProduct = [string]$sync["WPFWinISODownloadProductComboBox"].SelectedItem
    $windowsRelease = [string]$sync["WPFWinISODownloadVersionComboBox"].SelectedItem
    $windowsLanguage = Get-ClarkSelectedISODirectDownloadLanguage

    if ([string]::IsNullOrWhiteSpace($windowsProduct)) {
        $windowsProduct = "Windows 11"
    }
    if ([string]::IsNullOrWhiteSpace($windowsRelease)) {
        $windowsRelease = "Latest"
    }

    $fileName = if ($windowsProduct -match "11") {
        "Win11_$windowsRelease.iso"
    } else {
        "Win10_$windowsRelease.iso"
    }

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title = "Save downloaded ISO"
    $dlg.Filter = "ISO files (*.iso)|*.iso"
    $dlg.FileName = $fileName
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $destination = $dlg.FileName
    $sync["WinISODownloadRunning"] = $true
    $sync["WinISODownloadStopRequested"] = $false
    $sync["WinISODownloadPauseRequested"] = $false
    $sync["WinISODownloadIsPaused"] = $false
    $sync["WinISODownloadBitsJobId"] = $null
    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
    Add-Win11ISOStatusLogLineUIThread "Starting direct download: $windowsProduct $windowsRelease ($windowsLanguage) -> $destination"

    Invoke-WPFRunspace -ParameterList @(("windowsProduct", $windowsProduct), ("windowsRelease", $windowsRelease), ("windowsLanguage", $windowsLanguage), ("destination", $destination)) -ScriptBlock {
        param($windowsProduct, $windowsRelease, $windowsLanguage, $destination)
        try {
            $sync.ProcessRunning = $true
            Set-ClarkISODownloadProgress -Percent 0 -Text "Preparing download..."

            $archiveUrl = Get-ClarkInternetArchiveIsoUrlFromConfig -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            $url = $null
            $triedArchive = $false

            if (-not [string]::IsNullOrWhiteSpace($archiveUrl)) {
                $url = $archiveUrl
                $triedArchive = $true
                Write-Win11ISOLog "Using mirror URL from config\\isomirrors.json for $windowsProduct $windowsRelease."
                Set-ClarkProgressBar -Label "Downloading ISO (configured mirror)..." -Percent 15
            } else {
                Write-Win11ISOLog "No mirror URL in config for $windowsProduct $windowsRelease; resolving via Fido (Microsoft)..."
                Set-ClarkProgressBar -Label "Resolving ISO URL (Fido)..." -Percent 10
                $url = Get-ClarkDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease -WindowsLanguage $windowsLanguage
                Set-ClarkProgressBar -Label "Starting ISO download..." -Percent 20
            }

            Write-Win11ISOLog "Download target: $destination"
            try {
                Invoke-ClarkISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            } catch {
                if ($triedArchive) {
                    Write-Win11ISOLog "Mirror download failed ($($_.Exception.Message)); falling back to Fido (Microsoft)."
                    if (Test-Path -LiteralPath $destination) {
                        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                    }
                    Set-ClarkProgressBar -Label "Resolving ISO URL (Fido fallback)..." -Percent 12
                    $url = Get-ClarkDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease -WindowsLanguage $windowsLanguage
                    Write-Win11ISOLog "Fido URL resolved; starting download."
                    Set-ClarkProgressBar -Label "Starting ISO download (Fido)..." -Percent 20
                    Invoke-ClarkISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
                } else {
                    throw
                }
            }

            Set-ClarkProgressBar -Label "Download complete" -Percent 100
            Set-ClarkISODownloadProgress -Percent 100 -Text "Download complete: $destination"
            Write-Win11ISOLog "ISO download completed: $destination"
            $null = Show-ClarkISOMessageBox -Message "ISO download complete:`n`n$destination" -Title "Download Complete" -Button OK -Image Information
        } catch {
            $errMsg = [string]$_.Exception.Message
            if ($errMsg -match "stopped by user") {
                Write-Win11ISOLog "ISO download stopped by user."
                Set-ClarkISODownloadProgress -Percent 0 -Text "Download stopped."
                $null = Show-ClarkISOMessageBox -Message "ISO download was stopped." -Title "Download Stopped" -Button OK -Image Information
                return
            }

            Write-Win11ISOLog "ERROR during direct ISO download: $_"
            Set-ClarkISODownloadProgress -Percent 0 -Text "Download failed. Check the log for details."
            $officialPage = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $windowsProduct
            if (Test-ClarkFidoMicrosoftAccessDenied -Text $errMsg) {
                $prompt = "$errMsg`n`nOpen Microsoft's official download page in your browser?"
                $answer = Show-ClarkISOMessageBox -Message $prompt -Title "Microsoft blocked automated download" -Button YesNo -Image Warning
                if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                    Start-Process $officialPage
                }
            } else {
                $null = Show-ClarkISOMessageBox -Message "Direct ISO download failed:`n`n$errMsg" -Title "Download Error" -Button OK -Image Error
            }
        } finally {
            $sync.ProcessRunning = $false
            $sync["WinISODownloadRunning"] = $false
            $sync["WinISODownloadStopRequested"] = $false
            $sync["WinISODownloadPauseRequested"] = $false
            $sync["WinISODownloadIsPaused"] = $false
            $sync["WinISODownloadBitsJobId"] = $null
            Set-ClarkProgressBar -Label "" -Percent 0
            Set-ClarkISODownloadControlState -IsRunning $false -IsPaused $false
        }
    } | Out-Null
}

function Invoke-ClarkISOBrowse {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Title            = "Select Windows 10 or Windows 11 ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso|All files (*.*)|*.*"
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $isoPath    = $dlg.FileName
    $fileSizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 2)

    $sync["WPFWin11ISOPath"].Text           = $isoPath
    $sync["WPFWin11ISOFileInfo"].Text       = "File size: $fileSizeGB GB"
    $sync["WPFWin11ISOFileInfo"].Visibility = "Visible"
    $sync["WPFWin11ISOMountSection"].Visibility       = "Visible"
    $sync["WPFWin11ISOVerifyResultPanel"].Visibility  = "Collapsed"
    $sync["WPFWin11ISOModifySection"].Visibility      = "Collapsed"
    $sync["WPFWin11ISOOutputSection"].Visibility      = "Collapsed"

    $logPath = Get-Win11ISOLogFilePath
    Write-Win11ISOLog "ISO selected: $isoPath  ($fileSizeGB GB)"
    Write-Win11ISOLog "Logging to: $logPath"
}

function Invoke-ClarkISOMountAndVerify {
    $isoPath = $sync["WPFWin11ISOPath"].Text

    if ([string]::IsNullOrWhiteSpace($isoPath) -or $isoPath -eq "No ISO selected...") {
        [System.Windows.MessageBox]::Show("Please select an ISO file first.", "No ISO Selected", "OK", "Warning")
        return
    }

    # Recover stuck UI if a previous run left flags set but the pipeline is gone or finished
    if ($sync["Win11ISOMountVerifyRunning"]) {
        $ar = $sync["_isoMountAsyncResult"]
        $psRef = $sync["_isoMountPowerShell"]
        if (-not $ar -and -not $psRef) {
            $sync["Win11ISOMountVerifyRunning"] = $false
            if ($sync["WPFWin11ISOMountButton"]) { $sync["WPFWin11ISOMountButton"].IsEnabled = $true }
        } elseif ($ar -and $ar.IsCompleted) {
            try {
                if ($psRef) { [void]$psRef.EndInvoke($ar); $psRef.Dispose() }
            } catch {}
            $sync["_isoMountPowerShell"] = $null
            $sync["_isoMountAsyncResult"] = $null
            $sync["Win11ISOMountVerifyRunning"] = $false
            if ($sync["WPFWin11ISOMountButton"]) { $sync["WPFWin11ISOMountButton"].IsEnabled = $true }
        } else {
            $tsBusy = (Get-Date).ToString("HH:mm:ss")
            Add-Win11ISOStatusLogLineUIThread -Line "[$tsBusy] Mount/verify is already running; please wait."
            return
        }
    }

    $tsClick = (Get-Date).ToString("HH:mm:ss")
    Add-Win11ISOStatusLogLineUIThread -Line "[$tsClick] Mount & verify - starting (watch this log for progress)..."

    $mountBtn = $sync["WPFWin11ISOMountButton"]
    if ($mountBtn) { $mountBtn.IsEnabled = $false }
    $sync["Win11ISOMountVerifyRunning"] = $true

    try {
        Write-Win11ISOLog "Starting mount and verify in the background (UI stays responsive)..."
        Set-ClarkProgressBar -Label "Mounting ISO..." -Percent 10
    } catch {
        $sync["Win11ISOMountVerifyRunning"] = $false
        if ($mountBtn) { $mountBtn.IsEnabled = $true }
        [System.Windows.MessageBox]::Show(
            "Could not update the ISO status log (UI).`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Warning")
        return
    }

    $getLogDef  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDef = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",       $sync)
    $runspace.SessionStateProxy.SetVariable("isoPath",    $isoPath)
    $runspace.SessionStateProxy.SetVariable("getLogDef",  $getLogDef)
    $runspace.SessionStateProxy.SetVariable("logCoreDef", $logCoreDef)

    $ps = [Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function MountVerify-SetProgress {
            param([string]$Label, [int]$Percent)
            $win = $sync["Form"]
            if (-not $win) { return }
            # Stash on $sync so [System.Action] does not rely on broken PS delegate closure capture
            $sync["_isoUiProgLabel"] = $Label
            $sync["_isoUiProgPct"]   = $Percent
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pct = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pct -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pct, 5)
                    }
                }
            })
        }

        try {
            Write-Win11ISOLog "Mounting ISO: $isoPath"
            MountVerify-SetProgress "Mounting ISO..." 10

            Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop | Out-Null

            $deadline = (Get-Date).AddMinutes(5)
            do {
                Start-Sleep -Milliseconds 500
                $vol = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop | Get-Volume -ErrorAction SilentlyContinue
                if ($vol -and $vol.DriveLetter) { break }
                if ((Get-Date) -gt $deadline) {
                    throw "Timed out waiting for mounted ISO to receive a drive letter."
                }
            } while ($true)

            $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter + ":"
            Write-Win11ISOLog "Mounted at drive $driveLetter"

            MountVerify-SetProgress "Verifying ISO contents..." 30

            $wimPath = Join-Path $driveLetter "sources\install.wim"
            $esdPath = Join-Path $driveLetter "sources\install.esd"

            if (-not (Test-Path $wimPath) -and -not (Test-Path $esdPath)) {
                Dismount-DiskImage -ImagePath $isoPath | Out-Null
                Write-Win11ISOLog "ERROR: install.wim/install.esd not found - not a valid Windows ISO."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "This does not appear to be a valid Windows ISO.`n`ninstall.wim / install.esd was not found.",
                        "Invalid ISO", "OK", "Error")
                })
                return
            }

            $activeWim = if (Test-Path $wimPath) { $wimPath } else { $esdPath }

            MountVerify-SetProgress "Reading image metadata..." 55
            $imageInfo = Get-WindowsImage -ImagePath $activeWim | Select-Object ImageIndex, ImageName

            $clientImages = $imageInfo | Where-Object {
                ($_.ImageName -match '\bWindows 10\b' -or $_.ImageName -match '\bWindows 11\b') -and
                $_.ImageName -notmatch 'Windows Server'
            }
            if (-not $clientImages) {
                Dismount-DiskImage -ImagePath $isoPath | Out-Null
                Write-Win11ISOLog "ERROR: No Windows 10 or Windows 11 client edition found in the image."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "No Windows 10 or Windows 11 client edition was found in this ISO.`n`nUse an official Windows 10 or Windows 11 ISO from Microsoft (not Windows Server).",
                        "Unsupported ISO", "OK", "Error")
                })
                return
            }

            $uiDriveLetter = $driveLetter
            $uiActiveWim   = $activeWim
            $uiImageInfo   = $imageInfo
            $uiIsoPath     = $isoPath

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["Win11ISOImageInfo"] = $uiImageInfo
                $sync["WPFWin11ISOMountDriveLetter"].Text = "Mounted at: $uiDriveLetter   |   Image file: $(Split-Path $uiActiveWim -Leaf)"
                $cb = $sync["WPFWin11ISOEditionComboBox"]
                $cb.Items.Clear()
                foreach ($img in $uiImageInfo) {
                    [void]$cb.Items.Add("$($img.ImageIndex): $($img.ImageName)")
                }
                if ($cb.Items.Count -gt 0) {
                    $proIndex = -1
                    for ($i = 0; $i -lt $cb.Items.Count; $i++) {
                        if ($cb.Items[$i] -match "Windows 1[01] Pro(?![\w ])") {
                            $proIndex = $i; break
                        }
                    }
                    $cb.SelectedIndex = if ($proIndex -ge 0) { $proIndex } else { 0 }
                }
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Visible"
                $sync["Win11ISODriveLetter"] = $uiDriveLetter
                $sync["Win11ISOWimPath"]     = $uiActiveWim
                $sync["Win11ISOImagePath"]   = $uiIsoPath
                $sync["WPFWin11ISOModifySection"].Visibility = "Visible"
            })

            MountVerify-SetProgress "ISO verified" 100
            Write-Win11ISOLog "ISO verified OK. Editions found: $($imageInfo.Count)"
        } catch {
            Write-Win11ISOLog "ERROR during mount/verify: $($_.Exception.Message)"
            Write-Win11ISOLog "ERROR details: $($_ | Out-String)"
            try {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
            } catch {}
            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show(
                    "An error occurred while mounting or verifying the ISO:`n`n$m",
                    "Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            MountVerify-SetProgress "" 0
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOMountButton"].IsEnabled = $true
                $sync["Win11ISOMountVerifyRunning"] = $false
            })
        }
    })

    try {
        # Keep strong references so the pipeline is not GC'd mid-flight.
        $sync["_isoMountPowerShell"] = $ps
        $sync["_isoMountAsyncResult"] = $ps.BeginInvoke()
    } catch {
        $sync["_isoMountPowerShell"] = $null
        $sync["_isoMountAsyncResult"] = $null
        try { $ps.Dispose() } catch {}
        $sync["Win11ISOMountVerifyRunning"] = $false
        $mountBtn.IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start mount/verify job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start mount/verify in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
}

function Invoke-ClarkISOModify {
    $isoPath     = $sync["Win11ISOImagePath"]
    $driveLetter = $sync["Win11ISODriveLetter"]
    $wimPath     = $sync["Win11ISOWimPath"]

    if (-not $isoPath) {
        [System.Windows.MessageBox]::Show(
            "No verified ISO found. Please complete Steps 1 and 2 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    # Keep internal edition index for any legacy code that reads it
    $selectedItem     = $sync["WPFWin11ISOEditionComboBox"].SelectedItem
    $selectedWimIndex = 1
    if ($selectedItem -and $selectedItem -match '^(\d+):') {
        $selectedWimIndex = [int]$Matches[1]
    } elseif ($sync["Win11ISOImageInfo"]) {
        $selectedWimIndex = $sync["Win11ISOImageInfo"][0].ImageIndex
    }
    $selectedEditionName = if ($selectedItem) { ($selectedItem -replace '^\d+:\s*', '') } else { "Unknown" }
    Write-Win11ISOLog "All editions (Home / Home SL / Pro) will be processed."
    Write-Win11ISOLog "Opening build configuration dialog..."

    # ?????? Pre-Build Dialog: ask username, computer name, driver injection ??????????????????????????????
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    # Load saved usernames from Clark's own config folder
    $profilesPath   = Join-Path $PSScriptRoot "..\\..\\config\\iso-usernames.json"
    $savedUsernames = @()
    $defaultUsername = ""
    if (Test-Path $profilesPath) {
        try {
            $profileData     = Get-Content $profilesPath -Raw | ConvertFrom-Json
            $savedUsernames  = @($profileData.usernames)
            $defaultUsername = $profileData.default
        } catch { $savedUsernames = @(); $defaultUsername = "" }
    }

    # Determine Windows version from ISO
    $winVer = if ($selectedEditionName -match "Windows 10") { "10" } `
              elseif ($sync["Win11ISOImageInfo"] -and $sync["Win11ISOImageInfo"][0].ImageName -match "Windows 10") { "10" } `
              else { "11" }

    # Helper: save profiles back to Clark config
    function Save-Profiles {
        param([string[]]$Usernames, [string]$Default)
        $null = New-Item -ItemType Directory -Path (Split-Path $profilesPath) -Force
        @{ usernames = $Usernames; default = $Default } | ConvertTo-Json | Set-Content $profilesPath -Encoding UTF8
    }

    # Build WPF dialog
    [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ASYS ISO Build Configuration"
        SizeToContent="WidthAndHeight"
        MinWidth="440" MaxWidth="520"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#1e1e1e">
    <Window.Resources>
        <!-- Force dark system brushes inside this dialog so default control templates stay readable -->
        <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlLightBrushKey}" Color="#3b3b3b"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlDarkBrushKey}" Color="#1f1f1f"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.GrayTextBrushKey}" Color="#c7c7c7"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2b5f8a"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HotTrackBrushKey}" Color="#ffffff"/>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#555"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#2a2a2a"/>
                    <Setter Property="Foreground" Value="#b5b5b5"/>
                    <Setter Property="BorderBrush" Value="#444"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#dddddd"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#9a9a9a"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#555"/>
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="ItemTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <TextBlock Text="{Binding}" Foreground="White"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="#2d2d2d"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="HorizontalContentAlignment" Value="Left"/>
                        <Style.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter Property="Background" Value="#3a3a3a"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#2b5f8a"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#2a2a2a"/>
                    <Setter Property="Foreground" Value="#b5b5b5"/>
                    <Setter Property="BorderBrush" Value="#444"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#c7c7c7"/>
                    <Setter Property="Background" Value="#505050"/>
                    <Setter Property="BorderBrush" Value="#6f6f6f"/>
                    <Setter Property="Opacity" Value="1"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>
    <StackPanel Margin="24,20,24,20">
        <TextBlock Text="ISO Build Configuration" FontSize="16" FontWeight="Bold"
                   Foreground="White" Margin="0,0,0,16"/>

        <!-- Username row -->
        <TextBlock Text="Main Account Username:" Foreground="#cccccc" FontSize="13" Margin="0,0,0,4"/>
        <Grid Margin="0,0,0,4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TxtUsername" Grid.Column="0" Padding="6,4"
                     Background="#2d2d2d" Foreground="White" BorderBrush="#555"/>
            <ComboBox x:Name="CmbSaved" Grid.Column="2" Width="150"
                      IsEditable="False"
                      Background="#2d2d2d" Foreground="White" BorderBrush="#555"
                      ToolTip="Saved usernames">
                <ComboBox.Resources>
                    <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#2d2d2d"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#2d2d2d"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#ffffff"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#ffffff"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2b5f8a"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#ffffff"/>
                </ComboBox.Resources>
                <ComboBox.ItemContainerStyle>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="#2d2d2d"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="Padding" Value="6,3"/>
                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                        <Style.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter Property="Background" Value="#3a3a3a"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#2b5f8a"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </ComboBox.ItemContainerStyle>
                <ComboBox.Template>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="ComboBorder"
                                    Background="#2d2d2d"
                                    BorderBrush="#555"
                                    BorderThickness="1"
                                    SnapsToDevicePixels="True">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="24"/>
                                    </Grid.ColumnDefinitions>
                                    <ContentPresenter Grid.Column="0"
                                                      Margin="6,2,4,2"
                                                      VerticalAlignment="Center"
                                                      HorizontalAlignment="Left"
                                                      Content="{TemplateBinding SelectionBoxItem}"
                                                      ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                      ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                                                      TextElement.Foreground="White"/>
                                    <Border Grid.Column="1"
                                            Background="#2d2d2d"
                                            BorderBrush="#555"
                                            BorderThickness="1,0,0,0">
                                        <TextBlock Text="&#xE70D;"
                                                   FontFamily="Segoe MDL2 Assets"
                                                   Foreground="#cccccc"
                                                   FontSize="10"
                                                   HorizontalAlignment="Center"
                                                   VerticalAlignment="Center"/>
                                    </Border>
                                </Grid>
                            </Border>
                            <Popup Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide">
                                <Border Background="#2d2d2d"
                                        BorderBrush="#555"
                                        BorderThickness="1"
                                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                                    <ScrollViewer Margin="0"
                                                  SnapsToDevicePixels="True"
                                                  MaxHeight="240">
                                        <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ComboBorder" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </ComboBox.Template>
            </ComboBox>
        </Grid>

        <!-- Saved username management -->
        <StackPanel Orientation="Horizontal" Margin="0,2,0,4">
            <CheckBox x:Name="ChkSave" Content="Save this username"
                      Foreground="#cccccc" FontSize="12" IsChecked="True" Margin="0,0,16,0"/>
            <Button x:Name="BtnSetDefault" Content="Set as Default" FontSize="11"
                    Background="#2b5f8a" Foreground="White" BorderBrush="#4d8fc1"
                    Padding="8,3" Margin="0,0,8,0"
                    ToolTip="Set selected saved username as the default (pre-filled next time)"/>
            <Button x:Name="BtnDelete" Content="Delete" FontSize="11"
                    Background="#7a2f2f" Foreground="White" BorderBrush="#a84f4f"
                    Padding="8,3"
                    ToolTip="Remove selected saved username from the list"/>
        </StackPanel>
        <TextBlock x:Name="TxtProfileStatus" FontSize="11" Foreground="#888"
                   Margin="0,0,0,12" Text=""/>

        <!-- Computer name -->
        <TextBlock Text="Computer Name:" Foreground="#cccccc" FontSize="13" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtComputer" Padding="6,4" Margin="0,0,0,14"
                 Background="#2d2d2d" Foreground="White" BorderBrush="#555"
                 Text="ASYS-PC"/>

        <!-- Driver injection -->
        <CheckBox x:Name="ChkDrivers" Content="Inject current system drivers into ISO"
                  Foreground="#cccccc" FontSize="12" Margin="0,0,0,16"/>

        <!-- Deployment Mode -->
        <TextBlock Text="Deployment Mode:" Foreground="#cccccc" FontSize="13"
                   FontWeight="SemiBold" Margin="0,0,0,6"/>
        <RadioButton x:Name="RbWindowsOnly" GroupName="DeployMode"
                     Content="Windows installation only"
                     Foreground="#cccccc" FontSize="12" Margin="0,0,0,4"
                     ToolTip="ISO installs Windows with no additional scripts or configuration"/>
        <RadioButton x:Name="RbFullDeploy" GroupName="DeployMode"
                     Content="Full ASYS deployment (Windows + all setup scripts)"
                     Foreground="#cccccc" FontSize="12" Margin="0,0,0,16"
                     IsChecked="True"
                     ToolTip="Includes master.ps1, Stage 2 and Stage 3 scripts in the ISO"/>

        <!-- Action buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancel"  Content="Cancel"   Width="90" Height="32"
                    Margin="0,0,10,0" Background="#5a5a5a" Foreground="White" BorderBrush="#808080" IsCancel="True"/>
            <Button x:Name="BtnProceed" Content="Start Build" Width="110" Height="32"
                    Background="#0078d4" Foreground="White" BorderBrush="#1f96f2" IsDefault="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $dlgReader       = [System.Xml.XmlNodeReader]::new($dialogXaml)
    $dlgWindow       = [System.Windows.Markup.XamlReader]::Load($dlgReader)
    $txtUser         = $dlgWindow.FindName("TxtUsername")
    $cmbSaved        = $dlgWindow.FindName("CmbSaved")
    $chkSave         = $dlgWindow.FindName("ChkSave")
    $txtComp         = $dlgWindow.FindName("TxtComputer")
    $chkDrivers      = $dlgWindow.FindName("ChkDrivers")
    $btnCancel       = $dlgWindow.FindName("BtnCancel")
    $btnProceed      = $dlgWindow.FindName("BtnProceed")
    $rbWindowsOnly   = $dlgWindow.FindName("RbWindowsOnly")
    $rbFullDeploy    = $dlgWindow.FindName("RbFullDeploy")
    $btnSetDefault   = $dlgWindow.FindName("BtnSetDefault")
    $btnDelete       = $dlgWindow.FindName("BtnDelete")
    $txtStatus       = $dlgWindow.FindName("TxtProfileStatus")

    # Populate saved usernames dropdown
    if ($savedUsernames.Count -gt 0) {
        $cmbSaved.ItemsSource   = [System.Collections.ObjectModel.ObservableCollection[string]]$savedUsernames
        $cmbSaved.SelectedIndex = 0
        # Pre-fill with default if set, otherwise first saved
        $txtUser.Text = if ($defaultUsername -and $defaultUsername -in $savedUsernames) { $defaultUsername } else { $savedUsernames[0] }
        $txtStatus.Text = if ($defaultUsername) { "Default: $defaultUsername" } else { "" }
    } else {
        $txtStatus.Text = "No saved usernames yet."
    }

    # Sync dropdown selection to text box
    $cmbSaved.Add_SelectionChanged({
        if ($cmbSaved.SelectedItem) { $txtUser.Text = $cmbSaved.SelectedItem }
    })

    # Set as Default button
    $btnSetDefault.Add_Click({
        $selected = $cmbSaved.SelectedItem
        if ($selected) {
            $defaultUsername = $selected
            Save-Profiles -Usernames $savedUsernames -Default $defaultUsername
            $txtStatus.Text = "Default set: $defaultUsername"
            $txtUser.Text   = $defaultUsername
        }
    })

    # Delete button
    $btnDelete.Add_Click({
        $selected = $cmbSaved.SelectedItem
        if ($selected) {
            $savedUsernames = @($savedUsernames | Where-Object { $_ -ne $selected })
            $newDefault = if ($defaultUsername -eq $selected) { "" } else { $defaultUsername }
            Save-Profiles -Usernames $savedUsernames -Default $newDefault
            $defaultUsername = $newDefault
            $cmbSaved.ItemsSource   = [System.Collections.ObjectModel.ObservableCollection[string]]$savedUsernames
            if ($savedUsernames.Count -gt 0) {
                $cmbSaved.SelectedIndex = 0
                $txtUser.Text = $savedUsernames[0]
                $txtStatus.Text = if ($newDefault) { "Default: $newDefault" } else { "Deleted. No default set." }
            } else {
                $cmbSaved.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[string]]@()
                $txtUser.Text   = ""
                $txtStatus.Text = "No saved usernames."
            }
        }
    })

    # Use Window.Tag/DialogResult (shared object state) to avoid event-scope variable issues.
    $dlgWindow.Tag = "none"
    $btnProceed.Add_Click({
        $dlgWindow.Tag = "proceed"
        try { $dlgWindow.DialogResult = $true } catch {}
    })
    $btnCancel.Add_Click({
        $dlgWindow.Tag = "cancel"
        try { $dlgWindow.DialogResult = $false } catch {}
    })
    $dialogResult = $dlgWindow.ShowDialog()
    $dlgAction = [string]$dlgWindow.Tag
    if ([string]::IsNullOrWhiteSpace($dlgAction) -or $dlgAction -eq "none") {
        if ($dialogResult -eq $true) {
            $dlgAction = "proceed"
        } elseif ($dialogResult -eq $false) {
            $dlgAction = "cancel"
        } else {
            $dlgAction = "dismissed"
        }
    }

    if ($dlgAction -ne "proceed") {
        Write-Win11ISOLog "ISO modification cancelled from build configuration dialog. Action: $dlgAction"
        $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
        $sync["Win11ISOModifying"] = $false
        return
    }

    $mainUsername = ($txtUser.Text).Trim()
    $computerName = ($txtComp.Text).Trim()
    if (-not $mainUsername) { $mainUsername = "User" }
    if (-not $computerName) { $computerName = "ASYS-PC" }
    $injectDriversDialog = $chkDrivers.IsChecked -eq $true
    $fullDeploy          = $rbFullDeploy.IsChecked -eq $true
    Write-Win11ISOLog "Deployment mode: $(if ($fullDeploy) { "Full ASYS Deployment" } else { "Windows Only" })"
    Write-Win11ISOLog "Build configuration accepted. Preparing ISO modification job..."

    # Save username if requested
    if ($chkSave.IsChecked -and $mainUsername -and $mainUsername -notin $savedUsernames) {
        $savedUsernames  = @(@($mainUsername) + $savedUsernames | Select-Object -Unique | Select-Object -First 10)
        # Keep existing default or set first entry as default if none set
        if (-not $defaultUsername) { $defaultUsername = $mainUsername }
        Save-Profiles -Usernames $savedUsernames -Default $defaultUsername
        Write-Win11ISOLog "Username saved to Clark config: $mainUsername (default: $defaultUsername)"
    }
    Write-Win11ISOLog "Build config - Username: $mainUsername | Computer: $computerName | Drivers: $injectDriversDialog"

    $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
    $sync["Win11ISOModifying"] = $true

    $isoWorkDirCandidates = @()
    $isoWorkDirCandidates += Get-Item -Path (Join-Path $env:TEMP "ASYS_WinISO*") -ErrorAction SilentlyContinue
    $isoWorkDirCandidates += Get-Item -Path (Join-Path $env:TEMP "ASYS_Win11ISO*") -ErrorAction SilentlyContinue
    $existingWorkDir = $isoWorkDirCandidates |
        Where-Object { $_ -and $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $workDir = if ($existingWorkDir) {
        Write-Win11ISOLog "Reusing existing temp directory: $($existingWorkDir.FullName)"
        $existingWorkDir.FullName
    } else {
        Join-Path $env:TEMP "ASYS_WinISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    $pathCandidates = @(
        (Join-Path $PSScriptRoot "tools"),
        (Join-Path $PSScriptRoot "..\tools"),
        (Join-Path $PSScriptRoot "..\..\tools")
    )
    $toolsRoot = $pathCandidates |
        ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    $autounattendRaw = if ($ClarkAutounattendXml) {
        $ClarkAutounattendXml
    } else {
        $toolsXml = if ($toolsRoot) { Join-Path $toolsRoot "autounattend.xml" } else { "" }
        if (Test-Path $toolsXml) { Get-Content $toolsXml -Raw } else { "" }
    }

    # Ensure autounattend carries pre-staged setup scripts used by Invoke-ClarkISOScript.
    $masterScriptSource = if ($toolsRoot) { Join-Path $toolsRoot "`$OEM`$\`$1\Setup\master.ps1" } else { "" }
    if ($autounattendRaw -and (Test-Path $masterScriptSource)) {
        try {
            $autoDoc = [xml]$autounattendRaw
            $sgNs = "https://schneegans.de/windows/unattend-generator/"
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($autoDoc.NameTable)
            $nsMgr.AddNamespace("sg", $sgNs)

            $extensionsNode = $autoDoc.SelectSingleNode("//sg:Extensions", $nsMgr)
            if (-not $extensionsNode) {
                $extensionsNode = $autoDoc.CreateElement("Extensions", $sgNs)
                [void]$autoDoc.DocumentElement.AppendChild($extensionsNode)
            }

            $masterNode = $autoDoc.SelectSingleNode("//sg:File[@path='C:\Setup\master.ps1']", $nsMgr)
            if (-not $masterNode) {
                $masterNode = $autoDoc.CreateElement("File", $sgNs)
                [void]$masterNode.SetAttribute("path", "C:\Setup\master.ps1")
                [void]$extensionsNode.AppendChild($masterNode)
            }

            $masterNode.RemoveAll()
            [void]$masterNode.SetAttribute("path", "C:\Setup\master.ps1")
            $masterContent = Get-Content -LiteralPath $masterScriptSource -Raw
            [void]$masterNode.AppendChild($autoDoc.CreateCDataSection($masterContent))
            $autounattendRaw = $autoDoc.OuterXml
            Write-Win11ISOLog "Autounattend Extensions staging enabled for C:\Setup\master.ps1."
        } catch {
            Write-Win11ISOLog "Warning: failed to append autounattend Extensions file node for master.ps1: $_"
        }
    }

    # Inject username and computer name into autounattend.xml placeholders
    $autounattendContent = $autounattendRaw -replace "%%USERNAME%%", $mainUsername -replace "%%COMPUTERNAME%%", $computerName

    # Resolve $OEM$ folder path from whichever script location is active (compiled/uncompiled)
    $oemFolderSource = if ($toolsRoot) { Join-Path $toolsRoot "`$OEM`$" } else { "" }

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $injectDrivers = $injectDriversDialog  # Set by pre-build dialog

    $runspace.SessionStateProxy.SetVariable("sync",                $sync)
    $runspace.SessionStateProxy.SetVariable("isoPath",             $isoPath)
    $runspace.SessionStateProxy.SetVariable("driveLetter",         $driveLetter)
    $runspace.SessionStateProxy.SetVariable("wimPath",             $wimPath)
    $runspace.SessionStateProxy.SetVariable("workDir",             $workDir)
    $runspace.SessionStateProxy.SetVariable("selectedWimIndex",    $selectedWimIndex)
    $runspace.SessionStateProxy.SetVariable("selectedEditionName", $selectedEditionName)
    $runspace.SessionStateProxy.SetVariable("autounattendContent", $autounattendContent)
    $runspace.SessionStateProxy.SetVariable("injectDrivers",       $injectDrivers)
    $runspace.SessionStateProxy.SetVariable("oemFolderSource",     $oemFolderSource)
    $runspace.SessionStateProxy.SetVariable("fullDeploy",          $fullDeploy)

    $isoScriptFuncDef = "function Invoke-ClarkISOScript {`n" + ${function:Invoke-ClarkISOScript}.ToString() + "`n}"
    $getLogDef        = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDef       = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"
    $runspace.SessionStateProxy.SetVariable("isoScriptFuncDef", $isoScriptFuncDef)
    $runspace.SessionStateProxy.SetVariable("getLogDef",        $getLogDef)
    $runspace.SessionStateProxy.SetVariable("logCoreDef",       $logCoreDef)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($isoScriptFuncDef))
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function Log($msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $msg"
            Write-Win11ISOLogCore -Line $line
            Add-Content -Path (Join-Path $workDir "ASYS_WinISO.log") -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            Log "ISO modification worker started."
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOSelectSection"].Visibility = "Collapsed"
                $sync["WPFWin11ISOMountSection"].Visibility  = "Collapsed"
                $sync["WPFWin11ISOModifySection"].Visibility = "Collapsed"
            })

            Log "Global log file: $(Get-Win11ISOLogFilePath)"
            Log "Creating working directory: $workDir"
            $isoContents = Join-Path $workDir "iso_contents"
            $mountDir    = Join-Path $workDir "wim_mount"
            New-Item -ItemType Directory -Path $isoContents, $mountDir -Force | Out-Null
            SetProgress "Copying ISO contents..." 10

            Log "Copying ISO contents from $driveLetter to $isoContents..."
            & robocopy $driveLetter $isoContents /E /NFL /NDL /NJH /NJS | Out-Null
            Log "ISO contents copied."
            # ?????? Handle ESD: export Home/Pro editions to writable install.wim ??????????????????
            $localWim = Join-Path $isoContents "sources\install.wim"
            if (-not (Test-Path $localWim)) {
                $localEsd = Join-Path $isoContents "sources\install.esd"
                if (-not (Test-Path $localEsd)) {
                    throw "Neither install.wim nor install.esd was found in copied ISO contents."
                }
                SetProgress "Reading editions from install.esd..." 18
                Log "install.esd detected. Reading available editions..."
                $esdEditions = Get-WindowsImage -ImagePath $localEsd
                $esdTargets  = @($esdEditions | Where-Object { $_.ImageName -match "\\bHome Single Language\\b|\\bHome$|\\bPro$" } | Sort-Object ImageIndex)
                if ($esdTargets.Count -eq 0) { $esdTargets = @($esdEditions | Sort-Object ImageIndex) }
                Log "Exporting $($esdTargets.Count) edition(s) from ESD to install.wim..."
                $esdIdx = 0
                foreach ($esdEd in $esdTargets) {
                    $esdIdx++
                    $pctEsd = [int](18 + ($esdIdx / $esdTargets.Count) * 6)
                    SetProgress "Converting ESD: $($esdEd.ImageName) ($esdIdx/$($esdTargets.Count))..." $pctEsd
                    Log "  Exporting: $($esdEd.ImageName) (ESD Index $($esdEd.ImageIndex))..."
                    Export-WindowsImage -SourceImagePath $localEsd -SourceIndex $esdEd.ImageIndex -DestinationImagePath $localWim -ErrorAction Stop | Out-Null
                }
                Log "ESD conversion complete. install.wim now contains $esdIdx edition(s)."
            }

            # ?????? Determine target editions (Home, Home SL, Pro) in install.wim ????????????????????????
            Set-ItemProperty -Path $localWim -Name IsReadOnly -Value $false
            Log "Reading editions from install.wim..."
            $allWimEditions    = @(Get-WindowsImage -ImagePath $localWim)
            # Match only exact target editions: Home, Home Single Language, Pro
            $targetWimEditions = @($allWimEditions | Where-Object { $_.ImageName -match "\bHome Single Language\b|\bHome$|\bPro$" } | Sort-Object ImageIndex)
            if ($targetWimEditions.Count -eq 0) {
                Log "Warning: no Home/Pro editions found - processing all editions."
                $targetWimEditions = $allWimEditions | Sort-Object ImageIndex
            }
            $editionCount = $targetWimEditions.Count
            Log "Will process $editionCount edition(s): $(($targetWimEditions | ForEach-Object { $_.ImageName }) -join ", ")"

            function Test-MountPathActive {
                param([string]$Path)
                $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)
                if ($mounted.Count -eq 0) { return $false }
                $target = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
                return @($mounted | Where-Object {
                    try {
                        [System.IO.Path]::GetFullPath($_.Path).TrimEnd('\') -ieq $target
                    } catch { $false }
                }).Count -gt 0
            }

            # ?????? Apply ASYS modifications to each edition ??????????????????????????????????????????????????????????????????????????????????????????
            $edIdx = 0
            foreach ($edition in $targetWimEditions) {
                $edIdx++
                $pctStart = [int](25 + (($edIdx - 1) / $editionCount) * 50)
                $pctEnd   = [int](25 + ($edIdx / $editionCount) * 50)

                # Defensive cleanup in case a previous iteration left the mount active.
                if (Test-MountPathActive -Path $mountDir) {
                    Log "Warning: stale mount detected at $mountDir. Discarding before next mount..."
                    Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
                    Start-Sleep -Seconds 1
                }

                SetProgress "[$edIdx/$editionCount] Mounting: $($edition.ImageName)..." $pctStart
                Log "--- Edition $edIdx/${editionCount}: $($edition.ImageName) (Index $($edition.ImageIndex)) ---"
                Log "Mounting install.wim at $mountDir..."
                Mount-WindowsImage -ImagePath $localWim -Index $edition.ImageIndex -Path $mountDir -ErrorAction Stop | Out-Null

                SetProgress "[$edIdx/$editionCount] Modifying: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.25))
                Log "Applying ASYS modifications..."
                # Only inject autounattend.xml to ISO root on the first pass (it's ISO-level, not per-edition)
                $isoInjectDir = if ($edIdx -eq 1) { $isoContents } else { "" }
                Invoke-ClarkISOScript -ScratchDir $mountDir -ISOContentsDir $isoInjectDir -AutoUnattendXml $autounattendContent -InjectCurrentSystemDrivers $injectDrivers -Log { param($m) Log $m }

                SetProgress "[$edIdx/$editionCount] WinSxS cleanup: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.65))
                Log "Running DISM component store cleanup (/ResetBase)..."
                & dism /English "/image:$mountDir" /Cleanup-Image /StartComponentCleanup /ResetBase | ForEach-Object { Log $_ }
                Log "Component store cleanup complete."

                SetProgress "[$edIdx/$editionCount] Saving: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.9))
                Log "Dismounting and saving install.wim (this takes several minutes)..."
                try {
                    Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null
                } catch {
                    Log "Warning: standard dismount-save failed, attempting fallback commit. Details: $($_.Exception.Message)"
                    & dism /English /Unmount-Image "/MountDir:$mountDir" /Commit | ForEach-Object { Log $_ }
                    if (Test-MountPathActive -Path $mountDir) {
                        throw "Fallback commit dismount failed; mount path is still active: $mountDir"
                    }
                }
                Log "Edition '$($edition.ImageName)' saved successfully."
            }

            # ?????? Inject $OEM$ folder (contains master.ps1 and Setup files) ???????????????????????????????????????
            # ?????? Strip unused editions ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
            # Export only Home, Home SL, Pro to a fresh WIM
            SetProgress "Stripping unused editions from install.wim..." 76
            Log "Stripping unused editions (keeping Home / Home Single Language / Pro)..."
            $localWimStrip  = Join-Path $isoContents "sources\install.wim"
            $strippedWim    = Join-Path $isoContents "sources\install_stripped.wim"
            $finalEditions  = @(Get-WindowsImage -ImagePath $localWimStrip | Where-Object {
                $_.ImageName -match "\bHome Single Language\b|\bHome$|\bPro$"
            } | Sort-Object ImageIndex)
            foreach ($fe in $finalEditions) {
                Log "  Exporting to stripped WIM: $($fe.ImageName)..."
                Export-WindowsImage -SourceImagePath $localWimStrip -SourceIndex $fe.ImageIndex `
                    -DestinationImagePath $strippedWim -ErrorAction Stop | Out-Null
            }
            Remove-Item $localWimStrip -Force
            Rename-Item $strippedWim $localWimStrip
            Log "Strip complete. Final WIM: $(($finalEditions | ForEach-Object { $_.ImageName }) -join ", ")"

            if ($fullDeploy) {
                Log "Injecting OEM folder (Full ASYS Deployment mode)..."
                if ($oemFolderSource -and (Test-Path $oemFolderSource)) {
                    $oemFolderDest = Join-Path $isoContents "`$OEM`$"
                    Copy-Item -Path $oemFolderSource -Destination $oemFolderDest -Recurse -Force
                    Log "OEM folder injected: $oemFolderSource -> $oemFolderDest"
                } else {
                    Log "Warning: tools\`$OEM`$ folder not found at '$oemFolderSource' - skipping OEM injection."
                }
            } else {
                Log "Windows Only mode selected - skipping OEM injection. No setup scripts will be included."
            }


            SetProgress "Dismounting source ISO..." 80
            Log "Dismounting original ISO..."
            Dismount-DiskImage -ImagePath $isoPath | Out-Null

            $sync["Win11ISOWorkDir"]           = $workDir
            $sync["Win11ISOContentsDir"]       = $isoContents
            $sync["Win11ISOBuiltEditionName"]  = $selectedEditionName

            SetProgress "Modification complete" 100
            Log "install.wim modification complete. Choose an output option in Step 4."

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOOutputSection"].Visibility = "Visible"
            })
        } catch {
            Log "ERROR during modification: $($_.Exception.Message)"
            Log "ERROR details: $($_ | Out-String)"

            try {
                if (Test-Path $mountDir) {
                    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $mountDir }
                    if ($mountedImages) {
                        Log "Cleaning up: dismounting install.wim (discarding changes)..."
                        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            } catch { Log "Warning: could not dismount install.wim during cleanup: $_" }

            try {
                $mountedISO = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                if ($mountedISO -and $mountedISO.Attached) {
                    Log "Cleaning up: dismounting source ISO..."
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
                }
            } catch { Log "Warning: could not dismount ISO during cleanup: $_" }

            try {
                if (Test-Path $workDir) {
                    Log "Cleaning up: removing temp directory $workDir..."
                    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch { Log "Warning: could not remove temp directory during cleanup: $_" }

            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show(
                    "An error occurred during install.wim modification:`n`n$m",
                    "Modification Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            $sync["Win11ISOModifying"] = $false
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
                if ($sync["WPFWin11ISOOutputSection"].Visibility -ne "Visible") {
                    $sync["WPFWin11ISOSelectSection"].Visibility = "Visible"
                    $sync["WPFWin11ISOMountSection"].Visibility  = "Visible"
                    $sync["WPFWin11ISOModifySection"].Visibility = "Visible"
                }
            })
        }
    }) | Out-Null

    try {
        # Keep strong references so the background pipeline is not GC'd before it completes.
        $sync["_isoModifyPowerShell"] = $script
        $sync["_isoModifyAsyncResult"] = $script.BeginInvoke()
        Write-Win11ISOLog "ISO modification started in the background. Progress will stream in this log."
    } catch {
        $sync["_isoModifyPowerShell"] = $null
        $sync["_isoModifyAsyncResult"] = $null
        try { $script.Dispose() } catch {}
        $sync["Win11ISOModifying"] = $false
        $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start ISO modification job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start ISO modification in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
}

function Invoke-ClarkISOCheckExistingWork {
    if ($sync["Win11ISOContentsDir"] -and (Test-Path $sync["Win11ISOContentsDir"])) { return }

    # Check if ISO modification is currently in progress
    if ($sync["Win11ISOModifying"]) {
        return
    }

    $resumeIsoCandidates = @()
    $resumeIsoCandidates += Get-Item -Path (Join-Path $env:TEMP "ASYS_WinISO*") -ErrorAction SilentlyContinue
    $resumeIsoCandidates += Get-Item -Path (Join-Path $env:TEMP "ASYS_Win11ISO*") -ErrorAction SilentlyContinue
    $existingWorkDir = $resumeIsoCandidates |
        Where-Object { $_ -and $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $existingWorkDir) { return }

    $isoContents = Join-Path $existingWorkDir.FullName "iso_contents"
    if (-not (Test-Path $isoContents)) { return }

    $sync["Win11ISOWorkDir"]     = $existingWorkDir.FullName
    $sync["Win11ISOContentsDir"] = $isoContents

    $sync["WPFWin11ISOSelectSection"].Visibility = "Collapsed"
    $sync["WPFWin11ISOMountSection"].Visibility  = "Collapsed"
    $sync["WPFWin11ISOModifySection"].Visibility = "Collapsed"
    $sync["WPFWin11ISOOutputSection"].Visibility = "Visible"

    $modified = $existingWorkDir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-Win11ISOLog "Existing working directory found: $($existingWorkDir.FullName)"
    Write-Win11ISOLog "Last modified: $modified - Skipping Steps 1-3 and resuming at Step 4."
    Write-Win11ISOLog "Click 'Clean & Reset' if you want to start over with a new ISO."

    [System.Windows.MessageBox]::Show(
        "A previous clark ISO working directory was found:`n`n$($existingWorkDir.FullName)`n`n(Last modified: $modified)`n`nStep 4 (output options) has been restored so you can save the already-modified image.`n`nClick 'Clean & Reset' in Step 4 if you want to start over.",
        "Existing Work Found", "OK", "Info")
}

function Invoke-ClarkISOCleanAndReset {
    $workDir = $sync["Win11ISOWorkDir"]

    if ($workDir -and (Test-Path $workDir)) {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will delete the temporary working directory:`n`n$workDir`n`nAnd reset the interface back to the start.`n`nContinue?",
            "Clean & Reset", "YesNo", "Warning")
        if ($confirm -ne "Yes") { return }
    }

    $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $false

    $getLogDefClean  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDefClean = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",         $sync)
    $runspace.SessionStateProxy.SetVariable("workDir",      $workDir)
    $runspace.SessionStateProxy.SetVariable("getLogDef",    $getLogDefClean)
    $runspace.SessionStateProxy.SetVariable("logCoreDef",   $logCoreDefClean)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))

        function Log($msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $msg"
            Write-Win11ISOLogCore -Line $line
            if ($workDir) {
                Add-Content -Path (Join-Path $workDir "ASYS_WinISO.log") -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
            }
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            if ($workDir) {
                $mountDir = Join-Path $workDir "wim_mount"
                try {
                    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Path -like "$workDir*" }
                    if ($mountedImages) {
                        foreach ($img in $mountedImages) {
                            Log "Dismounting WIM at: $($img.Path) (discarding changes)..."
                            SetProgress "Dismounting WIM image..." 3
                            Dismount-WindowsImage -Path $img.Path -Discard -ErrorAction Stop | Out-Null
                            Log "WIM dismounted successfully."
                        }
                    } elseif (Test-Path $mountDir) {
                        Log "No mounted WIM reported by Get-WindowsImage. Running DISM /Cleanup-Wim as a precaution..."
                        SetProgress "Running DISM cleanup..." 3
                        & dism /English /Cleanup-Wim 2>&1 | ForEach-Object { Log $_ }
                    }
                } catch {
                    Log "Warning: could not dismount WIM cleanly. Attempting DISM /Cleanup-Wim fallback: $_"
                    try { & dism /English /Cleanup-Wim 2>&1 | ForEach-Object { Log $_ } } catch { Log "Warning: DISM /Cleanup-Wim also failed: $_" }
                }
            }

            if ($workDir -and (Test-Path $workDir)) {
                Log "Scanning files to delete in: $workDir"
                SetProgress "Scanning files..." 5

                $allFiles = @(Get-ChildItem -Path $workDir -File -Recurse -Force -ErrorAction SilentlyContinue)
                $allDirs  = @(Get-ChildItem -Path $workDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending)
                $total   = $allFiles.Count
                $deleted = 0

                Log "Found $total files to delete."

                foreach ($f in $allFiles) {
                    try { Remove-Item -Path $f.FullName -Force -ErrorAction Stop } catch { Log "WARNING: could not delete $($f.FullName): $_" }
                    $deleted++
                    if ($deleted % 100 -eq 0 -or $deleted -eq $total) {
                        $pct = [math]::Round(($deleted / [Math]::Max($total, 1)) * 85) + 5
                        SetProgress "Deleting files in $($f.Directory.Name)... ($deleted / $total)" $pct
                    }
                }

                foreach ($d in $allDirs) {
                    try { Remove-Item -Path $d.FullName -Force -ErrorAction SilentlyContinue } catch {}
                }

                try { Remove-Item -Path $workDir -Recurse -Force -ErrorAction Stop } catch {}

                if (Test-Path $workDir) {
                    Log "WARNING: some items could not be deleted in $workDir"
                } else {
                    Log "Temp directory deleted successfully."
                }
            } else {
                Log "No temp directory found - resetting UI."
            }

            SetProgress "Resetting UI..." 95
            Log "Resetting interface..."

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["Win11ISOWorkDir"]     = $null
                $sync["Win11ISOContentsDir"] = $null
                $sync["Win11ISOImagePath"]   = $null
                $sync["Win11ISODriveLetter"] = $null
                $sync["Win11ISOWimPath"]     = $null
                $sync["Win11ISOImageInfo"]        = $null
                $sync["Win11ISOUSBDisks"]         = $null
                $sync["Win11ISOBuiltEditionName"] = $null

                $sync["WPFWin11ISOPath"].Text                   = "No ISO selected..."
                $sync["WPFWin11ISOFileInfo"].Visibility          = "Collapsed"
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
                $sync["WPFWin11ISOOptionUSB"].Visibility         = "Collapsed"
                $sync["WPFWin11ISOOutputSection"].Visibility     = "Collapsed"
                $sync["WPFWin11ISOModifySection"].Visibility     = "Collapsed"
                $sync["WPFWin11ISOMountSection"].Visibility      = "Collapsed"
                $sync["WPFWin11ISOSelectSection"].Visibility     = "Visible"
                $sync["WPFWin11ISOModifyButton"].IsEnabled       = $true
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled   = $true

                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0

                $sync["WPFWin11ISOStatusLog"].Text   = "Ready. Please select a Windows 10 or Windows 11 ISO to begin."
            })
        } catch {
            Log "ERROR during Clean & Reset: $_"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $true
            })
        }
    }) | Out-Null

    $script.BeginInvoke() | Out-Null
}

function Invoke-ClarkISOExport {
    try {
    $contentsDir = $sync["Win11ISOContentsDir"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        [System.Windows.MessageBox]::Show(
            "No modified ISO content found.  Please complete Steps 1-3 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    # Determine Windows version from image info
    $builtName  = $sync["Win11ISOBuiltEditionName"]
    $isoWinVer  = if ($builtName -match "\bWindows 10\b") { "10" } `
                  elseif ($builtName -match "\bWindows 11\b") { "11" } `
                  else {
                      $imgInfo = $sync["Win11ISOImageInfo"]
                      if ($imgInfo -and $imgInfo[0].ImageName -match "Windows 10") { "10" } else { "11" }
                  }
    # Format: W10-HhsP or W11-HhsP (Home, Home Single Language, Pro)
    $isoBase    = "W$isoWinVer-HhsP.iso"

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title            = "Save Modified Windows ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso"
    $dlg.FileName         = $isoBase
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $outputISO = $dlg.FileName

    # Locate oscdimg.exe (prefer common ADK paths first, then fallback search)
    $oscdimg = $null
    $oscdimgCandidates = @(
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    foreach ($candidate in $oscdimgCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $oscdimg = $candidate
            break
        }
    }
    if (-not $oscdimg -and (Test-Path "C:\Program Files (x86)\Windows Kits")) {
        $oscdimg = Get-ChildItem "C:\Program Files (x86)\Windows Kits" -Recurse -Depth 10 -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $oscdimg) {
        $oscdimg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                   Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $oscdimg) {
        Write-Win11ISOLog "oscdimg.exe not found. Attempting to install via winget..."
        try {
            # First ensure winget is installed and operational
            Install-ClarkWinget

            $winget = Get-Command winget -ErrorAction Stop
            $result = & $winget install -e --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements 2>&1
            Write-Win11ISOLog "winget output: $result"
            $oscdimg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                       Select-Object -First 1 -ExpandProperty FullName
        } catch {
            Write-Win11ISOLog "winget not available or install failed: $_"
        }

        if (-not $oscdimg) {
            Write-Win11ISOLog "oscdimg.exe still not found after install attempt."
            [System.Windows.MessageBox]::Show(
                "oscdimg.exe could not be found or installed automatically.`n`nPlease install it manually:`n  winget install -e --id Microsoft.OSCDIMG`n`nOr install the Windows ADK from:`nhttps://learn.microsoft.com/windows-hardware/get-started/adk-install",
                "oscdimg Not Found", "OK", "Warning")
            return
        }
        Write-Win11ISOLog "oscdimg.exe installed successfully."
    }

    $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $false

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",        $sync)
    $runspace.SessionStateProxy.SetVariable("contentsDir", $contentsDir)
    $runspace.SessionStateProxy.SetVariable("outputISO",   $outputISO)
    $runspace.SessionStateProxy.SetVariable("oscdimg",     $oscdimg)

    $getLogDefEx  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDefEx = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"
    $runspace.SessionStateProxy.SetVariable("getLogDef",  $getLogDefEx)
    $runspace.SessionStateProxy.SetVariable("logCoreDef", $logCoreDefEx)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            Write-Win11ISOLog "Exporting to ISO: $outputISO"
            SetProgress "Building ISO..." 10

            $bootData    = "2#p0,e,b`"$contentsDir\boot\etfsboot.com`"#pEF,e,b`"$contentsDir\efi\microsoft\boot\efisys.bin`""
            $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-bootdata:$bootData", "-l`"ASYS_MODIFIED`"", "`"$contentsDir`"", "`"$outputISO`"")

            Write-Win11ISOLog "Running oscdimg..."

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $oscdimg
            $psi.Arguments              = $oscdimgArgs -join " "
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            # Stream stdout line-by-line as oscdimg runs
            while (-not $proc.StandardOutput.EndOfStream) {
                $line = $proc.StandardOutput.ReadLine()
                if ($line.Trim()) { Write-Win11ISOLog $line }
            }

            $proc.WaitForExit()

            # Flush any stderr after process exits
            $stderr = $proc.StandardError.ReadToEnd()
            foreach ($line in ($stderr -split "`r?`n")) {
                if ($line.Trim()) { Write-Win11ISOLog "[stderr]$line" }
            }

            if ($proc.ExitCode -eq 0) {
                SetProgress "ISO exported" 100
                Write-Win11ISOLog "ISO exported successfully: $outputISO"
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show("ISO exported successfully!`n`n$outputISO", "Export Complete", "OK", "Info")
                })
            } else {
                Write-Win11ISOLog "oscdimg exited with code $($proc.ExitCode)."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "oscdimg exited with code $($proc.ExitCode).`nCheck the status log for details.",
                        "Export Error", "OK", "Error")
                })
            }
        } catch {
            Write-Win11ISOLog "ERROR during ISO export: $($_.Exception.Message)"
            Write-Win11ISOLog "ERROR details: $($_ | Out-String)"
            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show("ISO export failed:`n`n$m", "Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true
            })
        }
    }) | Out-Null

    try {
        # Keep strong references so background export is not GC'd unexpectedly.
        $sync["_isoExportPowerShell"] = $script
        $sync["_isoExportAsyncResult"] = $script.BeginInvoke()
        Write-Win11ISOLog "ISO export started in the background. Progress will stream in this log."
    } catch {
        $sync["_isoExportPowerShell"] = $null
        $sync["_isoExportAsyncResult"] = $null
        try { $script.Dispose() } catch {}
        $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start ISO export job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start ISO export in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
    } catch {
        try { Write-Win11ISOLog "FATAL in Invoke-ClarkISOExport: $($_.Exception.Message)" } catch {}
        [System.Windows.MessageBox]::Show(
            "Unexpected error while preparing ISO export:`n`n$($_.Exception.Message)",
            "ISO Export Error", "OK", "Error")
    }
}

function Invoke-ClarkISOScript {

    <#

    .SYNOPSIS

        Applies Clark modifications to a mounted Windows 10 or Windows 11 install.wim image.



    .DESCRIPTION

        Removes AppX bloatware and OneDrive, optionally injects all drivers exported from

        the running system into install.wim and boot.wim (controlled by the

        -InjectCurrentSystemDrivers switch), applies offline registry tweaks (hardware

        bypass where applicable, privacy, OOBE, telemetry, update suppression), deletes CEIP/WU

        scheduled-task definition files, and optionally writes autounattend.xml to the ISO

        root and removes the support\ folder from the ISO contents directory.



        All setup scripts embedded in the autounattend.xml <Extensions><File> nodes are

        written directly into the WIM at their target paths under C:\Windows\Setup\Scripts\

        to ensure they survive Windows Setup stripping unrecognised-namespace XML elements

        from the Panther copy of the answer file.



        Mounting/dismounting the WIM is the caller's responsibility (e.g. Invoke-ClarkISO).



    .PARAMETER ScratchDir

        Mandatory. Full path to the directory where the Windows image is currently mounted.



    .PARAMETER ISOContentsDir

        Optional. Root directory of the extracted ISO contents. When supplied,

        autounattend.xml is written here and the support\ folder is removed.



    .PARAMETER AutoUnattendXml

        Optional. Full XML content for autounattend.xml. If empty, the OOBE bypass

        file is skipped and a warning is logged.



    .PARAMETER InjectCurrentSystemDrivers

        Optional. When $true, exports all drivers from the running system and injects

        them into install.wim and boot.wim index 2 (Windows Setup PE).

        Defaults to $false.



    .PARAMETER Log

        Optional ScriptBlock for progress/status logging. Receives a single [string] argument.



    .EXAMPLE

        Invoke-ClarkISOScript -ScratchDir "C:\Temp\wim_mount"



    .EXAMPLE

        $invokeIsoArgs = @{
            ScratchDir      = $mountDir
            ISOContentsDir  = $isoRoot
            AutoUnattendXml = (Get-Content .\tools\autounattend.xml -Raw)
            Log             = { param($m) Write-Host $m }
        }
        Invoke-ClarkISOScript @invokeIsoArgs



    .NOTES

        Author  : Chris Titus @christitustech

        GitHub  : https://github.com/ChrisTitusTech

    #>

    param (

        [Parameter(Mandatory)][string]$ScratchDir,

        [string]$ISOContentsDir = "",

        [string]$AutoUnattendXml = "",

        [bool]$InjectCurrentSystemDrivers = $false,

        [scriptblock]$Log = { param($m) Write-Output $m }

    )



    $adminSID   = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')

    $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])



    function Set-ISOScriptReg {

        param ([string]$path, [string]$name, [string]$type, [string]$value)

        try {

            & reg add $path /v $name /t $type /d $value /f

            & $Log "Set registry value: $path\$name"

        } catch {

            & $Log "Error setting registry value: $_"

        }

    }



    function Remove-ISOScriptReg {

        param ([string]$path)

        try {

            & reg delete $path /f

            & $Log "Removed registry key: $path"

        } catch {

            & $Log "Error removing registry key: $_"

        }

    }



    function Add-DriversToImage {

        param ([string]$MountPath, [string]$DriverDir, [string]$Label = "image", [scriptblock]$Logger)

        & dism /English "/image:$MountPath" /Add-Driver "/Driver:$DriverDir" /Recurse 2>&1 |

            ForEach-Object { & $Logger "  dism[$Label]: $_" }

    }



    function Invoke-BootWimInject {

        param ([string]$BootWimPath, [string]$DriverDir, [scriptblock]$Logger)

        Set-ItemProperty -Path $BootWimPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

        $mountDir = Join-Path $env:TEMP "Clark_BootMount_$(Get-Random)"

        New-Item -Path $mountDir -ItemType Directory -Force | Out-Null

        try {

            & $Logger "Mounting boot.wim (index 2) for driver injection..."

            Mount-WindowsImage -ImagePath $BootWimPath -Index 2 -Path $mountDir -ErrorAction Stop | Out-Null

            Add-DriversToImage -MountPath $mountDir -DriverDir $DriverDir -Label "boot" -Logger $Logger

            & $Logger "Saving boot.wim..."

            Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null

            & $Logger "boot.wim driver injection complete."

        } catch {

            & $Logger "Warning: boot.wim driver injection failed: $_"

            try { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null } catch {}

        } finally {

            Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue

        }

    }



    # ?????? 1. Remove provisioned AppX packages ??????????????????????????????????????????????????????????????????????????????????????????????????????

    & $Log "Removing provisioned AppX packages..."



    $packages = & dism /English "/image:$ScratchDir" /Get-ProvisionedAppxPackages |

        ForEach-Object { if ($_ -match 'PackageName : (.*)') { $matches[1] } }



    $packagePrefixes = @(

        'Clipchamp.Clipchamp',

        'Microsoft.BingNews',

        'Microsoft.BingSearch',

        'Microsoft.BingWeather',

        'Microsoft.MicrosoftOfficeHub',

        'Microsoft.MicrosoftSolitaireCollection',

        'Microsoft.OutlookForWindows',

        'Microsoft.Paint',

        'Microsoft.PowerAutomateDesktop',

        'Microsoft.StartExperiencesApp',

        'Microsoft.Todos',

        'Microsoft.Windows.DevHome',

        'Microsoft.WindowsFeedbackHub',

        'Microsoft.WindowsSoundRecorder',

        'Microsoft.ZuneMusic',

        'MicrosoftCorporationII.QuickAssist',

        'MSTeams'

    )



    $packages | Where-Object { $pkg = $_; $packagePrefixes | Where-Object { $pkg -like "*$_*" } } |

        ForEach-Object { & dism /English "/image:$ScratchDir" /Remove-ProvisionedAppxPackage "/PackageName:$_" }



    # ?????? 2. Inject current system drivers (optional) ?????????????????????????????????????????????????????????????????????????????????

    if ($InjectCurrentSystemDrivers) {

        & $Log "Exporting all drivers from running system..."

        $driverExportRoot = Join-Path $env:TEMP "Clark_DriverExport_$(Get-Random)"

        New-Item -Path $driverExportRoot -ItemType Directory -Force | Out-Null

        try {

            Export-WindowsDriver -Online -Destination $driverExportRoot | Out-Null



            & $Log "Injecting current system drivers into install.wim..."

            Add-DriversToImage -MountPath $ScratchDir -DriverDir $driverExportRoot -Label "install" -Logger $Log

            & $Log "install.wim driver injection complete."



            if ($ISOContentsDir -and (Test-Path $ISOContentsDir)) {

                $bootWim = Join-Path $ISOContentsDir "sources\boot.wim"

                if (Test-Path $bootWim) {

                    & $Log "Injecting current system drivers into boot.wim..."

                    Invoke-BootWimInject -BootWimPath $bootWim -DriverDir $driverExportRoot -Logger $Log

                } else {

                    & $Log "Warning: boot.wim not found - skipping boot.wim driver injection."

                }

            }

        } catch {

            & $Log "Error during driver export/injection: $_"

        } finally {

            Remove-Item -Path $driverExportRoot -Recurse -Force -ErrorAction SilentlyContinue

        }

    } else {

        & $Log "Driver injection skipped."

    }



    # ?????? 3. Remove OneDrive ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

    & $Log "Removing OneDrive..."

    & takeown /f "$ScratchDir\Windows\System32\OneDriveSetup.exe" | Out-Null

    & icacls    "$ScratchDir\Windows\System32\OneDriveSetup.exe" /grant "$($adminGroup.Value):(F)" /T /C | Out-Null

    Remove-Item -Path "$ScratchDir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue



    # ?????? 4. Registry tweaks ????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

    & $Log "Loading offline registry hives..."

    reg load HKLM\zCOMPONENTS "$ScratchDir\Windows\System32\config\COMPONENTS"

    reg load HKLM\zDEFAULT    "$ScratchDir\Windows\System32\config\default"

    reg load HKLM\zNTUSER     "$ScratchDir\Users\Default\ntuser.dat"

    reg load HKLM\zSOFTWARE   "$ScratchDir\Windows\System32\config\SOFTWARE"

    reg load HKLM\zSYSTEM     "$ScratchDir\Windows\System32\config\SYSTEM"



    & $Log "Bypassing system requirements..."

    Set-ISOScriptReg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV1' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV2' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck'   'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\MoSetup'   'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'



    & $Log "Disabling sponsored apps..."

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled'  'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled'     'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled'  'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed'      'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled'    'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled'          'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled'    'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\MRT'           'DontOfferThroughWUAU' 'REG_DWORD' '1'

    Remove-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'

    Remove-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent'       'REG_DWORD' '1'



    & $Log "Enabling local accounts on OOBE..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'



    if ($AutoUnattendXml) {

        try {
            # Normalize potential BOM/leading whitespace so XML declaration stays first.
            $normalizedAutoUnattendXml = $AutoUnattendXml.TrimStart([char]0xFEFF, [char]0x0009, [char]0x000A, [char]0x000D, [char]0x0020)

            $xmlDoc = [xml]::new()

            $xmlDoc.LoadXml($normalizedAutoUnattendXml)



            $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)

            $nsMgr.AddNamespace("sg", "https://schneegans.de/windows/unattend-generator/")



            $fileNodes = $xmlDoc.SelectNodes("//sg:File", $nsMgr)

            if ($fileNodes -and $fileNodes.Count -gt 0) {

                foreach ($fileNode in $fileNodes) {

                    $absPath  = $fileNode.GetAttribute("path")

                    $relPath  = $absPath -replace '^[A-Za-z]:[/\\]', ''

                    $destPath = Join-Path $ScratchDir $relPath

                    New-Item -Path (Split-Path $destPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null



                    $ext = [IO.Path]::GetExtension($destPath).ToLower()

                    $encoding = switch ($ext) {

                        { $_ -in '.ps1', '.xml' }        { [System.Text.Encoding]::UTF8 }

                        { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new($false, $true) }

                        default                          { [System.Text.Encoding]::Default }

                    }

                    [System.IO.File]::WriteAllBytes($destPath, ($encoding.GetPreamble() + $encoding.GetBytes($fileNode.InnerText.Trim())))

                    & $Log "Pre-staged setup script: $relPath"

                }

            } else {

                & $Log "Warning: no <Extensions><File> nodes found in autounattend.xml - setup scripts not pre-staged."

            }

        } catch {

            & $Log "Warning: could not pre-stage setup scripts from autounattend.xml: $_"

        }



        if ($ISOContentsDir -and (Test-Path $ISOContentsDir)) {

            $isoDest = Join-Path $ISOContentsDir "autounattend.xml"

            Set-Content -Path $isoDest -Value $normalizedAutoUnattendXml -Encoding UTF8 -Force

            & $Log "Written autounattend.xml to ISO root ($isoDest)."

        }

    } else {

        & $Log "Warning: autounattend.xml content is empty - skipping OOBE bypass file."

    }



    & $Log "Disabling reserved storage..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'



    & $Log "Disabling BitLocker device encryption..."

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'



    & $Log "Disabling Chat icon..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'



    & $Log "Disabling OneDrive folder backup..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 'REG_DWORD' '1'



    & $Log "Disabling telemetry..."

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection'  'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'



    & $Log "Preventing installation of DevHome and Outlook..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate'      'workCompleted' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate'      'workCompleted' 'REG_DWORD' '1'

    Remove-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'

    Remove-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'



    & $Log "Disabling Copilot..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'      'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer'       'DisableSearchBoxSuggestions' 'REG_DWORD' '1'



    & $Log "Disabling Windows Update during OOBE (re-enabled on first logon via FirstLogon.ps1)..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'              'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions'                 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer'               'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'    'DisableWindowsUpdateAccess' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'    'WUServer'                  'REG_SZ'    'http://localhost:8080'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'    'WUStatusServer'            'REG_SZ'    'http://localhost:8080'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\WindowsUpdate' 'workCompleted' 'REG_DWORD' '1'

    Remove-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\WindowsUpdate'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\BITS'         'Start' 'REG_DWORD' '4'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv'     'Start' 'REG_DWORD' '4'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc'       'Start' 'REG_DWORD' '4'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSvc' 'Start' 'REG_DWORD' '4'



    & $Log "Preventing installation of Teams..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'



    & $Log "Preventing installation of new Outlook..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'



    & $Log "Unloading offline registry hives..."

    reg unload HKLM\zCOMPONENTS

    reg unload HKLM\zDEFAULT

    reg unload HKLM\zNTUSER

    reg unload HKLM\zSOFTWARE

    reg unload HKLM\zSYSTEM



    # ?????? 5. Delete scheduled task definition files ???????????????????????????????????????????????????????????????????????????????????????

    & $Log "Deleting scheduled task definition files..."

    $tasksPath = "$ScratchDir\Windows\System32\Tasks"

    Remove-Item "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program"                  -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater"               -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Chkdsk\Proxy"                                            -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting"                  -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\InstallService"                                          -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\UpdateOrchestrator"                                      -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\UpdateAssistant"                                         -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\WaaSMedic"                                               -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\WindowsUpdate"                                           -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\WindowsUpdate"                                                   -Recurse -Force -ErrorAction SilentlyContinue

    & $Log "Scheduled task files deleted."



    # ?????? 6. Remove ISO support folder ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

    if ($ISOContentsDir -and (Test-Path $ISOContentsDir)) {

        & $Log "Removing ISO support\ folder..."

        Remove-Item -Path (Join-Path $ISOContentsDir "support") -Recurse -Force -ErrorAction SilentlyContinue

        & $Log "ISO support\ folder removed."

    }

}

function Invoke-ClarkISORefreshUSBDrives {

    $combo    = $sync["WPFWin11ISOUSBDriveComboBox"]

    $removable = @(Get-Disk | Where-Object { $_.BusType -eq "USB" } | Sort-Object Number)



    $combo.Items.Clear()



    if ($removable.Count -eq 0) {

        $combo.Items.Add("No USB drives detected.")

        $combo.SelectedIndex = 0

        $sync["Win11ISOUSBDisks"] = @()

        Write-Win11ISOLog "No USB drives detected."

        return

    }



    foreach ($disk in $removable) {

        $sizeGB = [math]::Round($disk.Size / 1GB, 1)

        $combo.Items.Add("Disk $($disk.Number): $($disk.FriendlyName)  [$sizeGB GB] - $($disk.PartitionStyle)")

    }

    $combo.SelectedIndex = 0

    Write-Win11ISOLog "Found $($removable.Count) USB drive(s)."

    $sync["Win11ISOUSBDisks"] = $removable

}



function Invoke-ClarkISOWriteUSB {

    $contentsDir = $sync["Win11ISOContentsDir"]

    $usbDisks    = $sync["Win11ISOUSBDisks"]



    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {

        [System.Windows.MessageBox]::Show("No modified ISO content found. Please complete Steps 1-3 first.", "Not Ready", "OK", "Warning")

        return

    }



    $combo = $sync["WPFWin11ISOUSBDriveComboBox"]

    $selectedIndex = $combo.SelectedIndex

    $selectedItemText = [string]$combo.SelectedItem

    $usbDisks = @($usbDisks)



    $targetDisk = $null

    if ($selectedIndex -ge 0 -and $selectedIndex -lt $usbDisks.Count) {

        $targetDisk = $usbDisks[$selectedIndex]

    } elseif ($selectedItemText -match 'Disk\s+(\d+):') {

        $selectedDiskNum = [int]$matches[1]

        $targetDisk = $usbDisks | Where-Object { $_.Number -eq $selectedDiskNum } | Select-Object -First 1

    }



    if (-not $targetDisk) {

        [System.Windows.MessageBox]::Show("Please select a USB drive from the dropdown.", "No Drive Selected", "OK", "Warning")

        return

    }



    $diskNum    = $targetDisk.Number

    $sizeGB     = [math]::Round($targetDisk.Size / 1GB, 1)



    $confirm = [System.Windows.MessageBox]::Show(

        "ALL data on Disk $diskNum ($($targetDisk.FriendlyName), $sizeGB GB) will be PERMANENTLY ERASED.`n`nAre you sure you want to continue?",

        "Confirm USB Erase", "YesNo", "Warning")



    if ($confirm -ne "Yes") {

        Write-Win11ISOLog "USB write cancelled by user."

        return

    }



    $sync["WPFWin11ISOWriteUSBButton"].IsEnabled = $false

    Write-Win11ISOLog "Starting USB write to Disk $diskNum..."



    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()

    $runspace.ApartmentState = "STA"

    $runspace.ThreadOptions  = "ReuseThread"

    $runspace.Open()

    $getLogDefUsb  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"

    $logCoreDefUsb = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"



    $runspace.SessionStateProxy.SetVariable("sync",        $sync)

    $runspace.SessionStateProxy.SetVariable("diskNum",     $diskNum)

    $runspace.SessionStateProxy.SetVariable("contentsDir", $contentsDir)

    $runspace.SessionStateProxy.SetVariable("getLogDef",   $getLogDefUsb)

    $runspace.SessionStateProxy.SetVariable("logCoreDef",  $logCoreDefUsb)



    $script = [Management.Automation.PowerShell]::Create()

    $script.Runspace = $runspace

    $script.AddScript({

        . ([scriptblock]::Create($getLogDef))

        . ([scriptblock]::Create($logCoreDef))



        function Log($msg) {

            $ts = (Get-Date).ToString("HH:mm:ss")

            Write-Win11ISOLogCore -Line "[$ts] $msg"

        }



        function SetProgress($label, $pct) {

            $win = $sync["Form"]

            if (-not $win) { return }

            $sync["_isoUiProgLabel"] = $label

            $sync["_isoUiProgPct"]   = $pct

            $win.Dispatcher.Invoke([System.Action]{

                $lbl = [string]$sync["_isoUiProgLabel"]

                $pc  = [int]$sync["_isoUiProgPct"]

                if ($sync.progressBarTextBlock) {

                    $sync.progressBarTextBlock.Text    = $lbl

                    $sync.progressBarTextBlock.ToolTip = $lbl

                }

                if ($sync.ProgressBar) {

                    if ($pc -le 0) {

                        $sync.ProgressBar.Value = 0

                    } else {

                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)

                    }

                }

            })

        }



        function Get-FreeDriveLetter {

            $used = (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name

            foreach ($c in [char[]](68..90)) {

                if ($used -notcontains [string]$c) { return $c }

            }

            return $null

        }



        try {

            SetProgress "Formatting USB drive..." 10



            # Phase 1: Clean disk via diskpart (retry once if the drive is not yet ready)

            $dpFile1 = Join-Path $env:TEMP "clark_diskpart_$(Get-Random).txt"

            "select disk $diskNum`nclean`nexit" | Set-Content -Path $dpFile1 -Encoding ASCII

            Log "Running diskpart clean on Disk $diskNum..."

            $dpCleanOut = diskpart /s $dpFile1 2>&1

            $dpCleanOut | Where-Object { $_ -match '\S' } | ForEach-Object { Log "  diskpart: $_" }

            Remove-Item $dpFile1 -Force -ErrorAction SilentlyContinue



            if (($dpCleanOut -join ' ') -match 'device is not ready') {

                Log "Disk $diskNum was not ready; waiting 5 seconds and retrying clean..."

                Start-Sleep -Seconds 5

                Update-Disk -Number $diskNum -ErrorAction SilentlyContinue

                $dpFile1b = Join-Path $env:TEMP "clark_diskpart_$(Get-Random).txt"

                "select disk $diskNum`nclean`nexit" | Set-Content -Path $dpFile1b -Encoding ASCII

                diskpart /s $dpFile1b 2>&1 | Where-Object { $_ -match '\S' } | ForEach-Object { Log "  diskpart: $_" }

                Remove-Item $dpFile1b -Force -ErrorAction SilentlyContinue

            }



            # Phase 2: Initialize as GPT

            Start-Sleep -Seconds 2

            Update-Disk -Number $diskNum -ErrorAction SilentlyContinue

            $diskObj = Get-Disk -Number $diskNum -ErrorAction Stop

            if ($diskObj.PartitionStyle -eq 'RAW') {

                Initialize-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction Stop

                Log "Disk $diskNum initialized as GPT."

            } else {

                Set-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction Stop

                Log "Disk $diskNum converted to GPT (was $($diskObj.PartitionStyle))."

            }



            # Phase 3: Create FAT32 partition via diskpart, then format with Format-Volume

            # (diskpart's 'format' command can fail with "no volume selected" on fresh/never-formatted drives)

            $volLabel = "W11-" + (Get-Date).ToString('yyMMdd')

            $dpFile2  = Join-Path $env:TEMP "clark_diskpart2_$(Get-Random).txt"

            $maxFat32PartitionMB = 32768

            $diskSizeMB = [int][Math]::Floor((Get-Disk -Number $diskNum -ErrorAction Stop).Size / 1MB)

            $createPartitionCommand = "create partition primary"

            if ($diskSizeMB -gt $maxFat32PartitionMB) {

                $createPartitionCommand = "create partition primary size=$maxFat32PartitionMB"

                Log "Disk $diskNum is $diskSizeMB MB; creating FAT32 partition capped at $maxFat32PartitionMB MB (32 GB)."

            }



            @(

                "select disk $diskNum"

                $createPartitionCommand

                "exit"

            ) | Set-Content -Path $dpFile2 -Encoding ASCII

            Log "Creating partitions on Disk $diskNum..."

            diskpart /s $dpFile2 2>&1 | Where-Object { $_ -match '\S' } | ForEach-Object { Log "  diskpart: $_" }

            Remove-Item $dpFile2 -Force -ErrorAction SilentlyContinue



            SetProgress "Formatting USB partition..." 25

            Start-Sleep -Seconds 3

            Update-Disk -Number $diskNum -ErrorAction SilentlyContinue



            $partitions = Get-Partition -DiskNumber $diskNum -ErrorAction Stop

            Log "Partitions on Disk $diskNum after creation: $($partitions.Count)"

            foreach ($p in $partitions) {

                Log "  Partition $($p.PartitionNumber)  Type=$($p.Type)  Letter=$($p.DriveLetter)  Size=$([math]::Round($p.Size/1MB))MB"

            }



            $winpePart = $partitions | Where-Object { $_.Type -eq "Basic" } | Select-Object -Last 1

            if (-not $winpePart) {

                throw "Could not find the Basic partition on Disk $diskNum after creation."

            }



            # Format using Format-Volume (reliable on fresh drives; diskpart format fails

            # with 'no volume selected' when the partition has never been formatted before)

            Log "Formatting Partition $($winpePart.PartitionNumber) as FAT32 (label: $volLabel)..."

            Get-Partition -DiskNumber $diskNum -PartitionNumber $winpePart.PartitionNumber |

                Format-Volume -FileSystem FAT32 -NewFileSystemLabel $volLabel -Force -Confirm:$false | Out-Null

            Log "Partition $($winpePart.PartitionNumber) formatted as FAT32."



            SetProgress "Assigning drive letters..." 30

            Start-Sleep -Seconds 2

            Update-Disk -Number $diskNum -ErrorAction SilentlyContinue



            try { Remove-PartitionAccessPath -DiskNumber $diskNum -PartitionNumber $winpePart.PartitionNumber -AccessPath "$($winpePart.DriveLetter):" -ErrorAction SilentlyContinue } catch {}

            $usbLetter = Get-FreeDriveLetter

            if (-not $usbLetter) { throw "No free drive letters (D-Z) available to assign to the USB data partition." }

            Set-Partition -DiskNumber $diskNum -PartitionNumber $winpePart.PartitionNumber -NewDriveLetter $usbLetter

            Log "Assigned drive letter $usbLetter to WINPE partition (Partition $($winpePart.PartitionNumber))."

            Start-Sleep -Seconds 2



            $usbDrive = "${usbLetter}:"

            $retries = 0

            while (-not (Test-Path $usbDrive) -and $retries -lt 6) {

                $retries++

                Log "Waiting for $usbDrive to become accessible (attempt $retries/6)..."

                Start-Sleep -Seconds 2

            }

            if (-not (Test-Path $usbDrive)) { throw "Drive $usbDrive is not accessible after letter assignment." }

            Log "USB data partition: $usbDrive"



            $contentSizeBytes = (Get-ChildItem -LiteralPath $contentsDir -File -Recurse -Force -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum

            if (-not $contentSizeBytes) { $contentSizeBytes = 0 }

            $usbVolume = Get-Volume -DriveLetter $usbLetter -ErrorAction Stop

            $partitionCapacityBytes = [int64]$usbVolume.Size

            $partitionFreeBytes = [int64]$usbVolume.SizeRemaining



            $contentSizeGB = [math]::Round($contentSizeBytes / 1GB, 2)

            $partitionCapacityGB = [math]::Round($partitionCapacityBytes / 1GB, 2)

            $partitionFreeGB = [math]::Round($partitionFreeBytes / 1GB, 2)



            Log "Source content size: $contentSizeGB GB. USB partition capacity: $partitionCapacityGB GB, free: $partitionFreeGB GB."



            if ($contentSizeBytes -gt $partitionCapacityBytes) {

                throw "ISO content ($contentSizeGB GB) is larger than the USB partition capacity ($partitionCapacityGB GB). Use a larger USB drive or reduce image size."

            }



            if ($contentSizeBytes -gt $partitionFreeBytes) {

                throw "Insufficient free space on USB partition. Required: $contentSizeGB GB, available: $partitionFreeGB GB."

            }



            SetProgress "Copying Windows setup files to USB..." 45



            # Copy files; split install.wim if > 4 GB (FAT32 limit)

            $installWim = Join-Path $contentsDir "sources\install.wim"

            if (Test-Path $installWim) {

                $wimSizeMB = [math]::Round((Get-Item $installWim).Length / 1MB)

                if ($wimSizeMB -gt 3800) {

                    Log "install.wim is $wimSizeMB MB - splitting for FAT32 compatibility... This will take several minutes."

                    $splitDest = Join-Path $usbDrive "sources\install.swm"

                    New-Item -ItemType Directory -Path (Split-Path $splitDest) -Force | Out-Null

                    Split-WindowsImage -ImagePath $installWim -SplitImagePath $splitDest -FileSize 3800 -CheckIntegrity

                    Log "install.wim split complete."

                    Log "Copying remaining files to USB..."

                    & robocopy $contentsDir $usbDrive /E /XF install.wim /NFL /NDL /NJH /NJS

                } else {

                    & robocopy $contentsDir $usbDrive /E /NFL /NDL /NJH /NJS

                }

            } else {

                & robocopy $contentsDir $usbDrive /E /NFL /NDL /NJH /NJS

            }



            SetProgress "Finalising USB drive..." 90

            Log "Files copied to USB."

            SetProgress "USB write complete" 100

            Log "USB drive is ready for use."



            $sync["Form"].Dispatcher.Invoke([System.Action]{

                [System.Windows.MessageBox]::Show(

                    "USB drive created successfully!`n`nYou can now boot from this drive to install Windows.",

                    "USB Ready", "OK", "Info")

            })

        } catch {

            Log "ERROR during USB write: $_"

            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"

            $sync["Form"].Dispatcher.Invoke([System.Action]{

                $m = [string]$sync["__isoLastErrorMessage"]

                [System.Windows.MessageBox]::Show("USB write failed:`n`n$m", "USB Write Error", "OK", "Error")

            })

        } finally {

            Start-Sleep -Milliseconds 800

            $sync["Form"].Dispatcher.Invoke([System.Action]{

                $sync.progressBarTextBlock.Text    = ""

                $sync.progressBarTextBlock.ToolTip = ""

                $sync.ProgressBar.Value            = 0

                $sync["WPFWin11ISOWriteUSBButton"].IsEnabled = $true

            })

        }

    }) | Out-Null



    $script.BeginInvoke() | Out-Null

}

function Get-ClarkProfileDocument {

    <#

    .SYNOPSIS

        Builds a versioned profile object for JSON export (apps, tweaks, toggles, features).

    #>

    [ordered]@{

        schema       = 1

        clarkVersion = [string]$sync.version

        apps         = @($sync.selectedApps | ForEach-Object { [string]$_ })

        tweaks       = @($sync.selectedTweaks | ForEach-Object { [string]$_ })

        toggles      = @($sync.selectedToggles | ForEach-Object { [string]$_ })

        features     = @($sync.selectedFeatures | ForEach-Object { [string]$_ })

    }

}



function Invoke-ClarkProfileExportToPath {

    param(

        [Parameter(Mandatory)]

        [string]$LiteralPath

    )

    $doc = Get-ClarkProfileDocument

    ($doc | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $LiteralPath -Encoding UTF8

}



function Invoke-ClarkProfileImportFromObject {

    <#

    .SYNOPSIS

        Applies profile data from ConvertFrom-Json (flat array or schema document).

    #>

    param(

        [Parameter(Mandatory)]

        $ProfileObject

    )

    Update-ClarkSelections -flatJson $ProfileObject

}

function Get-ClarkClarkBackupsDirectory {

    $d = Join-Path $env:USERPROFILE "Clark\Backups"

    if (-not (Test-Path -LiteralPath $d)) {

        New-Item -ItemType Directory -Path $d -Force | Out-Null

    }

    return $d

}



function Invoke-ClarkPreTweakRegistryExport {

    <#

    .SYNOPSIS

        Exports HKCU and HKLM to timestamped .reg files before applying tweaks.

    .NOTES

        Coarse safety net only. Per-tweak undo remains Save-ClarkRollbackSnapshot / rollback journal.

    #>

    [CmdletBinding()]

    param()



    $dir = Get-ClarkClarkBackupsDirectory

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



function Test-ClarkRegistryBackupThrottle {

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



function Invoke-ClarkPreTweakRegistryExportIfNeeded {

    <#

    .SYNOPSIS

        Exports registry backup unless a recent backup exists (toggle spam guard).

    #>

    param(

        [switch]$Force

    )

    if (-not $Force -and (Test-ClarkRegistryBackupThrottle -Seconds 120)) {

        return $null

    }

    $out = Invoke-ClarkPreTweakRegistryExport

    $sync.LastPreTweakRegistryBackupUtc = [datetime]::UtcNow

    return $out

}



function Get-ClarkRegistryBackupFiles {

    $dir = Get-ClarkClarkBackupsDirectory

    if (-not (Test-Path -LiteralPath $dir)) {

        return @()

    }

    return Get-ChildItem -LiteralPath $dir -Filter "pre-tweak-*.reg" -File -ErrorAction SilentlyContinue |

        Sort-Object LastWriteTime -Descending

}



function Invoke-ClarkRegistryBackupRestore {

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

function Invoke-ClarkScript {

    <#



    .SYNOPSIS

        Invokes the provided scriptblock. Intended for things that can't be handled with the other functions.



    .PARAMETER Name

        The name of the scriptblock being invoked



    .PARAMETER scriptblock

        The scriptblock to be invoked



    .EXAMPLE

        $Scriptblock = [scriptblock]::Create({"Write-output 'Hello World'"})

        Invoke-ClarkScript -ScriptBlock $scriptblock -Name "Hello World"



    #>

    param (

        $Name,

        [scriptblock]$scriptblock

    )



    try {

        Write-Host "Running Script for $Name"

        Invoke-Command $scriptblock -ErrorAction Stop

    } catch [System.Management.Automation.CommandNotFoundException] {

        Write-Warning "The specified command was not found."

        Write-Warning $PSItem.Exception.message

    } catch [System.Management.Automation.RuntimeException] {

        Write-Warning "A runtime exception occurred."

        Write-Warning $PSItem.Exception.message

    } catch [System.Security.SecurityException] {

        Write-Warning "A security exception occurred."

        Write-Warning $PSItem.Exception.message

    } catch [System.UnauthorizedAccessException] {

        Write-Warning "Access denied. You do not have permission to perform this operation."

        Write-Warning $PSItem.Exception.message

    } catch {

        # Generic catch block to handle any other type of exception

        Write-Warning "Unable to run script for $Name due to unhandled exception."

        Write-Warning $psitem.Exception.StackTrace

    }



}

Function Invoke-ClarkSponsors {

    <#

    .SYNOPSIS

        Lists Sponsors from ChrisTitusTech

    .DESCRIPTION

        Lists Sponsors from ChrisTitusTech

    .EXAMPLE

        Invoke-ClarkSponsors

    .NOTES

        This function is used to list sponsors from ChrisTitusTech

    #>

    try {

        # Define the URL and headers

        $url = "https://github.com/sponsors/ChrisTitusTech"

        $headers = @{

            "User-Agent" = "Chrome/58.0.3029.110"

        }



        # Fetch the webpage content

        try {

            $html = Invoke-RestMethod -Uri $url -Headers $headers

        } catch {

            Write-Output $_.Exception.Message

            exit

        }



        # Use regex to extract the content between "Current sponsors" and "Past sponsors"

        $currentSponsorsPattern = '(?s)(?<=Current sponsors).*?(?=Past sponsors)'

        $currentSponsorsHtml = [regex]::Match($html, $currentSponsorsPattern).Value



        # Use regex to extract the sponsor usernames from the alt attributes in the "Current Sponsors" section

        $sponsorPattern = '(?<=alt="@)[^"]+'

        $sponsors = [regex]::Matches($currentSponsorsHtml, $sponsorPattern) | ForEach-Object { $_.Value }



        # Exclude "ChrisTitusTech" from the sponsors

        $sponsors = $sponsors | Where-Object { $_ -ne "ChrisTitusTech" }



        # Return the sponsors

        return $sponsors

    } catch {

        Write-Error "An error occurred while fetching or processing the sponsors: $_"

        return $null

    }

}

function Invoke-ClarkSSHServer {

    <#

    .SYNOPSIS

        Enables OpenSSH server to remote into your windows device

    #>



    # Install the OpenSSH Server feature if not already installed

    if ((Get-WindowsCapability -Name OpenSSH.Server -Online).State -ne "Installed") {

        Write-Host "Enabling OpenSSH Server... This will take a long time"

        Add-WindowsCapability -Name OpenSSH.Server -Online

    }



    Write-Host "Starting the services"



    Set-Service -Name sshd -StartupType Automatic

    Start-Service -Name sshd



    Set-Service -Name ssh-agent -StartupType Automatic

    Start-Service -Name ssh-agent



    #Adding Firewall rule for port 22

    Write-Host "Setting up firewall rules"

    if (-not ((Get-NetFirewallRule -Name 'sshd').Enabled)) {

        New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

        Write-Host "Firewall rule for OpenSSH Server created and enabled."

    }



    # Check for the authorized_keys file

    $sshFolderPath = "$Home\.ssh"

    $authorizedKeysPath = "$sshFolderPath\authorized_keys"



    if (-not (Test-Path -Path $sshFolderPath)) {

        Write-Host "Creating ssh directory..."

        New-Item -Path $sshFolderPath -ItemType Directory -Force

    }



    if (-not (Test-Path -Path $authorizedKeysPath)) {

        Write-Host "Creating authorized_keys file..."

        New-Item -Path $authorizedKeysPath -ItemType File -Force

        Write-Host "authorized_keys file created at $authorizedKeysPath."

    }



    Write-Host "Configuring sshd_config for standard authorized_keys behavior..."

    $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"



    $configContent = Get-Content -Path $sshdConfigPath -Raw



    $updatedContent = $configContent -replace '(?m)^(Match Group administrators)$', '# $1'

    $updatedContent = $updatedContent -replace '(?m)^(\s+AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys)$', '# $1'



    if ($updatedContent -ne $configContent) {

        Set-Content -Path $sshdConfigPath -Value $updatedContent -Force

        Write-Host "Commented out administrator-specific SSH key configuration in sshd_config"

        Restart-Service -Name sshd -Force

    }



    Write-Host "OpenSSH server was successfully enabled."

    Write-Host "The config file can be located at C:\ProgramData\ssh\sshd_config"

    Write-Host "Add your public keys to this file -> $authorizedKeysPath"

}

function Invoke-ClarkThemeChange {

    <#

    .SYNOPSIS

        Toggles between light and dark themes for a Windows utility application.



    .DESCRIPTION

        This function toggles the theme of the user interface between 'Light' and 'Dark' modes,

        modifying various UI elements such as colors, margins, corner radii, font families, etc.

        If the '-init' switch is used, it initializes the theme based on the system's current dark mode setting.



    .EXAMPLE

        Invoke-ClarkThemeChange

        # Toggles the theme between 'Light' and 'Dark'.





    #>

    param (

        [string]$theme = "Auto"

    )



    function Set-ClarkTheme {

        <#

        .SYNOPSIS

            Applies the specified theme to the application's user interface.



        .DESCRIPTION

            This internal function applies the given theme by setting the relevant properties

            like colors, font families, corner radii, etc., in the UI. It uses the

            'Set-ThemeResourceProperty' helper function to modify the application's resources.



        .PARAMETER currentTheme

            The name of the theme to be applied. Common values are "Light", "Dark", or "shared".

        #>

        param (

            [string]$currentTheme

        )



        function Set-ThemeResourceProperty {

            <#

            .SYNOPSIS

                Sets a specific UI property in the application's resources.



            .DESCRIPTION

                This helper function sets a property (e.g., color, margin, corner radius) in the

                application's resources, based on the provided type and value. It includes

                error handling to manage potential issues while setting a property.



            .PARAMETER Name

                The name of the resource property to modify (e.g., "MainBackgroundColor", "ButtonBackgroundMouseoverColor").



            .PARAMETER Value

                The value to assign to the resource property (e.g., "#FFFFFF" for a color).



            .PARAMETER Type

                The type of the resource, such as "ColorBrush", "CornerRadius", "GridLength", or "FontFamily".

            #>

            param($Name, $Value, $Type)

            try {

                # Set the resource property based on its type

                $sync.Form.Resources[$Name] = switch ($Type) {

                    "ColorBrush" { [Windows.Media.SolidColorBrush]::new($Value) }

                    "Color" {

                        # Convert hex string to RGB values

                        $hexColor = $Value.TrimStart("#")

                        $r = [Convert]::ToInt32($hexColor.Substring(0,2), 16)

                        $g = [Convert]::ToInt32($hexColor.Substring(2,2), 16)

                        $b = [Convert]::ToInt32($hexColor.Substring(4,2), 16)

                        [Windows.Media.Color]::FromRgb($r, $g, $b)

                    }

                    "CornerRadius" { [System.Windows.CornerRadius]::new($Value) }

                    "GridLength" { [System.Windows.GridLength]::new($Value) }

                    "Thickness" {

                        # Parse the Thickness value (supports 1, 2, or 4 inputs)

                        $values = $Value -split ","

                        switch ($values.Count) {

                            1 { [System.Windows.Thickness]::new([double]$values[0]) }

                            2 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1]) }

                            4 { [System.Windows.Thickness]::new([double]$values[0], [double]$values[1], [double]$values[2], [double]$values[3]) }

                        }

                    }

                    "FontFamily" { [Windows.Media.FontFamily]::new($Value) }

                    "Double" { [double]$Value }

                    default { $Value }

                }

            } catch {

                # Log a warning if there's an issue setting the property

                Write-Warning "Failed to set property $($Name): $_"

            }

        }



        # Retrieve all theme properties from the theme configuration

        $themeProperties = $sync.configs.themes.$currentTheme.PSObject.Properties

        foreach ($_ in $themeProperties) {

            # Apply properties that deal with colors

            if ($_.Name -like "*color*") {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "ColorBrush"

                # For certain color properties, also set complementary values (e.g., BorderColor -> CBorderColor) This is required because e.g DropShadowEffect requires a <Color> and not a <SolidColorBrush> object

                if ($_.Name -in @("BorderColor", "ButtonBackgroundMouseoverColor")) {

                    Set-ThemeResourceProperty -Name "C$($_.Name)" -Value $_.Value -Type "Color"

                }

            }

            # Apply corner radius properties

            elseif ($_.Name -like "*Radius*") {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "CornerRadius"

            }

            # Apply row height properties

            elseif ($_.Name -like "*RowHeight*") {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "GridLength"

            }

            # Apply thickness or margin properties

            elseif (($_.Name -like "*Thickness*") -or ($_.Name -like "*margin")) {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "Thickness"

            }

            # Apply font family properties

            elseif ($_.Name -like "*FontFamily*") {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "FontFamily"

            }

            # Apply any other properties as doubles (numerical values)

            else {

                Set-ThemeResourceProperty -Name $_.Name -Value $_.Value -Type "Double"

            }

        }

    }



    $sync.preferences.theme = $theme

    Set-Preferences -save

    Set-ClarkTheme -currentTheme "shared"



    switch ($sync.preferences.theme) {

        "Auto" {

            $systemUsesDarkMode = Get-ClarkToggleStatus WPFToggleDarkMode

            if ($systemUsesDarkMode) {

                $theme = "Dark"

            } else {

                $theme = "Light"

            }



            Set-ClarkTheme -currentTheme $theme

            $themeButtonIcon = [char]0xF08C

        }

        "Dark" {

            Set-ClarkTheme -currentTheme $sync.preferences.theme

            $themeButtonIcon = [char]0xE708

           }

        "Light" {

            Set-ClarkTheme -currentTheme $sync.preferences.theme

            $themeButtonIcon = [char]0xE706

        }

    }



    # Set FOSS Highlight Color

    $fossEnabled = $true

    if ($sync.WPFToggleFOSSHighlight) {

        $fossEnabled = $sync.WPFToggleFOSSHighlight.IsChecked

    }



    if ($fossEnabled) {

         $sync.Form.Resources["FOSSColor"] = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(76, 175, 80)) # #4CAF50

    } else {

         $sync.Form.Resources["FOSSColor"] = $sync.Form.Resources["MainForegroundColor"]

    }



    # Update the theme selector button with the appropriate icon

    $ThemeButton = $sync.Form.FindName("ThemeButton")

    $ThemeButton.Content = [string]$themeButtonIcon

}

function Invoke-ClarkTweaks {

    <#



    .SYNOPSIS

        Invokes the function associated with each provided checkbox



    .PARAMETER CheckBox

        The checkbox to invoke



    .PARAMETER undo

        Indicates whether to undo the operation contained in the checkbox



    .PARAMETER KeepServiceStartup

        Indicates whether to override the startup of a service with the one given from Clark,

        or to keep the startup of said service, if it was changed by the user, or another program, from its default value.

    #>



    param(

        $CheckBox,

        $undo = $false,

        $KeepServiceStartup = $true

    )



    Write-Debug "Tweaks: $($CheckBox)"

    $executedAction = $false

    $tweakConfig = $sync.configs.tweaks.$CheckBox



    # Skip Windows 11-only tweaks on Windows 10 hosts.

    # This keeps imports/autoruns usable across both OS generations.

    if (-not $sync.ContainsKey("OSBuildNumber")) {

        $buildNumber = [System.Environment]::OSVersion.Version.Build

        try {

            $regBuild = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber

            if ($regBuild -match '^\d+$') {

                $buildNumber = [int]$regBuild

            }

        } catch {

            Write-Debug "Falling back to Environment OS build: $buildNumber"

        }

        $sync.OSBuildNumber = $buildNumber

    }



    $isWindows11OnlyTweak = $false

    if ($tweakConfig -and $tweakConfig.PSObject.Properties.Name -contains "Description") {

        $descriptionText = [string]$tweakConfig.Description

        if (

            $descriptionText -match '\[Windows\s*11\]' -or

            $descriptionText -match 'Windows 11\s+\d{2}H\d+\s+and later' -or

            $descriptionText -match 'Windows 11\s+only'

        ) {

            $isWindows11OnlyTweak = $true

        }

    }



    if ($isWindows11OnlyTweak -and [int]$sync.OSBuildNumber -lt 22000) {

        Write-Warning "Skipping $CheckBox because it requires Windows 11. Current OS build: $($sync.OSBuildNumber)."

        return

    }



    if (-not $undo) {

        Save-ClarkRollbackSnapshot -CheckBox $CheckBox

    }



    if($undo) {

        $Values = @{

            Registry = "OriginalValue"

            ScheduledTask = "OriginalState"

            Service = "OriginalType"

            ScriptType = "UndoScript"

        }



    } else {

        $Values = @{

            Registry = "Value"

            ScheduledTask = "State"

            Service = "StartupType"

            OriginalService = "OriginalType"

            ScriptType = "InvokeScript"

        }

    }

    if($sync.configs.tweaks.$CheckBox.ScheduledTask) {

        $executedAction = $true

        $sync.configs.tweaks.$CheckBox.ScheduledTask | ForEach-Object {

            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.ScheduledTask))"

            Set-ClarkScheduledTask -Name $psitem.Name -State $psitem.$($values.ScheduledTask)

        }

    }

    if($sync.configs.tweaks.$CheckBox.service) {

        $executedAction = $true

        Write-Debug "KeepServiceStartup is $KeepServiceStartup"

        $sync.configs.tweaks.$CheckBox.service | ForEach-Object {

            $changeservice = $true



        # The check for !($undo) is required, without it the script will throw an error for accessing unavailable member, which's the 'OriginalService' Property

            if($KeepServiceStartup -AND !($undo)) {

                try {

                    # Check if the service exists

                    $service = Get-Service -Name $psitem.Name -ErrorAction Stop

                    if(!($service.StartType.ToString() -eq $psitem.$($values.OriginalService))) {

                        Write-Debug "Service $($service.Name) was changed in the past to $($service.StartType.ToString()) from it's original type of $($psitem.$($values.OriginalService)), will not change it to $($psitem.$($values.service))"

                        $changeservice = $false

                    }

                } catch [System.ServiceProcess.ServiceNotFoundException] {

                    Write-Warning "Service $($psitem.Name) was not found."

                }

            }



            if($changeservice) {

                Write-Debug "$($psitem.Name) and state is $($psitem.$($values.service))"

                Set-ClarkService -Name $psitem.Name -StartupType $psitem.$($values.Service)

            }

        }

    }

    if($sync.configs.tweaks.$CheckBox.registry) {

        $executedAction = $true

        $sync.configs.tweaks.$CheckBox.registry | ForEach-Object {

            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.registry))"

            if (($psitem.Path -imatch "hku") -and !(Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {

                $null = (New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS)

                if (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue) {

                    Write-Debug "HKU drive created successfully."

                } else {

                    Write-Debug "Failed to create HKU drive."

                }

            }

            Set-ClarkRegistry -Name $psitem.Name -Path $psitem.Path -Type $psitem.Type -Value $psitem.$($values.registry)

        }

    }

    if($sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {

        $executedAction = $true

        $sync.configs.tweaks.$CheckBox.$($values.ScriptType) | ForEach-Object {

            Write-Debug "$($psitem) and state is $($psitem.$($values.ScriptType))"

            $Scriptblock = [scriptblock]::Create($psitem)

            Invoke-ClarkScript -ScriptBlock $scriptblock -Name $CheckBox

        }

    }



    if(!$undo) {

        if($sync.configs.tweaks.$CheckBox.appx) {

            $sync.configs.tweaks.$CheckBox.appx | ForEach-Object {

                Write-Debug "UNDO $($psitem.Name)"

                Remove-ClarkAPPX -Name $psitem

            }

        }



    }



    if ($undo -and -not $executedAction) {

        Invoke-ClarkRollbackLatest -CheckBox $CheckBox | Out-Null

    }

}

function Invoke-ClarkUninstallPSProfile {

    if (Test-Path ($Profile + '.bak')) {

        Remove-Item $Profile

        Rename-Item ($Profile + '.bak') -NewName $Profile

    } else {

        Remove-Item $Profile

    }



    Write-Host "Successfully uninstalled CTT PowerShell Profile." -ForegroundColor Green

}

function Remove-ClarkAPPX {

    <#



    .SYNOPSIS

        Removes all APPX packages that match the given name



    .PARAMETER Name

        The name of the APPX package to remove



    .EXAMPLE

        Remove-ClarkAPPX -Name "Microsoft.Microsoft3DViewer"



    #>

    param (

        $Name

    )



    Write-Host "Removing $Name"

    Get-AppxPackage $Name -AllUsers | Remove-AppxPackage -AllUsers

    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Name | Remove-AppxProvisionedPackage -Online

}

function Reset-WPFCheckBoxes {

    <#



    .SYNOPSIS

        Set clark checkboxs to match $sync.selected values.

        Should only need to be run if $sync.selected updated outside of UI (i.e. presets or import)



    .PARAMETER doToggles

        Whether or not to set UI toggles. WARNING: they will trigger if altered



    .PARAMETER checkboxfilterpattern

        The Pattern to use when filtering through CheckBoxes, defaults to "**"

        Used to make reset blazingly fast.

    #>



    param (

        [Parameter(position=0)]

        [bool]$doToggles = $false,



        [Parameter(position=1)]

        [string]$checkboxfilterpattern = "**"

    )



    $CheckBoxesToCheck = $sync.selectedApps + $sync.selectedTweaks + $sync.selectedFeatures

    $CheckBoxes = ($sync.GetEnumerator()).where{ $_.Value -is [System.Windows.Controls.CheckBox] -and $_.Name -notlike "WPFToggle*" -and $_.Name -like "$checkboxfilterpattern"}

    Write-Debug "Getting checkboxes to set, number of checkboxes: $($CheckBoxes.Count)"



    if ($CheckBoxesToCheck -ne "") {

        $debugMsg = "CheckBoxes to Check are: "

        $CheckBoxesToCheck | ForEach-Object { $debugMsg += "$_, " }

        $debugMsg = $debugMsg -replace (',\s*$', '')

        Write-Debug "$debugMsg"

    }



    foreach ($CheckBox in $CheckBoxes) {

        $checkboxName = $CheckBox.Key

        if (-not $CheckBoxesToCheck) {

            $sync.$checkBoxName.IsChecked = $false

            continue

        }



        # Check if the checkbox name exists in the flattened JSON hashtable

        if ($CheckBoxesToCheck -contains $checkboxName) {

            # If it exists, set IsChecked to true

            $sync.$checkboxName.IsChecked = $true

            Write-Debug "$checkboxName is checked"

        } else {

            # If it doesn't exist, set IsChecked to false

            $sync.$checkboxName.IsChecked = $false

            Write-Debug "$checkboxName is not checked"

        }

    }



    # Update Installs tab UI values

    $count = $sync.SelectedApps.Count

    $sync.WPFselectedAppsButton.Content = "Selected Apps: $count"

    # On every change, remove all entries inside the Popup Menu. This is done, so we can keep the alphabetical order even if elements are selected in a random way

    $sync.selectedAppsstackPanel.Children.Clear()

    $sync.selectedApps | Foreach-Object { Add-SelectedAppsMenuItem -name $($sync.configs.applicationsHashtable.$_.Content) -key $_ }



    if($doToggles) {

        # Restore toggle switch states from imported config.

        # Only act on toggles that are explicitly listed in the import - toggles absent

        # from the export file were not part of the saved config and should keep whatever

        # state the live system already has (set during UI initialisation via Get-ClarkToggleStatus).

        $importedToggles = $sync.selectedToggles

        $allToggles = $sync.GetEnumerator() | Where-Object { $_.Key -like "WPFToggle*" -and $_.Value -is [System.Windows.Controls.CheckBox] }

        foreach ($toggle in $allToggles) {

            if ($importedToggles -contains $toggle.Key) {

                $sync[$toggle.Key].IsChecked = $true

                Write-Debug "Restoring toggle: $($toggle.Key) = checked"

            }

            # Toggles not present in the import are intentionally left untouched;

            # their current UI state already reflects the real system state.

        }

    }

}

function Set-ClarkDNS {

    <#



    .SYNOPSIS

        Sets DNS servers on selected network adapters (defaults to adapters in Up state).



    .PARAMETER DNSProvider

        Key from dns.json (e.g. Google, Cloudflare), DHCP, or Custom.



    .PARAMETER InterfaceIndex

        Optional list of adapter interface indexes. When omitted, uses all Up adapters unless AllAdapters is set.



    .PARAMETER AllAdapters

        When set, includes every Get-NetAdapter result (not only Up).



    .PARAMETER CustomPrimaryV4

    .PARAMETER CustomSecondaryV4

    .PARAMETER CustomPrimaryV6

    .PARAMETER CustomSecondaryV6

        Used when DNSProvider is Custom.



    .EXAMPLE

        Set-ClarkDNS -DNSProvider "google"



    #>

    param(

        [string]$DNSProvider = "Default",

        [int[]]$InterfaceIndex = $null,

        [switch]$AllAdapters,

        [string]$CustomPrimaryV4,

        [string]$CustomSecondaryV4,

        [string]$CustomPrimaryV6,

        [string]$CustomSecondaryV6

    )



    if ($DNSProvider -eq "Default") {

        return

    }



    $useAddressFamily = $false

    try {

        $cmd = Get-Command Set-DnsClientServerAddress -ErrorAction Stop

        $useAddressFamily = $cmd.Parameters.ContainsKey("AddressFamily")

    } catch {

        $useAddressFamily = $false

    }



    try {

        $allNet = @(Get-NetAdapter -ErrorAction Stop)

        if ($InterfaceIndex -and $InterfaceIndex.Count -gt 0) {

            $Adapters = @($allNet | Where-Object { $InterfaceIndex -contains $_.ifIndex })

        } elseif ($AllAdapters) {

            $Adapters = $allNet

        } else {

            $Adapters = @($allNet | Where-Object { $_.Status -eq "Up" })

        }



        if ($Adapters.Count -eq 0) {

            Write-Warning "No network adapters matched the selection."

            return

        }



        Write-Host "DNS target: $DNSProvider - adapters:"

        Write-Host ($Adapters | Select-Object Name, InterfaceIndex, Status | Format-Table | Out-String)



        foreach ($Adapter in $Adapters) {

            $idx = $Adapter.ifIndex

            if ($DNSProvider -eq "DHCP") {

                if ($useAddressFamily) {

                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ResetServerAddresses -ErrorAction SilentlyContinue

                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ResetServerAddresses -ErrorAction SilentlyContinue

                } else {

                    Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction SilentlyContinue

                }

                continue

            }



            if ($DNSProvider -eq "Custom") {

                $v4 = @($CustomPrimaryV4, $CustomSecondaryV4 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                $v6 = @($CustomPrimaryV6, $CustomSecondaryV6 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

                if ($v4.Count -eq 0 -and $v6.Count -eq 0) {

                    Write-Warning "Custom DNS selected but no addresses were provided."

                    continue

                }

                if ($useAddressFamily) {

                    if ($v4.Count -gt 0) {

                        Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ServerAddresses $v4 -ErrorAction Stop

                    }

                    if ($v6.Count -gt 0) {

                        Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ServerAddresses $v6 -ErrorAction Stop

                    }

                } else {

                    if ($v4.Count -gt 0) {

                        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $v4 -ErrorAction Stop

                    }

                    if ($v6.Count -gt 0) {

                        Write-Warning "IPv6 custom DNS may require a newer DnsClient module (AddressFamily)."

                    }

                }

                continue

            }



            $cfg = $sync.configs.dns.$DNSProvider

            if (-not $cfg) {

                Write-Warning "Unknown DNS provider key: $DNSProvider"

                continue

            }



            $v4p = [string]$cfg.Primary

            $v4s = [string]$cfg.Secondary

            $v6p = if ($cfg.PSObject.Properties.Name -contains "Primary6") { [string]$cfg.Primary6 } else { "" }

            $v6s = if ($cfg.PSObject.Properties.Name -contains "Secondary6") { [string]$cfg.Secondary6 } else { "" }



            if ($useAddressFamily) {

                Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ServerAddresses @($v4p, $v4s) -ErrorAction Stop

                if (-not [string]::IsNullOrWhiteSpace($v6p) -or -not [string]::IsNullOrWhiteSpace($v6s)) {

                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ServerAddresses @($v6p, $v6s) -ErrorAction SilentlyContinue

                }

            } else {

                Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($v4p, $v4s) -ErrorAction Stop

            }

        }

    } catch {

        Write-Warning "Unable to set DNS: $($_.Exception.Message)"

        Write-Warning $_.ScriptStackTrace

    }

}

function Set-ClarkProgressbar{

    <#

    .SYNOPSIS

        This function is used to Update the Progress Bar displayed in the clark GUI.

        It will be automatically hidden if the user clicks something and no process is running

    .PARAMETER Label

        The Text to be overlaid onto the Progress Bar

    .PARAMETER PERCENT

        The percentage of the Progress Bar that should be filled (0-100)

    #>

    param(

        [string]$Label,

        [ValidateRange(0,100)]

        [int]$Percent

    )



    if($PARAM_NOUI) {

        return;

    }



    Invoke-WPFUIThread -ScriptBlock {$sync.progressBarTextBlock.Text = $label}

    Invoke-WPFUIThread -ScriptBlock {$sync.progressBarTextBlock.ToolTip = $label}

    if ($percent -lt 5 ) {

        $percent = 5 # Ensure the progress bar is not empty, as it looks weird

    }

    Invoke-WPFUIThread -ScriptBlock { $sync.ProgressBar.Value = $percent}



}

function Set-ClarkRegistry {

    <#



    .SYNOPSIS

        Modifies the registry based on the given inputs



    .PARAMETER Name

        The name of the key to modify



    .PARAMETER Path

        The path to the key



    .PARAMETER Type

        The type of value to set the key to



    .PARAMETER Value

        The value to set the key to



    .EXAMPLE

        Set-ClarkRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"



    #>

    param (

        $Name,

        $Path,

        $Type,

        $Value

    )



    try {

        if(!(Test-Path 'HKU:\')) {New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS}



        If (!(Test-Path $Path)) {

            Write-Host "$Path was not found. Creating..."

            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null

        }



        if ($Value -ne "<RemoveEntry>") {

            Write-Host "Set $Path\$Name to $Value"

            Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null

        } else {

            Write-Host "Remove $Path\$Name"

            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop | Out-Null

        }

    } catch [System.Security.SecurityException] {

        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception."

    } catch [System.Management.Automation.ItemNotFoundException] {

        Write-Warning $psitem.Exception.ErrorRecord

    } catch [System.UnauthorizedAccessException] {

       Write-Warning $psitem.Exception.Message

    } catch {

        Write-Warning "Unable to set $Name due to unhandled exception."

        Write-Warning $psitem.Exception.StackTrace

    }

}

function Set-ClarkScheduledTask {

    <#



    .SYNOPSIS

        Enables/Disables the provided Scheduled Task



    .PARAMETER Name

        The path to the Scheduled Task



    .PARAMETER State

        The State to set the Task to



    .EXAMPLE

        Set-ClarkScheduledTask -Name "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -State "Disabled"



    #>

    param (

        $Name,

        $State

    )



    try {

        if($State -eq "Disabled") {

            Write-Host "Disabling Scheduled Task $Name"

            Disable-ScheduledTask -TaskName $Name -ErrorAction Stop

        }

        if($State -eq "Enabled") {

            Write-Host "Enabling Scheduled Task $Name"

            Enable-ScheduledTask -TaskName $Name -ErrorAction Stop

        }

    } catch [System.Exception] {

        if($psitem.Exception.Message -like "*The system cannot find the file specified*") {

            Write-Warning "Scheduled Task $Name was not found."

        } else {

            Write-Warning "Unable to set $Name due to unhandled exception."

            Write-Warning $psitem.Exception.Message

        }

    } catch {

        Write-Warning "Unable to run script for $name due to unhandled exception."

        Write-Warning $psitem.Exception.StackTrace

    }

}

Function Set-ClarkService {

    <#



    .SYNOPSIS

        Changes the startup type of the given service



    .PARAMETER Name

        The name of the service to modify



    .PARAMETER StartupType

        The startup type to set the service to



    .EXAMPLE

        Set-ClarkService -Name "HomeGroupListener" -StartupType "Manual"



    #>

    param (

        $Name,

        $StartupType

    )

    try {

        Write-Host "Setting Service $Name to $StartupType"



        # Check if the service exists

        $service = Get-Service -Name $Name -ErrorAction Stop



        # Service exists, proceed with changing properties -- while handling auto delayed start for PWSH 5

        if (($PSVersionTable.PSVersion.Major -lt 7) -and ($StartupType -eq "AutomaticDelayedStart")) {

            sc.exe config $Name start=delayed-auto

        } else {

            $service | Set-Service -StartupType $StartupType -ErrorAction Stop

        }

    } catch [System.ServiceProcess.ServiceNotFoundException] {

        Write-Warning "Service $Name was not found."

    } catch {

        Write-Warning "Unable to set $Name due to unhandled exception."

        Write-Warning $_.Exception.Message

    }



}

function Set-ClarkTaskbaritem {

    <#



    .SYNOPSIS

        Modifies the Taskbaritem of the WPF Form



    .PARAMETER value

        Value can be between 0 and 1, 0 being no progress done yet and 1 being fully completed

        Value does not affect item without setting the state to 'Normal', 'Error' or 'Paused'

        Set-ClarkTaskbaritem -value 0.5



    .PARAMETER state

        State can be 'None' > No progress, 'Indeterminate' > inf. loading gray, 'Normal' > Gray, 'Error' > Red, 'Paused' > Yellow

        no value needed:

        - Set-ClarkTaskbaritem -state "None"

        - Set-ClarkTaskbaritem -state "Indeterminate"

        value needed:

        - Set-ClarkTaskbaritem -state "Error"

        - Set-ClarkTaskbaritem -state "Normal"

        - Set-ClarkTaskbaritem -state "Paused"



    .PARAMETER overlay

        Overlay icon to display on the taskbar item, there are the presets 'None', 'logo' and 'checkmark' or you can specify a path/link to an image file.

        A-SYS_clark logo preset:

        - Set-ClarkTaskbaritem -overlay "logo"

        Checkmark preset:

        - Set-ClarkTaskbaritem -overlay "checkmark"

        Warning preset:

        - Set-ClarkTaskbaritem -overlay "warning"

        No overlay:

        - Set-ClarkTaskbaritem -overlay "None"

        Custom icon (needs to be supported by WPF):

        - Set-ClarkTaskbaritem -overlay "C:\path\to\icon.png"



    .PARAMETER description

        Description to display on the taskbar item preview

        Set-ClarkTaskbaritem -description "This is a description"

    #>

    param (

        [string]$state,

        [double]$value,

        [string]$overlay,

        [string]$description

    )



    if ($value) {

        $sync["Form"].taskbarItemInfo.ProgressValue = $value

    }



    if ($state) {

        switch ($state) {

            'None' { $sync["Form"].taskbarItemInfo.ProgressState = "None" }

            'Indeterminate' { $sync["Form"].taskbarItemInfo.ProgressState = "Indeterminate" }

            'Normal' { $sync["Form"].taskbarItemInfo.ProgressState = "Normal" }

            'Error' { $sync["Form"].taskbarItemInfo.ProgressState = "Error" }

            'Paused' { $sync["Form"].taskbarItemInfo.ProgressState = "Paused" }

            default { throw "[Set-ClarkTaskbarItem] Invalid state" }

        }

    }



    if ($overlay) {

        switch ($overlay) {

            'logo' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["logorender"]

            }

            'checkmark' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["checkmarkrender"]

            }

            'warning' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["warningrender"]

            }

            'None' {

                $sync["Form"].taskbarItemInfo.Overlay = $null

            }

            default {

                if (Test-Path $overlay) {

                    $sync["Form"].taskbarItemInfo.Overlay = $overlay

                }

            }

        }

    }



    if ($description) {

        $sync["Form"].taskbarItemInfo.Description = $description

    }

}

function Set-Preferences{



    param(

        [switch]$save=$false

    )



    # TODO delete this function sometime later

    function Clean-OldPrefs{

        if (Test-Path -Path "$clarkdir\LightTheme.ini") {

            $sync.preferences.theme = "Light"

            Remove-Item -Path "$clarkdir\LightTheme.ini"

        }



        if (Test-Path -Path "$clarkdir\DarkTheme.ini") {

            $sync.preferences.theme = "Dark"

            Remove-Item -Path "$clarkdir\DarkTheme.ini"

        }



        # check old prefs, if its first line has no =, then absorb it as pm

        if (Test-Path -Path $iniPath) {

            $oldPM = Get-Content $iniPath

            if ($oldPM -notlike "*=*") {

                $sync.preferences.packagemanager = $oldPM

            }

        }



        if (Test-Path -Path "$clarkdir\preferChocolatey.ini") {

            $sync.preferences.packagemanager = "Choco"

            Remove-Item -Path "$clarkdir\preferChocolatey.ini"

        }

    }



    function Save-Preferences{

        $ini = ""

        foreach($key in $sync.preferences.Keys) {

            $pref = "$($key)=$($sync.preferences.$key)"

            Write-Debug "Saving pref: $($pref)"

            $ini = $ini + $pref + "`r`n"

        }

        $ini | Out-File $iniPath

    }



    function Load-Preferences{

        Clean-OldPrefs

        if (Test-Path -Path $iniPath) {

            $iniData = Get-Content "$clarkdir\preferences.ini"

            foreach ($line in $iniData) {

                if ($line -like "*=*") {

                    $arr = $line -split "=",-2

                    $key = $arr[0] -replace "\s",""

                    $value = $arr[1] -replace "\s",""

                    Write-Debug "Preference: Key = '$($key)' Value ='$($value)'"

                    $sync.preferences.$key = $value

                }

            }

        }



        # write defaults in case preferences dont exist

        if ($null -eq $sync.preferences.theme) {

            $sync.preferences.theme = "Auto"

        }

        if ($null -eq $sync.preferences.packagemanager) {

            $sync.preferences.packagemanager = "Winget"

        }

        if ($null -eq $sync.preferences.activeprofile) {

            $sync.preferences.activeprofile = ""

        }



        # convert packagemanager to enum

        if ($sync.preferences.packagemanager -eq "Choco") {

            $sync.preferences.packagemanager = [PackageManagers]::Choco

        }

        elseif ($sync.preferences.packagemanager -eq "Winget") {

            $sync.preferences.packagemanager = [PackageManagers]::Winget

        }

    }



    $iniPath = "$clarkdir\preferences.ini"



    if ($save) {

        Save-Preferences

    } else {

        Load-Preferences

    }

}

function Set-WinFormsButtonFullText {
    <#
    .SYNOPSIS
        WinForms Button defaults to a narrow width (~75px), which truncates labels.
        Sets AutoSize so the full caption is visible.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Windows.Forms.Button[]]$Button
    )
    process {
        foreach ($b in $Button) {
            if ($null -eq $b) { continue }
            $b.AutoSize = $true
        }
    }
}
function Show-ASYSItemInfoPopup {
    <#
    .SYNOPSIS
        Shows item description and reference URL in an in-app dialog (no browser on open).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ItemTitle,

        [string]$Description,
        [string]$Link
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $parts.Add($Description.Trim())
    }
    if (-not [string]::IsNullOrWhiteSpace($Link)) {
        $parts.Add("Reference URL:`n$Link")
    }
    $message = if ($parts.Count) {
        $parts -join "`n`n"
    } else {
        "No additional details are available for this item."
    }

    $baseFs = [int]$sync.Form.Resources.CustomDialogFontSize
    $baseHdr = [int]$sync.Form.Resources.CustomDialogFontSizeHeader

    Show-CustomDialog -Title $ItemTitle `
        -HeadingLine $ItemTitle `
        -Message $message `
        -Width 560 `
        -Height 420 `
        -FontSize ($baseFs + 4) `
        -HeaderFontSize ($baseHdr + 4) `
        -EnableScroll $true `
        -HideLogo `
        -ItalicBrandTitle
}
function Show-CustomDialog {

    <#

    .SYNOPSIS

    Displays a custom dialog box with an image, heading, message, and an OK button.



    .DESCRIPTION

    This function creates a custom dialog box with the specified message and additional elements such as an image, heading, and an OK button. The dialog box is designed with a green border, rounded corners, and a black background.



    .PARAMETER Title

    The Title to use for the dialog window's Title Bar, this will not be visible by the user, as window styling is set to None.



    .PARAMETER Message

    The message to be displayed in the dialog box.



    .PARAMETER Width

    The width of the custom dialog window.



    .PARAMETER Height

    The height of the custom dialog window.



    .PARAMETER FontSize

    The Font Size of message shown inside custom dialog window.



    .PARAMETER HeaderFontSize

    The Font Size for the Header of custom dialog window.



    .PARAMETER LogoSize

    The Size of the Logo used inside the custom dialog window.



    .PARAMETER ForegroundColor

    The Foreground Color of dialog window title & message.



    .PARAMETER BackgroundColor

    The Background Color of dialog window.



    .PARAMETER BorderColor

    The Color for dialog window border.



    .PARAMETER ButtonBackgroundColor

    The Background Color for Buttons in dialog window.



    .PARAMETER ButtonForegroundColor

    The Foreground Color for Buttons in dialog window.



    .PARAMETER ShadowColor

    The Color used when creating the Drop-down Shadow effect for dialog window.



    .PARAMETER LogoColor

    The color of the A-SYS_clark title text next to the logo inside the dialog window.



    .PARAMETER LinkForegroundColor

    The Foreground Color for Links inside dialog window.



    .PARAMETER LinkHoverForegroundColor

    The Foreground Color for Links when the mouse pointer hovers over them inside dialog window.



    .PARAMETER EnableScroll

    A flag indicating whether to enable scrolling if the content exceeds the window size.



    .EXAMPLE

    Show-CustomDialog -Title "My Custom Dialog" -Message "This is a custom dialog with a message and an image above." -Width 300 -Height 200



    Makes a new Custom Dialog with the title 'My Custom Dialog' and a message 'This is a custom dialog with a message and an image above.', with dimensions of 300 by 200 pixels.

    Other styling options are grabbed from '$sync.Form.Resources' global variable.



    .EXAMPLE

    $foregroundColor = New-Object System.Windows.Media.SolidColorBrush("#0088e5")

    $backgroundColor = New-Object System.Windows.Media.SolidColorBrush("#1e1e1e")

    $linkForegroundColor = New-Object System.Windows.Media.SolidColorBrush("#0088e5")

    $linkHoverForegroundColor = New-Object System.Windows.Media.SolidColorBrush("#005289")

    Show-CustomDialog -Title "My Custom Dialog" -Message "This is a custom dialog with a message and an image above." -Width 300 -Height 200 -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor -LinkForegroundColor $linkForegroundColor -LinkHoverForegroundColor $linkHoverForegroundColor



    Makes a new Custom Dialog with the title 'My Custom Dialog' and a message 'This is a custom dialog with a message and an image above.', with dimensions of 300 by 200 pixels, with a link foreground (and general foreground) colors of '#0088e5', background color of '#1e1e1e', and Link Color on Hover of '005289', all of which are in Hexadecimal (the '#' Symbol is required by SolidColorBrush Constructor).

    Other styling options are grabbed from '$sync.Form.Resources' global variable.



    #>

    param(

        [string]$Title,

        [string]$Message,

        [int]$Width = $sync.Form.Resources.CustomDialogWidth,

        [int]$Height = $sync.Form.Resources.CustomDialogHeight,



        [System.Windows.Media.FontFamily]$FontFamily = $sync.Form.Resources.FontFamily,

        [int]$FontSize = $sync.Form.Resources.CustomDialogFontSize,

        [int]$HeaderFontSize = $sync.Form.Resources.CustomDialogFontSizeHeader,

        [int]$LogoSize = $sync.Form.Resources.CustomDialogLogoSize,



        [System.Windows.Media.Color]$ShadowColor = "#AAAAAAAA",

        [System.Windows.Media.SolidColorBrush]$LogoColor = $sync.Form.Resources.LabelboxForegroundColor,

        [System.Windows.Media.SolidColorBrush]$BorderColor = $sync.Form.Resources.BorderColor,

        [System.Windows.Media.SolidColorBrush]$ForegroundColor = $sync.Form.Resources.MainForegroundColor,

        [System.Windows.Media.SolidColorBrush]$BackgroundColor = $sync.Form.Resources.MainBackgroundColor,

        [System.Windows.Media.SolidColorBrush]$ButtonForegroundColor = $sync.Form.Resources.ButtonInstallForegroundColor,

        [System.Windows.Media.SolidColorBrush]$ButtonBackgroundColor = $sync.Form.Resources.ButtonInstallBackgroundColor,

        [System.Windows.Media.SolidColorBrush]$LinkForegroundColor = $sync.Form.Resources.LinkForegroundColor,

        [System.Windows.Media.SolidColorBrush]$LinkHoverForegroundColor = $sync.Form.Resources.LinkHoverForegroundColor,



        [bool]$EnableScroll = $false,



        [switch]$HideLogo,

        [switch]$ItalicBrandTitle,

        [string]$HeadingLine

    )



    # Create a custom dialog window

    $dialog = New-Object Windows.Window

    $dialog.Title = $Title

    $dialog.Height = $Height

    $dialog.Width = $Width

    $dialog.Margin = New-Object Windows.Thickness(10)  # Add margin to the entire dialog box

    $dialog.WindowStyle = [Windows.WindowStyle]::None  # Remove title bar and window controls

    $dialog.ResizeMode = [Windows.ResizeMode]::NoResize  # Disable resizing

    $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen  # Center the window

    $dialog.Foreground = $ForegroundColor

    $dialog.Background = $BackgroundColor

    $dialog.FontFamily = $FontFamily

    $dialog.FontSize = $FontSize

    if ($sync.Form) {

        $dialog.Owner = $sync.Form

    }



    # Create a Border for the green edge with rounded corners

    $border = New-Object Windows.Controls.Border

    $border.BorderBrush = $BorderColor

    $border.BorderThickness = New-Object Windows.Thickness(1)  # Adjust border thickness as needed

    $border.CornerRadius = New-Object Windows.CornerRadius(10)  # Adjust the radius for rounded corners



    # Create a drop shadow effect

    $dropShadow = New-Object Windows.Media.Effects.DropShadowEffect

    $dropShadow.Color = $ShadowColor

    $dropShadow.Direction = 270

    $dropShadow.ShadowDepth = 5

    $dropShadow.BlurRadius = 10



    # Apply drop shadow effect to the border

    $dialog.Effect = $dropShadow



    $dialog.Content = $border



    # Create a grid for layout inside the Border

    $grid = New-Object Windows.Controls.Grid

    $border.Child = $grid



    # Uncomment the following line to show gridlines

    #$grid.ShowGridLines = $true



    # Add the following line to set the background color of the grid

    $grid.Background = [Windows.Media.Brushes]::Transparent

    # Add the following line to make the Grid stretch

    $grid.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch

    $grid.VerticalAlignment = [Windows.VerticalAlignment]::Stretch



    # Add the following line to make the Border stretch

    $border.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch

    $border.VerticalAlignment = [Windows.VerticalAlignment]::Stretch



    # Set up Row Definitions

    $row0 = New-Object Windows.Controls.RowDefinition

    $row0.Height = [Windows.GridLength]::Auto



    $row1 = New-Object Windows.Controls.RowDefinition

    $row1.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)



    $row2 = New-Object Windows.Controls.RowDefinition

    $row2.Height = [Windows.GridLength]::Auto



    # Add Row Definitions to Grid

    $grid.RowDefinitions.Add($row0)

    $grid.RowDefinitions.Add($row1)

    $grid.RowDefinitions.Add($row2)



    # Add StackPanel for horizontal layout with margins

    $stackPanel = New-Object Windows.Controls.StackPanel

    $stackPanel.Margin = New-Object Windows.Thickness(10)  # Add margins around the stack panel

    $stackPanel.Orientation = [Windows.Controls.Orientation]::Horizontal

    $stackPanel.HorizontalAlignment = [Windows.HorizontalAlignment]::Left  # Align to the left

    $stackPanel.VerticalAlignment = [Windows.VerticalAlignment]::Top  # Align to the top



    $grid.Children.Add($stackPanel)

    [Windows.Controls.Grid]::SetRow($stackPanel, 0)  # Set the row to the second row (0-based index)



    # Optional vector logo beside brand text

    if (-not $HideLogo) {

        $stackPanel.Children.Add((Invoke-ClarkAssets -Type "logo" -Size $LogoSize)) | Out-Null

    }



    # Header title

    $clarkTextBlock = New-Object Windows.Controls.TextBlock

    $clarkTextBlock.Text = "clark"

    $clarkTextBlock.FontSize = $HeaderFontSize

    $clarkTextBlock.FontStyle = if ($ItalicBrandTitle) { [Windows.FontStyles]::Italic } else { [Windows.FontStyles]::Normal }

    $clarkTextBlock.Foreground = $LogoColor

    $clarkTextBlock.Margin = New-Object Windows.Thickness(10, 10, 10, 5)  # Add margins around the text block

    $stackPanel.Children.Add($clarkTextBlock)

    # Add TextBlock for information with text wrapping and margins

    $messageTextBlock = New-Object Windows.Controls.TextBlock

    $messageTextBlock.FontSize = $FontSize

    $messageTextBlock.TextWrapping = [Windows.TextWrapping]::Wrap  # Enable text wrapping

    $messageTextBlock.HorizontalAlignment = [Windows.HorizontalAlignment]::Left

    $messageTextBlock.VerticalAlignment = [Windows.VerticalAlignment]::Top

    $messageTextBlock.Margin = New-Object Windows.Thickness(10)  # Add margins around the text block



    if (-not [string]::IsNullOrWhiteSpace($HeadingLine)) {

        $headingRun = New-Object Windows.Documents.Run($HeadingLine)

        $headingRun.FontWeight = [Windows.FontWeights]::Bold

        $headingRun.FontSize = [double]$HeaderFontSize + 2

        $messageTextBlock.Inlines.Add($headingRun)

        $messageTextBlock.Inlines.Add([Windows.Documents.LineBreak]::new())

        $messageTextBlock.Inlines.Add([Windows.Documents.LineBreak]::new())

    }



    # Define the Regex to find hyperlinks formatted as HTML <a> tags

    $regex = [regex]::new('<a href="([^"]+)">([^<]+)</a>')

    $lastPos = 0

    $matches = $regex.Matches($Message)



    # Iterate through each match and add regular text and hyperlinks

    foreach ($match in $matches) {

        # Add the text before the hyperlink, if any

        $textBefore = $Message.Substring($lastPos, $match.Index - $lastPos)

        if ($textBefore.Length -gt 0) {

            $messageTextBlock.Inlines.Add((New-Object Windows.Documents.Run($textBefore)))

        }



        # Create and add the hyperlink

        $hyperlink = New-Object Windows.Documents.Hyperlink

        $hyperlink.NavigateUri = New-Object System.Uri($match.Groups[1].Value)

        $hyperlink.Inlines.Add($match.Groups[2].Value)

        $hyperlink.TextDecorations = [Windows.TextDecorations]::None  # Remove underline

        $hyperlink.Foreground = $LinkForegroundColor



        $hyperlink.Add_Click({

            param($sender, $args)

            Start-Process $sender.NavigateUri.AbsoluteUri

        })

        $hyperlink.Add_MouseEnter({

            param($sender, $args)

            $sender.Foreground = $LinkHoverForegroundColor

            $sender.FontSize = ($FontSize + ($FontSize / 4))

            $sender.FontWeight = "SemiBold"

        })

        $hyperlink.Add_MouseLeave({

            param($sender, $args)

            $sender.Foreground = $LinkForegroundColor

            $sender.FontSize = $FontSize

            $sender.FontWeight = "Normal"

        })



        $messageTextBlock.Inlines.Add($hyperlink)



        # Update the last position

        $lastPos = $match.Index + $match.Length

    }



    # Add any remaining text after the last hyperlink (also covers plain text when there are no <a> tags)

    if (-not [string]::IsNullOrEmpty($Message) -and $lastPos -lt $Message.Length) {

        $textAfter = $Message.Substring($lastPos)

        $messageTextBlock.Inlines.Add((New-Object Windows.Documents.Run($textAfter)))

    }



    # Create a ScrollViewer if EnableScroll is true

    if ($EnableScroll) {

        $scrollViewer = New-Object System.Windows.Controls.ScrollViewer

        $scrollViewer.VerticalScrollBarVisibility = 'Auto'

        $scrollViewer.HorizontalScrollBarVisibility = 'Disabled'

        $scrollViewer.Content = $messageTextBlock

        $grid.Children.Add($scrollViewer)

        [Windows.Controls.Grid]::SetRow($scrollViewer, 1)  # Set the row to the second row (0-based index)

    } else {

        $grid.Children.Add($messageTextBlock)

        [Windows.Controls.Grid]::SetRow($messageTextBlock, 1)  # Set the row to the second row (0-based index)

    }



    # Add OK button

    $okButton = New-Object Windows.Controls.Button

    $okButton.Content = "OK"

    $okButton.FontSize = $FontSize

    $okButton.Width = 80

    $okButton.Height = 30

    $okButton.HorizontalAlignment = [Windows.HorizontalAlignment]::Center

    $okButton.VerticalAlignment = [Windows.VerticalAlignment]::Bottom

    $okButton.Margin = New-Object Windows.Thickness(0, 0, 0, 10)

    $okButton.Background = $buttonBackgroundColor

    $okButton.Foreground = $buttonForegroundColor

    $okButton.BorderBrush = $BorderColor

    $okButton.Add_Click({

        $dialog.Close()

    })

    $grid.Children.Add($okButton)

    [Windows.Controls.Grid]::SetRow($okButton, 2)  # Set the row to the third row (0-based index)



    # Handle Escape key press to close the dialog

    $dialog.Add_KeyDown({

        if ($_.Key -eq 'Escape') {

            $dialog.Close()

        }

    })



    # Set the OK button as the default button (activated on Enter)

    $okButton.IsDefault = $true



    # Show the custom dialog

    $dialog.ShowDialog()

}

function Show-WPFInstallAppBusy {
    <#
    .SYNOPSIS
        Displays a busy overlay in the install app area of the WPF form.
        This is used to indicate that an install or uninstall is in progress.
        Dynamically updates the size of the overlay based on the app area on each invocation.
    .PARAMETER text
        The text to display in the busy overlay. Defaults to "Installing apps...".
    #>
    param (
        $text = "Installing apps..."
    )
    Invoke-WPFUIThread -ScriptBlock {
        $sync.InstallAppAreaOverlay.Visibility = [Windows.Visibility]::Visible
        $sync.InstallAppAreaOverlay.Width = $($sync.InstallAppAreaScrollViewer.ActualWidth * 0.4)
        $sync.InstallAppAreaOverlay.Height = $($sync.InstallAppAreaScrollViewer.ActualWidth * 0.4)
        $sync.InstallAppAreaOverlayText.Text = $text
        $sync.InstallAppAreaBorder.IsEnabled = $false
        $sync.InstallAppAreaScrollViewer.Effect.Radius = 5
    }
}
function Test-ClarkPackageManager {

    <#



    .SYNOPSIS

        Checks if WinGet and/or Choco are installed



    .PARAMETER winget

        Check if WinGet is installed



    .PARAMETER choco

        Check if Chocolatey is installed



    #>



    Param(

        [System.Management.Automation.SwitchParameter]$winget,

        [System.Management.Automation.SwitchParameter]$choco

    )



    if ($winget) {

        if (Get-Command winget -ErrorAction SilentlyContinue) {

            Write-Host "===========================================" -ForegroundColor Green

            Write-Host "---        WinGet is installed          ---" -ForegroundColor Green

            Write-Host "===========================================" -ForegroundColor Green

            $status = "installed"

        } else {

            Write-Host "===========================================" -ForegroundColor Red

            Write-Host "---      WinGet is not installed        ---" -ForegroundColor Red

            Write-Host "===========================================" -ForegroundColor Red

            $status = "not-installed"

        }

    }



    if ($choco) {

        if (Get-Command choco -ErrorAction SilentlyContinue) {

            Write-Host "===========================================" -ForegroundColor Green

            Write-Host "---      Chocolatey is installed        ---" -ForegroundColor Green

            Write-Host "===========================================" -ForegroundColor Green

            $status = "installed"

        } else {

            Write-Host "===========================================" -ForegroundColor Red

            Write-Host "---    Chocolatey is not installed      ---" -ForegroundColor Red

            Write-Host "===========================================" -ForegroundColor Red

            $status = "not-installed"

        }

    }



    return $status

}

Function Update-ClarkProgramWinget {



    <#



    .SYNOPSIS

        This will update all programs using WinGet



    #>



    [ScriptBlock]$wingetinstall = {



        $host.ui.RawUI.WindowTitle = """WinGet Install"""



        Start-Transcript "$logdir\winget-update_$dateTime.log" -Append

        winget upgrade --all --accept-source-agreements --accept-package-agreements --scope=machine --silent



    }



    $global:WinGetInstall = Start-Process -Verb runas powershell -ArgumentList "-command invoke-command -scriptblock {$wingetinstall} -argumentlist '$($ProgramsToInstall -join ",")'" -PassThru



}

function Update-ClarkSelections {

    <#



    .SYNOPSIS

        Updates the $sync.selected variables with a given preset.



    .PARAMETER flatJson

        The flattened json list of $sync values to select.

    #>



    param (

        $flatJson

    )



    Write-Debug "JSON to import: $($flatJson)"



    $items = Convert-ClarkProfileInputToList -InputObject $flatJson

    foreach ($item in $items) {

        # Ensure each item is treated as a string to handle PSCustomObject from JSON deserialization

        $cbkey = [string]$item

        $group = if ($cbkey.StartsWith("WPFInstall")) { "Install" }

                    elseif ($cbkey.StartsWith("WPFTweaks")) { "Tweaks" }

                    elseif ($cbkey.StartsWith("WPFToggle")) { "Toggle" }

                    elseif ($cbkey.StartsWith("WPFFeature")) { "Feature" } else { "na" }



        switch ($group) {

            "Install" {

                if (!$sync.selectedApps.Contains($cbkey)) {

                    $sync.selectedApps.Add($cbkey)

                    # The List type needs to be specified again, because otherwise Sort-Object will convert the list to a string if there is only a single entry

                    [System.Collections.Generic.List[string]]$sync.selectedApps = $sync.SelectedApps | Sort-Object

                }

            }

            "Tweaks" {

                if (!$sync.selectedTweaks.Contains($cbkey)) {

                    $sync.selectedTweaks.Add($cbkey)

                }

            }

            "Toggle" {

                if (!$sync.selectedToggles.Contains($cbkey)) {

                    $sync.selectedToggles.Add($cbkey)

                }

            }

            "Feature" {

                if (!$sync.selectedFeatures.Contains($cbkey)) {

                    $sync.selectedFeatures.Add($cbkey)

                }

            }

            default {

                Write-Host "Unknown group for checkbox: $($cbkey)"

            }

        }

    }



    Write-Debug "-------------------------------------"

    Write-Debug "Selected Apps: $($sync.selectedApps)"

    Write-Debug "Selected Tweaks: $($sync.selectedTweaks)"

    Write-Debug "Selected Toggles: $($sync.selectedToggles)"

    Write-Debug "Selected Features: $($sync.selectedFeatures)"

    Write-Debug "--------------------------------------"

}

function Initialize-WPFUI {
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$TargetGridName
    )

    switch ($TargetGridName) {
        "appscategory"{
            # TODO
            # Switch UI generation of the sidebar to this function
            # $sync.ItemsControl = Initialize-InstallAppArea -TargetElement $TargetGridName
            # ...

            # Create and configure a popup for displaying selected apps
            $selectedAppsPopup = New-Object Windows.Controls.Primitives.Popup
            $selectedAppsPopup.IsOpen = $false
            $selectedAppsPopup.PlacementTarget = $sync.WPFselectedAppsButton
            $selectedAppsPopup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
            $selectedAppsPopup.AllowsTransparency = $true

            # Style the popup with a border and background
            $selectedAppsBorder = New-Object Windows.Controls.Border
            $selectedAppsBorder.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, "MainBackgroundColor")
            $selectedAppsBorder.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, "MainForegroundColor")
            $selectedAppsBorder.SetResourceReference([Windows.Controls.Control]::BorderThicknessProperty, "ButtonBorderThickness")
            $selectedAppsBorder.Width = 200
            $selectedAppsBorder.Padding = 5
            $selectedAppsPopup.Child = $selectedAppsBorder
            $sync.selectedAppsPopup = $selectedAppsPopup

            # Add a stack panel inside the popup's border to organize its child elements
            $sync.selectedAppsstackPanel = New-Object Windows.Controls.StackPanel
            $selectedAppsBorder.Child = $sync.selectedAppsstackPanel

            # Close selectedAppsPopup when mouse leaves both button and selectedAppsPopup
            $sync.WPFselectedAppsButton.Add_MouseLeave({
                if (-not $sync.selectedAppsPopup.IsMouseOver) {
                    $sync.selectedAppsPopup.IsOpen = $false
                }
            })
            $selectedAppsPopup.Add_MouseLeave({
                if (-not $sync.WPFselectedAppsButton.IsMouseOver) {
                    $sync.selectedAppsPopup.IsOpen = $false
                }
            })

            # Creates the popup that is displayed when the user right-clicks on an app entry
            # This popup contains buttons for installing, uninstalling, and viewing app information

            $appPopup = New-Object Windows.Controls.Primitives.Popup
            $appPopup.StaysOpen = $false
            $appPopup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
            $appPopup.AllowsTransparency = $true
            # Store the popup globally so the position can be set later
            $sync.appPopup = $appPopup

            $appPopupStackPanel = New-Object Windows.Controls.StackPanel
            $appPopupStackPanel.Orientation = "Horizontal"
            $appPopupStackPanel.Add_MouseLeave({
                $sync.appPopup.IsOpen = $false
            })
            $appPopup.Child = $appPopupStackPanel

            $appButtons = @(
            [PSCustomObject]@{ Name = "Install";    Icon = [char]0xE118 },
            [PSCustomObject]@{ Name = "Uninstall";  Icon = [char]0xE74D },
            [PSCustomObject]@{ Name = "Info";       Icon = [char]0xE946 }
            )
            foreach ($button in $appButtons) {
                $newButton = New-Object Windows.Controls.Button
                $newButton.Style = $sync.Form.Resources.AppEntryButtonStyle
                $newButton.Content = $button.Icon
                $appPopupStackPanel.Children.Add($newButton) | Out-Null

                # Dynamically load the selected app object so the buttons can be reused and do not need to be created for each app
                switch ($button.Name) {
                    "Install" {
                        $newButton.Add_MouseEnter({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            $this.ToolTip = "Install or Upgrade $($appObject.content)"
                        })
                        $newButton.Add_Click({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            Invoke-WPFInstall -PackagesToInstall $appObject
                        })
                    }
                    "Uninstall" {
                        $newButton.Add_MouseEnter({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            $this.ToolTip = "Uninstall $($appObject.content)"
                        })
                        $newButton.Add_Click({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            Invoke-WPFUnInstall -PackagesToUninstall $appObject
                        })
                    }
                    "Info" {
                        $newButton.Add_MouseEnter({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            $this.ToolTip = "Open the application's website in your default browser`n$($appObject.link)"
                        })
                        $newButton.Add_Click({
                            $appObject = $sync.configs.applicationsHashtable.$($sync.appPopupSelectedApp)
                            Start-Process $appObject.link
                        })
                    }
                }
            }
        }
        "appspanel" {
            $sync.ItemsControl = Initialize-InstallAppArea -TargetElement $TargetGridName
            Initialize-InstallCategoryAppList -TargetElement $sync.ItemsControl -Apps $sync.configs.applicationsHashtable
        }
        default {
            Write-Output "$TargetGridName not yet implemented"
        }
    }
}

function Invoke-ClarkAutoRun {

    <#



    .SYNOPSIS

        Runs Install, Tweaks, and Features with optional UI invocation.

    #>



    function BusyWait {

        Start-Sleep -Seconds 5

        while ($sync.ProcessRunning) {

                Start-Sleep -Seconds 5

            }

    }



    BusyWait



    Write-Host "Applying tweaks..."

    Invoke-WPFtweaksbutton

    BusyWait



    Write-Host "Applying toggles..."

    $handle = Invoke-WPFRunspace -ScriptBlock {

        $Toggles = $sync.selectedToggles

        Write-Debug "Inside Number of toggles to process: $($Toggles.Count)"



        $sync.ProcessRunning = $true



        if ($Toggles.Count -gt 0) {

            try {

                $bak = Invoke-ClarkPreTweakRegistryExport

                foreach ($m in @($bak.Messages)) { Write-Host $m }

            } catch {

                Write-Warning "Pre-toggle registry backup failed: $($_.Exception.Message)"

            }

        }



        for ($i = 0; $i -lt $Toggles.Count; $i++) {

            Invoke-ClarkTweaks $Toggles[$i]

        }



        $sync.ProcessRunning = $false

        Write-Host "================================="

        Write-Host "--     Toggles are Finished    ---"

        Write-Host "================================="

    }

    BusyWait



    Write-Host "Applying features..."

    Invoke-WPFFeatureInstall

    BusyWait



    Write-Host "Installing applications..."

    Invoke-WPFInstall

    BusyWait



    Write-Host "Done."

}

function Invoke-ClarkRemoveEdge {

  $Path = Get-ChildItem -Path "$Env:ProgramFiles (x86)\Microsoft\Edge\Application\*\Installer\setup.exe" | Select-Object -First 1



  New-Item -Path "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -Force

  Start-Process -FilePath $Path -ArgumentList '--uninstall --system-level --force-uninstall --delete-profile' -Wait



  Write-Host "Microsoft Edge was removed" -ForegroundColor Green

}

function Invoke-WPFAppRemovalTool {
    <#
    .SYNOPSIS
        List installed programs from registry uninstall keys; uninstall selected or open Programs and Features.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-InstalledProgramsFromRegistry {
        $list = [System.Collections.Generic.List[object]]::new()
        $roots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if (-not $p) { return }
                $name = [string]$p.DisplayName
                if ([string]::IsNullOrWhiteSpace($name)) { return }
                if ($p.SystemComponent -eq 1) { return }
                $quiet = [string]$p.QuietUninstallString
                $loud = [string]$p.UninstallString
                if ([string]::IsNullOrWhiteSpace($quiet) -and [string]::IsNullOrWhiteSpace($loud)) { return }
                [void]$list.Add([pscustomobject]@{
                        DisplayName     = $name
                        Publisher       = [string]$p.Publisher
                        Version         = [string]$p.DisplayVersion
                        QuietUninstall  = $quiet
                        UninstallString = $loud
                    })
            }
        }
        return @($list | Sort-Object DisplayName)
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark - Installed programs & deep clean'
    $form.Size = New-Object System.Drawing.Size(920, 560)
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Dock = 'Top'
    $lbl.Height = 40
    $lbl.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 0)
    $lbl.Text = 'Programs from registry uninstall keys. Uninstall runs the quiet command when available; some installers still show UI. Create a restore point before bulk removals.'

    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Dock = 'Fill'
    $dg.ReadOnly = $true
    $dg.AutoGenerateColumns = $false
    $dg.SelectionMode = 'FullRowSelect'
    $dg.MultiSelect = $false
    $dg.AllowUserToAddRows = $false
    foreach ($colDef in @(
            @{ Name = 'DisplayName'; HeaderText = 'Name'; Width = 280 }
            @{ Name = 'Publisher'; HeaderText = 'Publisher'; Width = 160 }
            @{ Name = 'Version'; HeaderText = 'Version'; Width = 90 }
            @{ Name = 'QuietUninstall'; HeaderText = 'Quiet uninstall'; Width = 200 }
            @{ Name = 'UninstallString'; HeaderText = 'Uninstall command'; Width = 260 }
        )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $colDef.Name
        $c.HeaderText = $colDef.HeaderText
        $c.Width = $colDef.Width
        $c.DataPropertyName = $colDef.Name
        [void]$dg.Columns.Add($c)
    }

    $table = New-Object System.Data.DataTable
    [void]$table.Columns.Add('DisplayName', [string])
    [void]$table.Columns.Add('Publisher', [string])
    [void]$table.Columns.Add('Version', [string])
    [void]$table.Columns.Add('QuietUninstall', [string])
    [void]$table.Columns.Add('UninstallString', [string])
    foreach ($row in @(Get-InstalledProgramsFromRegistry)) {
        [void]$table.Rows.Add(@($row.DisplayName, $row.Publisher, $row.Version, $row.QuietUninstall, $row.UninstallString))
    }
    $bs = New-Object System.Windows.Forms.BindingSource
    $bs.DataSource = $table
    $dg.DataSource = $bs

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Bottom'
    $flow.WrapContents = $true
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flow.AutoSize = $true
    $flow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flow.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)

    $btnUn = New-Object System.Windows.Forms.Button
    $btnUn.Text = 'Uninstall selected'
    $btnUn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnUn.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $r = $dg.SelectedRows[0]
        $cmd = [string]$r.Cells['QuietUninstall'].Value
        if ([string]::IsNullOrWhiteSpace($cmd)) { $cmd = [string]$r.Cells['UninstallString'].Value }
        $disp = [string]$r.Cells['DisplayName'].Value
        if ([string]::IsNullOrWhiteSpace($cmd)) {
            [System.Windows.Forms.MessageBox]::Show('No uninstall command for this entry.', 'clark', 'OK', 'Information')
            return
        }
        $c = [System.Windows.Forms.MessageBox]::Show(
            "Run uninstall for:`n`n$disp`n`nCommand:`n$cmd",
            'Confirm uninstall',
            'YesNo',
            'Warning'
        )
        if ($c -ne 'Yes') { return }
        try {
            Start-Process cmd.exe -ArgumentList @('/c', $cmd) -Wait
            [System.Windows.Forms.MessageBox]::Show('Uninstall process exited. Click Refresh if the program was removed.', 'clark', 'OK', 'Information')
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Uninstall', 'OK', 'Error')
        }
    })
    [void]$flow.Controls.Add($btnUn)

    $btnAppwiz = New-Object System.Windows.Forms.Button
    $btnAppwiz.Text = 'Programs and Features'
    $btnAppwiz.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnAppwiz.Add_Click({ Start-Process appwiz.cpl })
    [void]$flow.Controls.Add($btnAppwiz)

    $btnRef = New-Object System.Windows.Forms.Button
    $btnRef.Text = 'Refresh'
    $btnRef.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnRef.Add_Click({
        $table.Rows.Clear()
        foreach ($row in @(Get-InstalledProgramsFromRegistry)) {
            [void]$table.Rows.Add(@($row.DisplayName, $row.Publisher, $row.Version, $row.QuietUninstall, $row.UninstallString))
        }
    })
    [void]$flow.Controls.Add($btnRef)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnClose.Add_Click({ $form.Close() })
    [void]$flow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnUn, $btnAppwiz, $btnRef, $btnClose)

    # Dock: add Top and Bottom first, then Fill, so the grid uses remaining client area.
    [void]$form.Controls.Add($lbl)
    [void]$form.Controls.Add($flow)
    [void]$form.Controls.Add($dg)

    [void]$form.ShowDialog()
}
function Invoke-WPFButton {



    <#



    .SYNOPSIS

        Invokes the function associated with the clicked button



    .PARAMETER Button

        The name of the button that was clicked



    #>



    Param ([string]$Button)



    # Use this to get the name of the button

    #[System.Windows.MessageBox]::Show("$Button","Chris Titus Tech's Windows Utility","OK","Info")

    if (-not $sync.ProcessRunning) {

        Set-ClarkProgressBar  -label "" -percent 0

    }



    # Check if button is defined in feature config with function or InvokeScript

    if ($sync.configs.feature.$Button) {

        $buttonConfig = $sync.configs.feature.$Button



        # If button has a function defined, call it

        if ($buttonConfig.function) {

            $functionName = $buttonConfig.function

            if (Get-Command $functionName -ErrorAction SilentlyContinue) {

                & $functionName

                return

            }

        }



        # If button has InvokeScript defined, execute the scripts

        if ($buttonConfig.InvokeScript -and $buttonConfig.InvokeScript.Count -gt 0) {

            foreach ($script in $buttonConfig.InvokeScript) {

                if (-not [string]::IsNullOrWhiteSpace($script)) {

                    Invoke-Expression $script

                }

            }

            return

        }

    }



    # Profiles tab (and similar): buttons defined in profiles.json with function name

    if ($sync.configs.profiles -and ($null -ne $sync.configs.profiles.$Button)) {

        $profBtn = $sync.configs.profiles.$Button

        if ($profBtn.function) {

            $fn = [string]$profBtn.function

            if (Get-Command $fn -ErrorAction SilentlyContinue) {

                & $fn

                return

            }

        }

    }



    if ($sync.configs.tools -and ($null -ne $sync.configs.tools.$Button)) {

        $toolBtn = $sync.configs.tools.$Button

        if ($toolBtn.function) {

            $tfn = [string]$toolBtn.function

            if (Get-Command $tfn -ErrorAction SilentlyContinue) {

                & $tfn

                return

            }

        }

    }



    # Fallback to hard-coded switch for buttons not in feature.json

    Switch -Wildcard ($Button) {

        "WPFTab?BT" {Invoke-WPFTab $Button}

        "WPFInstall" {Invoke-WPFInstall}

        "WPFUninstall" {Invoke-WPFUnInstall}

        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade}

        "WPFCollapseAllCategories" {Invoke-WPFToggleAllCategories -Action "Collapse"}

        "WPFExpandAllCategories" {Invoke-WPFToggleAllCategories -Action "Expand"}

        "WPFStandard" {Invoke-WPFPresets "Standard" -checkboxfilterpattern "WPFTweak*"}

        "WPFMinimal" {Invoke-WPFPresets "Minimal" -checkboxfilterpattern "WPFTweak*"}

        "WPFClearTweaksSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFTweak*"}

        "WPFClearInstallSelection" {Invoke-WPFPresets -imported $true -checkboxfilterpattern "WPFInstall*"}

        "WPFtweaksbutton" {Invoke-WPFtweaksbutton}

        "WPFOOSUbutton" {Invoke-WPFOOSU}

        "WPFAddUltPerf" {Invoke-WPFUltimatePerformance -Do}

        "WPFRemoveUltPerf" {Invoke-WPFUltimatePerformance}

        "WPFundoall" {Invoke-WPFundoall}

        "WPFUpdatesdefault" {Invoke-WPFUpdatesdefault}

        "WPFUpdatesdisable" {Invoke-WPFUpdatesdisable}

        "WPFUpdatessecurity" {Invoke-WPFUpdatessecurity}

        "WPFUpdateDestroyer" {Invoke-WPFUpdateDestroyer}

        "WPFUpdateDestroyerUndo" {Invoke-WPFUpdateDestroyerUndo}

        "WPFGetInstalled" {Invoke-WPFGetInstalled -CheckBox "winget"}

        "WPFGetInstalledTweaks" {Invoke-WPFGetInstalled -CheckBox "tweaks"}

        "WPFMinimizeButton" { $sync.Form.WindowState = [Windows.WindowState]::Minimized }

        "WPFMaximizeButton" {

            if ($sync.Form.WindowState -eq [Windows.WindowState]::Maximized) {

                $sync.Form.WindowState = [Windows.WindowState]::Normal

            } else {

                $sync.Form.WindowState = [Windows.WindowState]::Maximized

            }

        }

        "WPFCloseButton" {$sync.Form.Close(); Write-Host "Bye bye!"}

        "WPFselectedAppsButton" {$sync.selectedAppsPopup.IsOpen = -not $sync.selectedAppsPopup.IsOpen}

        "WPFActivationScripts" { Invoke-WPFActivationScriptsMenu }

        "WPFCheckActivationStatus" { Invoke-WPFActivationStatus }

        "WPFToggleFOSSHighlight" {

            if ($sync.WPFToggleFOSSHighlight.IsChecked) {

                 $sync.Form.Resources["FOSSColor"] = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromRgb(76, 175, 80)) # #4CAF50

            } else {

                 $sync.Form.Resources["FOSSColor"] = $sync.Form.Resources["MainForegroundColor"]

            }

        }

    }

}

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
        # Command guide text lives only in this script (not downloaded). Shown in a WinForms window ??? no readme .txt on disk.
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
function Invoke-WPFDnsManager {

    <#

    .SYNOPSIS

        DNS presets per adapter or all adapters, plus DHCP reset.

    #>

    Add-Type -AssemblyName System.Windows.Forms

    Add-Type -AssemblyName System.Drawing



    $providers = @("DHCP") + @($sync.configs.dns.PSObject.Properties.Name | Sort-Object) + @("Custom")



    $form = New-Object System.Windows.Forms.Form

    $form.Text = "Clark - DNS manager"

    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

    $form.MaximizeBox = $false

    $form.StartPosition = "CenterScreen"



    # Use a dedicated name + [int] ??? a plain $y can collide with outer scopes and become Object[], breaking $y - 2.

    [int]$dnsFormY = 12

    $lbl = New-Object System.Windows.Forms.Label

    $lbl.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $lbl.Size = New-Object System.Drawing.Size(600, 40)

    $lbl.Text = "Pick a DNS preset first, then select adapters and click Apply. DHCP resets both IPv4 and IPv6 where supported."

    [void]$form.Controls.Add($lbl)

    $dnsFormY = [int]($dnsFormY + 46)



    $lblP = New-Object System.Windows.Forms.Label

    $lblP.Text = "DNS preset:"

    $lblP.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $lblP.AutoSize = $true

    [void]$form.Controls.Add($lblP)

    $combo = New-Object System.Windows.Forms.ComboBox

    $combo.DropDownStyle = "DropDownList"

    $combo.Location = New-Object System.Drawing.Point(100, [int]($dnsFormY - 2))

    $combo.Width = 220

    foreach ($p in $providers) { [void]$combo.Items.Add($p) }

    $combo.SelectedIndex = [math]::Max(0, $combo.Items.IndexOf("Cloudflare"))

    if ($combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }

    [void]$form.Controls.Add($combo)

    $combo.Add_DropDown({ $combo.BringToFront() })

    $dnsFormY = [int]($dnsFormY + 32)



    $cbAll = New-Object System.Windows.Forms.CheckBox

    $cbAll.Text = "Select all adapters (including not Up)"

    $cbAll.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $cbAll.Width = 400

    [void]$form.Controls.Add($cbAll)

    $dnsFormY = [int]($dnsFormY + 28)



    $list = New-Object System.Windows.Forms.CheckedListBox

    $list.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $list.Size = New-Object System.Drawing.Size(600, 160)

    $ifIndexByRow = [System.Collections.Generic.List[int]]::new()

    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object Name)) {

        $label = "$($a.Name)  [ifIndex $($a.ifIndex)]  $($a.Status)"

        [void]$list.Items.Add($label, ($a.Status -eq 'Up'))

        [void]$ifIndexByRow.Add($a.ifIndex)

    }

    $list.Tag = $ifIndexByRow

    [void]$form.Controls.Add($list)

    $dnsFormY = [int]($dnsFormY + 168)



    $lblC = New-Object System.Windows.Forms.Label

    $lblC.Text = "Custom IPv4 (primary / secondary):"

    $lblC.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $lblC.Width = 260

    [void]$form.Controls.Add($lblC)

    $dnsFormY = [int]($dnsFormY + 22)

    $tPri = New-Object System.Windows.Forms.TextBox

    $tPri.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $tPri.Width = 120

    [void]$form.Controls.Add($tPri)

    $tSec = New-Object System.Windows.Forms.TextBox

    $tSec.Location = New-Object System.Drawing.Point(140, $dnsFormY)

    $tSec.Width = 120

    [void]$form.Controls.Add($tSec)

    $dnsFormY = [int]($dnsFormY + 34)



    $lbl6 = New-Object System.Windows.Forms.Label

    $lbl6.Text = "Custom IPv6 (optional, primary / secondary):"

    $lbl6.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $lbl6.Width = 360

    [void]$form.Controls.Add($lbl6)

    $dnsFormY = [int]($dnsFormY + 22)

    $t6p = New-Object System.Windows.Forms.TextBox

    $t6p.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $t6p.Width = 240

    [void]$form.Controls.Add($t6p)

    $t6s = New-Object System.Windows.Forms.TextBox

    $t6s.Location = New-Object System.Drawing.Point(260, $dnsFormY)

    $t6s.Width = 240

    [void]$form.Controls.Add($t6s)

    $dnsFormY = [int]($dnsFormY + 44)



    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel

    $btnRow.Location = New-Object System.Drawing.Point(12, $dnsFormY)

    $btnRow.Width = 616

    $btnRow.AutoSize = $true

    $btnRow.WrapContents = $false

    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight

    $btnRow.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)



    $btnApply = New-Object System.Windows.Forms.Button

    $btnApply.Text = "Apply to selected adapters"

    $btnApply.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)

    $btnApply.Add_Click({

        $indexes = [System.Collections.Generic.List[int]]::new()

        $rows = [System.Collections.Generic.List[int]]$list.Tag

        for ($i = 0; $i -lt $list.Items.Count; $i++) {

            if ($list.GetItemChecked($i)) {

                [void]$indexes.Add([int]$rows[$i])

            }

        }

        if ($indexes.Count -eq 0) {

            [System.Windows.Forms.MessageBox]::Show("Check at least one adapter.", "clark", "OK", "Information")

            return

        }

        $prov = [string]$combo.SelectedItem

        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {

            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")

            return

        }

        try {

            if ($prov -eq "Custom") {

                $dnsArgs = @{
                    DNSProvider       = "Custom"
                    InterfaceIndex    = $indexes.ToArray()
                    CustomPrimaryV4   = $tPri.Text.Trim()
                    CustomSecondaryV4 = $tSec.Text.Trim()
                    CustomPrimaryV6   = $t6p.Text.Trim()
                    CustomSecondaryV6 = $t6s.Text.Trim()
                }
                Set-ClarkDNS @dnsArgs

            } else {

                Set-ClarkDNS -DNSProvider $prov -InterfaceIndex $indexes.ToArray()

            }

            [System.Windows.Forms.MessageBox]::Show("DNS update finished. See console output for details.", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")

        }

    })

    [void]$btnRow.Controls.Add($btnApply)



    $btnAll = New-Object System.Windows.Forms.Button

    $btnAll.Text = "Apply preset to ALL adapters"

    $btnAll.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)

    $btnAll.Add_Click({

        $prov = [string]$combo.SelectedItem

        if ($prov -eq "Custom" -and [string]::IsNullOrWhiteSpace($tPri.Text)) {

            [System.Windows.Forms.MessageBox]::Show("Enter at least a primary custom IPv4 address.", "clark", "OK", "Warning")

            return

        }

        try {

            if ($prov -eq "Custom") {

                $dnsArgs = @{
                    DNSProvider       = "Custom"
                    AllAdapters       = $true
                    CustomPrimaryV4   = $tPri.Text.Trim()
                    CustomSecondaryV4 = $tSec.Text.Trim()
                    CustomPrimaryV6   = $t6p.Text.Trim()
                    CustomSecondaryV6 = $t6s.Text.Trim()
                }
                Set-ClarkDNS @dnsArgs

            } else {

                Set-ClarkDNS -DNSProvider $prov -AllAdapters

            }

            [System.Windows.Forms.MessageBox]::Show("DNS update applied to all adapters.", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "clark", "OK", "Error")

        }

    })

    [void]$btnRow.Controls.Add($btnAll)



    $btnClose = New-Object System.Windows.Forms.Button

    $btnClose.Text = "Close"

    $btnClose.Add_Click({ $form.Close() })

    [void]$btnRow.Controls.Add($btnClose)



    Set-WinFormsButtonFullText -Button @($btnApply, $btnAll, $btnClose)

    [void]$form.Controls.Add($btnRow)

    $dnsFormY = [int]($dnsFormY + [math]::Max(44, $btnRow.PreferredSize.Height + 4))



    $cbAll.Add_CheckedChanged({

        if ($cbAll.Checked) {

            for ($i = 0; $i -lt $list.Items.Count; $i++) {

                $list.SetItemChecked($i, $true)

            }

        }

    })



    $form.ClientSize = New-Object System.Drawing.Size(640, [int]($dnsFormY + 48))



    [void]$form.ShowDialog()

}

function Invoke-WPFFeatureInstall {

    <#



    .SYNOPSIS

        Installs selected Windows Features



    #>



    if($sync.ProcessRunning) {

        $msg = "[Invoke-WPFFeatureInstall] Install process is currently running."

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    $handle = Invoke-WPFRunspace -ScriptBlock {

        $Features = $sync.selectedFeatures

        $sync.ProcessRunning = $true

        if ($Features.count -eq 1) {

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" -value 0.01 -overlay "logo" }

        } else {

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo" }

        }



        $x = 0



        $Features | ForEach-Object {

            Invoke-ClarkFeatureInstall $_

            $X++

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -value ($x/$CheckBox.Count) }

        }



        $sync.ProcessRunning = $false

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }



        Write-Host "==================================="

        Write-Host "---   Features are Installed    ---"

        Write-Host "---  A Reboot may be required   ---"

        Write-Host "==================================="

    }

}

function Invoke-WPFFixesNetwork {

    <#



    .SYNOPSIS

        Resets various network configurations



    #>



    Write-Host "Resetting Network with netsh"



    Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo"

    # Reset WinSock catalog to a clean state

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset"



    Set-ClarkTaskbaritem -state "Normal" -value 0.35 -overlay "logo"

    # Resets WinHTTP proxy setting to DIRECT

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy"



    Set-ClarkTaskbaritem -state "Normal" -value 0.7 -overlay "logo"

    # Removes all user configured IP settings

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "int", "ip", "reset"



    Set-ClarkTaskbaritem -state "None" -overlay "checkmark"



    Write-Host "Process complete. Please reboot your computer."



    $ButtonType = [System.Windows.MessageBoxButton]::OK

    $MessageboxTitle = "Network Reset "

    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")

    $MessageIcon = [System.Windows.MessageBoxImage]::Information



    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    Write-Host "=========================================="

    Write-Host "-- Network Configuration has been Reset --"

    Write-Host "=========================================="

}

function Invoke-WPFFixesNTPPool {
    <#
    .SYNOPSIS
        Configures Windows to use pool.ntp.org for NTP synchronization

    .DESCRIPTION
        Replaces the default Windows NTP server (time.windows.com) with
        pool.ntp.org for improved time synchronization accuracy and reliability.
    #>

    Start-Service w32time
    w32tm /config /update /manualpeerlist:"pool.ntp.org,0x8" /syncfromflags:MANUAL

    Restart-Service w32time
    w32tm /resync

    Write-Host "================================="
    Write-Host "-- NTP Configuration Complete ---"
    Write-Host "================================="
}
function Invoke-WPFFixesUpdate {



    <#



    .SYNOPSIS

        Performs various tasks in an attempt to repair Windows Update



    .DESCRIPTION

        1. (Aggressive Only) Scans the system for corruption using the Invoke-WPFSystemRepair function

        2. Stops Windows Update Services

        3. Remove the QMGR Data file, which stores BITS jobs

        4. (Aggressive Only) Renames the DataStore and CatRoot2 folders

            DataStore - Contains the Windows Update History and Log Files

            CatRoot2 - Contains the Signatures for Windows Update Packages

        5. Renames the Windows Update Download Folder

        6. Deletes the Windows Update Log

        7. (Aggressive Only) Resets the Security Descriptors on the Windows Update Services

        8. Reregisters the BITS and Windows Update DLLs

        9. Removes the WSUS client settings

        10. Resets WinSock

        11. Gets and deletes all BITS jobs

        12. Sets the startup type of the Windows Update Services then starts them

        13. Forces Windows Update to check for updates



    .PARAMETER Aggressive

        If specified, the script will take additional steps to repair Windows Update that are more dangerous, take a significant amount of time, or are generally unnecessary



    #>



    param($Aggressive = $false)



    Write-Progress -Id 0 -Activity "Repairing Windows Update" -PercentComplete 0

    Set-ClarkTaskbaritem -state "Indeterminate" -overlay "logo"

    Write-Host "Starting Windows Update Repair..."

    # Wait for the first progress bar to show, otherwise the second one won't show

    Start-Sleep -Milliseconds 200



    if ($Aggressive) {

        Invoke-WPFSystemRepair

    }





    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Stopping Windows Update Services..." -PercentComplete 10

    # Stop the Windows Update Services

    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping BITS..." -PercentComplete 0

    Stop-Service -Name BITS -Force

    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping wuauserv..." -PercentComplete 20

    Stop-Service -Name wuauserv -Force

    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping appidsvc..." -PercentComplete 40

    Stop-Service -Name appidsvc -Force

    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping cryptsvc..." -PercentComplete 60

    Stop-Service -Name cryptsvc -Force

    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Completed" -PercentComplete 100





    # Remove the QMGR Data file

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Renaming/Removing Files..." -PercentComplete 20

    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Removing QMGR Data files..." -PercentComplete 0

    Remove-Item "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue





    if ($Aggressive) {

        # Rename the Windows Update Log and Signature Folders

        Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Renaming the Windows Update Log, Download, and Signature Folder..." -PercentComplete 20

        Rename-Item $env:systemroot\SoftwareDistribution\DataStore DataStore.bak -ErrorAction SilentlyContinue

        Rename-Item $env:systemroot\System32\Catroot2 catroot2.bak -ErrorAction SilentlyContinue

    }



    # Rename the Windows Update Download Folder

    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Renaming the Windows Update Download Folder..." -PercentComplete 20

    Rename-Item $env:systemroot\SoftwareDistribution\Download Download.bak -ErrorAction SilentlyContinue



    # Delete the legacy Windows Update Log

    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Removing the old Windows Update log..." -PercentComplete 80

    Remove-Item $env:systemroot\WindowsUpdate.log -ErrorAction SilentlyContinue

    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Completed" -PercentComplete 100





    if ($Aggressive) {

        # Reset the Security Descriptors on the Windows Update Services

        Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Resetting the WU Service Security Descriptors..." -PercentComplete 25

        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Resetting the BITS Security Descriptor..." -PercentComplete 0

        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "bits", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait

        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Resetting the wuauserv Security Descriptor..." -PercentComplete 50

        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "wuauserv", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait

        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Completed" -PercentComplete 100

    }





    # Reregister the BITS and Windows Update DLLs

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Reregistering DLLs..." -PercentComplete 40

    $oldLocation = Get-Location

    Set-Location $env:systemroot\system32

    $i = 0

    $DLLs = @(

        "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",

        "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",

        "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll",

        "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",

        "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll",

        "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",

        "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"

    )

    foreach ($dll in $DLLs) {

        Write-Progress -Id 5 -ParentId 0 -Activity "Reregistering DLLs" -Status "Registering $dll..." -PercentComplete ($i / $DLLs.Count * 100)

        $i++

        Start-Process -NoNewWindow -FilePath "regsvr32.exe" -ArgumentList "/s", $dll

    }

    Set-Location $oldLocation

    Write-Progress -Id 5 -ParentId 0 -Activity "Reregistering DLLs" -Status "Completed" -PercentComplete 100





    # Remove the WSUS client settings

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate") {

        Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Removing WSUS client settings..." -PercentComplete 60

        Write-Progress -Id 6 -ParentId 0 -Activity "Removing WSUS client settings" -PercentComplete 0

        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "AccountDomainSid", "/f" -RedirectStandardError "NUL"

        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "PingID", "/f" -RedirectStandardError "NUL"

        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "SusClientId", "/f" -RedirectStandardError "NUL"

        Write-Progress -Id 6 -ParentId 0 -Activity "Removing WSUS client settings" -Status "Completed" -PercentComplete 100

    }



    # Remove Group Policy Windows Update settings

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Removing Group Policy Windows Update settings..." -PercentComplete 60

    Write-Progress -Id 7 -ParentId 0 -Activity "Removing Group Policy Windows Update settings" -PercentComplete 0

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue

    Write-Host "Defaulting driver offering through Windows Update..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue

    Write-Host "Defaulting Windows Update automatic restart..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue

    Write-Host "Clearing ANY Windows Update Policy settings..."

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue

    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKCU:\Software\Microsoft\WindowsSelfHost" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKCU:\Software\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\Microsoft\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\Microsoft\WindowsSelfHost" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Policies" -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue

    Start-Process -NoNewWindow -FilePath "secedit" -ArgumentList "/configure", "/cfg", "$env:windir\inf\defltbase.inf", "/db", "defltbase.sdb", "/verbose" -Wait

    Start-Process -NoNewWindow -FilePath "cmd.exe" -ArgumentList "/c RD /S /Q $env:WinDir\System32\GroupPolicyUsers" -Wait

    Start-Process -NoNewWindow -FilePath "cmd.exe" -ArgumentList "/c RD /S /Q $env:WinDir\System32\GroupPolicy" -Wait

    Start-Process -NoNewWindow -FilePath "gpupdate" -ArgumentList "/force" -Wait

    Write-Progress -Id 7 -ParentId 0 -Activity "Removing Group Policy Windows Update settings" -Status "Completed" -PercentComplete 100





    # Reset WinSock

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Resetting WinSock..." -PercentComplete 65

    Write-Progress -Id 7 -ParentId 0 -Activity "Resetting WinSock" -Status "Resetting WinSock..." -PercentComplete 0

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset"

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy"

    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "int", "ip", "reset"

    Write-Progress -Id 7 -ParentId 0 -Activity "Resetting WinSock" -Status "Completed" -PercentComplete 100





    # Get and delete all BITS jobs

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Deleting BITS jobs..." -PercentComplete 75

    Write-Progress -Id 8 -ParentId 0 -Activity "Deleting BITS jobs" -Status "Deleting BITS jobs..." -PercentComplete 0

    Get-BitsTransfer | Remove-BitsTransfer

    Write-Progress -Id 8 -ParentId 0 -Activity "Deleting BITS jobs" -Status "Completed" -PercentComplete 100





    # Change the startup type of the Windows Update Services and start them

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Starting Windows Update Services..." -PercentComplete 90

    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting BITS..." -PercentComplete 0

    Get-Service BITS | Set-Service -StartupType Manual -PassThru | Start-Service

    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting wuauserv..." -PercentComplete 25

    Get-Service wuauserv | Set-Service -StartupType Manual -PassThru | Start-Service

    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting AppIDSvc..." -PercentComplete 50

    # The AppIDSvc service is protected, so the startup type has to be changed in the registry

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value "3" # Manual

    Start-Service AppIDSvc

    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting CryptSvc..." -PercentComplete 75

    Get-Service CryptSvc | Set-Service -StartupType Manual -PassThru | Start-Service

    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Completed" -PercentComplete 100





    # Force Windows Update to check for updates

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Forcing discovery..." -PercentComplete 95

    Write-Progress -Id 10 -ParentId 0 -Activity "Forcing discovery" -Status "Forcing discovery..." -PercentComplete 0

    try {

        (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()

    } catch {

        Set-ClarkTaskbaritem -state "Error" -overlay "warning"

        Write-Warning "Failed to create Windows Update COM object: $_"

    }

    Start-Process -NoNewWindow -FilePath "wuauclt" -ArgumentList "/resetauthorization", "/detectnow"

    Write-Progress -Id 10 -ParentId 0 -Activity "Forcing discovery" -Status "Completed" -PercentComplete 100

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Completed" -PercentComplete 100



    Set-ClarkTaskbaritem -state "None" -overlay "checkmark"



    $ButtonType = [System.Windows.MessageBoxButton]::OK

    $MessageboxTitle = "Reset Windows Update "

    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")

    $MessageIcon = [System.Windows.MessageBoxImage]::Information



    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    Write-Host "==============================================="

    Write-Host "-- Reset All Windows Update Settings to Stock -"

    Write-Host "==============================================="



    # Remove the progress bars

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Completed

    Write-Progress -Id 1 -Activity "Scanning for corruption" -Completed

    Write-Progress -Id 2 -Activity "Stopping Services" -Completed

    Write-Progress -Id 3 -Activity "Renaming/Removing Files" -Completed

    Write-Progress -Id 4 -Activity "Resetting the WU Service Security Descriptors" -Completed

    Write-Progress -Id 5 -Activity "Reregistering DLLs" -Completed

    Write-Progress -Id 6 -Activity "Removing Group Policy Windows Update settings" -Completed

    Write-Progress -Id 7 -Activity "Resetting WinSock" -Completed

    Write-Progress -Id 8 -Activity "Deleting BITS jobs" -Completed

    Write-Progress -Id 9 -Activity "Starting Windows Update Services" -Completed

    Write-Progress -Id 10 -Activity "Forcing discovery" -Completed

}

function Invoke-WPFFixesWinget {



    <#



    .SYNOPSIS

        Fixes WinGet by running `choco install winget`

    .DESCRIPTION

        BravoNorris for the fantastic idea of a button to reinstall WinGet

    #>

    # Install Choco if not already present

    try {

        Set-ClarkTaskbaritem -state "Indeterminate" -overlay "logo"

        Write-Host "==> Starting WinGet Repair"

        Install-ClarkWinget

    } catch {

        Write-Error "Failed to install WinGet: $_"

        Set-ClarkTaskbaritem -state "Error" -overlay "warning"

    } finally {

        Write-Host "==> Finished WinGet Repair"

        Set-ClarkTaskbaritem -state "None" -overlay "checkmark"

    }



}

function Invoke-WPFGetInstalled {

    <#

    TODO: Add the Option to use Chocolatey as Engine

    .SYNOPSIS

        Invokes the function that gets the checkboxes to check in a new runspace



    .PARAMETER checkbox

        Indicates whether to check for installed 'winget' programs or applied 'tweaks'



    #>

    param($checkbox)

    if ($sync.ProcessRunning) {

        $msg = "[Invoke-WPFGetInstalled] Install process is currently running."

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    if (($sync.ChocoRadioButton.IsChecked -eq $false) -and ((Test-ClarkPackageManager -winget) -eq "not-installed") -and $checkbox -eq "winget") {

        return

    }

    $managerPreference = $sync.preferences.packagemanager



    Invoke-WPFRunspace -ParameterList @(("managerPreference", $managerPreference),("checkbox", $checkbox)) -ScriptBlock {

        param (

            [string]$checkbox,

            [PackageManagers]$managerPreference

        )

        $sync.ProcessRunning = $true

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" }



        if ($checkbox -eq "winget") {

            Write-Host "Getting Installed Programs..."

            switch ($managerPreference) {

                "Choco"{$Checkboxes = Invoke-ClarkCurrentSystem -CheckBox "choco"; break}

                "Winget"{$Checkboxes = Invoke-ClarkCurrentSystem -CheckBox $checkbox; break}

            }

        }

        elseif ($checkbox -eq "tweaks") {

            Write-Host "Getting Installed Tweaks..."

            $Checkboxes = Invoke-ClarkCurrentSystem -CheckBox $checkbox

        }



        $sync.form.Dispatcher.invoke({

            foreach ($checkbox in $Checkboxes) {

                $sync.$checkbox.ischecked = $True

            }

        })



        Write-Host "Done..."

        $sync.ProcessRunning = $false

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" }

    }

}

function Invoke-WPFHardwareSummary {

    Add-Type -AssemblyName System.Windows.Forms

    Add-Type -AssemblyName System.Drawing



    $text = Get-ClarkHardwareSummaryData



    $form = New-Object System.Windows.Forms.Form

    $form.Text = "Clark - Hardware summary"

    $form.Size = New-Object System.Drawing.Size(760, 560)

    $form.StartPosition = "CenterScreen"



    $tv = New-Object System.Windows.Forms.TreeView

    $tv.Dock = "Fill"

    $tv.HideSelection = $false

    $current = $null

    foreach ($line in ($text -split "`r?`n")) {

        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^=== (.+) ===$') {

            $current = $tv.Nodes.Add($matches[1])

            continue

        }

        if ($null -eq $current) { continue }

        [void]$current.Nodes.Add($line)

    }

    $tv.ExpandAll()



    $panel = New-Object System.Windows.Forms.FlowLayoutPanel

    $panel.Dock = "Bottom"

    $panel.WrapContents = $true

    $panel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight

    $panel.AutoSize = $true

    $panel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

    $panel.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 6)



    function Save-HtmlReport {

        param([string]$Path)

        $esc = [System.Net.WebUtility]::HtmlEncode($text)

        $html = @"

<!DOCTYPE html><html><head><meta charset="utf-8"><title>Clark hardware</title>

<style>body{font-family:Segoe UI,Arial;margin:16px;}pre{white-space:pre-wrap}</style></head>

<body><h1>Clark hardware summary</h1><pre>$esc</pre></body></html>

"@

        Set-Content -LiteralPath $Path -Value $html -Encoding UTF8

        return $Path

    }



    function Invoke-EdgeHeadless {

        param([string[]]$Arguments)

        $candidates = @(

            (Join-Path ${env:ProgramFiles} "Microsoft\Edge\Application\msedge.exe"),

            (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")

        )

        $edge = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

        if (-not $edge) {

            throw "Microsoft Edge (msedge.exe) not found. Save as HTML instead."

        }

        $p = Start-Process -FilePath $edge -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden

        return $p.ExitCode

    }



    $btnPdf = New-Object System.Windows.Forms.Button

    $btnPdf.Text = "Export PDF..."

    $btnPdf.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)

    $btnPdf.Add_Click({

        $sfd = New-Object System.Windows.Forms.SaveFileDialog

        $sfd.Filter = "PDF|*.pdf"

        $sfd.FileName = "clark-hardware.pdf"

        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $htmlPath = Join-Path $env:TEMP ("clark-hw-{0}.html" -f [Guid]::NewGuid().ToString("n"))

        try {

            $null = Save-HtmlReport -Path $htmlPath

            $uri = ([Uri]$htmlPath).AbsoluteUri

            Invoke-EdgeHeadless -Arguments @(

                "--headless=new",

                "--disable-gpu",

                "--no-first-run",

                "--disable-extensions",

                "--print-to-pdf=$($sfd.FileName)",

                $uri

            ) | Out-Null

            if (-not (Test-Path -LiteralPath $sfd.FileName)) {

                throw "PDF was not created."

            }

            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export PDF", "OK", "Error")

        } finally {

            Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue

        }

    })

    [void]$panel.Controls.Add($btnPdf)



    $btnPng = New-Object System.Windows.Forms.Button

    $btnPng.Text = "Export PNG..."

    $btnPng.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)

    $btnPng.Add_Click({

        $sfd = New-Object System.Windows.Forms.SaveFileDialog

        $sfd.Filter = "PNG|*.png"

        $sfd.FileName = "clark-hardware.png"

        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $htmlPath = Join-Path $env:TEMP ("clark-hw-{0}.html" -f [Guid]::NewGuid().ToString("n"))

        try {

            $null = Save-HtmlReport -Path $htmlPath

            $uri = ([Uri]$htmlPath).AbsoluteUri

            Invoke-EdgeHeadless -Arguments @(

                "--headless=new",

                "--disable-gpu",

                "--window-size=1280,2000",

                "--screenshot=$($sfd.FileName)",

                $uri

            ) | Out-Null

            if (-not (Test-Path -LiteralPath $sfd.FileName)) {

                throw "PNG was not created."

            }

            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export PNG", "OK", "Error")

        } finally {

            Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue

        }

    })

    [void]$panel.Controls.Add($btnPng)



    $btnHtml = New-Object System.Windows.Forms.Button

    $btnHtml.Text = "Export HTML..."

    $btnHtml.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)

    $btnHtml.Add_Click({

        $sfd = New-Object System.Windows.Forms.SaveFileDialog

        $sfd.Filter = "HTML|*.html"

        $sfd.FileName = "clark-hardware.html"

        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        try {

            Save-HtmlReport -Path $sfd.FileName | Out-Null

            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export HTML", "OK", "Error")

        }

    })

    [void]$panel.Controls.Add($btnHtml)



    $btnClose = New-Object System.Windows.Forms.Button

    $btnClose.Text = "Close"

    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)

    $btnClose.Add_Click({ $form.Close() })

    [void]$panel.Controls.Add($btnClose)



    Set-WinFormsButtonFullText -Button @($btnPdf, $btnPng, $btnHtml, $btnClose)



    [void]$form.Controls.Add($panel)

    [void]$form.Controls.Add($tv)

    [void]$form.ShowDialog()

}

function Invoke-WPFImpex {

    <#



    .SYNOPSIS

        Handles importing and exporting of the checkboxes checked for the tweaks section



    .PARAMETER type

        Indicates whether to 'import' or 'export'



    .PARAMETER checkbox

        The checkbox to export to a file or apply the imported file to



    .EXAMPLE

        Invoke-WPFImpex -type "export"



    #>

    param(

        $type,

        $Config = $null

    )



    function ConfigDialog {

        if (!$Config) {

            switch ($type) {

                "export" { $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog }

                "import" { $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog }

            }

            $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')

            $FileBrowser.Filter = "JSON Files (*.json)|*.json"

            $FileBrowser.ShowDialog() | Out-Null



            if ($FileBrowser.FileName -eq "") {

                return $null

            } else {

                return $FileBrowser.FileName

            }

        } else {

            return $Config

        }

    }



    switch ($type) {

        "export" {

            try {

                $Config = ConfigDialog

                if ($Config) {

                    $allConfs = ($sync.selectedApps + $sync.selectedTweaks + $sync.selectedToggles + $sync.selectedFeatures) | ForEach-Object { [string]$_ }

                    if (-not $allConfs) {

                        [System.Windows.MessageBox]::Show(

                            "No settings are selected to export. Please select at least one app, tweak, toggle, or feature before exporting.",

                            "Nothing to Export", "OK", "Warning")

                        return

                    }

                    $jsonFile = $allConfs | ConvertTo-Json

                    $jsonFile | Out-File $Config -Force

                    @"

`$scriptPath = Join-Path `$env:TEMP 'A-SYS_clark.ps1'

irm 'https://clark.advancesystems4042.com/?token=covxo5-nyrmUh-rodgac' -ErrorAction Stop | Out-File -FilePath `$scriptPath -Encoding utf8 -Force

& `$scriptPath -Config '$Config'

"@ | Set-Clipboard

                }

            } catch {

                Write-Error "An error occurred while exporting: $_"

            }

        }

        "import" {

            try {

                $Config = ConfigDialog

                if ($Config) {

                    try {

                        if ($Config -match '^https?://') {

                            $jsonFile = (Invoke-WebRequest "$Config").Content | ConvertFrom-Json

                        } else {

                            $jsonFile = Get-Content $Config | ConvertFrom-Json

                        }

                    } catch {

                        Write-Error "Failed to load the JSON file from the specified path or URL: $_"

                        return

                    }

                    # TODO how to handle old style? detected json type then flatten it in a func?

                    # $flattenedJson = $jsonFile.PSObject.Properties.Where({ $_.Name -ne "Install" }).ForEach({ $_.Value })

                    $flattenedJson = $jsonFile



                    if (-not $flattenedJson) {

                        [System.Windows.MessageBox]::Show(

                            "The selected file contains no settings to import. No changes have been made.",

                            "Empty Configuration", "OK", "Warning")

                        return

                    }



                    # Clear all existing selections before importing so the import replaces

                    # the current state rather than merging with it

                    $sync.selectedApps = [System.Collections.Generic.List[string]]::new()

                    $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()

                    $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()

                    $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()



                    Update-ClarkSelections -flatJson $flattenedJson



                    if (!$PARAM_NOUI) {

                        # Set flag so toggle Checked/Unchecked events don't trigger registry writes

                        # while we're programmatically restoring UI state from the imported config

                        $sync.ImportInProgress = $true

                        try {

                            Reset-WPFCheckBoxes -doToggles $true

                        } finally {

                            $sync.ImportInProgress = $false

                        }

                    }

                }

            } catch {

                Write-Error "An error occurred while importing: $_"

            }

        }

    }

}

function Invoke-WPFInstall {

    <#

    .SYNOPSIS

        Installs the selected programs using winget, if one or more of the selected programs are already installed on the system, winget will try and perform an upgrade if there's a newer version to install.

    #>



    $PackagesToInstall = $sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ }





    if($sync.ProcessRunning) {

        $msg = "[Invoke-WPFInstall] An Install process is currently running."

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    if ($PackagesToInstall.Count -eq 0) {

        $WarningMsg = "Please select the program(s) to install or upgrade."

        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    $ManagerPreference = $sync.preferences.packagemanager



    $handle = Invoke-WPFRunspace -ParameterList @(("PackagesToInstall", $PackagesToInstall),("ManagerPreference", $ManagerPreference)) -ScriptBlock {

        param($PackagesToInstall, $ManagerPreference)



        $packagesSorted = Get-ClarkSelectedPackages -PackageList $PackagesToInstall -Preference $ManagerPreference



        $packagesWinget = $packagesSorted[[PackageManagers]::Winget]

        $packagesChoco = $packagesSorted[[PackageManagers]::Choco]



        try {

            $sync.ProcessRunning = $true

            if($packagesWinget.Count -gt 0 -and $packagesWinget -ne "0") {

                Show-WPFInstallAppBusy -text "Installing apps..."

                Install-ClarkWinget

                Install-ClarkProgramWinget -Action Install -Programs $packagesWinget

            }

            if($packagesChoco.Count -gt 0) {

                Install-ClarkChoco

                Install-ClarkProgramChoco -Action Install -Programs $packagesChoco

            }

            Hide-WPFInstallAppBusy

            Write-Host "==========================================="

            Write-Host "--      Installs have finished          ---"

            Write-Host "==========================================="

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }

        } catch {

            Write-Host "==========================================="

            Write-Host "Error: $_"

            Write-Host "==========================================="

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Error" -overlay "warning" }

        }

        $sync.ProcessRunning = $False

    }

}

function Invoke-WPFInstallUpgrade {

    <#



    .SYNOPSIS

        Invokes the function that upgrades all installed programs



    #>

    if ($sync.ChocoRadioButton.IsChecked) {

        Install-ClarkChoco

        $chocoUpgradeStatus = (Start-Process "choco" -ArgumentList "upgrade all -y" -Wait -PassThru -NoNewWindow).ExitCode

        if ($chocoUpgradeStatus -eq 0) {

            Write-Host "Upgrade Successful"

        } else {

            Write-Host "Error Occurred. Return Code: $chocoUpgradeStatus"

        }

    } else {

        if((Test-ClarkPackageManager -winget) -eq "not-installed") {

            return

        }



        if(Get-ClarkInstallerProcess -Process $global:WinGetInstall) {

            $msg = "[Invoke-WPFInstallUpgrade] Install process is currently running. Please check for a powershell window labeled 'Winget Install'"

            [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

            return

        }



        Update-ClarkProgramWinget



        Write-Host "==========================================="

        Write-Host "--           Updates started            ---"

        Write-Host "-- You can close this window if desired ---"

        Write-Host "==========================================="

    }

}

function Invoke-WPFOOSU {
    <#
    .SYNOPSIS
        Downloads and runs OO Shutup 10
    #>
    try {
        $OOSU_filepath = "$ENV:temp\OOSU10.exe"
        $Initial_ProgressPreference = $ProgressPreference
        $ProgressPreference = "SilentlyContinue" # Disables the Progress Bar to drasticly speed up Invoke-WebRequest
        Invoke-WebRequest -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -OutFile $OOSU_filepath
        Write-Host "Starting OO Shutup 10 ..."
        Start-Process $OOSU_filepath
    } catch {
        Write-Host "Error Downloading and Running OO Shutup 10" -ForegroundColor Red
    }
    finally {
        $ProgressPreference = $Initial_ProgressPreference
    }
}
function Invoke-WPFPanelAutologin {
    <#

    .SYNOPSIS
        Enables autologin using Sysinternals Autologon.exe

    #>

    # Official Microsoft recommendation: https://learn.microsoft.com/en-us/sysinternals/downloads/autologon
    Invoke-WebRequest -Uri "https://live.sysinternals.com/Autologon.exe" -OutFile "$env:temp\autologin.exe"
    cmd /c "$env:temp\autologin.exe" /accepteula
}
function Invoke-WPFPopup {
    param (
        [ValidateSet("Show", "Hide", "Toggle")]
        [string]$Action = "",

        [string[]]$Popups = @(),

        [ValidateScript({
            $invalid = $_.GetEnumerator() | Where-Object { $_.Value -notin @("Show", "Hide", "Toggle") }
            if ($invalid) {
                throw "Found invalid Popup-Action pair(s): " + ($invalid | ForEach-Object { "$($_.Key) = $($_.Value)" } -join "; ")
            }
            $true
        })]
        [hashtable]$PopupActionTable = @{}
    )

    if (-not $PopupActionTable.Count -and (-not $Action -or -not $Popups.Count)) {
        throw "Provide either 'PopupActionTable' or both 'Action' and 'Popups'."
    }

    if ($PopupActionTable.Count -and ($Action -or $Popups.Count)) {
        throw "Use 'PopupActionTable' on its own, or 'Action' with 'Popups'."
    }

    # Collect popups and actions
    $PopupsToProcess = if ($PopupActionTable.Count) {
        $PopupActionTable.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = "$($_.Key)Popup"; Action = $_.Value } }
    } else {
        $Popups | ForEach-Object { [PSCustomObject]@{ Name = "$_`Popup"; Action = $Action } }
    }

    $PopupsNotFound = @()

    # Apply actions
    foreach ($popupEntry in $PopupsToProcess) {
        $popupName = $popupEntry.Name

        if (-not $sync.$popupName) {
            $PopupsNotFound += $popupName
            continue
        }

        $sync.$popupName.IsOpen = switch ($popupEntry.Action) {
            "Show" { $true }
            "Hide" { $false }
            "Toggle" { -not $sync.$popupName.IsOpen }
        }
    }

    if ($PopupsNotFound.Count -gt 0) {
        throw "Could not find the following popups: $($PopupsNotFound -join ', ')"
    }
}
function Invoke-WPFPresets {

    <#



    .SYNOPSIS

        Sets the checkboxes in clark to the given preset



    .PARAMETER preset

        The preset to set the checkboxes to



    .PARAMETER imported

        If the preset is imported from a file, defaults to false



    .PARAMETER checkboxfilterpattern

        The Pattern to use when filtering through CheckBoxes, defaults to "**"



    #>



    param (

        [Parameter(position=0)]

        [Array]$preset = $null,



        [Parameter(position=1)]

        [bool]$imported = $false,



        [Parameter(position=2)]

        [string]$checkboxfilterpattern = "**"

    )



    if ($imported -eq $true) {

        $CheckBoxesToCheck = $preset

    } else {

        $CheckBoxesToCheck = $sync.configs.preset.$preset

    }



    # clear out the filtered pattern so applying a preset replaces the current

    # state rather than merging with it

    switch ($checkboxfilterpattern) {

        "WPFTweak*" { $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new() }

        "WPFInstall*" { $sync.selectedApps = [System.Collections.Generic.List[string]]::new() }

        "WPFeatures" { $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new() }

        "WPFToggle" { $sync.selectedToggles = [System.Collections.Generic.List[string]]::new() }

        default {}

    }



    if ($preset) {

        Update-ClarkSelections -flatJson $CheckBoxesToCheck

    }



    Reset-WPFCheckBoxes -doToggles $false -checkboxfilterpattern $checkboxfilterpattern

}

function Invoke-WPFAutoReapplyEnable {

    Add-Type -AssemblyName Microsoft.VisualBasic

    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "AutoReapply" }

    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name for scheduled reapply:", "Enable Auto Reapply", $defaultName)

    if ([string]::IsNullOrWhiteSpace($profileName)) {

        return

    }



    try {

        Register-ClarkAutoReapplyTask -ProfileName $profileName

        [System.Windows.MessageBox]::Show("Auto reapply enabled. Scheduled tasks were created for startup and logon using profile '$profileName'.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to enable auto reapply: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFAutoReapplyDisable {

    try {

        Unregister-ClarkAutoReapplyTask

        [System.Windows.MessageBox]::Show("Auto reapply scheduled tasks have been removed.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to disable auto reapply: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileExportFile {

    Add-Type -AssemblyName System.Windows.Forms

    $dlg = New-Object System.Windows.Forms.SaveFileDialog

    $dlg.Filter = "Clark profile JSON (*.json)|*.json"

    $dlg.FileName = "clark-profile.json"

    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {

        return

    }

    $path = $dlg.FileName

    if ([string]::IsNullOrWhiteSpace($path)) {

        return

    }

    try {

        Invoke-ClarkProfileExportToPath -LiteralPath $path

        [System.Windows.MessageBox]::Show("Profile exported to:`n$path", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Export failed: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileImportFile {

    Add-Type -AssemblyName System.Windows.Forms

    $dlg = New-Object System.Windows.Forms.OpenFileDialog

    $dlg.Filter = "Clark profile JSON (*.json)|*.json|All files (*.*)|*.*"

    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {

        return

    }

    $path = $dlg.FileName

    if ([string]::IsNullOrWhiteSpace($path)) {

        return

    }

    try {

        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop

        $obj = $raw | ConvertFrom-Json

        $sync.selectedApps = [System.Collections.Generic.List[string]]::new()

        $sync.selectedTweaks = [System.Collections.Generic.List[string]]::new()

        $sync.selectedToggles = [System.Collections.Generic.List[string]]::new()

        $sync.selectedFeatures = [System.Collections.Generic.List[string]]::new()

        Invoke-ClarkProfileImportFromObject -ProfileObject $obj

        if (-not $PARAM_NOUI) {

            $sync.ImportInProgress = $true

            try {

                Reset-WPFCheckBoxes -doToggles $true

            } finally {

                $sync.ImportInProgress = $false

            }

        }

        [System.Windows.MessageBox]::Show("Profile imported from:`n$path", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Import failed: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileSave {

    Add-Type -AssemblyName Microsoft.VisualBasic

    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "MyProfile" }

    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Profile name to save current selections:", "Save Profile", $defaultName)

    if ([string]::IsNullOrWhiteSpace($profileName)) {

        return

    }



    try {

        Save-ClarkProfile -Name $profileName | Out-Null

        [System.Windows.MessageBox]::Show("Profile '$profileName' saved.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to save profile: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileLoad {

    $profiles = @(Get-ClarkProfiles)

    if ($profiles.Count -eq 0) {

        [System.Windows.MessageBox]::Show("No saved profiles were found.", "clark", "OK", "Warning")

        return

    }



    Add-Type -AssemblyName Microsoft.VisualBasic

    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { $profiles[0] }

    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to load:", "Load Profile", $defaultName)

    if ([string]::IsNullOrWhiteSpace($profileName)) {

        return

    }



    try {

        Import-ClarkProfile -Name $profileName -ApplyToUI

        [System.Windows.MessageBox]::Show("Profile '$profileName' loaded.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to load profile: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileDelete {

    $profiles = @(Get-ClarkProfiles)

    if ($profiles.Count -eq 0) {

        [System.Windows.MessageBox]::Show("No saved profiles were found.", "clark", "OK", "Warning")

        return

    }



    Add-Type -AssemblyName Microsoft.VisualBasic

    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Available profiles: $($profiles -join ', ')`nEnter profile name to delete:", "Delete Profile", $profiles[0])

    if ([string]::IsNullOrWhiteSpace($profileName)) {

        return

    }



    try {

        Remove-ClarkProfile -Name $profileName

        [System.Windows.MessageBox]::Show("Profile '$profileName' deleted.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to delete profile: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFRollbackLastTweak {

    try {

        $restored = Invoke-ClarkRollbackLatest

        if ($restored) {

            [System.Windows.MessageBox]::Show("Last tweak snapshot was restored from rollback journal.", "clark", "OK", "Information")

        } else {

            [System.Windows.MessageBox]::Show("No rollback snapshot could be restored.", "clark", "OK", "Warning")

        }

    } catch {

        [System.Windows.MessageBox]::Show("Rollback failed: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Get-ClarkActivationScriptsRoot {

    $basePaths = @()

    if (-not [string]::IsNullOrWhiteSpace($sync.PSScriptRoot)) {

        $basePaths += $sync.PSScriptRoot

    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {

        $basePaths += $PSScriptRoot

    }

    $cwdPath = (Get-Location).Path

    if (-not [string]::IsNullOrWhiteSpace($cwdPath)) {

        $basePaths += $cwdPath

    }



    $candidateRoots = New-Object System.Collections.Generic.List[string]

    foreach ($basePath in ($basePaths | Select-Object -Unique)) {

        $current = $basePath

        for ($i = 0; $i -lt 5 -and -not [string]::IsNullOrWhiteSpace($current); $i++) {

            $candidateRoots.Add((Join-Path $current "Microsoft-Activation-Scripts-master"))

            $parent = Split-Path -Path $current -Parent

            if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $current)) {

                break

            }

            $current = $parent

        }

    }



    foreach ($candidate in ($candidateRoots | Select-Object -Unique)) {

        $masAioPath = Join-Path $candidate "MAS\All-In-One-Version-KL\MAS_AIO.cmd"

        if (Test-Path $masAioPath) {

            return $candidate

        }

    }



    return $null

}



function Invoke-WPFActivationScriptsMenu {

    try {

        $masRoot = Get-ClarkActivationScriptsRoot

        if (-not $masRoot) {

            throw "Microsoft-Activation-Scripts-master folder was not found near clark."

        }



        $masAioPath = Join-Path $masRoot "MAS\All-In-One-Version-KL\MAS_AIO.cmd"

        if (-not (Test-Path $masAioPath)) {

            throw "MAS menu script was not found: $masAioPath"

        }



        Start-Process -FilePath $masAioPath

    } catch {

        [System.Windows.MessageBox]::Show("Unable to open MAS menu: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFActivationStatus {

    try {

        # Summary is read from the license service via WMI only. Running MAS Check_Activation_Status.cmd

        # first blocked the UI for a long time and did not affect this dialog.

        $st = Get-ClarkActivationStatus

        $lines = @(

            "Summary (license service on this PC):",

            "",

            "Windows: $($st.Windows)",

            "Office: $($st.Office)",

            ""

        )



        $needActivate = @()

        if ($st.Windows -eq "Not Activated") {

            $needActivate += "Windows"

        }

        if ($st.OfficeDetected -and ($st.Office -eq "Not Activated")) {

            $needActivate += "Office"

        }



        if ($needActivate.Count -gt 0) {

            $lines += "May need activation: $($needActivate -join ', ')."

            $lines += "If you have a valid license, use the MAS activation menu."

        } else {

            $lines += "Nothing flagged as not activated (Windows activated; Office OK or not installed)."

        }



        [System.Windows.MessageBox]::Show(($lines -join [Environment]::NewLine), "Activation check", "OK", "Information") | Out-Null



        if ($needActivate.Count -gt 0) {

            if (Get-ClarkActivationScriptsRoot) {

                $openMas = [System.Windows.MessageBox]::Show(

                    "Open the MAS activation menu now?",

                    "Activation",

                    "YesNo",

                    "Question"

                )

                if ($openMas -eq [System.Windows.MessageBoxResult]::Yes) {

                    Invoke-WPFActivationScriptsMenu

                }

            }

        }

    } catch {

        [System.Windows.MessageBox]::Show("Activation check failed: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}



function Invoke-WPFProfileCreateWithOptions {

    Add-Type -AssemblyName System.Windows.Forms



    $defaultName = if ($sync.preferences.activeprofile) { $sync.preferences.activeprofile } else { "MyProfile" }



    $form = New-Object System.Windows.Forms.Form

    $form.Text = "Create profile - choose what to save"

    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    $form.ClientSize = New-Object System.Drawing.Size(440, 300)

    $form.MaximizeBox = $false

    $form.MinimizeBox = $false



    $lblName = New-Object System.Windows.Forms.Label

    $lblName.Text = "Profile name:"

    $lblName.Location = New-Object System.Drawing.Point(12, 14)

    $lblName.AutoSize = $true

    [void]$form.Controls.Add($lblName)



    $txtName = New-Object System.Windows.Forms.TextBox

    $txtName.Text = $defaultName

    $txtName.Location = New-Object System.Drawing.Point(12, 34)

    $txtName.Width = 410

    [void]$form.Controls.Add($txtName)



    [int]$profileFormY = 68

    $cbApps = New-Object System.Windows.Forms.CheckBox

    $cbApps.Text = "Include selected Applications (Install tab)"

    $cbApps.Checked = $true

    $cbApps.Location = New-Object System.Drawing.Point(12, $profileFormY)

    $cbApps.Width = 410

    [void]$form.Controls.Add($cbApps)

    $profileFormY = [int]($profileFormY + 28)



    $cbTweaks = New-Object System.Windows.Forms.CheckBox

    $cbTweaks.Text = "Include selected Tweaks"

    $cbTweaks.Checked = $true

    $cbTweaks.Location = New-Object System.Drawing.Point(12, $profileFormY)

    $cbTweaks.Width = 410

    [void]$form.Controls.Add($cbTweaks)

    $profileFormY = [int]($profileFormY + 28)



    $cbToggles = New-Object System.Windows.Forms.CheckBox

    $cbToggles.Text = "Include selected Config toggles"

    $cbToggles.Checked = $true

    $cbToggles.Location = New-Object System.Drawing.Point(12, $profileFormY)

    $cbToggles.Width = 410

    [void]$form.Controls.Add($cbToggles)

    $profileFormY = [int]($profileFormY + 28)



    $cbFeatures = New-Object System.Windows.Forms.CheckBox

    $cbFeatures.Text = "Include selected Config features"

    $cbFeatures.Checked = $true

    $cbFeatures.Location = New-Object System.Drawing.Point(12, $profileFormY)

    $cbFeatures.Width = 410

    [void]$form.Controls.Add($cbFeatures)

    $profileFormY = [int]($profileFormY + 32)



    $cbMerge = New-Object System.Windows.Forms.CheckBox

    $cbMerge.Text = "If this profile already exists, merge (add new entries; keep existing)"

    $cbMerge.Checked = $false

    $cbMerge.Location = New-Object System.Drawing.Point(12, $profileFormY)

    $cbMerge.Width = 410

    [void]$form.Controls.Add($cbMerge)



    $btnOk = New-Object System.Windows.Forms.Button

    $btnOk.Text = "Save"

    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $btnOk.Location = New-Object System.Drawing.Point(268, 258)

    $btnOk.Width = 75

    [void]$form.Controls.Add($btnOk)



    $btnCancel = New-Object System.Windows.Forms.Button

    $btnCancel.Text = "Cancel"

    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $btnCancel.Location = New-Object System.Drawing.Point(347, 258)

    $btnCancel.Width = 75

    [void]$form.Controls.Add($btnCancel)



    $form.AcceptButton = $btnOk

    $form.CancelButton = $btnCancel



    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {

        return

    }



    $profileName = $txtName.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($profileName)) {

        [System.Windows.MessageBox]::Show("Profile name cannot be empty.", "clark", "OK", "Warning")

        return

    }



    try {

        $saveArgs = @{
            Name            = $profileName
            IncludeApps     = [bool]$cbApps.Checked
            IncludeTweaks   = [bool]$cbTweaks.Checked
            IncludeToggles  = [bool]$cbToggles.Checked
            IncludeFeatures = [bool]$cbFeatures.Checked
            MergeExisting   = [bool]$cbMerge.Checked
        }
        Save-ClarkProfilePartial @saveArgs

        [System.Windows.MessageBox]::Show("Profile '$profileName' saved.", "clark", "OK", "Information")

    } catch {

        [System.Windows.MessageBox]::Show("Failed to save profile: $($_.Exception.Message)", "clark", "OK", "Error")

    }

}

function Invoke-WPFRegistryBackupManager {

    <#

    .SYNOPSIS

        UI to list pre-tweak .reg backups, open folder, or restore via reg import.

    #>

    Add-Type -AssemblyName System.Windows.Forms

    Add-Type -AssemblyName System.Drawing



    $form = New-Object System.Windows.Forms.Form

    $form.Text = "Clark - Registry backups (pre-tweak)"

    $form.Size = New-Object System.Drawing.Size(720, 420)

    $form.StartPosition = "CenterScreen"



    $lbl = New-Object System.Windows.Forms.Label

    $lbl.Location = New-Object System.Drawing.Point(12, 10)

    $lbl.Size = New-Object System.Drawing.Size(680, 40)

    $lbl.Text = "Backups are created automatically before running tweaks (HKCU/HKLM). Restoring merges values from the file into the registry; it does not delete keys added after the backup. Distinct from 'Rollback Last Tweak Snapshot' (rollback journal)."

    [void]$form.Controls.Add($lbl)



    $list = New-Object System.Windows.Forms.ListBox

    $list.Location = New-Object System.Drawing.Point(12, 55)

    $list.Size = New-Object System.Drawing.Size(680, 240)

    $list.SelectionMode = "MultiExtended"

    [void]$form.Controls.Add($list)



    foreach ($f in @(Get-ClarkRegistryBackupFiles)) {

        [void]$list.Items.Add($f.FullName)

    }



    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel

    $btnRow.Location = New-Object System.Drawing.Point(12, 302)

    $btnRow.Width = 696

    $btnRow.AutoSize = $true

    $btnRow.WrapContents = $true

    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight



    $btnFolder = New-Object System.Windows.Forms.Button

    $btnFolder.Text = "Open backups folder"

    $btnFolder.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)

    $btnFolder.Add_Click({

        Start-Process explorer.exe (Get-ClarkClarkBackupsDirectory)

    })

    [void]$btnRow.Controls.Add($btnFolder)



    $btnRefresh = New-Object System.Windows.Forms.Button

    $btnRefresh.Text = "Refresh"

    $btnRefresh.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)

    $btnRefresh.Add_Click({

        $list.Items.Clear()

        foreach ($f in @(Get-ClarkRegistryBackupFiles)) {

            [void]$list.Items.Add($f.FullName)

        }

    })

    [void]$btnRow.Controls.Add($btnRefresh)



    $btnRestore = New-Object System.Windows.Forms.Button

    $btnRestore.Text = "Restore selected..."

    $btnRestore.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)

    $btnRestore.Add_Click({

        if ($list.SelectedItems.Count -eq 0) {

            [System.Windows.Forms.MessageBox]::Show("Select one or more .reg files.", "clark", "OK", "Information")

            return

        }

        $msg = @"

reg import merges the selected file(s) into the current registry.



Run Clark as Administrator. Incorrect restores can destabilize Windows.



Continue?

"@

        $c = [System.Windows.Forms.MessageBox]::Show($msg, "Confirm restore", "YesNo", "Warning")

        if ($c -ne 'Yes') { return }

        $paths = @($list.SelectedItems | ForEach-Object { [string]$_ })

        try {

            Invoke-ClarkRegistryBackupRestore -LiteralPaths $paths

            [System.Windows.Forms.MessageBox]::Show("Restore completed.", "clark", "OK", "Information")

        } catch {

            [System.Windows.Forms.MessageBox]::Show("Restore failed: $($_.Exception.Message)", "clark", "OK", "Error")

        }

    })

    [void]$btnRow.Controls.Add($btnRestore)



    $btnClose = New-Object System.Windows.Forms.Button

    $btnClose.Text = "Close"

    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 6)

    $btnClose.Add_Click({ $form.Close() })

    [void]$btnRow.Controls.Add($btnClose)



    Set-WinFormsButtonFullText -Button @($btnFolder, $btnRefresh, $btnRestore, $btnClose)

    [void]$form.Controls.Add($btnRow)



    [void]$form.ShowDialog()

}

function Invoke-WPFRunspace {

    <#

    .SYNOPSIS
        Creates and invokes a runspace using the given scriptblock and argumentlist

    .PARAMETER ScriptBlock
        The scriptblock to invoke in the runspace

    .PARAMETER ArgumentList
        A list of arguments to pass to the runspace

    .PARAMETER ParameterList
        A list of named parameters that should be provided.
    .EXAMPLE
        Invoke-WPFRunspace `
            -ScriptBlock $sync.ScriptsInstallPrograms `
            -ArgumentList "Installadvancedip,Installbitwarden" `

        Invoke-WPFRunspace`
            -ScriptBlock $sync.ScriptsInstallPrograms `
            -ParameterList @(("PackagesToInstall", @("Installadvancedip,Installbitwarden")),("ChocoPreference", $true))
    #>

    [CmdletBinding()]
    Param (
        $ScriptBlock,
        $ArgumentList,
        $ParameterList
    )

    # Create a PowerShell instance
    $script:powershell = [powershell]::Create()

    # Add Scriptblock and Arguments to runspace
    $script:powershell.AddScript($ScriptBlock)
    $script:powershell.AddArgument($ArgumentList)

    foreach ($parameter in $ParameterList) {
        $script:powershell.AddParameter($parameter[0], $parameter[1])
    }

    $script:powershell.RunspacePool = $sync.runspace

    # Execute the RunspacePool
    $script:handle = $script:powershell.BeginInvoke()

    # Clean up the RunspacePool threads when they are complete, and invoke the garbage collector to clean up the memory
    if ($script:handle.IsCompleted) {
        $script:powershell.EndInvoke($script:handle)
        $script:powershell.Dispose()
        $sync.runspace.Dispose()
        $sync.runspace.Close()
        [System.GC]::Collect()
    }
    # Return the handle
    return $handle
}
function Invoke-WPFSelectedCheckboxesUpdate{
    <#
        .SYNOPSIS
            This is a helper function that is called by the Checked and Unchecked events of the Checkboxes.
            It also Updates the "Selected Apps" selectedAppLabel on the Install Tab to represent the current collection
        .PARAMETER type
            Either: Add | Remove
        .PARAMETER checkboxName
            should contain the name of the current instance of the checkbox that triggered the Event.
            Most of the time will be the automatic variable $this.Parent.Tag
        .EXAMPLE
            $checkbox.Add_Unchecked({Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $this.Parent.Tag})
            OR
            Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $specificCheckbox.Parent.Tag
    #>
    param (
        $type,
        $checkboxName
    )

    if (($type -ne "Add") -and ($type -ne "Remove")) {
        Write-Error "Type: $type not implemented"
        return
    }

    # Get the actual Name from the selectedAppLabel inside the Checkbox
    $appKey = $checkboxName
    $group = if ($appKey.StartsWith("WPFInstall")) { "Install" }
                elseif ($appKey.StartsWith("WPFTweaks")) { "Tweaks" }
                elseif ($appKey.StartsWith("WPFToggle")) { "Toggle" }
                elseif ($appKey.StartsWith("WPFFeature")) { "Feature" } else { "na" }

    switch ($group) {
        "Install" {
            if ($type -eq "Add") {
               if (!$sync.selectedApps.Contains($appKey)) {
                    $sync.selectedApps.Add($appKey)
                    # The List type needs to be specified again, because otherwise Sort-Object will convert the list to a string if there is only a single entry
                    [System.Collections.Generic.List[string]]$sync.selectedApps = $sync.SelectedApps | Sort-Object
                }
            } else {
                $sync.selectedApps.Remove($appKey)
            }

            $count = $sync.SelectedApps.Count
            $sync.WPFselectedAppsButton.Content = "Selected Apps: $count"
            # On every change, remove all entries inside the Popup Menu. This is done, so we can keep the alphabetical order even if elements are selected in a random way
            $sync.selectedAppsstackPanel.Children.Clear()
            $sync.selectedApps | Foreach-Object { Add-SelectedAppsMenuItem -name $($sync.configs.applicationsHashtable.$_.Content) -key $_ }
        }
        "Tweaks" {
            if ($type -eq "Add") {
                if (!$sync.selectedTweaks.Contains($appKey)) {
                    $sync.selectedTweaks.Add($appKey)
                }
            } else {
                $sync.selectedTweaks.Remove($appKey)
            }
        }
        "Toggle" {
            if ($type -eq "Add") {
                if (!$sync.selectedToggles.Contains($appKey)) {
                    $sync.selectedToggles.Add($appKey)
                }
            } else {
                $sync.selectedToggles.Remove($appKey)
            }
        }
        "Feature" {
            if ($type -eq "Add") {
                if (!$sync.selectedFeatures.Contains($appKey)) {
                    $sync.selectedFeatures.Add($appKey)
                }
            } else {
                $sync.selectedFeatures.Remove($appKey)
            }
        }
        default {
            Write-Host "Unknown group for checkbox: $($appKey)"
        }
    }

    Write-Debug "-------------------------------------"
    Write-Debug "Selected Apps: $($sync.selectedApps)"
    Write-Debug "Selected Tweaks: $($sync.selectedTweaks)"
    Write-Debug "Selected Toggles: $($sync.selectedToggles)"
    Write-Debug "Selected Features: $($sync.selectedFeatures)"
    Write-Debug "--------------------------------------"
}
function Invoke-WPFSSHServer {

    <#



    .SYNOPSIS

        Invokes the OpenSSH Server install in a runspace



  #>



    Invoke-WPFRunspace -ScriptBlock {



        Invoke-ClarkSSHServer



        Write-Host "======================================="

        Write-Host "--     OpenSSH Server installed!    ---"

        Write-Host "======================================="

    }

}

function Invoke-WPFStartupManager {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Get-ExecutablePathFromStartupCommand {
        param([string]$CommandLine)
        if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
        $t = $CommandLine.Trim()
        if ($t -match '^"([^"]+\.(?:exe|EXE))"') { return $matches[1] }
        $idx = $t.ToLowerInvariant().IndexOf('.exe')
        if ($idx -ge 0) {
            return $t.Substring(0, $idx + 4).Trim().Trim('"')
        }
        if ($t -match '^(\S+\.(?:exe|EXE))\b') { return $matches[1] }
        return $null
    }

    function Test-StartupExePath {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
        try {
            return (Test-Path -LiteralPath $Path)
        } catch {
            return $false
        }
    }

    function Get-StartupEntries {
        $list = [System.Collections.Generic.List[object]]::new()

        $runPaths = @(
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; L = 'HKCU Run' },
            @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; L = 'HKCU RunOnce' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; L = 'HKLM Run' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; L = 'HKLM RunOnce' },
            @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; L = 'HKLM WOW Run' }
        )
        foreach ($rp in $runPaths) {
            if (-not (Test-Path -LiteralPath $rp.P)) { continue }
            $props = Get-ItemProperty -LiteralPath $rp.P -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($n in $props.PSObject.Properties) {
                if ($n.Name -match '^PS') { continue }
                if ($n.Name -eq '(default)') { continue }
                $cmd = [string]$n.Value
                if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
                $pub = ""
                $exePath = Get-ExecutablePathFromStartupCommand -CommandLine $cmd
                if ($exePath -and (Test-StartupExePath -Path $exePath)) {
                    try {
                        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
                        $pub = $ver.CompanyName
                    } catch { }
                }
                [void]$list.Add([pscustomobject]@{
                        Kind     = 'RunKey'
                        Location = $rp.L
                        RegPath  = $rp.P
                        Name     = $n.Name
                        Command  = $cmd
                        Publisher = $pub
                    })
            }
        }

        foreach ($folderKind in @('User', 'Common')) {
            $fd = if ($folderKind -eq 'User') {
                [Environment]::GetFolderPath('Startup')
            } else {
                [Environment]::GetFolderPath('CommonStartup')
            }
            if (-not (Test-Path -LiteralPath $fd)) { continue }
            Get-ChildItem -LiteralPath $fd -ErrorAction SilentlyContinue | ForEach-Object {
                $target = $_.FullName
                if ($_.Extension -eq '.lnk') {
                    try {
                        $sh = New-Object -ComObject WScript.Shell
                        $sc = $sh.CreateShortcut($_.FullName)
                        $target = $sc.TargetPath
                    } catch { }
                }
                $pub = ""
                if ($target -and (Test-Path -LiteralPath $target)) {
                    try {
                        $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($target)
                        $pub = $ver.CompanyName
                    } catch { }
                }
                [void]$list.Add([pscustomobject]@{
                        Kind     = 'StartupFolder'
                        Location = "$folderKind Startup"
                        RegPath  = $fd
                        Name     = $_.Name
                        Command  = $target
                        Publisher = $pub
                    })
            }
        }
        return $list
    }

    function Move-StartupFolderItemDisabled {
        param($item)
        $disabledRoot = Join-Path $env:LOCALAPPDATA "asys\StartupDisabled"
        if (-not (Test-Path $disabledRoot)) {
            New-Item -ItemType Directory -Path $disabledRoot -Force | Out-Null
        }
        $src = Join-Path $item.RegPath $item.Name
        $dst = Join-Path $disabledRoot $item.Name
        Move-Item -LiteralPath $src -Destination $dst -Force
    }

    function Move-StartupFolderItemEnabled {
        param($item)
        $disabledRoot = Join-Path $env:LOCALAPPDATA "asys\StartupDisabled"
        $src = Join-Path $disabledRoot $item.Name
        $dst = Join-Path $item.RegPath $item.Name
        if (Test-Path -LiteralPath $src) {
            Move-Item -LiteralPath $src -Destination $dst -Force
        }
    }

    function Set-RunKeyDisabled {
        param($item)
        $backup = 'HKCU:\Software\Clark\DisabledStartup'
        if (-not (Test-Path $backup)) {
            New-Item -Path $backup -Force | Out-Null
        }
        Set-ItemProperty -LiteralPath $backup -Name $item.Name -Value $item.Command -Type String -Force
        Remove-ItemProperty -LiteralPath $item.RegPath -Name $item.Name -ErrorAction Stop
    }

    function Set-RunKeyEnabled {
        param($item)
        $backup = 'HKCU:\Software\Clark\DisabledStartup'
        $prop = Get-ItemProperty -LiteralPath $backup -ErrorAction Stop
        $cmd = $prop.$($item.Name)
        if ([string]::IsNullOrWhiteSpace([string]$cmd)) { throw "No backup value for $($item.Name)." }
        Set-ItemProperty -LiteralPath $item.RegPath -Name $item.Name -Value $cmd -Type String -Force
        Remove-ItemProperty -LiteralPath $backup -Name $item.Name -ErrorAction SilentlyContinue
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark - Startup manager"
    $form.Size = New-Object System.Drawing.Size(900, 520)
    $form.StartPosition = "CenterScreen"

    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.Dock = "Fill"
    $dg.ReadOnly = $true
    $dg.AutoGenerateColumns = $false
    $dg.SelectionMode = "FullRowSelect"
    $dg.MultiSelect = $false
    foreach ($colDef in @(
            @{ Name = 'Kind'; HeaderText = 'Kind'; Width = 90 }
            @{ Name = 'Location'; HeaderText = 'Location'; Width = 120 }
            @{ Name = 'Name'; HeaderText = 'Name'; Width = 140 }
            @{ Name = 'Command'; HeaderText = 'Executable / command'; Width = 360 }
            @{ Name = 'Publisher'; HeaderText = 'Publisher'; Width = 120 }
        )) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $colDef.Name
        $c.HeaderText = $colDef.HeaderText
        $c.Width = $colDef.Width
        [void]$dg.Columns.Add($c)
    }
    $dg.Tag = [System.Collections.Generic.List[object]]::new()

    function Refresh-Grid {
        $dg.Rows.Clear()
        $dg.Tag.Clear()
        foreach ($e in @(Get-StartupEntries)) {
            [void]$dg.Tag.Add($e)
            [void]$dg.Rows.Add(@($e.Kind, $e.Location, $e.Name, $e.Command, $e.Publisher))
        }
    }

    Refresh-Grid

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = "Bottom"
    $flow.WrapContents = $true
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $flow.AutoSize = $true
    $flow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $flow.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 6)

    $btnDis = New-Object System.Windows.Forms.Button
    $btnDis.Text = "Disable selected"
    $btnDis.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnDis.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $idx = $dg.SelectedRows[0].Index
        $item = $dg.Tag[$idx]
        try {
            if ($item.Kind -eq 'RunKey') {
                if ($item.RegPath -like 'HKLM:*') {
                    [System.Windows.Forms.MessageBox]::Show("Disabling HKLM Run entries requires manual policy or running elevated scripts. Only HKCU Run keys are auto-disabled here.", "clark", "OK", "Information")
                    return
                }
                Set-RunKeyDisabled -item $item
            } else {
                Move-StartupFolderItemDisabled -item $item
            }
            Refresh-Grid
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Disable", "OK", "Error")
        }
    })
    [void]$flow.Controls.Add($btnDis)

    $btnEn = New-Object System.Windows.Forms.Button
    $btnEn.Text = "Enable (restore)"
    $btnEn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnEn.Add_Click({
        if ($dg.SelectedRows.Count -eq 0) { return }
        $idx = $dg.SelectedRows[0].Index
        $item = $dg.Tag[$idx]
        try {
            if ($item.Kind -eq 'RunKey') {
                if ($item.RegPath -like 'HKLM:*') { return }
                Set-RunKeyEnabled -item $item
            } else {
                Move-StartupFolderItemEnabled -item $item
            }
            Refresh-Grid
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Enable", "OK", "Error")
        }
    })
    [void]$flow.Controls.Add($btnEn)

    $btnRef = New-Object System.Windows.Forms.Button
    $btnRef.Text = "Refresh"
    $btnRef.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnRef.Add_Click({ Refresh-Grid })
    [void]$flow.Controls.Add($btnRef)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnClose.Add_Click({ $form.Close() })
    [void]$flow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnDis, $btnEn, $btnRef, $btnClose)

    [void]$form.Controls.Add($flow)
    [void]$form.Controls.Add($dg)
    [void]$form.ShowDialog()
}
function Invoke-WPFSystemRepair {

    <#

    .SYNOPSIS

        Checks for system corruption using SFC, and DISM

        Checks for disk failure using Chkdsk



    .DESCRIPTION

        1. Chkdsk - Checks for disk errors, which can cause system file corruption and notifies of early disk failure

        2. SFC - scans protected system files for corruption and fixes them

        3. DISM - Repair a corrupted Windows operating system image

    #>



    Start-Process cmd.exe -ArgumentList "/c chkdsk /scan /perf" -NoNewWindow -Wait

    Start-Process cmd.exe -ArgumentList "/c sfc /scannow" -NoNewWindow -Wait

    Start-Process cmd.exe -ArgumentList "/c dism /online /cleanup-image /restorehealth" -NoNewWindow -Wait



    Write-Host "==> Finished System Repair"

    Set-ClarkTaskbaritem -state "None" -overlay "checkmark"

}

function Invoke-WPFTab {



    <#



    .SYNOPSIS

        Sets the selected tab to the tab that was clicked



    .PARAMETER ClickedTab

        The name of the tab that was clicked



    #>



    Param (

        [Parameter(Mandatory,position=0)]

        [string]$ClickedTab

    )



    $tabItemName = $ClickedTab -replace 'BT$'

    $tabButtons = Get-ClarkVariables -Type ToggleButton | Where-Object { $_ -match '^WPFTab\d+BT$' }

    foreach ($buttonName in $tabButtons) {

        $tb = $sync[$buttonName]

        if ($tb) {

            $tb.IsChecked = ($buttonName -eq $ClickedTab)

        }

    }



    if ($sync[$tabItemName]) {

        $sync[$tabItemName].IsSelected = $true

        $sync.currentTab = [string]$sync[$tabItemName].Header

    } else {

        return

    }



    # Always reset the filter for the current tab

    if ($sync.currentTab -eq "Install") {

        # Reset Install tab filter

        Find-AppsByNameOrDescription -SearchString ""

    } elseif ($sync.currentTab -eq "Tweaks") {

        # Reset Tweaks tab filter

        Find-TweaksByNameOrDescription -SearchString ""

    }



    # Show search bar in Install and Tweaks tabs (null-safe: other tabs used to NRE here and close the app)

    $win = $sync["Form"]

    $sbByName = if ($win) { $win.FindName("SearchBar") } else { $null }

    if ($sync.currentTab -eq "Install" -or $sync.currentTab -eq "Tweaks") {

        if ($sync.SearchBar) {

            $sync.SearchBar.Visibility = "Visible"

        }

        if ($sbByName -and $sbByName.Parent) {

            $searchIcon = @($sbByName.Parent.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Text -eq [char]0xE721 })[0]

            if ($searchIcon) {

                $searchIcon.Visibility = "Visible"

            }

        }

    } else {

        if ($sync.SearchBar) {

            $sync.SearchBar.Visibility = "Collapsed"

        }

        if ($sbByName -and $sbByName.Parent) {

            $searchIcon = @($sbByName.Parent.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Text -eq [char]0xE721 })[0]

            if ($searchIcon) {

                $searchIcon.Visibility = "Collapsed"

            }

        }

        if ($sync.SearchBarClearButton) {

            $sync.SearchBarClearButton.Visibility = "Collapsed"

        }

    }

}

function Invoke-WPFToggleAllCategories {
    <#
        .SYNOPSIS
            Expands or collapses all categories in the Install tab

        .PARAMETER Action
            The action to perform: "Expand" or "Collapse"

        .DESCRIPTION
            This function iterates through all category containers in the Install tab
            and expands or collapses their WrapPanels while updating the toggle button labels
    #>

    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Expand", "Collapse")]
        [string]$Action
    )

    try {
        if ($null -eq $sync.ItemsControl) {
            Write-Warning "ItemsControl not initialized"
            return
        }

        $targetVisibility = if ($Action -eq "Expand") { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
        $targetPrefix = if ($Action -eq "Expand") { "-" } else { "+" }
        $sourcePrefix = if ($Action -eq "Expand") { "+" } else { "-" }

        # Iterate through all items in the ItemsControl
        $sync.ItemsControl.Items | ForEach-Object {
            $categoryContainer = $_

            # Check if this is a category container (StackPanel with children)
            if ($categoryContainer -is [System.Windows.Controls.StackPanel] -and $categoryContainer.Children.Count -ge 2) {
                # Get the WrapPanel (second child)
                $wrapPanel = $categoryContainer.Children[1]
                $wrapPanel.Visibility = $targetVisibility

                # Update the label to show the correct state
                $categoryLabel = $categoryContainer.Children[0]
                if ($categoryLabel.Content -like "$sourcePrefix*") {
                    $escapedSourcePrefix = [regex]::Escape($sourcePrefix)
                    $categoryLabel.Content = $categoryLabel.Content -replace "^$escapedSourcePrefix ", "$targetPrefix "
                }
            }
        }
    } catch {
        Write-Error "Error toggling categories: $_"
    }
}
function Invoke-WPFtweaksbutton {

  <#



    .SYNOPSIS

        Invokes the functions associated with each group of checkboxes



  #>



  if($sync.ProcessRunning) {

    $msg = "[Invoke-WPFtweaksbutton] Install process is currently running."

    [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

    return

  }



  $Tweaks = $sync.selectedTweaks

  $dnsProvider = $sync["WPFchangedns"].text

  $restorePointTweak = "WPFTweaksRestorePoint"

  $restorePointSelected = $Tweaks -contains $restorePointTweak

  $tweaksToRun = @($Tweaks | Where-Object { $_ -ne $restorePointTweak })

  $totalSteps = [Math]::Max($Tweaks.Count, 1)

  $completedSteps = 0



  if ($tweaks.count -eq 0 -and $dnsProvider -eq "Default") {

    $msg = "Please check the tweaks you wish to perform."

    [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

    return

  }



  Write-Debug "Number of tweaks to process: $($Tweaks.Count)"



  $needsRegistryTweakWork = ($restorePointSelected -or ($tweaksToRun.Count -gt 0))

  if ($needsRegistryTweakWork) {

    try {

      $bak = Invoke-ClarkPreTweakRegistryExport

      foreach ($m in @($bak.Messages)) { Write-Host $m }

      if (-not $bak.HKCUOk -or -not $bak.HKLMOk) {

        Write-Warning "Pre-tweak registry export incomplete (HKCU:$($bak.HKCUOk) HKLM:$($bak.HKLMOk)). Restore may require Administrator."

      }

    } catch {

      Write-Warning "Pre-tweak registry backup failed: $($_.Exception.Message)"

    }

  }



  if ($restorePointSelected) {

    $sync.ProcessRunning = $true



    if ($Tweaks.Count -eq 1) {

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" -value 0.01 -overlay "logo" }

    } else {

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo" }

    }



    Set-ClarkProgressBar -Label "Creating restore point" -Percent 0

    Invoke-ClarkTweaks $restorePointTweak

    $completedSteps = 1



    if ($tweaksToRun.Count -eq 0 -and $dnsProvider -eq "Default") {

      Set-ClarkProgressBar -Label "Tweaks finished" -Percent 100

      $sync.ProcessRunning = $false

      Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }

      Write-Host "================================="

      Write-Host "--     Tweaks are Finished    ---"

      Write-Host "================================="

      return

    }

  }



  # The leading "," in the ParameterList is necessary because we only provide one argument and powershell cannot be convinced that we want a nested loop with only one argument otherwise

  $handle = Invoke-WPFRunspace -ParameterList @(("tweaks", $tweaksToRun), ("dnsProvider", $dnsProvider), ("completedSteps", $completedSteps), ("totalSteps", $totalSteps)) -ScriptBlock {

    param($tweaks, $dnsProvider, $completedSteps, $totalSteps)

    Write-Debug "Inside Number of tweaks to process: $($Tweaks.Count)"



    $sync.ProcessRunning = $true



    if ($completedSteps -eq 0) {

      if ($Tweaks.count -eq 1) {

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" -value 0.01 -overlay "logo" }

      } else {

        Invoke-WPFUIThread -ScriptBlock{ Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo" }

      }

    }



    Set-ClarkDNS -DNSProvider $dnsProvider



    for ($i = 0; $i -lt $tweaks.Count; $i++) {

      Set-ClarkProgressBar -Label "Applying $($tweaks[$i])" -Percent ($completedSteps / $totalSteps * 100)

      Invoke-ClarkTweaks $tweaks[$i]

      $completedSteps++

      $progress = $completedSteps / $totalSteps

      Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -value $progress }

    }

    Set-ClarkProgressBar -Label "Tweaks finished" -Percent 100

    $sync.ProcessRunning = $false

    Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }

    Write-Host "================================="

    Write-Host "--     Tweaks are Finished    ---"

    Write-Host "================================="

  }

}

function Invoke-WPFUIElements {

    <#

    .SYNOPSIS

        Adds UI elements to a specified Grid in the A-SYS_clark GUI based on a JSON configuration.

    .PARAMETER configVariable

        The variable/link containing the JSON configuration.

    .PARAMETER targetGridName

        The name of the grid to which the UI elements should be added.

    .PARAMETER columncount

        The number of columns to be used in the Grid. If not provided, a default value is used based on the panel.

    .EXAMPLE

        Invoke-WPFUIElements -configVariable $sync.configs.applications -targetGridName "install" -columncount 5

    .NOTES

        Future me/contributor: If possible, please wrap this into a runspace to make it load all panels at the same time.

    #>



    param(

        [Parameter(Mandatory, Position = 0)]

        [PSCustomObject]$configVariable,



        [Parameter(Mandatory, Position = 1)]

        [string]$targetGridName,



        [Parameter(Mandatory, Position = 2)]

        [int]$columncount

    )



    $window = $sync.form



    $borderstyle = $window.FindResource("BorderStyle")

    $HoverTextBlockStyle = $window.FindResource("HoverTextBlockStyle")

    $ColorfulToggleSwitchStyle = $window.FindResource("ColorfulToggleSwitchStyle")

    $ToggleButtonStyle = $window.FindResource("ToggleButtonStyle")



    if (!$borderstyle -or !$HoverTextBlockStyle -or !$ColorfulToggleSwitchStyle) {

        throw "Failed to retrieve Styles using 'FindResource' from main window element."

    }



    $targetGrid = $window.FindName($targetGridName)



    if (!$targetGrid) {

        throw "Failed to retrieve Target Grid by name, provided name: $targetGrid"

    }



    # Clear existing ColumnDefinitions and Children

    $targetGrid.ColumnDefinitions.Clear() | Out-Null

    $targetGrid.Children.Clear() | Out-Null



    # Add ColumnDefinitions to the target Grid

    for ($i = 0; $i -lt $columncount; $i++) {

        $colDef = New-Object Windows.Controls.ColumnDefinition

        $colDef.Width = New-Object Windows.GridLength(1, [Windows.GridUnitType]::Star)

        $targetGrid.ColumnDefinitions.Add($colDef) | Out-Null

    }



    # Convert PSCustomObject to Hashtable

    $configHashtable = @{}

    $configVariable.PSObject.Properties.Name | ForEach-Object {

        $configHashtable[$_] = $configVariable.$_

    }



    $radioButtonGroups = @{}



    $organizedData = @{}

    # Iterate through JSON data and organize by panel and category

    foreach ($entry in $configHashtable.Keys) {

        $entryInfo = $configHashtable[$entry]



        # Create an object for the application

        $cat = if ($null -ne $entryInfo.Category) { $entryInfo.Category } elseif ($null -ne $entryInfo.category) { $entryInfo.category } else { "" }

        $typ = if ($null -ne $entryInfo.Type) { $entryInfo.Type } elseif ($null -ne $entryInfo.type) { $entryInfo.type } else { "" }

        $desc = if ($null -ne $entryInfo.Description) { $entryInfo.Description } elseif ($null -ne $entryInfo.description) { $entryInfo.description } else { "" }



        $entryObject = [PSCustomObject]@{

            Name        = $entry

            Category    = $cat

            Content     = $entryInfo.Content

            Panel       = if ($entryInfo.Panel) { $entryInfo.Panel } elseif ($entryInfo.panel) { $entryInfo.panel } else { "0" }

            Order       = if ($null -ne $entryInfo.Order) { [int]$entryInfo.Order } elseif ($null -ne $entryInfo.order) { [int]$entryInfo.order } else { [int]::MaxValue }

            Link        = $entryInfo.link

            Description = $desc

            Type        = $typ

            ComboItems  = $entryInfo.ComboItems

            Checked     = $entryInfo.Checked

            ButtonWidth = $entryInfo.ButtonWidth

            GroupName   = $entryInfo.GroupName  # Added for RadioButton groupings

        }



        if (-not $organizedData.ContainsKey($entryObject.Panel)) {

            $organizedData[$entryObject.Panel] = @{}

        }



        if (-not $organizedData[$entryObject.Panel].ContainsKey($entryObject.Category)) {

            $organizedData[$entryObject.Panel][$entryObject.Category] = @()

        }



        # Store application data in an array under the category

        $organizedData[$entryObject.Panel][$entryObject.Category] += $entryObject



    }



    # Initialize panel count

    $panelcount = 0



    # Iterate through 'organizedData' by panel, category, and application

    $count = 0

    foreach ($panelKey in ($organizedData.Keys | Sort-Object)) {

        # Create a Border for each column

        $border = New-Object Windows.Controls.Border

        $border.VerticalAlignment = "Stretch"

        [System.Windows.Controls.Grid]::SetColumn($border, $panelcount)

        $border.style = $borderstyle

        $targetGrid.Children.Add($border) | Out-Null



        # Use a DockPanel to contain the content

        $dockPanelContainer = New-Object Windows.Controls.DockPanel

        $border.Child = $dockPanelContainer



        # Create an ItemsControl for application content

        $itemsControl = New-Object Windows.Controls.ItemsControl

        $itemsControl.HorizontalAlignment = 'Stretch'

        $itemsControl.VerticalAlignment = 'Stretch'



        # Set the ItemsPanel to a VirtualizingStackPanel

        $itemsPanelTemplate = New-Object Windows.Controls.ItemsPanelTemplate

        $factory = New-Object Windows.FrameworkElementFactory ([Windows.Controls.VirtualizingStackPanel])

        $itemsPanelTemplate.VisualTree = $factory

        $itemsControl.ItemsPanel = $itemsPanelTemplate



        # Set virtualization properties

        $itemsControl.SetValue([Windows.Controls.VirtualizingStackPanel]::IsVirtualizingProperty, $true)

        $itemsControl.SetValue([Windows.Controls.VirtualizingStackPanel]::VirtualizationModeProperty, [Windows.Controls.VirtualizationMode]::Recycling)



        # Add the ItemsControl directly to the DockPanel

        [Windows.Controls.DockPanel]::SetDock($itemsControl, [Windows.Controls.Dock]::Bottom)

        $dockPanelContainer.Children.Add($itemsControl) | Out-Null

        $panelcount++



        # Now proceed with adding category labels and entries to $itemsControl

        foreach ($category in ($organizedData[$panelKey].Keys | Sort-Object)) {

            $count++



            $label = New-Object Windows.Controls.Label

            $label.Content = $category -replace ".*__", ""

            $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")

            $label.SetResourceReference([Windows.Controls.Control]::FontFamilyProperty, "HeaderFontFamily")

            $label.UseLayoutRounding = $true

            $itemsControl.Items.Add($label) | Out-Null

            $sync[$category] = $label



            # Sort entries by explicit Order first, then by type, then alphabetically by Content.

            $entries = $organizedData[$panelKey][$category] | Sort-Object Order, @{Expression = {

                switch ($_.Type) {

                    'Button' { 1 }

                    'Combobox' { 2 }

                    default { 0 }

                }

            }}, Content

            foreach ($entryInfo in $entries) {

                $count++

                # Create the UI elements based on the entry type

                switch ($entryInfo.Type) {

                    "Toggle" {

                        $dockPanel = New-Object Windows.Controls.DockPanel

                        [System.Windows.Automation.AutomationProperties]::SetName($dockPanel, $entryInfo.Content)

                        $checkBox = New-Object Windows.Controls.CheckBox

                        $checkBox.Name = $entryInfo.Name

                        $checkBox.HorizontalAlignment = "Right"

                        $checkBox.UseLayoutRounding = $true

                        [System.Windows.Automation.AutomationProperties]::SetName($checkBox, $entryInfo.Content)

                        $dockPanel.Children.Add($checkBox) | Out-Null

                        $checkBox.Style = $ColorfulToggleSwitchStyle



                        $label = New-Object Windows.Controls.Label

                        $label.Content = $entryInfo.Content

                        $label.ToolTip = $entryInfo.Description

                        $label.HorizontalAlignment = "Left"

                        $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")

                        $label.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")

                        $label.UseLayoutRounding = $true

                        $dockPanel.Children.Add($label) | Out-Null

                        $itemsControl.Items.Add($dockPanel) | Out-Null



                        $sync[$entryInfo.Name] = $checkBox

                        if ($entryInfo.Name -eq "WPFToggleFOSSHighlight") {

                             if ($entryInfo.Checked -eq $true) {

                                 $sync[$entryInfo.Name].IsChecked = $true

                             }



                             $sync[$entryInfo.Name].Add_Checked({

                                 Invoke-WPFButton -Button "WPFToggleFOSSHighlight"

                             })

                             $sync[$entryInfo.Name].Add_Unchecked({

                                 Invoke-WPFButton -Button "WPFToggleFOSSHighlight"

                             })

                        } else {

                            $sync[$entryInfo.Name].IsChecked = (Get-ClarkToggleStatus $entryInfo.Name)



                            $sync[$entryInfo.Name].Add_Checked({

                                [System.Object]$Sender = $args[0]

                                Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $Sender.name

                                # Skip applying tweaks while an import is restoring toggle states

                                if (-not $sync.ImportInProgress) {

                                    $null = Invoke-ClarkPreTweakRegistryExportIfNeeded

                                    Invoke-ClarkTweaks $Sender.name

                                }

                            })



                            $sync[$entryInfo.Name].Add_Unchecked({

                                [System.Object]$Sender = $args[0]

                                Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkboxName $Sender.name

                                # Skip undoing tweaks while an import is restoring toggle states

                                if (-not $sync.ImportInProgress) {

                                    $null = Invoke-ClarkPreTweakRegistryExportIfNeeded

                                    Invoke-Clarktweaks $Sender.name -undo $true

                                }

                            })

                        }

                    }



                    "ToggleButton" {

                        $toggleButton = New-Object Windows.Controls.Primitives.ToggleButton

                        $toggleButton.Name = $entryInfo.Name

                        $toggleButton.Content = $entryInfo.Content[1]

                        $toggleButton.ToolTip = $entryInfo.Description

                        $toggleButton.HorizontalAlignment = "Left"

                        $toggleButton.Style = $ToggleButtonStyle

                        [System.Windows.Automation.AutomationProperties]::SetName($toggleButton, $entryInfo.Content[0])



                        $toggleButton.Tag = @{

                            contentOn = if ($entryInfo.Content.Count -ge 1) { $entryInfo.Content[0] } else { "" }

                            contentOff = if ($entryInfo.Content.Count -ge 2) { $entryInfo.Content[1] } else { $contentOn }

                        }



                        $itemsControl.Items.Add($toggleButton) | Out-Null



                        $sync[$entryInfo.Name] = $toggleButton



                        $sync[$entryInfo.Name].Add_Checked({

                            $this.Content = $this.Tag.contentOn

                        })



                        $sync[$entryInfo.Name].Add_Unchecked({

                            $this.Content = $this.Tag.contentOff

                        })

                    }



                    "Combobox" {

                        $horizontalStackPanel = New-Object Windows.Controls.StackPanel

                        $horizontalStackPanel.Orientation = "Horizontal"

                        $horizontalStackPanel.Margin = "0,5,0,0"

                        [System.Windows.Automation.AutomationProperties]::SetName($horizontalStackPanel, $entryInfo.Content)



                        $label = New-Object Windows.Controls.Label

                        $label.Content = $entryInfo.Content

                        $label.HorizontalAlignment = "Left"

                        $label.VerticalAlignment = "Center"

                        $label.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")

                        $label.UseLayoutRounding = $true

                        $horizontalStackPanel.Children.Add($label) | Out-Null



                        $comboBox = New-Object Windows.Controls.ComboBox

                        $comboBox.Name = $entryInfo.Name

                        $comboBox.SetResourceReference([Windows.Controls.Control]::HeightProperty, "ButtonHeight")

                        $comboBox.SetResourceReference([Windows.Controls.Control]::WidthProperty, "ButtonWidth")

                        $comboBox.HorizontalAlignment = "Left"

                        $comboBox.VerticalAlignment = "Center"

                        $comboBox.SetResourceReference([Windows.Controls.Control]::MarginProperty, "ButtonMargin")

                        $comboBox.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")

                        $comboBox.UseLayoutRounding = $true

                        [System.Windows.Automation.AutomationProperties]::SetName($comboBox, $entryInfo.Content)



                        foreach ($comboitem in ($entryInfo.ComboItems -split " ")) {

                            $comboBoxItem = New-Object Windows.Controls.ComboBoxItem

                            $comboBoxItem.Content = $comboitem

                            $comboBoxItem.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")

                            $comboBoxItem.UseLayoutRounding = $true

                            $comboBox.Items.Add($comboBoxItem) | Out-Null

                        }



                        $horizontalStackPanel.Children.Add($comboBox) | Out-Null

                        $itemsControl.Items.Add($horizontalStackPanel) | Out-Null



                        $comboBox.SelectedIndex = 0



                        # Set initial text

                        if ($comboBox.Items.Count -gt 0) {

                            $comboBox.Text = $comboBox.Items[0].Content

                        }



                        # Add SelectionChanged event handler to update the text property

                        $comboBox.Add_SelectionChanged({

                            $selectedItem = $this.SelectedItem

                            if ($selectedItem) {

                                $this.Text = $selectedItem.Content

                            }

                        })



                        $sync[$entryInfo.Name] = $comboBox

                    }



                    "Button" {

                        $button = New-Object Windows.Controls.Button

                        $button.Name = $entryInfo.Name

                        $button.Content = $entryInfo.Content

                        $button.HorizontalAlignment = "Left"

                        $button.SetResourceReference([Windows.Controls.Control]::MarginProperty, "ButtonMargin")

                        $button.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")

                        if ($entryInfo.Description) {

                            $button.ToolTip = $entryInfo.Description

                        }

                        if ($entryInfo.ButtonWidth) {

                            $baseWidth = [int]$entryInfo.ButtonWidth

                            $button.Width = [math]::Max($baseWidth, 350)

                        }

                        [System.Windows.Automation.AutomationProperties]::SetName($button, $entryInfo.Content)

                        $itemsControl.Items.Add($button) | Out-Null



                        $sync[$entryInfo.Name] = $button

                    }



                    "RadioButton" {

                        # Check if a container for this GroupName already exists

                        if (-not $radioButtonGroups.ContainsKey($entryInfo.GroupName)) {

                            # Create a StackPanel for this group

                            $groupStackPanel = New-Object Windows.Controls.StackPanel

                            $groupStackPanel.Orientation = "Vertical"

                            [System.Windows.Automation.AutomationProperties]::SetName($groupStackPanel, $entryInfo.GroupName)



                            # Add the group container to the ItemsControl

                            $itemsControl.Items.Add($groupStackPanel) | Out-Null

                        } else {

                            # Retrieve the existing group container

                            $groupStackPanel = $radioButtonGroups[$entryInfo.GroupName]

                        }



                        # Create the RadioButton

                        $radioButton = New-Object Windows.Controls.RadioButton

                        $radioButton.Name = $entryInfo.Name

                        $radioButton.GroupName = $entryInfo.GroupName

                        $radioButton.Content = $entryInfo.Content

                        $radioButton.HorizontalAlignment = "Left"

                        $radioButton.SetResourceReference([Windows.Controls.Control]::MarginProperty, "CheckBoxMargin")

                        $radioButton.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "ButtonFontSize")

                        $radioButton.ToolTip = $entryInfo.Description

                        $radioButton.UseLayoutRounding = $true

                        [System.Windows.Automation.AutomationProperties]::SetName($radioButton, $entryInfo.Content)



                        if ($entryInfo.Checked -eq $true) {

                            $radioButton.IsChecked = $true

                        }



                        # Add the RadioButton to the group container

                        $groupStackPanel.Children.Add($radioButton) | Out-Null

                        $sync[$entryInfo.Name] = $radioButton

                    }



                    default {

                        $horizontalStackPanel = New-Object Windows.Controls.StackPanel

                        $horizontalStackPanel.Orientation = "Horizontal"

                        [System.Windows.Automation.AutomationProperties]::SetName($horizontalStackPanel, $entryInfo.Content)



                        $checkBox = New-Object Windows.Controls.CheckBox

                        $checkBox.Name = $entryInfo.Name

                        $checkBox.Content = $entryInfo.Content

                        $checkBox.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "FontSize")

                        $checkBox.ToolTip = $entryInfo.Description

                        $checkBox.SetResourceReference([Windows.Controls.Control]::MarginProperty, "CheckBoxMargin")

                        $checkBox.UseLayoutRounding = $true

                        [System.Windows.Automation.AutomationProperties]::SetName($checkBox, $entryInfo.Content)

                        if ($entryInfo.Checked -eq $true) {

                            $checkBox.IsChecked = $entryInfo.Checked

                        }

                        $horizontalStackPanel.Children.Add($checkBox) | Out-Null



                        if ($entryInfo.Link) {

                            $textBlock = New-Object Windows.Controls.TextBlock

                            $textBlock.Name = $checkBox.Name + "Link"

                            $textBlock.Text = "Open"

                            $textBlock.ToolTip = if ($entryInfo.Description) { $entryInfo.Description } else { $entryInfo.Link }

                            $textBlock.Style = $HoverTextBlockStyle

                            $textBlock.UseLayoutRounding = $true

                            $textBlock.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")

                            $textBlock.Margin = New-Object Windows.Thickness(6, 0, 0, 0)

                            $textBlock.Tag = [PSCustomObject]@{

                                ItemTitle   = $entryInfo.Content

                                Description = $entryInfo.Description

                                Link        = $entryInfo.Link

                            }



                            $horizontalStackPanel.Children.Add($textBlock) | Out-Null



                            $sync[$textBlock.Name] = $textBlock

                        }



                        $itemsControl.Items.Add($horizontalStackPanel) | Out-Null

                        $sync[$entryInfo.Name] = $checkBox



                        $sync[$entryInfo.Name].Add_Checked({

                            [System.Object]$Sender = $args[0]

                            Invoke-WPFSelectedCheckboxesUpdate -type "Add" -checkboxName $Sender.name

                        })



                        $sync[$entryInfo.Name].Add_Unchecked({

                            [System.Object]$Sender = $args[0]

                            Invoke-WPFSelectedCheckboxesUpdate -type "Remove" -checkbox $Sender.name

                        })

                    }

                }

            }

        }

    }

}

function Invoke-WPFUIThread {
    <#

    .SYNOPSIS
        Creates and runs a task on the A-SYS_clark WPF UI thread.

    .PARAMETER ScriptBlock
        The scriptblock to invoke in the thread
    #>

    [CmdletBinding()]
    Param (
        $ScriptBlock
    )

    if ($PARAM_NOUI) {
        return;
    }

    $sync.form.Dispatcher.Invoke([action]$ScriptBlock)
}
function Invoke-WPFUltimatePerformance {
    param(
        [switch]$Do
    )

    if ($Do) {
        if (-not (powercfg /list | Select-String "ChrisTitus - Ultimate Power Plan")) {
            if (-not (powercfg /list | Select-String "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")) {
                powercfg /restoredefaultschemes
                if (-not (powercfg /list | Select-String "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")) {
                    Write-Host "Failed to restore High Performance plan. Default plans do not include high performance. If you are on a laptop, do NOT use High Performance or Ultimate Performance plans." -ForegroundColor Red
                    return
                }
            }
            $guid = ((powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c) -split '\s+')[3]
            powercfg /changename $guid "ChrisTitus - Ultimate Power Plan"
            powercfg /setacvalueindex $guid SUB_PROCESSOR IDLEDISABLE 1
            powercfg /setacvalueindex $guid 54533251-82be-4824-96c1-47b60b740d00 4d2b0152-7d5c-498b-88e2-34345392a2c5 1
            powercfg /setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMIN 100
            powercfg /setactive $guid
            Write-Host "ChrisTitus - Ultimate Power Plan plan installed and activated." -ForegroundColor Green
        } else {
            Write-Host "ChrisTitus - Ultimate Power Plan plan is already installed." -ForegroundColor Red
            return
        }
    } else {
        if (powercfg /list | Select-String "ChrisTitus - Ultimate Power Plan") {
            powercfg /setactive SCHEME_BALANCED
            powercfg /delete ((powercfg /list | Select-String "ChrisTitus - Ultimate Power Plan").ToString().Split()[3])
            Write-Host "ChrisTitus - Ultimate Power Plan plan was removed." -ForegroundColor Red
        } else {
            Write-Host "ChrisTitus - Ultimate Power Plan plan is not installed." -ForegroundColor Yellow
        }
    }
}
function Invoke-WPFundoall {

    <#



    .SYNOPSIS

        Undoes every selected tweak



    #>



    if($sync.ProcessRunning) {

        $msg = "[Invoke-WPFundoall] Install process is currently running."

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    $tweaks = $sync.selectedTweaks



    if ($tweaks.count -eq 0) {

        $msg = "Please check the tweaks you wish to undo."

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    Invoke-WPFRunspace -ArgumentList $tweaks -ScriptBlock {

        param($tweaks)



        $sync.ProcessRunning = $true

        if ($tweaks.count -eq 1) {

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Indeterminate" -value 0.01 -overlay "logo" }

        } else {

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Normal" -value 0.01 -overlay "logo" }

        }





        for ($i = 0; $i -lt $tweaks.Count; $i++) {

            Set-ClarkProgressBar -Label "Undoing $($tweaks[$i])" -Percent ($i / $tweaks.Count * 100)

            Invoke-Clarktweaks $tweaks[$i] -undo $true

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -value ($i/$tweaks.Count) }

        }



        Set-ClarkProgressBar -Label "Undo Tweaks Finished" -Percent 100

        $sync.ProcessRunning = $false

        Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }

        Write-Host "=================================="

        Write-Host "---  Undo Tweaks are Finished  ---"

        Write-Host "=================================="



    }

}

function Invoke-WPFUnInstall {

    param(

        [Parameter(Mandatory=$false)]

        [PSObject[]]$PackagesToUninstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })

    )

    <#



    .SYNOPSIS

        Uninstalls the selected programs

    #>



    if($sync.ProcessRunning) {

        $msg = "[Invoke-WPFUnInstall] Install process is currently running"

        [System.Windows.MessageBox]::Show($msg, "clark", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    if ($PackagesToUninstall.Count -eq 0) {

        $WarningMsg = "Please select the program(s) to uninstall"

        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)

        return

    }



    $ButtonType = [System.Windows.MessageBoxButton]::YesNo

    $MessageboxTitle = "Are you sure?"

    $Messageboxbody = ("This will uninstall the following applications: `n $($PackagesToUninstall | Select-Object Name, Description| Out-String)")

    $MessageIcon = [System.Windows.MessageBoxImage]::Information



    $confirm = [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)



    if($confirm -eq "No") {return}



    $ManagerPreference = $sync.preferences.packagemanager



    Invoke-WPFRunspace -ParameterList @(("PackagesToUninstall", $PackagesToUninstall),("ManagerPreference", $ManagerPreference)) -ScriptBlock {

        param($PackagesToUninstall, $ManagerPreference)



        $packagesSorted = Get-ClarkSelectedPackages -PackageList $PackagesToUninstall -Preference $ManagerPreference

        $packagesWinget = $packagesSorted[[PackageManagers]::Winget]

        $packagesChoco = $packagesSorted[[PackageManagers]::Choco]



        try {

            $sync.ProcessRunning = $true

            Show-WPFInstallAppBusy -text "Uninstalling apps..."



            # Uninstall all selected programs in new window

            if($packagesWinget.Count -gt 0) {

                Install-ClarkProgramWinget -Action Uninstall -Programs $packagesWinget

            }

            if($packagesChoco.Count -gt 0) {

                Install-ClarkProgramChoco -Action Uninstall -Programs $packagesChoco

            }

            Hide-WPFInstallAppBusy

            Write-Host "==========================================="

            Write-Host "--       Uninstalls have finished       ---"

            Write-Host "==========================================="

            Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "None" -overlay "checkmark" }

        } catch {

            Write-Host "==========================================="

            Write-Host "Error: $_"

            Write-Host "==========================================="

           Invoke-WPFUIThread -ScriptBlock { Set-ClarkTaskbaritem -state "Error" -overlay "warning" }

        }

        $sync.ProcessRunning = $False



    }

}

function Invoke-WPFUpdateDestroyer {
    <#
    .SYNOPSIS
        Custom update destroyer action.

    .DESCRIPTION
        Paste your "Update Destroyer" implementation in this function.
    #>

    $batPath = Join-Path $sync.PSScriptRoot "tools\UpdateDestroyer.bat"

    if (-not (Test-Path $batPath)) {
        [System.Windows.MessageBox]::Show(
            "Update Destroyer batch file not found:`n$batPath`n`nPlace your .bat file at this path and try again.",
            "Update Destroyer",
            "OK",
            "Warning"
        ) | Out-Null
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "This action is dangerous and can heavily modify Windows Update behavior.`n`nProceed only if you understand the impact and have a recovery plan.`n`nDo you want to continue?",
        "Dangerous Action - Confirm",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$batPath`"") -Wait -NoNewWindow
    } catch {
        [System.Windows.MessageBox]::Show(
            "Failed to run Update Destroyer batch file.`n`n$($_.Exception.Message)",
            "Update Destroyer",
            "OK",
            "Error"
        ) | Out-Null
    }
}
function Invoke-WPFUpdateDestroyerUndo {
    <#
    .SYNOPSIS
        Reverts custom update destroyer action.

    .DESCRIPTION
        Paste your "Update Destroyer Undo" implementation in this function.
    #>

    $batPath = Join-Path $sync.PSScriptRoot "tools\UpdateDestroyerUndo.bat"

    if (-not (Test-Path $batPath)) {
        [System.Windows.MessageBox]::Show(
            "Update Destroyer Undo batch file not found:`n$batPath`n`nPlace your .bat file at this path and try again.",
            "Update Destroyer Undo",
            "OK",
            "Warning"
        ) | Out-Null
        return
    }

    try {
        Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$batPath`"") -Wait -NoNewWindow
    } catch {
        [System.Windows.MessageBox]::Show(
            "Failed to run Update Destroyer Undo batch file.`n`n$($_.Exception.Message)",
            "Update Destroyer Undo",
            "OK",
            "Error"
        ) | Out-Null
    }
}
function Invoke-WPFUpdatesdefault {
    <#

    .SYNOPSIS
        Resets Windows Update settings to default

    #>
    $ErrorActionPreference = 'SilentlyContinue'

    Write-Host "Removing Windows Update policy settings..." -ForegroundColor Green

    Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Recurse -Force
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization" -Recurse -Force
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Recurse -Force
    Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Recurse -Force
    Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Recurse -Force
    Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Recurse -Force

    Write-Host "Reenabling Windows Update Services..." -ForegroundColor Green

    Write-Host "Restored BITS to Manual"
    Set-Service -Name BITS -StartupType Manual

    Write-Host "Restored wuauserv to Manual"
    Set-Service -Name wuauserv -StartupType Manual

    Write-Host "Restored UsoSvc to Automatic"
    Start-Service -Name UsoSvc
    Set-Service -Name UsoSvc -StartupType Automatic

    Write-Host "Restored WaaSMedicSvc to Manual"
    Set-Service -Name WaaSMedicSvc -StartupType Manual

    Write-Host "Enabling update related scheduled tasks..." -ForegroundColor Green

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task | Enable-ScheduledTask -ErrorAction SilentlyContinue
    }

    Write-Host "Windows Local Policies Reset to Default"
    secedit /configure /cfg "$Env:SystemRoot\inf\defltbase.inf" /db defltbase.sdb

    Write-Host "===================================================" -ForegroundColor Green
    Write-Host "---  Windows Update Settings Reset to Default   ---" -ForegroundColor Green
    Write-Host "===================================================" -ForegroundColor Green

    Write-Host "Note: You must restart your system in order for all changes to take effect." -ForegroundColor Yellow
}
function Invoke-WPFUpdatesdisable {
    <#

    .SYNOPSIS
        Disables Windows Update

    .NOTES
        Disabling Windows Update is not recommended. This is only for advanced users who know what they are doing.

    #>
    $ErrorActionPreference = 'SilentlyContinue'

    Write-Host "Configuring registry settings..." -ForegroundColor Yellow
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 1

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 0

    Write-Host "Disabled BITS Service"
    Set-Service -Name BITS -StartupType Disabled

    Write-Host "Disabled wuauserv Service"
    Set-Service -Name wuauserv -StartupType Disabled

    Write-Host "Disabled UsoSvc Service"
    Stop-Service -Name UsoSvc -Force
    Set-Service -Name UsoSvc -StartupType Disabled

    Remove-Item "C:\Windows\SoftwareDistribution\*" -Recurse -Force
    Write-Host "Cleared SoftwareDistribution folder"

    Write-Host "Disabling update related scheduled tasks..." -ForegroundColor Yellow

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }

    Write-Host "=================================" -ForegroundColor Green
    Write-Host "---   Updates Are Disabled    ---" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green

    Write-Host "Note: You must restart your system in order for all changes to take effect." -ForegroundColor Yellow
}
function Invoke-WPFUpdatessecurity {
    <#

    .SYNOPSIS
        Sets Windows Update to recommended settings

    .DESCRIPTION
        1. Disables driver offering through Windows Update
        2. Disables Windows Update automatic restart
        3. Sets Windows Update to Semi-Annual Channel (Targeted)
        4. Defers feature updates for 365 days
        5. Defers quality updates for 4 days

    #>

    Write-Host "Disabling driver offering through Windows Update..."

    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1

    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Force

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value 0

    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1

    Write-Host "Setting cumulative updates back by 1 year and security updates by 4 days"

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Force

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -Type DWord -Value 20
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -Type DWord -Value 365
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays" -Type DWord -Value 4

    Write-Host "Disabling Windows Update automatic restart..."

    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Type DWord -Value 0

    Write-Host "================================="
    Write-Host "-- Updates Set to Recommended ---"
    Write-Host "================================="
}
function Invoke-WPFWindowsUpdatePolicy {
    <#
    .SYNOPSIS
        Configure Windows Update policy (defer / disable automatic updates) or remove policy keys.
        HKLM paths require Administrator.
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $clark = 'HKCU:\Software\Clark\WindowsUpdatePolicy'

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Clark - Windows Update policy'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(480, 48)
    $lbl.Text = 'Policy values are written under HKLM\SOFTWARE\Policies (requires Administrator). Use Remove policy keys to clear defer/disable settings Clark applied.'
    [void]$form.Controls.Add($lbl)

    [int]$wuFormY = 68
    $chkDeferFeat = New-Object System.Windows.Forms.CheckBox
    $chkDeferFeat.Text = 'Defer feature updates (enable policy)'
    $chkDeferFeat.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkDeferFeat.Width = 280
    [void]$form.Controls.Add($chkDeferFeat)
    $wuFormY = [int]($wuFormY + 28)

    $lblDf = New-Object System.Windows.Forms.Label
    $lblDf.Text = 'Feature defer (days, 0-365):'
    $lblDf.Location = New-Object System.Drawing.Point(28, $wuFormY)
    $lblDf.AutoSize = $true
    [void]$form.Controls.Add($lblDf)
    $numFeat = New-Object System.Windows.Forms.NumericUpDown
    $numFeat.Location = New-Object System.Drawing.Point(220, [int]($wuFormY - 2))
    $numFeat.Width = 80
    $numFeat.Minimum = 0
    $numFeat.Maximum = 365
    $numFeat.Value = 120
    [void]$form.Controls.Add($numFeat)
    $wuFormY = [int]($wuFormY + 32)

    $chkDeferQual = New-Object System.Windows.Forms.CheckBox
    $chkDeferQual.Text = 'Defer quality updates (enable policy)'
    $chkDeferQual.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkDeferQual.Width = 280
    [void]$form.Controls.Add($chkDeferQual)
    $wuFormY = [int]($wuFormY + 28)

    $lblDq = New-Object System.Windows.Forms.Label
    $lblDq.Text = 'Quality defer (days, 0-30):'
    $lblDq.Location = New-Object System.Drawing.Point(28, $wuFormY)
    $lblDq.AutoSize = $true
    [void]$form.Controls.Add($lblDq)
    $numQual = New-Object System.Windows.Forms.NumericUpDown
    $numQual.Location = New-Object System.Drawing.Point(220, [int]($wuFormY - 2))
    $numQual.Width = 80
    $numQual.Minimum = 0
    $numQual.Maximum = 30
    $numQual.Value = 7
    [void]$form.Controls.Add($numQual)
    $wuFormY = [int]($wuFormY + 36)

    $chkNoAuto = New-Object System.Windows.Forms.CheckBox
    $chkNoAuto.Text = 'Disable automatic updates (NoAutoUpdate = 1) - use with caution'
    $chkNoAuto.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $chkNoAuto.Width = 440
    [void]$form.Controls.Add($chkNoAuto)
    $wuFormY = [int]($wuFormY + 40)

    $btnRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnRow.Location = New-Object System.Drawing.Point(12, $wuFormY)
    $btnRow.Width = 496
    $btnRow.AutoSize = $true
    $btnRow.WrapContents = $false
    $btnRow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Apply policy'
    $btnApply.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnApply.Add_Click({
        try {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
                [System.Windows.Forms.MessageBox]::Show('Applying HKLM policies requires running Clark as Administrator.', 'clark', 'OK', 'Warning')
                return
            }
            New-Item -Path $wu -Force | Out-Null
            New-Item -Path $au -Force | Out-Null

            if ($chkDeferFeat.Checked) {
                Set-ItemProperty -Path $wu -Name 'DeferFeatureUpdates' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -Type DWord -Value ([int]$numFeat.Value) -Force
            } else {
                Remove-ItemProperty -Path $wu -Name 'DeferFeatureUpdates' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -ErrorAction SilentlyContinue
            }

            if ($chkDeferQual.Checked) {
                Set-ItemProperty -Path $wu -Name 'DeferQualityUpdates' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -Type DWord -Value ([int]$numQual.Value) -Force
            } else {
                Remove-ItemProperty -Path $wu -Name 'DeferQualityUpdates' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -ErrorAction SilentlyContinue
            }

            if ($chkNoAuto.Checked) {
                Set-ItemProperty -Path $au -Name 'NoAutoUpdate' -Type DWord -Value 1 -Force
                Set-ItemProperty -Path $au -Name 'AUOptions' -Type DWord -Value 1 -Force
            } else {
                Remove-ItemProperty -Path $au -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $au -Name 'AUOptions' -ErrorAction SilentlyContinue
            }

            if (-not (Test-Path -LiteralPath $clark)) {
                New-Item -Path $clark -Force | Out-Null
            }
            Set-ItemProperty -Path $clark -Name 'LastApplied' -Type String -Value (Get-Date -Format 's') -Force

            [System.Windows.Forms.MessageBox]::Show('Policy values written. Reboot or gpupdate may be required for all components to respect policy.', 'clark', 'OK', 'Information')
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Apply failed', 'OK', 'Error')
        }
    })
    [void]$btnRow.Controls.Add($btnApply)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = 'Remove policy keys'
    $btnClear.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $btnClear.Add_Click({
        try {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
                [System.Windows.Forms.MessageBox]::Show('Removing HKLM policy values requires Administrator.', 'clark', 'OK', 'Warning')
                return
            }
            if (Test-Path -LiteralPath $wu) {
                foreach ($n in @('DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays')) {
                    Remove-ItemProperty -LiteralPath $wu -Name $n -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -LiteralPath $au) {
                foreach ($n in @('NoAutoUpdate', 'AUOptions')) {
                    Remove-ItemProperty -LiteralPath $au -Name $n -ErrorAction SilentlyContinue
                }
            }
            Remove-Item -Path $clark -Recurse -Force -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show('Removed defer / NoAutoUpdate policy values Clark uses, and the Clark marker under HKCU.', 'clark', 'OK', 'Information')
            $chkDeferFeat.Checked = $false
            $chkDeferQual.Checked = $false
            $chkNoAuto.Checked = $false
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Remove failed', 'OK', 'Error')
        }
    })
    [void]$btnRow.Controls.Add($btnClear)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Add_Click({ $form.Close() })
    [void]$btnRow.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnApply, $btnClear, $btnClose)
    [void]$form.Controls.Add($btnRow)
    $wuFormY = [int]($wuFormY + [math]::Max(44, $btnRow.PreferredSize.Height + 4))

    $form.ClientSize = New-Object System.Drawing.Size(520, [int]($wuFormY + 44))

    [void]$form.ShowDialog()
}
function Show-ASYSLogo {
    <#
    .SYNOPSIS
        Displays the A-SYS_clark ASCII logo.
    .DESCRIPTION
        Prints the A-SYS_clark banner and product name to the console.
    .EXAMPLE
        Show-ASYSLogo
    #>

    $asciiArt = @"
    ___                _______  _______
   /   |              / ___/\ \/ / ___/
  / /| |    ______    \__ \  \  /\__ \
 / ___ |   /_____/   ___/ /  / /___/ /
/_/  |_|            /____/  /_//____/


====clark=====
=====Advance Systems 4042=====
"@

    Write-Host $asciiArt
}
$sync.configs.applications = @'
{
    "WPFInstall7zip":  {
                           "category":  "Utilities",
                           "choco":  "7zip",
                           "content":  "7-Zip",
                           "description":  "7-Zip is a free and open-source file archiver utility. It supports several compression formats and provides a high compression ratio, making it a popular choice for file compression.",
                           "link":  "https://www.7-zip.org/",
                           "winget":  "7zip.7zip",
                           "foss":  true
                       },
    "WPFInstalladobe":  {
                            "category":  "Productivity",
                            "choco":  "adobereader",
                            "content":  "Adobe Acrobat Reader",
                            "description":  "Adobe Acrobat Reader is a free PDF viewer with essential features for viewing, printing, and annotating PDF documents.",
                            "link":  "https://www.adobe.com/acrobat/pdf-reader.html",
                            "winget":  "Adobe.Acrobat.Reader.64-bit"
                        },
    "WPFInstalladvancedip":  {
                                 "category":  "Developer",
                                 "choco":  "advanced-ip-scanner",
                                 "content":  "Advanced IP Scanner",
                                 "description":  "Advanced IP Scanner is a fast and easy-to-use network scanner. It is designed to analyze LAN networks and provides information about connected devices.",
                                 "link":  "https://www.advanced-ip-scanner.com/",
                                 "winget":  "Famatech.AdvancedIPScanner"
                             },
    "WPFInstallalacritty":  {
                                "category":  "Utilities",
                                "choco":  "alacritty",
                                "content":  "Alacritty Terminal",
                                "description":  "Alacritty is a fast, cross-platform, and GPU-accelerated terminal emulator. It is designed for performance and aims to be the fastest terminal emulator available.",
                                "link":  "https://alacritty.org/",
                                "winget":  "Alacritty.Alacritty",
                                "foss":  true
                            },
    "WPFInstallanaconda3":  {
                                "category":  "Developer",
                                "choco":  "anaconda3",
                                "content":  "Anaconda",
                                "description":  "Anaconda is a distribution of the Python and R programming languages for scientific computing.",
                                "link":  "https://www.anaconda.com/products/distribution",
                                "winget":  "Anaconda.Anaconda3"
                            },
    "WPFInstallangryipscanner":  {
                                     "category":  "Developer",
                                     "choco":  "angryip",
                                     "content":  "Angry IP Scanner",
                                     "description":  "Angry IP Scanner is an open-source and cross-platform network scanner. It is used to scan IP addresses and ports, providing information about network connectivity.",
                                     "link":  "https://angryip.org/",
                                     "winget":  "angryziber.AngryIPScanner",
                                     "foss":  true
                                 },
    "WPFInstallanydesk":  {
                              "category":  "Utilities",
                              "choco":  "anydesk",
                              "content":  "AnyDesk",
                              "description":  "AnyDesk is a remote desktop software that enables users to access and control computers remotely. It is known for its fast connection and low latency.",
                              "link":  "https://anydesk.com/",
                              "winget":  "AnyDesk.AnyDesk"
                          },
    "WPFInstallautoruns":  {
                               "category":  "Developer",
                               "choco":  "autoruns",
                               "content":  "Autoruns",
                               "description":  "This utility shows you what programs are configured to run during system bootup or login.",
                               "link":  "https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns",
                               "winget":  "Microsoft.Sysinternals.Autoruns"
                           },
    "WPFInstallrdcman":  {
                             "category":  "Developer",
                             "choco":  "rdcman",
                             "content":  "RDCMan",
                             "description":  "RDCMan manages multiple remote desktop connections. It is useful for managing server labs where you need regular access to each machine such as automated checkin systems and data centers.",
                             "link":  "https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman",
                             "winget":  "Microsoft.Sysinternals.RDCMan"
                         },
    "WPFInstallautohotkey":  {
                                 "category":  "Utilities",
                                 "choco":  "autohotkey",
                                 "content":  "AutoHotkey",
                                 "description":  "AutoHotkey is a scripting language for Windows that allows users to create custom automation scripts and macros. It is often used for automating repetitive tasks and customizing keyboard shortcuts.",
                                 "link":  "https://www.autohotkey.com/",
                                 "winget":  "AutoHotkey.AutoHotkey",
                                 "foss":  true
                             },
    "WPFInstallbeeper":  {
                             "category":  "Productivity",
                             "choco":  "na",
                             "content":  "Beeper",
                             "description":  "All your chats in one app.",
                             "link":  "https://www.beeper.com/",
                             "winget":  "Beeper.Beeper"
                         },
    "WPFInstallbitwarden":  {
                                "category":  "Utilities",
                                "choco":  "bitwarden",
                                "content":  "Bitwarden",
                                "description":  "Bitwarden is an open-source password management solution. It allows users to store and manage their passwords in a secure and encrypted vault, accessible across multiple devices.",
                                "link":  "https://bitwarden.com/",
                                "winget":  "Bitwarden.Bitwarden",
                                "foss":  true
                            },
    "WPFInstallblender":  {
                              "category":  "Media",
                              "choco":  "blender",
                              "content":  "Blender (3D Graphics)",
                              "description":  "Blender is a powerful open-source 3D creation suite, offering modeling, sculpting, animation, and rendering tools.",
                              "link":  "https://www.blender.org/",
                              "winget":  "BlenderFoundation.Blender",
                              "foss":  true
                          },
    "WPFInstallbrave":  {
                            "category":  "Browser",
                            "choco":  "brave",
                            "content":  "Brave",
                            "description":  "Brave is a privacy-focused web browser that blocks ads and trackers, offering a faster and safer browsing experience.",
                            "link":  "https://www.brave.com",
                            "winget":  "Brave.Brave",
                            "foss":  true
                        },
    "WPFInstallAdvancedRenamer":  {
                                      "category":  "Utilities",
                                      "choco":  "advanced-renamer",
                                      "content":  "Advanced Renamer",
                                      "description":  "Advanced Renamer is a program for renaming multiple files and folders at once. By configuring renaming methods the names can be manipulated in various ways.",
                                      "link":  "https://www.advancedrenamer.com/",
                                      "winget":  "HulubuluSoftware.AdvancedRenamer"
                                  },
    "WPFInstallcryptomator":  {
                                  "category":  "Utilities",
                                  "choco":  "cryptomator",
                                  "content":  "Cryptomator",
                                  "description":  "Cryptomator for Windows, macOS, and Linux: Secure client-side encryption for your cloud storage, ensuring privacy and control over your data.",
                                  "link":  "https://github.com/cryptomator/cryptomator/",
                                  "winget":  "Cryptomator.Cryptomator",
                                  "foss":  true
                              },
    "WPFInstallcitrixworkspaceapp":  {
                                         "category":  "Utilities",
                                         "choco":  "citrix-workspace",
                                         "content":  "Citrix Workspace app",
                                         "description":  "A secure, unified client application that provides instant access to virtual desktops, SaaS, web, and Windows apps from any device (Windows, macOS, Linux, iOS, Android) or browser.",
                                         "link":  "https://www.citrix.com/downloads/workspace-app/",
                                         "winget":  "Citrix.Workspace"
                                     },
    "WPFInstallcarnac":  {
                             "category":  "Utilities",
                             "choco":  "carnac",
                             "content":  "Carnac",
                             "description":  "Carnac is a keystroke visualizer for Windows. It displays keystrokes in an overlay, making it useful for presentations, tutorials, and live demonstrations.",
                             "link":  "https://carnackeys.com/",
                             "winget":  "code52.Carnac",
                             "foss":  true
                         },
    "WPFInstallchrome":  {
                             "category":  "Browser",
                             "choco":  "googlechrome",
                             "content":  "Chrome",
                             "description":  "Google Chrome is a widely used web browser known for its speed, simplicity, and seamless integration with Google services.",
                             "link":  "https://www.google.com/chrome/",
                             "winget":  "Google.Chrome"
                         },
    "WPFInstallchromium":  {
                               "category":  "Browser",
                               "choco":  "chromium",
                               "content":  "Chromium",
                               "description":  "Chromium is the open-source project that serves as the foundation for various web browsers, including Chrome.",
                               "link":  "https://github.com/Hibbiki/chromium-win64",
                               "winget":  "Hibbiki.Chromium",
                               "foss":  true
                           },
    "WPFInstallcpuz":  {
                           "category":  "Utilities",
                           "choco":  "cpu-z",
                           "content":  "CPU-Z",
                           "description":  "CPU-Z is a system monitoring and diagnostic tool for Windows. It provides detailed information about the computer\u0027s hardware components, including the CPU, memory, and motherboard.",
                           "link":  "https://www.cpuid.com/softwares/cpu-z.html",
                           "winget":  "CPUID.CPU-Z"
                       },
    "WPFInstallcrystaldiskinfo":  {
                                      "category":  "Utilities",
                                      "choco":  "crystaldiskinfo",
                                      "content":  "Crystal Disk Info",
                                      "description":  "Crystal Disk Info is a disk health monitoring tool that provides information about the status and performance of hard drives. It helps users anticipate potential issues and monitor drive health.",
                                      "link":  "https://crystalmark.info/en/software/crystaldiskinfo/",
                                      "winget":  "CrystalDewWorld.CrystalDiskInfo",
                                      "foss":  true
                                  },
    "WPFInstallcrystaldiskmark":  {
                                      "category":  "Utilities",
                                      "choco":  "crystaldiskmark",
                                      "content":  "Crystal Disk Mark",
                                      "description":  "Crystal Disk Mark is a disk benchmarking tool that measures the read and write speeds of storage devices. It helps users assess the performance of their hard drives and SSDs.",
                                      "link":  "https://crystalmark.info/en/software/crystaldiskmark/",
                                      "winget":  "CrystalDewWorld.CrystalDiskMark",
                                      "foss":  true
                                  },
    "WPFInstalldiskgenius":  {
                                 "category":  "Utilities",
                                 "choco":  "na",
                                 "content":  "DiskGenius",
                                 "description":  "Disk partition manager, backup, and data recovery for Windows. Supports partition operations, disk cloning, and file recovery.",
                                 "link":  "https://www.diskgenius.com/",
                                 "winget":  "Eassos.DiskGenius"
                             },
    "WPFInstallcursor":  {
                             "category":  "Developer",
                             "choco":  "cursoride",
                             "content":  "Cursor",
                             "description":  "AI-powered code editor (VS Code-based) with agentic coding features and integrated AI assistance for development workflows.",
                             "link":  "https://cursor.com/",
                             "winget":  "Anysphere.Cursor",
                             "foss":  false
                         },
    "WPFInstallddu":  {
                          "category":  "Utilities",
                          "choco":  "ddu",
                          "content":  "Display Driver Uninstaller",
                          "description":  "Display Driver Uninstaller (DDU) is a tool for completely uninstalling graphics drivers from NVIDIA, AMD, and Intel. It is useful for troubleshooting graphics driver-related issues.",
                          "link":  "https://www.wagnardsoft.com/display-driver-uninstaller-DDU-",
                          "winget":  "Wagnardsoft.DisplayDriverUninstaller"
                      },
    "WPFInstalldeluge":  {
                             "category":  "Utilities",
                             "choco":  "deluge",
                             "content":  "Deluge",
                             "description":  "Deluge is a free and open-source BitTorrent client. It features a user-friendly interface, support for plugins, and the ability to manage torrents remotely.",
                             "link":  "https://deluge-torrent.org/",
                             "winget":  "DelugeTeam.Deluge",
                             "foss":  true
                         },
    "WPFInstalldevtoys":  {
                              "category":  "Utilities",
                              "choco":  "devtoys",
                              "content":  "DevToys",
                              "description":  "DevToys is a collection of development-related utilities and tools for Windows. It includes tools for file management, code formatting, and productivity enhancements for developers.",
                              "link":  "https://devtoys.app/",
                              "winget":  "DevToys-app.DevToys"
                          },
    "WPFInstalldiscord":  {
                              "category":  "Productivity",
                              "choco":  "discord",
                              "content":  "Discord",
                              "description":  "Discord is a popular communication platform with voice, video, and text chat, designed for gamers but used by a wide range of communities.",
                              "link":  "https://discord.com/",
                              "winget":  "Discord.Discord"
                          },
    "WPFInstallvencord":  {
                              "category":  "Productivity",
                              "choco":  "na",
                              "content":  "Vencord (Vesktop)",
                              "description":  "Vesktop is a Vencord-powered desktop client compatible with Discord, adding customization and quality-of-life features.",
                              "link":  "https://vesktop.dev/",
                              "winget":  "Vencord.Vesktop",
                              "foss":  true
                          },
    "WPFInstallntlite":  {
                             "category":  "Developer",
                             "choco":  "ntlite-free",
                             "content":  "NTLite",
                             "description":  "Integrate updates, drivers, automate Windows and application setup, speedup Windows deployment process and have it all set for the next time.",
                             "link":  "https://ntlite.com",
                             "winget":  "Nlitesoft.NTLite"
                         },
    "WPFInstalldockerdesktop":  {
                                    "category":  "Developer",
                                    "choco":  "docker-desktop",
                                    "content":  "Docker Desktop",
                                    "description":  "Docker Desktop is a powerful tool for containerized application development and deployment.",
                                    "link":  "https://www.docker.com/products/docker-desktop",
                                    "winget":  "Docker.DockerDesktop"
                                },
    "WPFInstalldotnet5":  {
                              "category":  "Developer",
                              "choco":  "dotnet-5.0-runtime",
                              "content":  ".NET Desktop Runtime 5",
                              "description":  ".NET Desktop Runtime 5 is a runtime environment required for running applications developed with .NET 5.",
                              "link":  "https://dotnet.microsoft.com/download/dotnet/5.0",
                              "winget":  "Microsoft.DotNet.DesktopRuntime.5"
                          },
    "WPFInstalldotnet10":  {
                               "category":  "Developer",
                               "choco":  "dotnet-10.0-runtime",
                               "content":  ".NET Desktop Runtime 10",
                               "description":  ".NET Desktop Runtime 10 is a runtime environment required for running applications developed with .NET 10.",
                               "link":  "https://dotnet.microsoft.com/download/dotnet/10.0",
                               "winget":  "Microsoft.DotNet.DesktopRuntime.10"
                           },
    "WPFInstallecm":  {
                          "category":  "Utilities",
                          "choco":  "ecm",
                          "content":  "Easy Context Menu",
                          "description":  "Easy Context Menu (ECM) lets you add a variety of useful commands and tweaks to the Desktop, My Computer, Drives, File and Folder right-click context menus. This enables you to access the most used Windows components quickly and easily. Simply check the box next to the items you wish to add. Once added, just right click and the select the component shortcut to launch it. Easy Context Menu is both portable and freeware.",
                          "link":  "https://www.sordum.org/7615/easy-context-menu-v1-6/",
                          "winget":  "sordum.EasyContextMenu"
                      },
    "WPFInstalledge":  {
                           "category":  "Browser",
                           "choco":  "microsoft-edge",
                           "content":  "Edge",
                           "description":  "Microsoft Edge is a modern web browser built on Chromium, offering performance, security, and integration with Microsoft services.",
                           "link":  "https://www.microsoft.com/edge",
                           "winget":  "Microsoft.Edge"
                       },
    "WPFInstallefibooteditor":  {
                                    "category":  "Developer",
                                    "choco":  "na",
                                    "content":  "EFI Boot Editor",
                                    "description":  "EFI Boot Editor is a tool for managing the EFI/UEFI boot entries on your system. It allows you to customize the boot configuration of your computer.",
                                    "link":  "https://www.easyuefi.com/",
                                    "winget":  "EFIBootEditor.EFIBootEditor"
                                },
    "WPFInstallemulationstation":  {
                                       "category":  "Media",
                                       "choco":  "emulationstation",
                                       "content":  "Emulation Station",
                                       "description":  "Emulation Station is a graphical and themeable emulator front-end that allows you to access all your favorite games in one place.",
                                       "link":  "https://emulationstation.org/",
                                       "winget":  "Emulationstation.Emulationstation",
                                       "foss":  true
                                   },
    "WPFInstallepicgames":  {
                                "category":  "Media",
                                "choco":  "epicgameslauncher",
                                "content":  "Epic Games Launcher",
                                "description":  "Epic Games Launcher is the client for accessing and playing games from the Epic Games Store.",
                                "link":  "https://www.epicgames.com/store/en-US/",
                                "winget":  "EpicGames.EpicGamesLauncher"
                            },
    "WPFInstallesearch":  {
                              "category":  "Utilities",
                              "choco":  "everything",
                              "content":  "Everything Search",
                              "description":  "Everything Search is a fast and efficient file search utility for Windows.",
                              "link":  "https://www.voidtools.com/",
                              "winget":  "voidtools.Everything"
                          },
    "WPFInstallffmpeg":  {
                             "category":  "Utilities",
                             "choco":  "na",
                             "content":  "FFmpeg Batch AV Converter",
                             "description":  "FFmpeg Batch AV Converter is a universal audio and video encoder, that allows to use the full potential of ffmpeg command line with a few mouse clicks in a convenient GUI with drag and drop, progress information.",
                             "link":  "https://ffmpeg-batch.sourceforge.io/",
                             "winget":  "eibol.FFmpegBatchAVConverter",
                             "foss":  true
                         },
    "WPFInstallfastfetch":  {
                                "category":  "Utilities",
                                "choco":  "na",
                                "content":  "Fastfetch",
                                "description":  "Fastfetch is a neofetch-like tool for fetching system information and displaying them in a pretty way.",
                                "link":  "https://github.com/fastfetch-cli/fastfetch/",
                                "winget":  "Fastfetch-cli.Fastfetch",
                                "foss":  true
                            },
    "WPFInstallfileconverter":  {
                                    "category":  "Utilities",
                                    "choco":  "file-converter",
                                    "content":  "File-Converter",
                                    "description":  "File Converter is a very simple tool which allows you to convert and compress one or several file(s) using the context menu in Windows Explorer.",
                                    "link":  "https://file-converter.io/",
                                    "winget":  "AdrienAllard.FileConverter",
                                    "foss":  true
                                },
    "WPFInstallfirefox":  {
                              "category":  "Browser",
                              "choco":  "firefox",
                              "content":  "Firefox",
                              "description":  "Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions.",
                              "link":  "https://www.mozilla.org/en-US/firefox/new/",
                              "winget":  "Mozilla.Firefox",
                              "foss":  true
                          },
    "WPFInstallfloorp":  {
                             "category":  "Browser",
                             "choco":  "na",
                             "content":  "Floorp",
                             "description":  "Floorp is an open-source web browser project that aims to provide a simple and fast browsing experience.",
                             "link":  "https://floorp.app/",
                             "winget":  "Ablaze.Floorp",
                             "foss":  true
                         },
    "WPFInstallgog":  {
                          "category":  "Media",
                          "choco":  "goggalaxy",
                          "content":  "GOG Galaxy",
                          "description":  "GOG Galaxy is a gaming client that offers DRM-free games, additional content, and more.",
                          "link":  "https://www.gog.com/galaxy",
                          "winget":  "GOG.Galaxy"
                      },
    "WPFInstallgoogledrive":  {
                                  "category":  "Utilities",
                                  "choco":  "googledrive",
                                  "content":  "Google Drive",
                                  "description":  "File syncing across devices all tied to your Google account.",
                                  "link":  "https://www.google.com/drive/",
                                  "winget":  "Google.GoogleDrive"
                              },
    "WPFInstallgpuz":  {
                           "category":  "Utilities",
                           "choco":  "gpu-z",
                           "content":  "GPU-Z",
                           "description":  "GPU-Z provides detailed information about your graphics card and GPU.",
                           "link":  "https://www.techpowerup.com/gpuz/",
                           "winget":  "TechPowerUp.GPU-Z"
                       },
    "WPFInstallhwinfo":  {
                             "category":  "Utilities",
                             "choco":  "hwinfo",
                             "content":  "HWiNFO",
                             "description":  "HWiNFO provides comprehensive hardware information and diagnostics for Windows.",
                             "link":  "https://www.hwinfo.com/",
                             "winget":  "REALiX.HWiNFO"
                         },
    "WPFInstallhwmonitor":  {
                                "category":  "Utilities",
                                "choco":  "hwmonitor",
                                "content":  "HWMonitor",
                                "description":  "HWMonitor is a hardware monitoring program that reads PC systems main health sensors.",
                                "link":  "https://www.cpuid.com/softwares/hwmonitor.html",
                                "winget":  "CPUID.HWMonitor"
                            },
    "WPFInstallimhex":  {
                            "category":  "Developer",
                            "choco":  "na",
                            "content":  "ImHex (Hex Editor)",
                            "description":  "A modern, featureful Hex Editor for Reverse Engineers and Developers.",
                            "link":  "https://imhex.werwolv.net/",
                            "winget":  "WerWolv.ImHex",
                            "foss":  true
                        },
    "WPFInstallimgburn":  {
                              "category":  "Media",
                              "choco":  "imgburn",
                              "content":  "ImgBurn",
                              "description":  "ImgBurn is a lightweight CD, DVD, HD-DVD, and Blu-ray burning application with advanced features for creating and burning disc images.",
                              "link":  "https://www.imgburn.com/",
                              "winget":  "LIGHTNINGUK.ImgBurn"
                          },
    "WPFInstallitch":  {
                           "category":  "Media",
                           "choco":  "itch",
                           "content":  "Itch.io",
                           "description":  "Itch.io is a digital distribution platform for indie games and creative projects.",
                           "link":  "https://itch.io/",
                           "winget":  "ItchIo.Itch",
                           "foss":  true
                       },
    "WPFInstallhydralauncher":  {
                                    "category":  "Media",
                                    "choco":  "na",
                                    "content":  "Hydra Launcher",
                                    "description":  "Game launcher with library management and download support for DRM-free and third-party sources. Open source.",
                                    "link":  "https://hydralauncher.gg/",
                                    "winget":  "HydraLauncher.Hydra",
                                    "foss":  true
                                },
    "WPFInstallitunes":  {
                             "category":  "Media",
                             "choco":  "itunes",
                             "content":  "iTunes",
                             "description":  "iTunes is a media player, media library, and online radio broadcaster application developed by Apple Inc.",
                             "link":  "https://www.apple.com/itunes/",
                             "winget":  "Apple.iTunes"
                         },
    "WPFInstalljava8":  {
                            "category":  "Developer",
                            "choco":  "corretto8jdk",
                            "content":  "Amazon Corretto 8 (LTS)",
                            "description":  "Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).",
                            "link":  "https://aws.amazon.com/corretto",
                            "winget":  "Amazon.Corretto.8.JDK",
                            "foss":  true
                        },
    "WPFInstalljava25":  {
                             "category":  "Developer",
                             "choco":  "corretto25jdk",
                             "content":  "Amazon Corretto 25 (LTS)",
                             "description":  "Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).",
                             "link":  "https://aws.amazon.com/corretto",
                             "winget":  "Amazon.Corretto.25.JDK",
                             "foss":  true
                         },
    "WPFInstalljdownloader":  {
                                  "category":  "Utilities",
                                  "choco":  "jdownloader",
                                  "content":  "JDownloader",
                                  "description":  "JDownloader is a feature-rich download manager with support for various file hosting services.",
                                  "link":  "https://jdownloader.org/",
                                  "winget":  "AppWork.JDownloader"
                              },
    "WPFInstalljellyfinmediaplayer":  {
                                          "category":  "Media",
                                          "choco":  "jellyfin-media-player",
                                          "content":  "Jellyfin Media Player",
                                          "description":  "Jellyfin Media Player is a client application for the Jellyfin media server, providing access to your media library.",
                                          "link":  "https://github.com/jellyfin/jellyfin-media-player",
                                          "winget":  "Jellyfin.JellyfinMediaPlayer",
                                          "foss":  true
                                      },
    "WPFInstalljellyfinserver":  {
                                     "category":  "Media",
                                     "choco":  "jellyfin",
                                     "content":  "Jellyfin Server",
                                     "description":  "Jellyfin Server is an open-source media server software, allowing you to organize and stream your media library.",
                                     "link":  "https://jellyfin.org/",
                                     "winget":  "Jellyfin.Server",
                                     "foss":  true
                                 },
    "WPFInstalljetbrains":  {
                                "category":  "Developer",
                                "choco":  "jetbrainstoolbox",
                                "content":  "Jetbrains Toolbox",
                                "description":  "Jetbrains Toolbox is a platform for easy installation and management of JetBrains developer tools.",
                                "link":  "https://www.jetbrains.com/toolbox/",
                                "winget":  "JetBrains.Toolbox"
                            },
    "WPFInstallkodi":  {
                           "category":  "Media",
                           "choco":  "kodi",
                           "content":  "Kodi Media Center",
                           "description":  "Kodi is an open-source media center application that allows you to play and view most videos, music, podcasts, and other digital media files.",
                           "link":  "https://kodi.tv/",
                           "winget":  "XBMCFoundation.Kodi",
                           "foss":  true
                       },
    "WPFInstalllibreoffice":  {
                                  "category":  "Productivity",
                                  "choco":  "libreoffice-fresh",
                                  "content":  "LibreOffice",
                                  "description":  "LibreOffice is a powerful and free office suite, compatible with other major office suites.",
                                  "link":  "https://www.libreoffice.org/",
                                  "winget":  "TheDocumentFoundation.LibreOffice",
                                  "foss":  true
                              },
    "WPFInstalllibrewolf":  {
                                "category":  "Browser",
                                "choco":  "librewolf",
                                "content":  "LibreWolf",
                                "description":  "LibreWolf is a privacy-focused web browser based on Firefox, with additional privacy and security enhancements.",
                                "link":  "https://librewolf-community.gitlab.io/",
                                "winget":  "LibreWolf.LibreWolf",
                                "foss":  true
                            },
    "WPFInstalllogitechghub":  {
                                   "category":  "Utilities",
                                   "choco":  "lghub",
                                   "content":  "Logitech G Hub",
                                   "description":  "Official software for managing Logitech gaming peripherals (mice, keyboards, headsets, lighting profiles, etc.).",
                                   "link":  "https://www.logitechg.com/en-us/software/ghub",
                                   "winget":  "Logitech.GHUB"
                               },
    "WPFInstallmalwarebytes":  {
                                   "category":  "Utilities",
                                   "choco":  "malwarebytes",
                                   "content":  "Malwarebytes",
                                   "description":  "Malwarebytes is an anti-malware software that provides real-time protection against threats.",
                                   "link":  "https://www.malwarebytes.com/",
                                   "winget":  "Malwarebytes.Malwarebytes"
                               },
    "WPFInstallmacriumreflect":  {
                                     "category":  "Utilities",
                                     "choco":  "reflect-free",
                                     "content":  "Macrium Reflect Free",
                                     "description":  "Disk imaging and cloning for backup and recovery. Free edition; Chocolatey package automates setup where silent install is limited.",
                                     "link":  "https://www.macrium.com/reflectfree",
                                     "winget":  "na"
                                 },
    "WPFInstallMotrix":  {
                             "category":  "Utilities",
                             "choco":  "motrix",
                             "content":  "Motrix Download Manager",
                             "description":  "A full-featured download manager.",
                             "link":  "https://motrix.app/",
                             "winget":  "agalwood.Motrix",
                             "foss":  true
                         },
    "WPFInstallmsiafterburner":  {
                                     "category":  "Utilities",
                                     "choco":  "msiafterburner",
                                     "content":  "MSI Afterburner",
                                     "description":  "MSI Afterburner is a graphics card overclocking utility with advanced features.",
                                     "link":  "https://www.msi.com/Landing/afterburner",
                                     "winget":  "Guru3D.Afterburner"
                                 },
    "WPFInstallmicrosoftoffice":  {
                                      "category":  "Productivity",
                                      "choco":  "na",
                                      "content":  "Microsoft 365 / Office (Click-to-Run)",
                                      "description":  "Microsoft 365 Apps (Office) via WinGet. May require admin and a Microsoft account or existing license; channel can vary by manifest.",
                                      "link":  "https://www.microsoft.com/microsoft-365",
                                      "winget":  "Microsoft.Office"
                                  },
    "WPFInstallCompactGUI":  {
                                 "category":  "Utilities",
                                 "choco":  "compactgui",
                                 "content":  "Compact GUI",
                                 "description":  "Transparently compress active games and programs using Windows 10/11 APIs",
                                 "link":  "https://github.com/IridiumIO/CompactGUI",
                                 "winget":  "IridiumIO.CompactGUI",
                                 "foss":  true
                             },
    "WPFInstallExifCleaner":  {
                                  "category":  "Utilities",
                                  "choco":  "na",
                                  "content":  "ExifCleaner",
                                  "description":  "Desktop app to clean metadata from images, videos, PDFs, and other files.",
                                  "link":  "https://github.com/szTheory/exifcleaner",
                                  "winget":  "szTheory.exifcleaner",
                                  "foss":  true
                              },
    "WPFInstallnetbird":  {
                              "category":  "Developer",
                              "choco":  "netbird",
                              "content":  "NetBird",
                              "description":  "NetBird is a open-source alternative comparable to TailScale that can be connected to a self-hosted server.",
                              "link":  "https://netbird.io/",
                              "winget":  "netbird",
                              "foss":  true
                          },
    "WPFInstallnaps2":  {
                            "category":  "Productivity",
                            "choco":  "naps2",
                            "content":  "NAPS2 (Document Scanner)",
                            "description":  "NAPS2 is a document scanning application that simplifies the process of creating electronic documents.",
                            "link":  "https://www.naps2.com/",
                            "winget":  "Cyanfish.NAPS2",
                            "foss":  true
                        },
    "WPFInstallneofetchwin":  {
                                  "category":  "Utilities",
                                  "choco":  "na",
                                  "content":  "Neofetch",
                                  "description":  "Neofetch is a command-line utility for displaying system information in a visually appealing way.",
                                  "link":  "https://github.com/nepnep39/neofetch-win",
                                  "winget":  "nepnep.neofetch-win",
                                  "foss":  true
                              },
    "WPFInstallneovim":  {
                             "category":  "Developer",
                             "choco":  "neovim",
                             "content":  "Neovim",
                             "description":  "Neovim is a highly extensible text editor and an improvement over the original Vim editor.",
                             "link":  "https://neovim.io/",
                             "winget":  "Neovim.Neovim"
                         },
    "WPFInstallnextclouddesktop":  {
                                       "category":  "Utilities",
                                       "choco":  "nextcloud-client",
                                       "content":  "Nextcloud Desktop",
                                       "description":  "Nextcloud Desktop is the official desktop client for the Nextcloud file synchronization and sharing platform.",
                                       "link":  "https://nextcloud.com/install/#install-clients",
                                       "winget":  "Nextcloud.NextcloudDesktop",
                                       "foss":  true
                                   },
    "WPFInstallnmap":  {
                           "category":  "Developer",
                           "choco":  "nmap",
                           "content":  "Nmap",
                           "description":  "Nmap (Network Mapper) is an open-source tool for network exploration and security auditing. It discovers devices on a network and provides information about their ports and services.",
                           "link":  "https://nmap.org/",
                           "winget":  "Insecure.Nmap",
                           "foss":  true
                       },
    "WPFInstallnodejslts":  {
                                "category":  "Developer",
                                "choco":  "nodejs-lts",
                                "content":  "NodeJS LTS",
                                "description":  "NodeJS LTS provides Long-Term Support releases for stable and reliable server-side JavaScript development.",
                                "link":  "https://nodejs.org/",
                                "winget":  "OpenJS.NodeJS.LTS",
                                "foss":  true
                            },
    "WPFInstallnotepadplus":  {
                                  "category":  "Productivity",
                                  "choco":  "notepadplusplus",
                                  "content":  "Notepad++",
                                  "description":  "Notepad++ is a free, open-source code editor and Notepad replacement with support for multiple languages.",
                                  "link":  "https://notepad-plus-plus.org/",
                                  "winget":  "Notepad++.Notepad++",
                                  "foss":  true
                              },
    "WPFInstallobs":  {
                          "category":  "Media",
                          "choco":  "obs-studio",
                          "content":  "OBS Studio",
                          "description":  "OBS Studio is a free and open-source software for video recording and live streaming. It supports real-time video/audio capturing and mixing, making it popular among content creators.",
                          "link":  "https://obsproject.com/",
                          "winget":  "OBSProject.OBSStudio",
                          "foss":  true
                      },
    "WPFInstallobsidian":  {
                               "category":  "Productivity",
                               "choco":  "obsidian",
                               "content":  "Obsidian",
                               "description":  "Obsidian is a powerful note-taking and knowledge management application.",
                               "link":  "https://obsidian.md/",
                               "winget":  "Obsidian.Obsidian"
                           },
    "WPFInstallonlyoffice":  {
                                 "category":  "Productivity",
                                 "choco":  "onlyoffice",
                                 "content":  "ONLYOffice Desktop",
                                 "description":  "ONLYOffice Desktop is a comprehensive office suite for document editing and collaboration.",
                                 "link":  "https://www.onlyoffice.com/desktop.aspx",
                                 "winget":  "ONLYOFFICE.DesktopEditors",
                                 "foss":  true
                             },
    "WPFInstallopenrgb":  {
                              "category":  "Utilities",
                              "choco":  "openrgb",
                              "content":  "OpenRGB",
                              "description":  "OpenRGB is an open-source RGB lighting control software designed to manage and control RGB lighting for various components and peripherals.",
                              "link":  "https://openrgb.org/",
                              "winget":  "OpenRGB.OpenRGB",
                              "foss":  true
                          },
    "WPFInstallOVirtualBox":  {
                                  "category":  "Utilities",
                                  "choco":  "virtualbox",
                                  "content":  "Oracle VirtualBox",
                                  "description":  "Oracle VirtualBox is a powerful and free open-source virtualization tool for x86 and AMD64/Intel64 architectures.",
                                  "link":  "https://www.virtualbox.org/",
                                  "winget":  "Oracle.VirtualBox",
                                  "foss":  true
                              },
    "WPFInstallownclouddesktop":  {
                                      "category":  "Utilities",
                                      "choco":  "owncloud-client",
                                      "content":  "ownCloud Desktop",
                                      "description":  "ownCloud Desktop is the official desktop client for the ownCloud file synchronization and sharing platform.",
                                      "link":  "https://owncloud.com/desktop-app/",
                                      "winget":  "ownCloud.ownCloudDesktop",
                                      "foss":  true
                                  },
    "WPFInstallpolicyplus":  {
                                 "category":  "Media",
                                 "choco":  "na",
                                 "content":  "Policy Plus",
                                 "description":  "Local Group Policy Editor plus more, for all Windows editions.",
                                 "link":  "https://github.com/Fleex255/PolicyPlus",
                                 "winget":  "Fleex255.PolicyPlus",
                                 "foss":  true
                             },
    "WPFInstallprocessexplorer":  {
                                      "category":  "Developer",
                                      "choco":  "na",
                                      "content":  "Process Explorer",
                                      "description":  "Process Explorer is a task manager and system monitor.",
                                      "link":  "https://learn.microsoft.com/sysinternals/downloads/process-explorer",
                                      "winget":  "Microsoft.Sysinternals.ProcessExplorer"
                                  },
    "WPFInstallpdfsam":  {
                             "category":  "Productivity",
                             "choco":  "pdfsam",
                             "content":  "PDFsam Basic",
                             "description":  "PDFsam Basic is a free and open-source tool for splitting, merging, and rotating PDF files.",
                             "link":  "https://pdfsam.org/",
                             "winget":  "PDFsam.PDFsam",
                             "foss":  true
                         },
    "WPFInstallplaynite":  {
                               "category":  "Media",
                               "choco":  "playnite",
                               "content":  "Playnite",
                               "description":  "Playnite is an open-source video game library manager with one simple goal: To provide a unified interface for all of your games.",
                               "link":  "https://playnite.link/",
                               "winget":  "Playnite.Playnite",
                               "foss":  true
                           },
    "WPFInstallplex":  {
                           "category":  "Media",
                           "choco":  "plexmediaserver",
                           "content":  "Plex Media Server",
                           "description":  "Plex Media Server is a media server software that allows you to organize and stream your media library. It supports various media formats and offers a wide range of features.",
                           "link":  "https://www.plex.tv/your-media/",
                           "winget":  "Plex.PlexMediaServer"
                       },
    "WPFInstallplexdesktop":  {
                                  "category":  "Media",
                                  "choco":  "plex",
                                  "content":  "Plex Desktop",
                                  "description":  "Plex Desktop for Windows is the front end for Plex Media Server.",
                                  "link":  "https://www.plex.tv",
                                  "winget":  "Plex.Plex"
                              },
    "WPFInstallPortmaster":  {
                                 "category":  "Developer",
                                 "choco":  "portmaster",
                                 "content":  "Portmaster",
                                 "description":  "Portmaster is a free and open-source application that puts you back in charge over all your computers network connections.",
                                 "link":  "https://safing.io/",
                                 "winget":  "Safing.Portmaster",
                                 "foss":  true
                             },
    "WPFInstallpowerautomate":  {
                                    "category":  "Developer",
                                    "choco":  "powerautomatedesktop",
                                    "content":  "Power Automate",
                                    "description":  "Using Power Automate Desktop you can automate tasks on the desktop as well as the Web.",
                                    "link":  "https://www.microsoft.com/en-us/power-platform/products/power-automate",
                                    "winget":  "Microsoft.PowerAutomateDesktop"
                                },
    "WPFInstallpowerbi":  {
                              "category":  "Developer",
                              "choco":  "powerbi",
                              "content":  "Power BI",
                              "description":  "Create stunning reports and visualizations with Power BI Desktop. It puts visual analytics at your fingertips with intuitive report authoring. Drag-and-drop to place content exactly where you want it on the flexible and fluid canvas. Quickly discover patterns as you explore a single unified view of linked, interactive visualizations.",
                              "link":  "https://www.microsoft.com/en-us/power-platform/products/power-bi/",
                              "winget":  "Microsoft.PowerBI"
                          },
    "WPFInstallpowershell":  {
                                 "category":  "Developer",
                                 "choco":  "powershell-core",
                                 "content":  "PowerShell",
                                 "description":  "PowerShell is a task automation framework and scripting language designed for system administrators, offering powerful command-line capabilities.",
                                 "link":  "https://github.com/PowerShell/PowerShell",
                                 "winget":  "Microsoft.PowerShell",
                                 "foss":  true
                             },
    "WPFInstallpowertoys":  {
                                "category":  "Developer",
                                "choco":  "powertoys",
                                "content":  "PowerToys",
                                "description":  "PowerToys is a set of utilities for power users to enhance productivity, featuring tools like FancyZones, PowerRename, and more.",
                                "link":  "https://github.com/microsoft/PowerToys",
                                "winget":  "Microsoft.PowerToys",
                                "foss":  true
                            },
    "WPFInstallprismlauncher":  {
                                    "category":  "Media",
                                    "choco":  "prismlauncher",
                                    "content":  "Prism Launcher",
                                    "description":  "Prism Launcher is an open-source Minecraft launcher with the ability to manage multiple instances, accounts and mods.",
                                    "link":  "https://prismlauncher.org/",
                                    "winget":  "PrismLauncher.PrismLauncher",
                                    "foss":  true
                                },
    "WPFInstallprocessmonitor":  {
                                     "category":  "Developer",
                                     "choco":  "procexp",
                                     "content":  "SysInternals Process Monitor",
                                     "description":  "SysInternals Process Monitor is an advanced monitoring tool that shows real-time file system, registry, and process/thread activity.",
                                     "link":  "https://docs.microsoft.com/en-us/sysinternals/downloads/procmon",
                                     "winget":  "Microsoft.Sysinternals.ProcessMonitor"
                                 },
    "WPFInstallprucaslicer":  {
                                  "category":  "Utilities",
                                  "choco":  "prusaslicer",
                                  "content":  "PrusaSlicer",
                                  "description":  "PrusaSlicer is a powerful and easy-to-use slicing software for 3D printing with Prusa 3D printers.",
                                  "link":  "https://www.prusa3d.com/prusaslicer/",
                                  "winget":  "Prusa3d.PrusaSlicer",
                                  "foss":  true
                              },
    "WPFInstallpsremoteplay":  {
                                   "category":  "Media",
                                   "choco":  "ps-remote-play",
                                   "content":  "PS Remote Play",
                                   "description":  "PS Remote Play is a free application that allows you to stream games from your PlayStation console to a PC or mobile device.",
                                   "link":  "https://remoteplay.dl.playstation.net/remoteplay/lang/gb/",
                                   "winget":  "PlayStation.PSRemotePlay"
                               },
    "WPFInstallputty":  {
                            "category":  "Developer",
                            "choco":  "putty",
                            "content":  "PuTTY",
                            "description":  "PuTTY is a free and open-source terminal emulator, serial console, and network file transfer application. It supports various network protocols such as SSH, Telnet, and SCP.",
                            "link":  "https://www.chiark.greenend.org.uk/~sgtatham/putty/",
                            "winget":  "PuTTY.PuTTY",
                            "foss":  true
                        },
    "WPFInstallpython3":  {
                              "category":  "Developer",
                              "choco":  "python",
                              "content":  "Python3",
                              "description":  "Python is a versatile programming language used for web development, data analysis, artificial intelligence, and more.",
                              "link":  "https://www.python.org/",
                              "winget":  "Python.Python.3.14",
                              "foss":  true
                          },
    "WPFInstallqbittorrent":  {
                                  "category":  "Utilities",
                                  "choco":  "qbittorrent",
                                  "content":  "qBittorrent",
                                  "description":  "qBittorrent is a free and open-source BitTorrent client that aims to provide a feature-rich and lightweight alternative to other torrent clients.",
                                  "link":  "https://www.qbittorrent.org/",
                                  "winget":  "qBittorrent.qBittorrent",
                                  "foss":  true
                              },
    "WPFInstallquicklook":  {
                                "category":  "Utilities",
                                "choco":  "quicklook",
                                "content":  "Quicklook",
                                "description":  "Bring macOS ?Quick Look? feature to Windows.",
                                "link":  "https://github.com/QL-Win/QuickLook",
                                "winget":  "QL-Win.QuickLook",
                                "foss":  true
                            },
    "WPFInstallrainmeter":  {
                                "category":  "Utilities",
                                "choco":  "na",
                                "content":  "Rainmeter",
                                "description":  "Rainmeter is a desktop customization tool that allows you to create and share customizable skins for your desktop.",
                                "link":  "https://www.rainmeter.net/",
                                "winget":  "Rainmeter.Rainmeter",
                                "foss":  true
                            },
    "WPFInstallrevo":  {
                           "category":  "Utilities",
                           "choco":  "revo-uninstaller",
                           "content":  "Revo Uninstaller",
                           "description":  "Revo Uninstaller is an advanced uninstaller tool that helps you remove unwanted software and clean up your system.",
                           "link":  "https://www.revouninstaller.com/",
                           "winget":  "RevoUninstaller.RevoUninstaller"
                       },
    "WPFInstallrufus":  {
                            "category":  "Utilities",
                            "choco":  "rufus",
                            "content":  "Rufus Imager",
                            "description":  "Rufus is a utility that helps format and create bootable USB drives, such as USB keys or pen drives.",
                            "link":  "https://rufus.ie/",
                            "winget":  "Rufus.Rufus",
                            "foss":  true
                        },
    "WPFInstallrustdesk":  {
                               "category":  "Developer",
                               "choco":  "rustdesk.portable",
                               "content":  "RustDesk",
                               "description":  "RustDesk is a free and open-source remote desktop application. It provides a secure way to connect to remote machines and access desktop environments.",
                               "link":  "https://rustdesk.com/",
                               "winget":  "RustDesk.RustDesk",
                               "foss":  true
                           },
    "WPFInstallsysteminformer":  {
                                     "category":  "Developer",
                                     "choco":  "na",
                                     "content":  "System Informer",
                                     "description":  "A free, powerful, multi-purpose tool that helps you monitor system resources, debug software and detect malware.",
                                     "link":  "https://systeminformer.com/",
                                     "winget":  "WinsiderSS.SystemInformer",
                                     "foss":  true
                                 },
    "WPFInstallsidebar":  {
                              "category":  "Advance Systems 4042",
                              "choco":  "na",
                              "content":  "Sidebar",
                              "description":  "Advance Systems 4042 utility (add your project URL in applications.json when ready). Install is manual until you publish a WinGet or Chocolatey package.",
                              "link":  "https://REPLACE_WITH_YOUR_SIDEBAR_URL",
                              "winget":  "na"
                          },
    "WPFInstallsideloadly":  {
                                 "category":  "Mobile \u0026 iOS tools",
                                 "choco":  "na",
                                 "content":  "Sideloadly",
                                 "description":  "Sideload apps to iOS devices without the App Store (IPA install, Apple ID sign-in). Use responsibly and in line with Apple?s terms.",
                                 "link":  "https://sideloadly.io/",
                                 "winget":  "iOSGods.Sideloadly"
                             },
    "WPFInstallslack":  {
                            "category":  "Productivity",
                            "choco":  "slack",
                            "content":  "Slack",
                            "description":  "Slack is a collaboration hub that connects teams and facilitates communication through channels, messaging, and file sharing.",
                            "link":  "https://slack.com/",
                            "winget":  "SlackTechnologies.Slack"
                        },
    "WPFInstallspacedrive":  {
                                 "category":  "Utilities",
                                 "choco":  "na",
                                 "content":  "Spacedrive File Manager",
                                 "description":  "Spacedrive is a file manager that offers cloud storage integration and file synchronization across devices.",
                                 "link":  "https://www.spacedrive.com/",
                                 "winget":  "spacedrive.Spacedrive",
                                 "foss":  true
                             },
    "WPFInstallspotify":  {
                              "category":  "Media",
                              "choco":  "spotify",
                              "content":  "Spotify",
                              "description":  "Spotify streams music and podcasts with playlists, discovery, and offline listening on premium plans.",
                              "link":  "https://www.spotify.com/download/windows/",
                              "winget":  "Spotify.Spotify"
                          },
    "WPFInstallsteam":  {
                            "category":  "Media",
                            "choco":  "steam-client",
                            "content":  "Steam",
                            "description":  "Steam is a digital distribution platform for purchasing and playing video games, offering multiplayer gaming, video streaming, and more.",
                            "link":  "https://store.steampowered.com/about/",
                            "winget":  "Valve.Steam"
                        },
    "WPFInstallsumatra":  {
                              "category":  "Productivity",
                              "choco":  "sumatrapdf",
                              "content":  "Sumatra PDF",
                              "description":  "Sumatra PDF is a lightweight and fast PDF viewer with minimalistic design.",
                              "link":  "https://www.sumatrapdfreader.org/free-pdf-reader.html",
                              "winget":  "SumatraPDF.SumatraPDF",
                              "foss":  true
                          },
    "WPFInstalltailscale":  {
                                "category":  "Utilities",
                                "choco":  "tailscale",
                                "content":  "Tailscale",
                                "description":  "Tailscale is a secure and easy-to-use VPN solution for connecting your devices and networks.",
                                "link":  "https://tailscale.com/",
                                "winget":  "tailscale.tailscale",
                                "foss":  true
                            },
    "WPFInstalltcpview":  {
                              "category":  "Developer",
                              "choco":  "tcpview",
                              "content":  "SysInternals TCPView",
                              "description":  "SysInternals TCPView is a network monitoring tool that displays a detailed list of all TCP and UDP endpoints on your system.",
                              "link":  "https://docs.microsoft.com/en-us/sysinternals/downloads/tcpview",
                              "winget":  "Microsoft.Sysinternals.TCPView"
                          },
    "WPFInstallteams":  {
                            "category":  "Productivity",
                            "choco":  "microsoft-teams",
                            "content":  "Teams",
                            "description":  "Microsoft Teams is a collaboration platform that integrates with Office 365 and offers chat, video conferencing, file sharing, and more.",
                            "link":  "https://www.microsoft.com/en-us/microsoft-teams/group-chat-software",
                            "winget":  "Microsoft.Teams"
                        },
    "WPFInstallteamviewer":  {
                                 "category":  "Utilities",
                                 "choco":  "teamviewer9",
                                 "content":  "TeamViewer",
                                 "description":  "TeamViewer is a popular remote access and support software that allows you to connect to and control remote devices.",
                                 "link":  "https://www.teamviewer.com/",
                                 "winget":  "TeamViewer.TeamViewer"
                             },
    "WPFInstallteamspeak3":  {
                                 "category":  "Utilities",
                                 "choco":  "teamspeak",
                                 "content":  "TeamSpeak 3",
                                 "description":  "TEAMSPEAK. YOUR TEAM. YOUR RULES. Use crystal clear sound to communicate with your team mates cross-platform with military-grade security, lag-free performance \u0026 unparalleled reliability and uptime.",
                                 "link":  "https://www.teamspeak.com/",
                                 "winget":  "TeamSpeakSystems.TeamSpeakClient"
                             },
    "WPFInstalltelegram":  {
                               "category":  "Productivity",
                               "choco":  "telegram",
                               "content":  "Telegram",
                               "description":  "Telegram is a cloud-based instant messaging app known for its security features, speed, and simplicity.",
                               "link":  "https://telegram.org/",
                               "winget":  "Telegram.TelegramDesktop",
                               "foss":  true
                           },
    "WPFInstallterminal":  {
                               "category":  "Developer",
                               "choco":  "microsoft-windows-terminal",
                               "content":  "Windows Terminal",
                               "description":  "Windows Terminal is a modern, fast, and efficient terminal application for command-line users, supporting multiple tabs, panes, and more.",
                               "link":  "https://aka.ms/terminal",
                               "winget":  "Microsoft.WindowsTerminal",
                               "foss":  true
                           },
    "WPFInstallthunderbird":  {
                                  "category":  "Productivity",
                                  "choco":  "thunderbird",
                                  "content":  "Thunderbird",
                                  "description":  "Mozilla Thunderbird is a free and open-source email client, news client, and chat client with advanced features.",
                                  "link":  "https://www.thunderbird.net/",
                                  "winget":  "Mozilla.Thunderbird",
                                  "foss":  true
                              },
    "WPFInstalltor":  {
                          "category":  "Browser",
                          "choco":  "tor-browser",
                          "content":  "Tor Browser",
                          "description":  "Tor Browser is designed for anonymous web browsing, utilizing the Tor network to protect user privacy and security.",
                          "link":  "https://www.torproject.org/",
                          "winget":  "TorProject.TorBrowser",
                          "foss":  true
                      },
    "WPFInstalltreesize":  {
                               "category":  "Utilities",
                               "choco":  "treesizefree",
                               "content":  "TreeSize Free",
                               "description":  "TreeSize Free is a disk space manager that helps you analyze and visualize the space usage on your drives.",
                               "link":  "https://www.jam-software.com/treesize_free/",
                               "winget":  "JAMSoftware.TreeSize.Free"
                           },
    "WPFInstallubisoft":  {
                              "category":  "Media",
                              "choco":  "ubisoft-connect",
                              "content":  "Ubisoft Connect",
                              "description":  "Ubisoft Connect is Ubisoft\u0027s digital distribution and online gaming service, providing access to Ubisoft\u0027s games and services.",
                              "link":  "https://ubisoftconnect.com/",
                              "winget":  "Ubisoft.Connect"
                          },
    "WPFInstallungoogled":  {
                                "category":  "Browser",
                                "choco":  "ungoogled-chromium",
                                "content":  "Ungoogled",
                                "description":  "Ungoogled Chromium is a version of Chromium without Google\u0027s integration for enhanced privacy and control.",
                                "link":  "https://github.com/Eloston/ungoogled-chromium",
                                "winget":  "eloston.ungoogled-chromium",
                                "foss":  true
                            },
    "WPFInstallunity":  {
                            "category":  "Developer",
                            "choco":  "unityhub",
                            "content":  "Unity Game Engine",
                            "description":  "Unity is a powerful game development platform for creating 2D, 3D, augmented reality, and virtual reality games.",
                            "link":  "https://unity.com/",
                            "winget":  "Unity.UnityHub"
                        },
    "WPFInstallvc2015_64":  {
                                "category":  "Developer",
                                "choco":  "na",
                                "content":  "Visual C++ 2015-2022 64-bit",
                                "description":  "Visual C++ 2015-2022 64-bit redistributable package installs runtime components of Visual C++ libraries required to run 64-bit applications.",
                                "link":  "https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads",
                                "winget":  "Microsoft.VCRedist.2015+.x64"
                            },
    "WPFInstallventoy":  {
                             "category":  "Developer",
                             "choco":  "ventoy",
                             "content":  "Ventoy",
                             "description":  "Ventoy is an open-source tool for creating bootable USB drives. It supports multiple ISO files on a single USB drive, making it a versatile solution for installing operating systems.",
                             "link":  "https://www.ventoy.net/",
                             "winget":  "Ventoy.Ventoy",
                             "foss":  true
                         },
    "WPFInstallvisualstudio2026":  {
                                       "category":  "Developer",
                                       "choco":  "visualstudio2026community",
                                       "content":  "Visual Studio 2026",
                                       "description":  "Visual Studio 2026 is an integrated development environment (IDE) for building, debugging, and deploying applications.",
                                       "link":  "https://visualstudio.microsoft.com/",
                                       "winget":  "Microsoft.VisualStudio.2026.Community"
                                   },
    "WPFInstallvortex":  {
                             "category":  "Media",
                             "choco":  "na",
                             "content":  "Vortex Mod Manager",
                             "description":  "Nexus Mods mod manager for games: install, enable, and sort mods with conflict detection and plugin support.",
                             "link":  "https://www.nexusmods.com/about/vortex/",
                             "winget":  "NexusMods.Vortex",
                             "foss":  true
                         },
    "WPFInstallvlc":  {
                          "category":  "Media",
                          "choco":  "vlc",
                          "content":  "VLC (Video Player)",
                          "description":  "VLC Media Player is a free and open-source multimedia player that supports a wide range of audio and video formats. It is known for its versatility and cross-platform compatibility.",
                          "link":  "https://www.videolan.org/vlc/",
                          "winget":  "VideoLAN.VLC",
                          "foss":  true
                      },
    "WPFInstallvoicemeeter":  {
                                  "category":  "Media",
                                  "choco":  "voicemeeter",
                                  "content":  "Voicemeeter (Audio)",
                                  "description":  "Voicemeeter is a virtual audio mixer that allows you to manage and enhance audio streams on your computer. It is commonly used for audio recording and streaming purposes.",
                                  "link":  "https://voicemeeter.com/",
                                  "winget":  "VB-Audio.Voicemeeter"
                              },
    "WPFInstallVoicemeeterPotato":  {
                                        "category":  "Media",
                                        "choco":  "voicemeeter-potato",
                                        "content":  "Voicemeeter Potato",
                                        "description":  "Voicemeeter Potato is the ultimate version of the Voicemeeter Audio Mixer Application endowed with Virtual Audio Device to mix and manage any audio sources from or to any audio devices or applications.",
                                        "link":  "https://voicemeeter.com/",
                                        "winget":  "VB-Audio.Voicemeeter.Potato"
                                    },
    "WPFInstallvscode":  {
                             "category":  "Developer",
                             "choco":  "vscode",
                             "content":  "VS Code",
                             "description":  "Visual Studio Code is a free, open-source code editor with support for multiple programming languages.",
                             "link":  "https://code.visualstudio.com/",
                             "winget":  "Microsoft.VisualStudioCode",
                             "foss":  true
                         },
    "WPFInstallwaterfox":  {
                               "category":  "Browser",
                               "choco":  "waterfox",
                               "content":  "Waterfox",
                               "description":  "Waterfox is a fast, privacy-focused web browser based on Firefox, designed to preserve user choice and privacy.",
                               "link":  "https://www.waterfox.net/",
                               "winget":  "Waterfox.Waterfox",
                               "foss":  true
                           },
    "WPFInstallwingetui":  {
                               "category":  "Utilities",
                               "choco":  "wingetui",
                               "content":  "UniGetUI",
                               "description":  "UniGetUI is a GUI for WinGet, Chocolatey, and other Windows CLI package managers.",
                               "link":  "https://devolutions.net/unigetui/",
                               "winget":  "Devolutions.UniGetUI",
                               "foss":  true
                           },
    "WPFInstallwinrar":  {
                             "category":  "Utilities",
                             "choco":  "winrar",
                             "content":  "WinRAR",
                             "description":  "WinRAR is a powerful archive manager that allows you to create, manage, and extract compressed files.",
                             "link":  "https://www.win-rar.com/",
                             "winget":  "RARLab.WinRAR"
                         },
    "WPFInstallwinscp":  {
                             "category":  "Developer",
                             "choco":  "winscp",
                             "content":  "WinSCP",
                             "description":  "WinSCP is a popular open-source SFTP, FTP, and SCP client for Windows. It allows secure file transfers between a local and a remote computer.",
                             "link":  "https://winscp.net/",
                             "winget":  "WinSCP.WinSCP",
                             "foss":  true
                         },
    "WPFInstallwireguard":  {
                                "category":  "Developer",
                                "choco":  "wireguard",
                                "content":  "WireGuard",
                                "description":  "WireGuard is a fast and modern VPN (Virtual Private Network) protocol. It aims to be simpler and more efficient than other VPN protocols, providing secure and reliable connections.",
                                "link":  "https://www.wireguard.com/",
                                "winget":  "WireGuard.WireGuard",
                                "foss":  true
                            },
    "WPFInstallwireshark":  {
                                "category":  "Developer",
                                "choco":  "wireshark",
                                "content":  "Wireshark",
                                "description":  "Wireshark is a widely-used open-source network protocol analyzer. It allows users to capture and analyze network traffic in real-time, providing detailed insights into network activities.",
                                "link":  "https://www.wireshark.org/",
                                "winget":  "WiresharkFoundation.Wireshark",
                                "foss":  true
                            },
    "WPFInstallwisetoys":  {
                               "category":  "Utilities",
                               "choco":  "na",
                               "content":  "WiseToys",
                               "description":  "WiseToys is a set of utilities and tools designed to enhance and optimize your Windows experience.",
                               "link":  "https://toys.wisecleaner.com/",
                               "winget":  "WiseCleaner.WiseToys"
                           },
    "WPFInstallwittytool":  {
                                "category":  "Utilities",
                                "choco":  "na",
                                "content":  "WittyTool",
                                "description":  "Free disk clone, partition, and data recovery tools from WittyTool. Install from the website; not available via WinGet or Chocolatey in this list.",
                                "link":  "https://www.wittytool.com/",
                                "winget":  "na"
                            },
    "WPFInstallwizfile":  {
                              "category":  "Utilities",
                              "choco":  "na",
                              "content":  "WizFile",
                              "description":  "Find files by name on your hard drives almost instantly.",
                              "link":  "https://antibody-software.com/wizfile/",
                              "winget":  "AntibodySoftware.WizFile"
                          },
    "WPFInstallwiztree":  {
                              "category":  "Utilities",
                              "choco":  "wiztree",
                              "content":  "WizTree",
                              "description":  "WizTree is a fast disk space analyzer that helps you quickly find the files and folders consuming the most space on your hard drive.",
                              "link":  "https://wiztreefree.com/",
                              "winget":  "AntibodySoftware.WizTree"
                          },
    "WPFInstallxdm":  {
                          "category":  "Utilities",
                          "choco":  "xdm",
                          "content":  "Xtreme Download Manager",
                          "description":  "Xtreme Download Manager is an advanced download manager with support for various protocols and browsers. *Browser integration deprecated by google store. No official release.*",
                          "link":  "https://xtremedownloadmanager.com/",
                          "winget":  "subhra74.XtremeDownloadManager",
                          "foss":  true
                      },
    "WPFInstallwindowsfirewallcontrol":  {
                                             "category":  "Utilities",
                                             "choco":  "windowsfirewallcontrol",
                                             "content":  "Windows Firewall Control",
                                             "description":  "Windows Firewall Control is a powerful tool which extends the functionality of Windows Firewall and provides new extra features which makes Windows Firewall better.",
                                             "link":  "https://www.binisoft.org/wfc",
                                             "winget":  "BiniSoft.WindowsFirewallControl"
                                         },
    "WPFInstallfancontrol":  {
                                 "category":  "Utilities",
                                 "choco":  "na",
                                 "content":  "FanControl",
                                 "description":  "Fan Control is a free and open-source software that allows the user to control his CPU, GPU and case fans using temperatures.",
                                 "link":  "https://getfancontrol.com/",
                                 "winget":  "Rem0o.FanControl",
                                 "foss":  true
                             },
    "WPFInstallWindhawk":  {
                               "category":  "Utilities",
                               "choco":  "windhawk",
                               "content":  "Windhawk",
                               "description":  "The customization marketplace for Windows programs.",
                               "link":  "https://windhawk.net",
                               "winget":  "RamenSoftware.Windhawk"
                           },
    "WPFInstallJoyToKey":  {
                               "category":  "Utilities",
                               "choco":  "joytokey",
                               "content":  "JoyToKey",
                               "description":  "Enables PC game controllers to emulate the keyboard and mouse input.",
                               "link":  "https://joytokey.net/en/",
                               "winget":  "JTKsoftware.JoyToKey"
                           },
    "WPFInstalldropox":  {
                             "category":  "Utilities",
                             "choco":  "na",
                             "content":  "Dropbox",
                             "description":  "The Dropbox desktop app! Save hard drive space, share and edit files and send for signature ? all without the distraction of countless browser tabs.",
                             "link":  "https://www.dropbox.com/en_GB/desktop",
                             "winget":  "Dropbox.Dropbox"
                         },
    "WPFInstallOverwolf":  {
                               "category":  "Media",
                               "choco":  "overwolf",
                               "content":  "Overwolf",
                               "description":  "Popular platform for game overlays and companion apps (mod managers, trackers, etc.), widely used by gamers.",
                               "link":  "https://www.overwolf.com/app/overwolf-curseforge",
                               "winget":  "Overwolf.CurseForge"
                           },
    "WPFInstallLenovoLegionToolkit":  {
                                          "category":  "Utilities",
                                          "choco":  "na",
                                          "content":  "Lenovo Legion Toolkit",
                                          "description":  "Lenovo Legion Toolkit (LLT) is a open-source utility created for Lenovo Legion laptops, that allows changing a couple of features that are only available in Lenovo Vantage or Legion Zone. It runs no background services, uses less memory, uses virtually no CPU, and contains no telemetry. Just like Lenovo Vantage, this application is Windows only.",
                                          "link":  "https://github.com/BartoszCichecki/LenovoLegionToolkit",
                                          "winget":  "BartoszCichecki.LenovoLegionToolkit",
                                          "foss":  true
                                      },
    "WPFInstallLenovoVantage":  {
                                    "category":  "Utilities",
                                    "choco":  "na",
                                    "content":  "Lenovo Vantage",
                                    "description":  "Official Lenovo utility for driver updates, hardware diagnostics, and device settings management.",
                                    "link":  "https://support.lenovo.com/solutions/ht505081",
                                    "winget":  "9WZDNCRFJ4MV"
                                },
    "WPFInstallMSICenter":  {
                                "category":  "Utilities",
                                "choco":  "na",
                                "content":  "MSI Center",
                                "description":  "Official MSI system utility for updates, hardware monitoring, performance tuning, and device features.",
                                "link":  "https://www.msi.com/Landing/MSI-Center",
                                "winget":  "na"
                            },
    "WPFInstallASUSArmouryCrate":  {
                                       "category":  "Utilities",
                                       "choco":  "na",
                                       "content":  "ASUS Armoury Crate",
                                       "description":  "ASUS/ROG control center for device updates, RGB management, fan profiles, and performance modes.",
                                       "link":  "https://rog.asus.com/armoury-crate/",
                                       "winget":  "Asus.ArmouryCrate"
                                   },
    "WPFInstallDellCommandUpdate":  {
                                        "category":  "Utilities",
                                        "choco":  "na",
                                        "content":  "Dell Command | Update",
                                        "description":  "Official Dell tool to update BIOS, firmware, drivers, and OEM software on Dell systems.",
                                        "link":  "https://www.dell.com/support/home/drivers/driversdetails?driverid=0xnvx",
                                        "winget":  "Dell.CommandUpdate"
                                    },
    "WPFInstallThrottleStop":  {
                                   "category":  "Utilities",
                                   "choco":  "na",
                                   "content":  "ThrottleStop",
                                   "description":  "Advanced CPU tuning and throttling diagnostics utility for laptops and mobile processors.",
                                   "link":  "https://www.techpowerup.com/download/techpowerup-throttlestop/",
                                   "winget":  "TechPowerUp.ThrottleStop"
                               },
    "WPFInstallValiDrive":  {
                                "category":  "Utilities",
                                "choco":  "na",
                                "content":  "ValiDrive",
                                "description":  "USB storage validation tool by GRC for detecting counterfeit or misreported flash drive capacity.",
                                "link":  "https://www.grc.com/validrive.htm",
                                "winget":  "GibsonResearchCorporation.ValiDrive"
                            },
    "WPFInstallZenBrowser":  {
                                 "category":  "Browser",
                                 "choco":  "na",
                                 "content":  "Zen Browser",
                                 "description":  "The modern, privacy-focused, performance-driven browser built on Firefox.",
                                 "link":  "https://zen-browser.app/",
                                 "winget":  "Zen-Team.Zen-Browser",
                                 "foss":  true
                             }
}
'@ | ConvertFrom-Json
$sync.configs.appnavigation = @'
{
    "WPFInstall":  {
                       "Content":  "Install/Upgrade Applications",
                       "Category":  "____Actions",
                       "Type":  "Button",
                       "Order":  "1",
                       "Description":  "Install or upgrade the selected applications"
                   },
    "WPFUninstall":  {
                         "Content":  "Uninstall Applications",
                         "Category":  "____Actions",
                         "Type":  "Button",
                         "Order":  "2",
                         "Description":  "Uninstall the selected applications"
                     },
    "WPFInstallUpgrade":  {
                              "Content":  "Upgrade all Applications",
                              "Category":  "____Actions",
                              "Type":  "Button",
                              "Order":  "3",
                              "Description":  "Upgrade all applications to the latest version"
                          },
    "WingetRadioButton":  {
                              "Content":  "WinGet",
                              "Category":  "__Package Manager",
                              "Type":  "RadioButton",
                              "GroupName":  "PackageManagerGroup",
                              "Checked":  true,
                              "Order":  "1",
                              "Description":  "Use WinGet for package management"
                          },
    "ChocoRadioButton":  {
                             "Content":  "Chocolatey",
                             "Category":  "__Package Manager",
                             "Type":  "RadioButton",
                             "GroupName":  "PackageManagerGroup",
                             "Checked":  false,
                             "Order":  "2",
                             "Description":  "Use Chocolatey for package management"
                         },
    "WPFCollapseAllCategories":  {
                                     "Content":  "Collapse All Categories",
                                     "Category":  "____Actions",
                                     "Type":  "Button",
                                     "Order":  "1",
                                     "Description":  "Collapse all application categories"
                                 },
    "WPFExpandAllCategories":  {
                                   "Content":  "Expand All Categories",
                                   "Category":  "____Actions",
                                   "Type":  "Button",
                                   "Order":  "2",
                                   "Description":  "Expand all application categories"
                               },
    "WPFClearInstallSelection":  {
                                     "Content":  "Clear Selection",
                                     "Category":  "____Actions",
                                     "Type":  "Button",
                                     "Order":  "3",
                                     "Description":  "Clear the selection of applications"
                                 },
    "WPFGetInstalled":  {
                            "Content":  "Show Installed Apps",
                            "Category":  "____Actions",
                            "Type":  "Button",
                            "Order":  "4",
                            "Description":  "Show installed applications"
                        },
    "WPFselectedAppsButton":  {
                                  "Content":  "Selected Apps: 0",
                                  "Category":  "____Actions",
                                  "Type":  "Button",
                                  "Order":  "5",
                                  "Description":  "Show the selected applications"
                              },
    "WPFActivationScripts":  {
                                 "Content":  "MAS - Activation menu (local)",
                                 "Category":  "__Activation (local MAS)",
                                 "Type":  "Button",
                                 "Order":  "1",
                                 "Description":  "Opens the local Microsoft Activation Scripts (MAS) menu from Microsoft-Activation-Scripts-master"
                             },
    "WPFCheckActivationStatus":  {
                                     "Content":  "MAS - Check activation status",
                                     "Category":  "__Activation (local MAS)",
                                     "Type":  "Button",
                                     "Order":  "2",
                                     "Description":  "Runs local MAS Check_Activation_Status for Windows and Office"
                                 },
    "WPFToggleFOSSHighlight":  {
                                   "Content":  "Highlight FOSS",
                                   "Category":  "__Package Manager",
                                   "Type":  "Toggle",
                                   "Checked":  true,
                                   "Order":  "6",
                                   "Description":  "Toggle the green highlight for FOSS applications"
                               }
}
'@ | ConvertFrom-Json
$sync.configs.dns = @'
{
    "Google":  {
                   "Primary":  "8.8.8.8",
                   "Secondary":  "8.8.4.4",
                   "Primary6":  "2001:4860:4860::8888",
                   "Secondary6":  "2001:4860:4860::8844"
               },
    "Cloudflare":  {
                       "Primary":  "1.1.1.1",
                       "Secondary":  "1.0.0.1",
                       "Primary6":  "2606:4700:4700::1111",
                       "Secondary6":  "2606:4700:4700::1001"
                   },
    "Cloudflare_Malware":  {
                               "Primary":  "1.1.1.2",
                               "Secondary":  "1.0.0.2",
                               "Primary6":  "2606:4700:4700::1112",
                               "Secondary6":  "2606:4700:4700::1002"
                           },
    "Cloudflare_Malware_Adult":  {
                                     "Primary":  "1.1.1.3",
                                     "Secondary":  "1.0.0.3",
                                     "Primary6":  "2606:4700:4700::1113",
                                     "Secondary6":  "2606:4700:4700::1003"
                                 },
    "Open_DNS":  {
                     "Primary":  "208.67.222.222",
                     "Secondary":  "208.67.220.220",
                     "Primary6":  "2620:119:35::35",
                     "Secondary6":  "2620:119:53::53"
                 },
    "Quad9":  {
                  "Primary":  "9.9.9.9",
                  "Secondary":  "149.112.112.112",
                  "Primary6":  "2620:fe::fe",
                  "Secondary6":  "2620:fe::9"
              },
    "AdGuard_Ads_Trackers":  {
                                 "Primary":  "94.140.14.14",
                                 "Secondary":  "94.140.15.15",
                                 "Primary6":  "2a10:50c0::ad1:ff",
                                 "Secondary6":  "2a10:50c0::ad2:ff"
                             },
    "AdGuard_Ads_Trackers_Malware_Adult":  {
                                               "Primary":  "94.140.14.15",
                                               "Secondary":  "94.140.15.16",
                                               "Primary6":  "2a10:50c0::bad1:ff",
                                               "Secondary6":  "2a10:50c0::bad2:ff"
                                           }
}
'@ | ConvertFrom-Json
$sync.configs.feature = @'
{
    "WPFFeaturesdotnet":  {
                              "Content":  "All .Net Framework (2,3,4)",
                              "Description":  ".NET and .NET Framework is a developer platform made up of tools, programming languages, and libraries for building many different types of applications.",
                              "category":  "Windows",
                              "panel":  "1",
                              "feature":  [
                                              "NetFx4-AdvSrvs",
                                              "NetFx3"
                                          ],
                              "InvokeScript":  [

                                               ],
                              "link":  "https://clark.christitus.com/dev/features/features/dotnet"
                          },
    "WPFFixesNTPPool":  {
                            "Content":  "Configure NTP Server",
                            "Description":  "Replaces the default Windows NTP server (time.windows.com) with pool.ntp.org for improved time synchronization accuracy and reliability.",
                            "category":  "Windows",
                            "panel":  "1",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "function":  "Invoke-WPFFixesNTPPool",
                            "link":  "https://clark.christitus.com/dev/features/fixes/ntppool"
                        },
    "WPFFeatureshyperv":  {
                              "Content":  "HyperV Virtualization",
                              "Description":  "Hyper-V is a hardware virtualization product developed by Microsoft that allows users to create and manage virtual machines.",
                              "category":  "Windows",
                              "panel":  "1",
                              "feature":  [
                                              "Microsoft-Hyper-V-All"
                                          ],
                              "InvokeScript":  [
                                                   "bcdedit /set hypervisorschedulertype classic"
                                               ],
                              "link":  "https://clark.christitus.com/dev/features/features/hyperv"
                          },
    "WPFFeatureslegacymedia":  {
                                   "Content":  "Legacy Media (WMP, DirectPlay)",
                                   "Description":  "Enables legacy programs from previous versions of Windows.",
                                   "category":  "Windows",
                                   "panel":  "1",
                                   "feature":  [
                                                   "WindowsMediaPlayer",
                                                   "MediaPlayback",
                                                   "DirectPlay",
                                                   "LegacyComponents"
                                               ],
                                   "InvokeScript":  [

                                                    ],
                                   "link":  "https://clark.christitus.com/dev/features/features/legacymedia"
                               },
    "WPFFeaturewsl":  {
                          "Content":  "Windows Subsystem for Linux",
                          "Description":  "Windows Subsystem for Linux is an optional feature of Windows that allows Linux programs to run natively on Windows without the need for a separate virtual machine or dual booting.",
                          "category":  "Windows",
                          "panel":  "1",
                          "feature":  [
                                          "VirtualMachinePlatform",
                                          "Microsoft-Windows-Subsystem-Linux"
                                      ],
                          "InvokeScript":  [

                                           ],
                          "link":  "https://clark.christitus.com/dev/features/features/wsl"
                      },
    "WPFFeaturenfs":  {
                          "Content":  "NFS - Network File System",
                          "Description":  "Network File System (NFS) is a mechanism for storing files on a network.",
                          "category":  "Windows",
                          "panel":  "1",
                          "feature":  [
                                          "ServicesForNFS-ClientOnly",
                                          "ClientForNFS-Infrastructure",
                                          "NFS-Administration"
                                      ],
                          "InvokeScript":  [
                                               "nfsadmin client stop",
                                               "Set-ItemProperty -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default\u0027 -Name \u0027AnonymousUID\u0027 -Type DWord -Value 0",
                                               "Set-ItemProperty -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default\u0027 -Name \u0027AnonymousGID\u0027 -Type DWord -Value 0",
                                               "nfsadmin client start",
                                               "nfsadmin client localhost config fileaccess=755 SecFlavors=+sys -krb5 -krb5i"
                                           ],
                          "link":  "https://clark.christitus.com/dev/features/features/nfs"
                      },
    "WPFFeatureRegBackup":  {
                                "Content":  "Enable Daily Registry Backup Task 12.30am",
                                "Description":  "Enables daily registry backup, previously disabled by Microsoft in Windows 10 1803.",
                                "category":  "Windows",
                                "panel":  "1",
                                "feature":  [

                                            ],
                                "InvokeScript":  [
                                                     "\r\n      New-ItemProperty -Path \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\u0027 -Name \u0027EnablePeriodicBackup\u0027 -Type DWord -Value 1 -Force\r\n      New-ItemProperty -Path \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\u0027 -Name \u0027BackupCount\u0027 -Type DWord -Value 2 -Force\r\n      $action = New-ScheduledTaskAction -Execute \u0027schtasks\u0027 -Argument \u0027/run /i /tn \"\\Microsoft\\Windows\\Registry\\RegIdleBackup\"\u0027\r\n      $trigger = New-ScheduledTaskTrigger -Daily -At 00:30\r\n      Register-ScheduledTask -Action $action -Trigger $trigger -TaskName \u0027AutoRegBackup\u0027 -Description \u0027Create System Registry Backups\u0027 -User \u0027System\u0027\r\n      "
                                                 ],
                                "link":  "https://clark.christitus.com/dev/features/features/regbackup"
                            },
    "WPFFeatureEnableLegacyRecovery":  {
                                           "Content":  "Enable Legacy F8 Boot Recovery",
                                           "Description":  "Enables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes.",
                                           "category":  "Windows",
                                           "panel":  "1",
                                           "feature":  [

                                                       ],
                                           "InvokeScript":  [
                                                                "bcdedit /set bootmenupolicy legacy"
                                                            ],
                                           "link":  "https://clark.christitus.com/dev/features/features/enablelegacyrecovery"
                                       },
    "WPFFeatureDisableLegacyRecovery":  {
                                            "Content":  "Disable Legacy F8 Boot Recovery",
                                            "Description":  "Disables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes.",
                                            "category":  "Windows",
                                            "panel":  "1",
                                            "feature":  [

                                                        ],
                                            "InvokeScript":  [
                                                                 "bcdedit /set bootmenupolicy standard"
                                                             ],
                                            "link":  "https://clark.christitus.com/dev/features/features/disablelegacyrecovery"
                                        },
    "WPFFeaturesSandbox":  {
                               "Content":  "Windows Sandbox",
                               "Description":  "Windows Sandbox is a lightweight virtual machine that provides a temporary desktop environment to safely run applications and programs in isolation.",
                               "category":  "Windows",
                               "panel":  "1",
                               "feature":  [
                                               "Containers-DisposableClientVM"
                                           ],
                               "link":  "https://clark.christitus.com/dev/features/features/sandbox"
                           },
    "WPFFeatureInstall":  {
                              "Content":  "Install Features",
                              "category":  "Windows",
                              "panel":  "1",
                              "Type":  "Button",
                              "ButtonWidth":  "300",
                              "function":  "Invoke-WPFFeatureInstall",
                              "link":  "https://clark.christitus.com/dev/features/features/install"
                          },
    "WPFPanelAutologin":  {
                              "Content":  "Set Up Autologin",
                              "category":  "Windows",
                              "panel":  "1",
                              "Type":  "Button",
                              "ButtonWidth":  "300",
                              "function":  "Invoke-WPFPanelAutologin",
                              "link":  "https://clark.christitus.com/dev/features/fixes/autologin"
                          },
    "WPFFixesUpdate":  {
                           "Content":  "Reset Windows Update",
                           "category":  "Windows",
                           "panel":  "1",
                           "Type":  "Button",
                           "ButtonWidth":  "300",
                           "function":  "Invoke-WPFFixesUpdate",
                           "link":  "https://clark.christitus.com/dev/features/fixes/update"
                       },
    "WPFFixesNetwork":  {
                            "Content":  "Reset Network",
                            "category":  "Windows",
                            "panel":  "1",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "function":  "Invoke-WPFFixesNetwork",
                            "link":  "https://clark.christitus.com/dev/features/fixes/network"
                        },
    "WPFPanelDISM":  {
                         "Content":  "System Corruption Scan",
                         "category":  "Windows",
                         "panel":  "1",
                         "Type":  "Button",
                         "ButtonWidth":  "300",
                         "function":  "Invoke-WPFSystemRepair",
                         "link":  "https://clark.christitus.com/dev/features/fixes/dism"
                     },
    "WPFFixesWinget":  {
                           "Content":  "WinGet Reinstall",
                           "category":  "Windows",
                           "panel":  "1",
                           "Type":  "Button",
                           "ButtonWidth":  "300",
                           "function":  "Invoke-WPFFixesWinget",
                           "link":  "https://clark.christitus.com/dev/features/fixes/winget"
                       },
    "WPFPanelControl":  {
                            "Content":  "Control Panel",
                            "category":  "Panels",
                            "panel":  "2",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "InvokeScript":  [
                                                 "control"
                                             ],
                            "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/control"
                        },
    "WPFPanelComputer":  {
                             "Content":  "Computer Management",
                             "category":  "Panels",
                             "panel":  "2",
                             "Type":  "Button",
                             "ButtonWidth":  "300",
                             "InvokeScript":  [
                                                  "compmgmt.msc"
                                              ],
                             "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/computer"
                         },
    "WPFPanelNetwork":  {
                            "Content":  "Network Connections",
                            "category":  "Panels",
                            "panel":  "2",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "InvokeScript":  [
                                                 "ncpa.cpl"
                                             ],
                            "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/network"
                        },
    "WPFPanelPower":  {
                          "Content":  "Power Panel",
                          "category":  "Panels",
                          "panel":  "2",
                          "Type":  "Button",
                          "ButtonWidth":  "300",
                          "InvokeScript":  [
                                               "powercfg.cpl"
                                           ],
                          "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/power"
                      },
    "WPFPanelPrinter":  {
                            "Content":  "Printer Panel",
                            "category":  "Panels",
                            "panel":  "2",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "InvokeScript":  [
                                                 "Start-Process \u0027shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}\u0027"
                                             ],
                            "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/printer"
                        },
    "WPFPanelRegion":  {
                           "Content":  "Region",
                           "category":  "Panels",
                           "panel":  "2",
                           "Type":  "Button",
                           "ButtonWidth":  "300",
                           "InvokeScript":  [
                                                "intl.cpl"
                                            ],
                           "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/region"
                       },
    "WPFPanelRestore":  {
                            "Content":  "Windows Restore",
                            "category":  "Panels",
                            "panel":  "2",
                            "Type":  "Button",
                            "ButtonWidth":  "300",
                            "InvokeScript":  [
                                                 "rstrui.exe"
                                             ],
                            "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/restore"
                        },
    "WPFPanelSound":  {
                          "Content":  "Sound Settings",
                          "category":  "Panels",
                          "panel":  "2",
                          "Type":  "Button",
                          "ButtonWidth":  "300",
                          "InvokeScript":  [
                                               "mmsys.cpl"
                                           ],
                          "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/sound"
                      },
    "WPFPanelSystem":  {
                           "Content":  "System Properties",
                           "category":  "Panels",
                           "panel":  "2",
                           "Type":  "Button",
                           "ButtonWidth":  "300",
                           "InvokeScript":  [
                                                "sysdm.cpl"
                                            ],
                           "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/system"
                       },
    "WPFPanelTimedate":  {
                             "Content":  "Time and Date",
                             "category":  "Panels",
                             "panel":  "2",
                             "Type":  "Button",
                             "ButtonWidth":  "300",
                             "InvokeScript":  [
                                                  "timedate.cpl"
                                              ],
                             "link":  "https://clark.christitus.com/dev/features/legacy-windows-panels/timedate"
                         },
    "WPFClarkInstallPSProfile":  {
                                     "Content":  "Install CTT PowerShell Profile",
                                     "category":  "PowerShell 7",
                                     "panel":  "2",
                                     "Type":  "Button",
                                     "ButtonWidth":  "300",
                                     "function":  "Invoke-ClarkInstallPSProfile",
                                     "link":  "https://clark.christitus.com/dev/features/powershell-profile-powershell-7--only/installpsprofile"
                                 },
    "WPFClarkUninstallPSProfile":  {
                                       "Content":  "Uninstall CTT PowerShell Profile",
                                       "category":  "PowerShell 7",
                                       "panel":  "2",
                                       "Type":  "Button",
                                       "ButtonWidth":  "300",
                                       "function":  "Invoke-ClarkUninstallPSProfile",
                                       "link":  "https://clark.christitus.com/dev/features/powershell-profile-powershell-7--only/uninstallpsprofile"
                                   },
    "WPFClarkSSHServer":  {
                              "Content":  "Enable OpenSSH Server",
                              "category":  "Remote",
                              "panel":  "2",
                              "Type":  "Button",
                              "ButtonWidth":  "300",
                              "function":  "Invoke-WPFSSHServer",
                              "link":  "https://clark.christitus.com/dev/features/remote-access/sshserver"
                          }
}
'@ | ConvertFrom-Json
$sync.configs.isomirrors = @'
{
    "_readme":  "Optional Internet Archive (or any https) direct links to .iso files. Keys must match the ISO tab: product Windows 11 / Windows 10 and release e.g. Latest, 25H2, 22H2. Empty string skips that slot. When a URL is set, clark tries it first; if download fails, it falls back to Fido (Microsoft).",
    "internetArchiveIsoUrls":  {
                                   "Windows 11":  {
                                                      "Latest":  "",
                                                      "25H2":  ""
                                                  },
                                   "Windows 10":  {
                                                      "Latest":  "",
                                                      "22H2":  ""
                                                  }
                               }
}
'@ | ConvertFrom-Json
$sync.configs.preset = @'
{
    "Standard":  [
                     "WPFTweaksActivity",
                     "WPFTweaksConsumerFeatures",
                     "WPFTweaksDisableExplorerAutoDiscovery",
                     "WPFTweaksWPBT",
                     "WPFTweaksDVR",
                     "WPFTweaksLocation",
                     "WPFTweaksServices",
                     "WPFTweaksTelemetry",
                     "WPFTweaksDiskCleanup",
                     "WPFTweaksDeleteTempFiles",
                     "WPFTweaksEndTaskOnTaskbar",
                     "WPFTweaksRestorePoint",
                     "WPFTweaksPowershell7Tele"
                 ],
    "Minimal":  [
                    "WPFTweaksConsumerFeatures",
                    "WPFTweaksWPBT",
                    "WPFTweaksServices",
                    "WPFTweaksTelemetry"
                ]
}
'@ | ConvertFrom-Json
$sync.configs.profiles = @'
{
    "WPFProfileCreateWithOptions":  {
                                        "Content":  "Create profile (pick what to include)",
                                        "Description":  "Name a profile and choose whether to save current Install apps, Tweaks, toggles, and/or Config features. Optionally merge into an existing profile file.",
                                        "Category":  "Profiles",
                                        "panel":  "1",
                                        "Type":  "Button",
                                        "ButtonWidth":  "360",
                                        "function":  "Invoke-WPFProfileCreateWithOptions"
                                    },
    "WPFProfileSave":  {
                           "Content":  "Save Current Selection as Profile",
                           "Description":  "Saves selected apps, tweaks, toggles, and features as a named profile.",
                           "Category":  "Profiles",
                           "panel":  "1",
                           "Type":  "Button",
                           "ButtonWidth":  "360",
                           "function":  "Invoke-WPFProfileSave"
                       },
    "WPFProfileLoad":  {
                           "Content":  "Load Profile",
                           "Description":  "Loads a named profile into current selections.",
                           "Category":  "Profiles",
                           "panel":  "1",
                           "Type":  "Button",
                           "ButtonWidth":  "360",
                           "function":  "Invoke-WPFProfileLoad"
                       },
    "WPFProfileDelete":  {
                             "Content":  "Delete Profile",
                             "Description":  "Deletes a named saved profile.",
                             "Category":  "Profiles",
                             "panel":  "1",
                             "Type":  "Button",
                             "ButtonWidth":  "360",
                             "function":  "Invoke-WPFProfileDelete"
                         },
    "WPFProfileExportFile":  {
                                 "Content":  "Export profile to JSON file...",
                                 "Description":  "Save current app/tweak/toggle/feature selections to a versioned JSON file for backup or sharing.",
                                 "Category":  "Profiles",
                                 "panel":  "1",
                                 "Type":  "Button",
                                 "ButtonWidth":  "360",
                                 "function":  "Invoke-WPFProfileExportFile"
                             },
    "WPFProfileImportFile":  {
                                 "Content":  "Import profile from JSON file...",
                                 "Description":  "Load selections from a Clark profile JSON file (schema v1 or legacy flat array).",
                                 "Category":  "Profiles",
                                 "panel":  "1",
                                 "Type":  "Button",
                                 "ButtonWidth":  "360",
                                 "function":  "Invoke-WPFProfileImportFile"
                             },
    "WPFAutoReapplyEnable":  {
                                 "Content":  "Enable Auto Reapply at Startup",
                                 "Description":  "Creates scheduled tasks that rerun the selected profile on logon and startup.",
                                 "Category":  "Automation",
                                 "panel":  "1",
                                 "Type":  "Button",
                                 "ButtonWidth":  "360",
                                 "function":  "Invoke-WPFAutoReapplyEnable"
                             },
    "WPFAutoReapplyDisable":  {
                                  "Content":  "Disable Auto Reapply Tasks",
                                  "Description":  "Removes scheduled tasks created for automatic reapply.",
                                  "Category":  "Automation",
                                  "panel":  "1",
                                  "Type":  "Button",
                                  "ButtonWidth":  "360",
                                  "function":  "Invoke-WPFAutoReapplyDisable"
                              },
    "WPFRollbackLastTweak":  {
                                 "Content":  "Rollback Last Tweak Snapshot",
                                 "Description":  "Restores the most recent captured tweak state from rollback journal.",
                                 "Category":  "Recovery",
                                 "panel":  "1",
                                 "Type":  "Button",
                                 "ButtonWidth":  "360",
                                 "function":  "Invoke-WPFRollbackLastTweak"
                             },
    "WPFRegistryBackupManager":  {
                                     "Content":  "Pre-tweak registry backups...",
                                     "Description":  "Lists automatic HKLM/HKCU exports before tweaks; open folder or restore selected .reg files (reg import).",
                                     "Category":  "Recovery",
                                     "panel":  "1",
                                     "Type":  "Button",
                                     "ButtonWidth":  "360",
                                     "function":  "Invoke-WPFRegistryBackupManager"
                                 }
}
'@ | ConvertFrom-Json
$sync.configs.themes = @'
{
    "shared":  {
                   "AppEntryWidth":  "200",
                   "AppEntryFontSize":  "11",
                   "AppEntryMargin":  "1,0,1,0",
                   "AppEntryBorderThickness":  "0",
                   "CustomDialogFontSize":  "15",
                   "CustomDialogFontSizeHeader":  "17",
                   "CustomDialogLogoSize":  "25",
                   "CustomDialogWidth":  "440",
                   "CustomDialogHeight":  "240",
                   "ToolTipFontSize":  "14",
                   "FontSize":  "12",
                   "FontFamily":  "Arial",
                   "HeaderFontSize":  "16",
                   "HeaderFontFamily":  "Consolas, Monaco",
                   "CheckBoxBulletDecoratorSize":  "14",
                   "CheckBoxMargin":  "15,0,0,2",
                   "TabContentMargin":  "5",
                   "TabButtonFontSize":  "14",
                   "TabButtonWidth":  "110",
                   "TabButtonHeight":  "26",
                   "TabRowHeightInPixels":  "50",
                   "ToolTipWidth":  "300",
                   "IconFontSize":  "14",
                   "IconButtonSize":  "35",
                   "SettingsIconFontSize":  "18",
                   "GroupBorderBackgroundColor":  "#232629",
                   "ButtonFontSize":  "12",
                   "ButtonFontFamily":  "Arial",
                   "ButtonWidth":  "200",
                   "ButtonHeight":  "25",
                   "ConfigTabButtonFontSize":  "14",
                   "ConfigUpdateButtonFontSize":  "14",
                   "SearchBarWidth":  "200",
                   "SearchBarHeight":  "26",
                   "SearchBarTextBoxFontSize":  "12",
                   "SearchBarClearButtonFontSize":  "14",
                   "CheckboxMouseOverColor":  "#999999",
                   "ButtonBorderThickness":  "1",
                   "ButtonMargin":  "1",
                   "ButtonCornerRadius":  "2"
               },
    "Light":  {
                  "AppInstallUnselectedColor":  "#F7F7F7",
                  "AppInstallHighlightedColor":  "#CFCFCF",
                  "AppInstallSelectedColor":  "#C2C2C2",
                  "AppInstallOverlayBackgroundColor":  "#6A6D72",
                  "ComboBoxForegroundColor":  "#232629",
                  "ComboBoxBackgroundColor":  "#F7F7F7",
                  "LabelboxForegroundColor":  "#232629",
                  "MainForegroundColor":  "#232629",
                  "MainBackgroundColor":  "#F7F7F7",
                  "LabelBackgroundColor":  "#F7F7F7",
                  "LinkForegroundColor":  "#484848",
                  "LinkHoverForegroundColor":  "#232629",
                  "ScrollBarBackgroundColor":  "#4A4D52",
                  "ScrollBarHoverColor":  "#5A5D62",
                  "ScrollBarDraggingColor":  "#6A6D72",
                  "ProgressBarForegroundColor":  "#2e77ff",
                  "ProgressBarBackgroundColor":  "Transparent",
                  "ProgressBarTextColor":  "#232629",
                  "ButtonInstallBackgroundColor":  "#F7F7F7",
                  "ButtonTweaksBackgroundColor":  "#F7F7F7",
                  "ButtonConfigBackgroundColor":  "#F7F7F7",
                  "ButtonUpdatesBackgroundColor":  "#F7F7F7",
                  "ButtonWin11ISOBackgroundColor":  "#F7F7F7",
                  "ButtonInstallForegroundColor":  "#232629",
                  "ButtonTweaksForegroundColor":  "#232629",
                  "ButtonConfigForegroundColor":  "#232629",
                  "ButtonUpdatesForegroundColor":  "#232629",
                  "ButtonWin11ISOForegroundColor":  "#232629",
                  "ButtonBackgroundColor":  "#F5F5F5",
                  "ButtonBackgroundPressedColor":  "#1A1A1A",
                  "ButtonBackgroundMouseoverColor":  "#C2C2C2",
                  "ButtonBackgroundSelectedColor":  "#F0F0F0",
                  "ButtonForegroundColor":  "#232629",
                  "ToggleButtonOnColor":  "#2e77ff",
                  "ToggleButtonOffColor":  "#707070",
                  "ToolTipBackgroundColor":  "#F7F7F7",
                  "BorderColor":  "#232629",
                  "BorderOpacity":  "0.2"
              },
    "Dark":  {
                 "AppInstallUnselectedColor":  "#232629",
                 "AppInstallHighlightedColor":  "#3C3C3C",
                 "AppInstallSelectedColor":  "#4C4C4C",
                 "AppInstallOverlayBackgroundColor":  "#2E3135",
                 "ComboBoxForegroundColor":  "#F7F7F7",
                 "ComboBoxBackgroundColor":  "#1E3747",
                 "LabelboxForegroundColor":  "#5bdcff",
                 "MainForegroundColor":  "#F7F7F7",
                 "MainBackgroundColor":  "#232629",
                 "LabelBackgroundColor":  "#232629",
                 "LinkForegroundColor":  "#add8e6",
                 "LinkHoverForegroundColor":  "#F7F7F7",
                 "ScrollBarBackgroundColor":  "#2E3135",
                 "ScrollBarHoverColor":  "#3B4252",
                 "ScrollBarDraggingColor":  "#5E81AC",
                 "ProgressBarForegroundColor":  "#222222",
                 "ProgressBarBackgroundColor":  "Transparent",
                 "ProgressBarTextColor":  "#232629",
                 "ButtonInstallBackgroundColor":  "#222222",
                 "ButtonTweaksBackgroundColor":  "#333333",
                 "ButtonConfigBackgroundColor":  "#444444",
                 "ButtonUpdatesBackgroundColor":  "#555555",
                 "ButtonWin11ISOBackgroundColor":  "#666666",
                 "ButtonInstallForegroundColor":  "#F7F7F7",
                 "ButtonTweaksForegroundColor":  "#F7F7F7",
                 "ButtonConfigForegroundColor":  "#F7F7F7",
                 "ButtonUpdatesForegroundColor":  "#F7F7F7",
                 "ButtonWin11ISOForegroundColor":  "#F7F7F7",
                 "ButtonBackgroundColor":  "#1E3747",
                 "ButtonBackgroundPressedColor":  "#F7F7F7",
                 "ButtonBackgroundMouseoverColor":  "#3B4252",
                 "ButtonBackgroundSelectedColor":  "#5E81AC",
                 "ButtonForegroundColor":  "#F7F7F7",
                 "ToggleButtonOnColor":  "#2e77ff",
                 "ToggleButtonOffColor":  "#707070",
                 "ToolTipBackgroundColor":  "#2F373D",
                 "BorderColor":  "#2F373D",
                 "BorderOpacity":  "0.2"
             }
}
'@ | ConvertFrom-Json
$sync.configs.tools = @'
{
    "WPFHardwareSummary":  {
                               "Content":  "Hardware summary",
                               "Description":  "CPU, RAM, GPU, motherboard, and storage from WMI/CIM; export to PDF or PNG.",
                               "Category":  "System",
                               "panel":  "1",
                               "Type":  "Button",
                               "ButtonWidth":  "360",
                               "function":  "Invoke-WPFHardwareSummary"
                           },
    "WPFDnsManager":  {
                          "Content":  "DNS manager (per adapter)",
                          "Description":  "Presets (Cloudflare, Google, Quad9, ...), custom IPv4/IPv6, DHCP reset; apply to selected or all adapters.",
                          "Category":  "Network",
                          "panel":  "1",
                          "Type":  "Button",
                          "ButtonWidth":  "360",
                          "function":  "Invoke-WPFDnsManager"
                      },
    "WPFStartupManager":  {
                              "Content":  "Startup manager",
                              "Description":  "Registry Run / RunOnce and Startup folder entries; enable or disable; show path and publisher when available.",
                              "Category":  "System",
                              "panel":  "1",
                              "Type":  "Button",
                              "ButtonWidth":  "360",
                              "function":  "Invoke-WPFStartupManager"
                          },
    "WPFWindowsUpdatePolicy":  {
                                   "Content":  "Windows Update policy",
                                   "Description":  "Defer feature/quality updates, disable automatic updates (policy), or clear Clark policy keys.",
                                   "Category":  "Updates",
                                   "panel":  "1",
                                   "Type":  "Button",
                                   "ButtonWidth":  "360",
                                   "function":  "Invoke-WPFWindowsUpdatePolicy"
                               },
    "WPFDiskToolsWizard":  {
                               "Content":  "Disk health \u0026 tools",
                               "Description":  "SMART/health summary, chkdsk scan, diskpart list script; destructive actions require confirmation.",
                               "Category":  "Storage",
                               "panel":  "2",
                               "Type":  "Button",
                               "ButtonWidth":  "360",
                               "function":  "Invoke-WPFDiskToolsWizard"
                           },
    "WPFAppRemovalTool":  {
                              "Content":  "Installed programs \u0026 deep clean",
                              "Description":  "List programs from registry uninstall keys, uninstall selection, optional restore point, leftover scan (preview).",
                              "Category":  "Applications",
                              "panel":  "2",
                              "Type":  "Button",
                              "ButtonWidth":  "360",
                              "function":  "Invoke-WPFAppRemovalTool"
                          }
}
'@ | ConvertFrom-Json
$sync.configs.tweaks = @'
{
    "WPFTweaksActivity":  {
                              "Content":  "Disable Activity History",
                              "Description":  "Erases recent docs, clipboard, and run history.",
                              "category":  "Essential",
                              "panel":  "1",
                              "registry":  [
                                               {
                                                   "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
                                                   "Name":  "EnableActivityFeed",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "\u003cRemoveEntry\u003e"
                                               },
                                               {
                                                   "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
                                                   "Name":  "PublishUserActivities",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "\u003cRemoveEntry\u003e"
                                               },
                                               {
                                                   "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
                                                   "Name":  "UploadUserActivities",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "\u003cRemoveEntry\u003e"
                                               }
                                           ],
                              "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/activity"
                          },
    "WPFTweaksHiber":  {
                           "Content":  "Disable Hibernation",
                           "Description":  "Hibernation is really meant for laptops as it saves what\u0027s in memory before turning the PC off. It really should never be used.",
                           "category":  "Essential",
                           "panel":  "1",
                           "registry":  [
                                            {
                                                "Path":  "HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power",
                                                "Name":  "HibernateEnabled",
                                                "Value":  "0",
                                                "Type":  "DWord",
                                                "OriginalValue":  "1"
                                            },
                                            {
                                                "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FlyoutMenuSettings",
                                                "Name":  "ShowHibernateOption",
                                                "Value":  "0",
                                                "Type":  "DWord",
                                                "OriginalValue":  "1"
                                            }
                                        ],
                           "InvokeScript":  [
                                                "powercfg.exe /hibernate off"
                                            ],
                           "UndoScript":  [
                                              "powercfg.exe /hibernate on"
                                          ],
                           "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/hiber"
                       },
    "WPFTweaksWidget":  {
                            "Content":  "Remove Widgets",
                            "Description":  "Removes the annoying widgets in the bottom left of the Taskbar.",
                            "category":  "Essential",
                            "panel":  "1",
                            "InvokeScript":  [
                                                 "\r\n      # Sometimes if you dont stop the Widgets process the removal may fail\r\n\r\n      Get-Process *Widget* | Stop-Process\r\n      Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers | Remove-AppxPackage -AllUsers\r\n      Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers | Remove-AppxPackage -AllUsers\r\n\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      Write-Host \"Removed widgets\"\r\n      "
                                             ],
                            "UndoScript":  [
                                               "\r\n      Write-Host \"Restoring widgets AppxPackages\"\r\n\r\n      Add-AppxPackage -Register \"C:\\Program Files\\WindowsApps\\Microsoft.WidgetsPlatformRuntime*\\AppxManifest.xml\" -DisableDevelopmentMode\r\n      Add-AppxPackage -Register \"C:\\Program Files\\WindowsApps\\MicrosoftWindows.Client.WebExperience*\\AppxManifest.xml\" -DisableDevelopmentMode\r\n\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                           ],
                            "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/widget"
                        },
    "WPFTweaksRevertStartMenu":  {
                                     "Content":  "Revert Start Menu layout",
                                     "Description":  "Bring back the old Start Menu layout from before the gradual rollout of the new one in 25H2.",
                                     "category":  "Essential",
                                     "panel":  "1",
                                     "InvokeScript":  [
                                                          "\r\n      Invoke-WebRequest https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip -OutFile ViVeTool.zip\r\n\r\n      Expand-Archive ViVeTool.zip\r\n      Remove-Item ViVeTool.zip\r\n\r\n      Start-Process \u0027ViVeTool\\ViVeTool.exe\u0027 -ArgumentList \u0027/disable /id:47205210\u0027 -Wait -NoNewWindow\r\n\r\n      Remove-Item ViVeTool -Recurse\r\n\r\n      Write-Host \u0027Old start menu reverted. Please restart your computer to take effect.\u0027\r\n      "
                                                      ],
                                     "UndoScript":  [
                                                        "\r\n      Invoke-WebRequest https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip -OutFile ViVeTool.zip\r\n\r\n      Expand-Archive ViVeTool.zip\r\n      Remove-Item ViVeTool.zip\r\n\r\n      Start-Process \u0027ViVeTool\\ViVeTool.exe\u0027 -ArgumentList \u0027/enable /id:47205210\u0027 -Wait -NoNewWindow\r\n\r\n      Remove-Item ViVeTool -Recurse\r\n\r\n      Write-Host \u0027New start menu reverted. Please restart your computer to take effect.\u0027\r\n      "
                                                    ],
                                     "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/revertstartmenu"
                                 },
    "WPFTweaksDisableStoreSearch":  {
                                        "Content":  "Disable Microsoft Store search results",
                                        "Description":  "Will not display recommended Microsoft Store apps when searching for apps in the Start menu.",
                                        "category":  "Essential",
                                        "panel":  "1",
                                        "InvokeScript":  [
                                                             "icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /deny Everyone:F"
                                                         ],
                                        "UndoScript":  [
                                                           "icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /grant Everyone:F"
                                                       ],
                                        "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/disablestoresearch"
                                    },
    "WPFTweaksLocation":  {
                              "Content":  "Disable Location Tracking",
                              "Description":  "Disables Location Tracking.",
                              "category":  "Essential",
                              "panel":  "1",
                              "service":  [
                                              {
                                                  "Name":  "lfsvc",
                                                  "StartupType":  "Disable",
                                                  "OriginalType":  "Manual"
                                              }
                                          ],
                              "registry":  [
                                               {
                                                   "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location",
                                                   "Name":  "Value",
                                                   "Value":  "Deny",
                                                   "Type":  "String",
                                                   "OriginalValue":  "Allow"
                                               },
                                               {
                                                   "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Sensor\\Overrides\\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}",
                                                   "Name":  "SensorPermissionState",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "1"
                                               },
                                               {
                                                   "Path":  "HKLM:\\SYSTEM\\Maps",
                                                   "Name":  "AutoUpdateEnabled",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "1"
                                               }
                                           ],
                              "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/location"
                          },
    "WPFTweaksServices":  {
                              "Content":  "Set Services to Manual",
                              "Description":  "Turns a bunch of system services to manual that don\u0027t need to be running all the time. This is pretty harmless as if the service is needed, it will simply start on demand.",
                              "category":  "Essential",
                              "panel":  "1",
                              "service":  [
                                              {
                                                  "Name":  "ALG",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "AppMgmt",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "AppReadiness",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "AppVClient",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "Appinfo",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "AssignedAccessManagerSvc",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "AudioEndpointBuilder",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "AudioSrv",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "Audiosrv",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "AxInstSV",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "BDESVC",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "BITS",
                                                  "StartupType":  "AutomaticDelayedStart",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "BTAGService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "BthAvctpSvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "CDPSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "COMSysApp",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "CertPropSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "CryptSvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "CscService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "DPS",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "DevQueryBroker",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "DeviceAssociationService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "DeviceInstall",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Dhcp",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "DiagTrack",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "DialogBlockingService",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "DispBrokerDesktopSvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "DisplayEnhancementService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "EFS",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "EapHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "EventLog",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "EventSystem",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "FDResPub",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "FontCache",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "FrameServer",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "FrameServerMonitor",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "GraphicsPerfSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "HvHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "IKEEXT",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "InstallService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "InventorySvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "IpxlatCfgSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "KeyIso",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "KtmRm",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "LanmanServer",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "LanmanWorkstation",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "LicenseManager",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "LxpSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "MSDTC",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "MSiSCSI",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "MapsBroker",
                                                  "StartupType":  "AutomaticDelayedStart",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "McpManagementService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "MicrosoftEdgeElevationService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NaturalAuthentication",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NcaSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NcbService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NcdAutoSetup",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NetSetupSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NetTcpPortSharing",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "Netman",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "NlaSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "PcaSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "PeerDistSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "PerfHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "PhoneSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "PlugPlay",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "PolicyAgent",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Power",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "PrintNotify",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "ProfSvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "PushToInstall",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "QWAVE",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "RasAuto",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "RasMan",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "RemoteAccess",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "RemoteRegistry",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "RetailDemo",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "RmSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "RpcLocator",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SCPolicySvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SCardSvr",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SDRSVC",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SEMgrSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SENS",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "SNMPTRAP",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SNMPTrap",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SSDPSRV",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SamSs",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "ScDeviceEnum",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SensorDataService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SensorService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SensrSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SessionEnv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "SharedAccess",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "ShellHWDetection",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "SmsRouter",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Spooler",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "SstpSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "StiSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "StorSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "SysMain",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "TapiSrv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "TermService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Themes",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "TieringEngineService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "TokenBroker",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "TrkWks",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "TroubleshootingSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "TrustedInstaller",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "UevAgentService",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "UmRdpService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "UserManager",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "UsoSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "VSS",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "VaultSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "W32Time",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WEPHOSTSVC",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WFDSConMgrSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WMPNetworkSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WManSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WPDBusEnum",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WSAIFabricSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "WSearch",
                                                  "StartupType":  "AutomaticDelayedStart",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "WalletService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WarpJITSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WbioSrvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Wcmsvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "WdiServiceHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WdiSystemHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WebClient",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Wecsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WerSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WiaRpc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WinRM",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "Winmgmt",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "WpcMonSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "WpnService",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "XblAuthManager",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "XblGameSave",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "XboxGipSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "XboxNetApiSvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "autotimesvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "bthserv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "camsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "cloudidsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "dcsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "defragsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "diagsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "dmwappushservice",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "dot3svc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "edgeupdate",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "edgeupdatem",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "fdPHost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "fhsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "hidserv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "icssvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "iphlpsvc",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "lfsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "lltdsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "lmhosts",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "netprofm",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "nsi",
                                                  "StartupType":  "Automatic",
                                                  "OriginalType":  "Automatic"
                                              },
                                              {
                                                  "Name":  "perceptionsimulation",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "pla",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "seclogon",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "shpamsvc",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "smphost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "ssh-agent",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "svsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "swprv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "tzautoupdate",
                                                  "StartupType":  "Disabled",
                                                  "OriginalType":  "Disabled"
                                              },
                                              {
                                                  "Name":  "upnphost",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vds",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicguestinterface",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicheartbeat",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmickvpexchange",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicrdv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicshutdown",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmictimesync",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicvmsession",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "vmicvss",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wbengine",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wcncsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "webthreatdefsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wercplsupport",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wisvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wlidsvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wlpasvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wmiApSrv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "workfolderssvc",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              },
                                              {
                                                  "Name":  "wuauserv",
                                                  "StartupType":  "Manual",
                                                  "OriginalType":  "Manual"
                                              }
                                          ],
                              "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/services"
                          },
    "WPFTweaksBraveDebloat":  {
                                  "Content":  "Brave Debloat",
                                  "Description":  "Disables various annoyances like Brave Rewards, Leo AI, Crypto Wallet and VPN.",
                                  "category":  "z__Advanced",
                                  "panel":  "1",
                                  "registry":  [
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave",
                                                       "Name":  "BraveRewardsDisabled",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                   },
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave",
                                                       "Name":  "BraveWalletDisabled",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                   },
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave",
                                                       "Name":  "BraveVPNDisabled",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                   },
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave",
                                                       "Name":  "BraveAIChatEnabled",
                                                       "Value":  "0",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                   },
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave",
                                                       "Name":  "BraveStatsPingEnabled",
                                                       "Value":  "0",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                   }
                                               ],
                                  "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/bravedebloat"
                              },
    "WPFTweaksEdgeDebloat":  {
                                 "Content":  "Edge Debloat",
                                 "Description":  "Disables various telemetry options, popups, and other annoyances in Edge.",
                                 "category":  "z__Advanced",
                                 "panel":  "1",
                                 "registry":  [
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\EdgeUpdate",
                                                      "Name":  "CreateDesktopShortcutDefault",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "PersonalizationReportingEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\\ExtensionInstallBlocklist",
                                                      "Name":  "1",
                                                      "Value":  "ofefcgjbeghpigppfmkologfjadafddi",
                                                      "Type":  "String",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "ShowRecommendationsEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "HideFirstRunExperience",
                                                      "Value":  "1",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "UserFeedbackAllowed",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "ConfigureDoNotTrack",
                                                      "Value":  "1",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "AlternateErrorPagesEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "EdgeCollectionsEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "EdgeShoppingAssistantEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "MicrosoftEdgeInsiderPromotionEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "ShowMicrosoftRewards",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "WebWidgetAllowed",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "DiagnosticData",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "EdgeAssetDeliveryServiceEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "WalletDonationEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  },
                                                  {
                                                      "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge",
                                                      "Name":  "DefaultBrowserSettingsCampaignEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                  }
                                              ],
                                 "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/edgedebloat"
                             },
    "WPFTweaksConsumerFeatures":  {
                                      "Content":  "Disable ConsumerFeatures",
                                      "Description":  "Windows will not automatically install any games, third-party apps, or application links from the Windows Store for the signed-in user. Some default Apps will be inaccessible (eg. Phone Link).",
                                      "category":  "Essential",
                                      "panel":  "1",
                                      "registry":  [
                                                       {
                                                           "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
                                                           "Name":  "DisableWindowsConsumerFeatures",
                                                           "Value":  "1",
                                                           "Type":  "DWord",
                                                           "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                       }
                                                   ],
                                      "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/consumerfeatures"
                                  },
    "WPFTweaksTelemetry":  {
                               "Content":  "Disable Telemetry",
                               "Description":  "Disables Microsoft Telemetry.",
                               "category":  "Essential",
                               "panel":  "1",
                               "registry":  [
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo",
                                                    "Name":  "Enabled",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Privacy",
                                                    "Name":  "TailoredExperiencesWithDiagnosticDataEnabled",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Speech_OneCore\\Settings\\OnlineSpeechPrivacy",
                                                    "Name":  "HasAccepted",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Input\\TIPC",
                                                    "Name":  "Enabled",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\InputPersonalization",
                                                    "Name":  "RestrictImplicitInkCollection",
                                                    "Value":  "1",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\InputPersonalization",
                                                    "Name":  "RestrictImplicitTextCollection",
                                                    "Value":  "1",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\InputPersonalization\\TrainedDataStore",
                                                    "Name":  "HarvestContacts",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Personalization\\Settings",
                                                    "Name":  "AcceptedPrivacyPolicy",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection",
                                                    "Name":  "AllowTelemetry",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                    "Name":  "Start_TrackProgs",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
                                                    "Name":  "PublishUserActivities",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                },
                                                {
                                                    "Path":  "HKCU:\\Software\\Microsoft\\Siuf\\Rules",
                                                    "Name":  "NumberOfSIUFInPeriod",
                                                    "Value":  "0",
                                                    "Type":  "DWord",
                                                    "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                }
                                            ],
                               "InvokeScript":  [
                                                    "\r\n      # Disable Defender Auto Sample Submission\r\n      Set-MpPreference -SubmitSamplesConsent 2\r\n\r\n      # Disable (Connected User Experiences and Telemetry) Service\r\n      Set-Service -Name diagtrack -StartupType Disabled\r\n\r\n      # Disable (Windows Error Reporting Manager) Service\r\n      Set-Service -Name wermgr -StartupType Disabled\r\n\r\n      $Memory = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB\r\n      Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name SvcHostSplitThresholdInKB -Value $Memory\r\n\r\n      Remove-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Siuf\\Rules\" -Name PeriodInNanoSeconds\r\n      "
                                                ],
                               "UndoScript":  [
                                                  "\r\n      # Enable Defender Auto Sample Submission\r\n      Set-MpPreference -SubmitSamplesConsent 1\r\n\r\n      # Enable (Connected User Experiences and Telemetry) Service\r\n      Set-Service -Name diagtrack -StartupType Automatic\r\n\r\n      # Enable (Windows Error Reporting Manager) Service\r\n      Set-Service -Name wermgr -StartupType Automatic\r\n      "
                                              ],
                               "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/telemetry"
                           },
    "WPFTweaksRemoveEdge":  {
                                "Content":  "Remove Microsoft Edge",
                                "Description":  "Unblocks Microsoft Edge uninstaller restrictions then uses that uninstaller to remove Microsoft Edge.",
                                "category":  "z__Advanced",
                                "panel":  "1",
                                "InvokeScript":  [
                                                     "Invoke-ClarkRemoveEdge"
                                                 ],
                                "UndoScript":  [
                                                   "\r\n      Write-Host \u0027Installing Microsoft Edge...\u0027\r\n      winget install Microsoft.Edge --source winget\r\n      "
                                               ],
                                "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/removeedge"
                            },
    "WPFTweaksUTC":  {
                         "Content":  "Set Time to UTC (Dual Boot)",
                         "Description":  "Essential for computers that are dual booting. Fixes the time sync with Linux systems.",
                         "category":  "z__Advanced",
                         "panel":  "1",
                         "registry":  [
                                          {
                                              "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation",
                                              "Name":  "RealTimeIsUniversal",
                                              "Value":  "1",
                                              "Type":  "QWord",
                                              "OriginalValue":  "0"
                                          }
                                      ],
                         "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/utc"
                     },
    "WPFTweaksRemoveOneDrive":  {
                                    "Content":  "Remove OneDrive",
                                    "Description":  "Denies permission to remove OneDrive user files, then uses its own uninstaller to remove it and restores the original permission afterward.",
                                    "category":  "z__Advanced",
                                    "panel":  "1",
                                    "InvokeScript":  [
                                                         "\r\n      # Deny permission to remove OneDrive folder\r\n      icacls $Env:OneDrive /deny \"Administrators:(D,DC)\"\r\n\r\n      Write-Host \"Uninstalling OneDrive...\"\r\n      Start-Process \u0027C:\\Windows\\System32\\OneDriveSetup.exe\u0027 -ArgumentList \u0027/uninstall\u0027 -Wait\r\n\r\n      # Some of OneDrive files use explorer, and OneDrive uses FileCoAuth\r\n      Write-Host \"Removing leftover OneDrive Files...\"\r\n      Stop-Process -Name FileCoAuth,Explorer\r\n      Remove-Item \"$Env:LocalAppData\\Microsoft\\OneDrive\" -Recurse -Force\r\n      Remove-Item \"C:\\ProgramData\\Microsoft OneDrive\" -Recurse -Force\r\n\r\n      # Grant back permission to access OneDrive folder\r\n      icacls $Env:OneDrive /grant \"Administrators:(D,DC)\"\r\n\r\n      # Disable OneSyncSvc\r\n      Set-Service -Name OneSyncSvc -StartupType Disabled\r\n      "
                                                     ],
                                    "UndoScript":  [
                                                       "\r\n      Write-Host \"Installing OneDrive\"\r\n      winget install Microsoft.Onedrive --source winget\r\n\r\n      # Enabled OneSyncSvc\r\n      Set-Service -Name OneSyncSvc -StartupType Automatic\r\n      "
                                                   ],
                                    "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/removeonedrive"
                                },
    "WPFTweaksRemoveHome":  {
                                "Content":  "Remove Home from Explorer",
                                "Description":  "Removes the Home from Explorer and sets This PC as default.",
                                "category":  "z__Advanced",
                                "panel":  "1",
                                "InvokeScript":  [
                                                     "\r\n      Remove-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Desktop\\NameSpace\\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}\"\r\n      Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" -Name LaunchTo -Value 1\r\n      "
                                                 ],
                                "UndoScript":  [
                                                   "\r\n      New-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Desktop\\NameSpace\\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}\"\r\n      Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" -Name LaunchTo -Value 0\r\n      "
                                               ],
                                "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/removehome"
                            },
    "WPFTweaksRemoveGallery":  {
                                   "Content":  "Remove Gallery from Explorer",
                                   "Description":  "Removes the Gallery from Explorer and sets This PC as default.",
                                   "category":  "z__Advanced",
                                   "panel":  "1",
                                   "InvokeScript":  [
                                                        "\r\n      Remove-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Desktop\\NameSpace\\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}\"\r\n      "
                                                    ],
                                   "UndoScript":  [
                                                      "\r\n      New-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Desktop\\NameSpace\\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}\"\r\n      "
                                                  ],
                                   "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/removegallery"
                               },
    "WPFTweaksDisplay":  {
                             "Content":  "Set Display for Performance",
                             "Description":  "Sets the system preferences to performance. You can do this manually with sysdm.cpl as well.",
                             "category":  "z__Advanced",
                             "panel":  "1",
                             "registry":  [
                                              {
                                                  "Path":  "HKCU:\\Control Panel\\Desktop",
                                                  "Name":  "DragFullWindows",
                                                  "Value":  "0",
                                                  "Type":  "String",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Control Panel\\Desktop",
                                                  "Name":  "MenuShowDelay",
                                                  "Value":  "200",
                                                  "Type":  "String",
                                                  "OriginalValue":  "400"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Control Panel\\Desktop\\WindowMetrics",
                                                  "Name":  "MinAnimate",
                                                  "Value":  "0",
                                                  "Type":  "String",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Control Panel\\Keyboard",
                                                  "Name":  "KeyboardDelay",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "ListviewAlphaSelect",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "ListviewShadow",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "TaskbarAnimations",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects",
                                                  "Name":  "VisualFXSetting",
                                                  "Value":  "3",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\DWM",
                                                  "Name":  "EnableAeroPeek",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "TaskbarMn",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "ShowTaskViewButton",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
                                                  "Name":  "SearchboxTaskbarMode",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              }
                                          ],
                             "InvokeScript":  [
                                                  "Set-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))"
                                              ],
                             "UndoScript":  [
                                                "Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\""
                                            ],
                             "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/display"
                         },
    "WPFTweaksXboxRemoval":  {
                                 "Content":  "Remove Xbox \u0026 Gaming Components",
                                 "Description":  "Removes Xbox services, the Xbox app, Game Bar, and related authentication components.",
                                 "category":  "z__Advanced",
                                 "panel":  "1",
                                 "registry":  [
                                                  {
                                                      "Path":  "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\GameDVR",
                                                      "Name":  "AppCaptureEnabled",
                                                      "Value":  "0",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "1"
                                                  }
                                              ],
                                 "appx":  [
                                              "Microsoft.XboxIdentityProvider",
                                              "Microsoft.XboxSpeechToTextOverlay",
                                              "Microsoft.GamingApp",
                                              "Microsoft.Xbox.TCUI",
                                              "Microsoft.XboxGamingOverlay"
                                          ],
                                 "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/xboxremoval"
                             },
    "WPFTweaksDeBloat":  {
                             "Content":  "Remove Unwanted Pre-Installed Apps",
                             "Description":  "This will remove a bunch of Windows pre-installed applications which most people dont want on there system.",
                             "category":  "z__Advanced",
                             "panel":  "1",
                             "appx":  [
                                          "Microsoft.WindowsFeedbackHub",
                                          "Microsoft.BingNews",
                                          "Microsoft.BingSearch",
                                          "Microsoft.BingWeather",
                                          "Clipchamp.Clipchamp",
                                          "Microsoft.Todos",
                                          "Microsoft.PowerAutomateDesktop",
                                          "Microsoft.MicrosoftSolitaireCollection",
                                          "Microsoft.WindowsSoundRecorder",
                                          "Microsoft.MicrosoftStickyNotes",
                                          "Microsoft.Windows.DevHome",
                                          "Microsoft.Paint",
                                          "Microsoft.OutlookForWindows",
                                          "Microsoft.WindowsAlarms",
                                          "Microsoft.StartExperiencesApp",
                                          "Microsoft.GetHelp",
                                          "Microsoft.ZuneMusic",
                                          "MicrosoftCorporationII.QuickAssist",
                                          "MSTeams"
                                      ],
                             "InvokeScript":  [
                                                  "\r\n      $TeamsPath = \"$Env:LocalAppData\\Microsoft\\Teams\\Update.exe\"\r\n\r\n      if (Test-Path $TeamsPath) {\r\n        Write-Host \"Uninstalling Teams\"\r\n        Start-Process $TeamsPath -ArgumentList -uninstall -wait\r\n\r\n        Write-Host \"Deleting Teams directory\"\r\n        Remove-Item $TeamsPath -Recurse -Force\r\n      }\r\n      "
                                              ],
                             "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/debloat"
                         },
    "WPFTweaksRestorePoint":  {
                                  "Content":  "Create Restore Point",
                                  "Description":  "Creates a restore point at runtime in case a revert is needed from A-SYS_clark modifications.",
                                  "category":  "Essential",
                                  "panel":  "1",
                                  "Checked":  "False",
                                  "registry":  [
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore",
                                                       "Name":  "SystemRestorePointCreationFrequency",
                                                       "Value":  "0",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "1440"
                                                   }
                                               ],
                                  "InvokeScript":  [
                                                       "\r\n      if (-not (Get-ComputerRestorePoint)) {\r\n          Enable-ComputerRestore -Drive $Env:SystemDrive\r\n      }\r\n\r\n      Checkpoint-Computer -Description \"System Restore Point created by A-SYS_clark (Advance Systems 4042)\" -RestorePointType MODIFY_SETTINGS\r\n      Write-Host \"System Restore Point Created Successfully\" -ForegroundColor Green\r\n      "
                                                   ],
                                  "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/restorepoint"
                              },
    "WPFTweaksEndTaskOnTaskbar":  {
                                      "Content":  "Enable End Task With Right Click",
                                      "Description":  "Enables option to end task when right clicking a program in the taskbar.",
                                      "category":  "Essential",
                                      "panel":  "1",
                                      "registry":  [
                                                       {
                                                           "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings",
                                                           "Name":  "TaskbarEndTask",
                                                           "Value":  "1",
                                                           "Type":  "DWord",
                                                           "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                       }
                                                   ],
                                      "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/endtaskontaskbar"
                                  },
    "WPFTweaksPowershell7Tele":  {
                                     "Content":  "Disable PowerShell 7 Telemetry",
                                     "Description":  "Creates an Environment Variable called \u0027POWERSHELL_TELEMETRY_OPTOUT\u0027 with a value of \u00271\u0027 which will tell PowerShell 7 to not send Telemetry Data.",
                                     "category":  "Essential",
                                     "panel":  "1",
                                     "InvokeScript":  [
                                                          "[Environment]::SetEnvironmentVariable(\u0027POWERSHELL_TELEMETRY_OPTOUT\u0027, \u00271\u0027, \u0027Machine\u0027)"
                                                      ],
                                     "UndoScript":  [
                                                        "[Environment]::SetEnvironmentVariable(\u0027POWERSHELL_TELEMETRY_OPTOUT\u0027, \u0027\u0027, \u0027Machine\u0027)"
                                                    ],
                                     "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/powershell7tele"
                                 },
    "WPFTweaksStorage":  {
                             "Content":  "Disable Storage Sense",
                             "Description":  "Storage Sense deletes temp files automatically.",
                             "category":  "z__Advanced",
                             "panel":  "1",
                             "registry":  [
                                              {
                                                  "Path":  "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy",
                                                  "Name":  "01",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1"
                                              }
                                          ],
                             "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/storage"
                         },
    "WPFTweaksRemoveCopilot":  {
                                   "Content":  "Remove Microsoft Copilot",
                                   "Description":  "Removes Copilot AppXPackages and related ai packages",
                                   "category":  "z__Advanced",
                                   "panel":  "1",
                                   "InvokeScript":  [
                                                        "\r\n      Get-AppxPackage -AllUsers *Copilot* | Remove-AppxPackage -AllUsers\r\n      Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers\r\n\r\n      $Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName\r\n      $Sid = (Get-LocalUser $Env:UserName).Sid.Value\r\n\r\n      New-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Appx\\AppxAllUserStore\\EndOfLife\\$Sid\\$Appx\" -Force\r\n      Remove-AppxPackage $Appx\r\n\r\n      Write-Host \"Copilot Removed\"\r\n      "
                                                    ],
                                   "UndoScript":  [
                                                      "\r\n      Write-Host \"Installing Copilot...\"\r\n      winget install --name Copilot --source msstore --accept-package-agreements --accept-source-agreements --silent\r\n      "
                                                  ],
                                   "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/removecopilot"
                               },
    "WPFTweaksWPBT":  {
                          "Content":  "Disable Windows Platform Binary Table (WPBT)",
                          "Description":  "If enabled, WPBT allows your computer vendor to execute programs at boot time, such as anti-theft software, software drivers, as well as force install software without user consent. Poses potential security risk.",
                          "category":  "Essential",
                          "panel":  "1",
                          "registry":  [
                                           {
                                               "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager",
                                               "Name":  "DisableWpbtExecution",
                                               "Value":  "1",
                                               "Type":  "DWord",
                                               "OriginalValue":  "\u003cRemoveEntry\u003e"
                                           }
                                       ],
                          "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/wpbt"
                      },
    "WPFTweaksRazerBlock":  {
                                "Content":  "Block Razer Software Installs",
                                "Description":  "Blocks ALL Razer Software installations. The hardware works fine without any software.",
                                "category":  "z__Advanced",
                                "panel":  "1",
                                "registry":  [
                                                 {
                                                     "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching",
                                                     "Name":  "SearchOrderConfig",
                                                     "Value":  "0",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "1"
                                                 },
                                                 {
                                                     "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Device Installer",
                                                     "Name":  "DisableCoInstallers",
                                                     "Value":  "1",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "0"
                                                 }
                                             ],
                                "InvokeScript":  [
                                                     "\r\n      $RazerPath = \"C:\\Windows\\Installer\\Razer\"\r\n\r\n      if (Test-Path $RazerPath) {\r\n        Remove-Item $RazerPath\\* -Recurse -Force\r\n      } else {\r\n        New-Item -Path $RazerPath -ItemType Directory\r\n      }\r\n\r\n      icacls $RazerPath /deny \"Everyone:(W)\"\r\n      "
                                                 ],
                                "UndoScript":  [
                                                   "\r\n      icacls \"C:\\Windows\\Installer\\Razer\" /remove:d Everyone\r\n      "
                                               ],
                                "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/razerblock"
                            },
    "WPFTweaksDisableNotifications":  {
                                          "Content":  "Disable Notification Tray/Calendar",
                                          "Description":  "Disables all Notifications INCLUDING Calendar.",
                                          "category":  "z__Advanced",
                                          "panel":  "1",
                                          "registry":  [
                                                           {
                                                               "Path":  "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer",
                                                               "Name":  "DisableNotificationCenter",
                                                               "Value":  "1",
                                                               "Type":  "DWord",
                                                               "OriginalValue":  "\u003cRemoveEntry\u003e"
                                                           },
                                                           {
                                                               "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications",
                                                               "Name":  "ToastEnabled",
                                                               "Value":  "0",
                                                               "Type":  "DWord",
                                                               "OriginalValue":  "1"
                                                           }
                                                       ],
                                          "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/disablenotifications"
                                      },
    "WPFTweaksBlockAdobeNet":  {
                                   "Content":  "Adobe Network Block",
                                   "Description":  "Reduces user interruptions by selectively blocking connections to Adobe\u0027s activation and telemetry servers. Credit: Ruddernation-Designs",
                                   "category":  "z__Advanced",
                                   "panel":  "1",
                                   "InvokeScript":  [
                                                        "\r\n      $hostsUrl = \"https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts\"\r\n      $hosts = \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\"\r\n\r\n      Move-Item $hosts \"$hosts.bak\"\r\n      Invoke-WebRequest $hostsUrl -OutFile $hosts\r\n      ipconfig /flushdns\r\n\r\n      Write-Host \"Added Adobe url block list from host file\"\r\n      "
                                                    ],
                                   "UndoScript":  [
                                                      "\r\n      $hosts = \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\"\r\n\r\n      Remove-Item $hosts\r\n      Move-Item \"$hosts.bak\" $hosts\r\n      ipconfig /flushdns\r\n\r\n      Write-Host \"Removed Adobe url block list from host file\"\r\n      "
                                                  ],
                                   "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/blockadobenet"
                               },
    "WPFTweaksRightClickMenu":  {
                                    "Content":  "Set Classic Right-Click Menu",
                                    "Description":  "Restores the classic context menu when right-clicking in File Explorer, replacing the simplified Windows 11 version.",
                                    "category":  "z__Advanced",
                                    "panel":  "1",
                                    "InvokeScript":  [
                                                         "\r\n      New-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Name \"InprocServer32\" -force -value \"\"\r\n      Write-Host Restarting explorer.exe ...\r\n      Stop-Process -Name \"explorer\" -Force\r\n      "
                                                     ],
                                    "UndoScript":  [
                                                       "\r\n      Remove-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Recurse -Confirm:$false -Force\r\n      # Restarting Explorer in the Undo Script might not be necessary, as the Registry change without restarting Explorer does work, but just to make sure.\r\n      Write-Host Restarting explorer.exe ...\r\n      Stop-Process -Name \"explorer\" -Force\r\n      "
                                                   ],
                                    "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/rightclickmenu"
                                },
    "WPFTweaksDiskCleanup":  {
                                 "Content":  "Run Disk Cleanup",
                                 "Description":  "Runs Disk Cleanup on Drive C: and removes old Windows Updates.",
                                 "category":  "Essential",
                                 "panel":  "1",
                                 "InvokeScript":  [
                                                      "\r\n      cleanmgr.exe /d C: /VERYLOWDISK\r\n      Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase\r\n      "
                                                  ],
                                 "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/diskcleanup"
                             },
    "WPFTweaksDeleteTempFiles":  {
                                     "Content":  "Delete Temporary Files",
                                     "Description":  "Erases TEMP Folders.",
                                     "category":  "Essential",
                                     "panel":  "1",
                                     "InvokeScript":  [
                                                          "\r\n      Remove-Item -Path \"$Env:Temp\\*\" -Recurse -Force\r\n      Remove-Item -Path \"$Env:SystemRoot\\Temp\\*\" -Recurse -Force\r\n      "
                                                      ],
                                     "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/deletetempfiles"
                                 },
    "WPFTweaksIPv46":  {
                           "Content":  "Prefer IPv4 over IPv6",
                           "Description":  "Setting the IPv4 preference can have latency and security benefits on private networks where IPv6 is not configured.",
                           "category":  "z__Advanced",
                           "panel":  "1",
                           "registry":  [
                                            {
                                                "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
                                                "Name":  "DisabledComponents",
                                                "Value":  "32",
                                                "Type":  "DWord",
                                                "OriginalValue":  "0"
                                            }
                                        ],
                           "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/ipv46"
                       },
    "WPFTweaksTeredo":  {
                            "Content":  "Disable Teredo",
                            "Description":  "Teredo network tunneling is an IPv6 feature that can cause additional latency, but may cause problems with some games.",
                            "category":  "z__Advanced",
                            "panel":  "1",
                            "registry":  [
                                             {
                                                 "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
                                                 "Name":  "DisabledComponents",
                                                 "Value":  "1",
                                                 "Type":  "DWord",
                                                 "OriginalValue":  "0"
                                             }
                                         ],
                            "InvokeScript":  [
                                                 "netsh interface teredo set state disabled"
                                             ],
                            "UndoScript":  [
                                               "netsh interface teredo set state default"
                                           ],
                            "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/teredo"
                        },
    "WPFTweaksDisableIPv6":  {
                                 "Content":  "Disable IPv6",
                                 "Description":  "Disables IPv6.",
                                 "category":  "z__Advanced",
                                 "panel":  "1",
                                 "registry":  [
                                                  {
                                                      "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
                                                      "Name":  "DisabledComponents",
                                                      "Value":  "255",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "0"
                                                  }
                                              ],
                                 "InvokeScript":  [
                                                      "Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"
                                                  ],
                                 "UndoScript":  [
                                                    "Enable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"
                                                ],
                                 "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/disableipv6"
                             },
    "WPFTweaksDisableBGapps":  {
                                   "Content":  "Disable Background Apps",
                                   "Description":  "Disables all Microsoft Store apps from running in the background, which has to be done individually since Windows 11.",
                                   "category":  "z__Advanced",
                                   "panel":  "1",
                                   "registry":  [
                                                    {
                                                        "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications",
                                                        "Name":  "GlobalUserDisabled",
                                                        "Value":  "1",
                                                        "Type":  "DWord",
                                                        "OriginalValue":  "0"
                                                    }
                                                ],
                                   "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/disablebgapps"
                               },
    "WPFTweaksDisableFSO":  {
                                "Content":  "Disable Fullscreen Optimizations",
                                "Description":  "Disables FSO in all applications. NOTE: This will disable Color Management in Exclusive Fullscreen.",
                                "category":  "z__Advanced",
                                "panel":  "1",
                                "registry":  [
                                                 {
                                                     "Path":  "HKCU:\\System\\GameConfigStore",
                                                     "Name":  "GameDVR_DXGIHonorFSEWindowsCompatible",
                                                     "Value":  "1",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "0"
                                                 }
                                             ],
                                "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/disablefso"
                            },
    "WPFToggleDarkMode":  {
                              "Content":  "Dark Theme for Windows",
                              "Description":  "Enable/Disable Dark Mode.",
                              "category":  "Preferences",
                              "panel":  "2",
                              "Type":  "Toggle",
                              "registry":  [
                                               {
                                                   "Path":  "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                                   "Name":  "AppsUseLightTheme",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "1",
                                                   "DefaultState":  "false"
                                               },
                                               {
                                                   "Path":  "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                                   "Name":  "SystemUsesLightTheme",
                                                   "Value":  "0",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "1",
                                                   "DefaultState":  "false"
                                               }
                                           ],
                              "InvokeScript":  [
                                                   "\r\n      Invoke-ClarkExplorerUpdate\r\n      if ($sync.ThemeButton.Content -eq [char]0xF08C) {\r\n        Invoke-ClarkThemeChange -theme \"Auto\"\r\n      }\r\n      "
                                               ],
                              "UndoScript":  [
                                                 "\r\n      Invoke-ClarkExplorerUpdate\r\n      if ($sync.ThemeButton.Content -eq [char]0xF08C) {\r\n        Invoke-ClarkThemeChange -theme \"Auto\"\r\n      }\r\n      "
                                             ],
                              "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/darkmode"
                          },
    "WPFToggleBingSearch":  {
                                "Content":  "Bing Search in Start Menu",
                                "Description":  "If enabled, Bing web search results will be included in your Start Menu search.",
                                "category":  "Preferences",
                                "panel":  "2",
                                "Type":  "Toggle",
                                "registry":  [
                                                 {
                                                     "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
                                                     "Name":  "BingSearchEnabled",
                                                     "Value":  "1",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "0",
                                                     "DefaultState":  "true"
                                                 }
                                             ],
                                "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/bingsearch"
                            },
    "WPFToggleStandbyFix":  {
                                "Content":  "Modern Standby fix",
                                "Description":  "Disable network connection during S0 Sleep. If network connectivity is turned on during S0 Sleep it could cause overheating on modern laptops.",
                                "category":  "Preferences",
                                "panel":  "2",
                                "Type":  "Toggle",
                                "registry":  [
                                                 {
                                                     "Path":  "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Power\\PowerSettings\\f15576e8-98b7-4186-b944-eafa664402d9",
                                                     "Name":  "ACSettingIndex",
                                                     "Value":  "0",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "\u003cRemoveEntry\u003e",
                                                     "DefaultState":  "true"
                                                 }
                                             ],
                                "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/standbyfix"
                            },
    "WPFToggleNumLock":  {
                             "Content":  "Num Lock on Startup",
                             "Description":  "Toggle the Num Lock key state when your computer starts.",
                             "category":  "Preferences",
                             "panel":  "2",
                             "Type":  "Toggle",
                             "registry":  [
                                              {
                                                  "Path":  "HKU:\\.Default\\Control Panel\\Keyboard",
                                                  "Name":  "InitialKeyboardIndicators",
                                                  "Value":  "2",
                                                  "Type":  "String",
                                                  "OriginalValue":  "0",
                                                  "DefaultState":  "false"
                                              },
                                              {
                                                  "Path":  "HKCU:\\Control Panel\\Keyboard",
                                                  "Name":  "InitialKeyboardIndicators",
                                                  "Value":  "2",
                                                  "Type":  "String",
                                                  "OriginalValue":  "0",
                                                  "DefaultState":  "false"
                                              }
                                          ],
                             "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/numlock"
                         },
    "WPFToggleVerboseLogon":  {
                                  "Content":  "Verbose Messages During Logon",
                                  "Description":  "Show detailed messages during the login process for troubleshooting and diagnostics.",
                                  "category":  "Preferences",
                                  "panel":  "2",
                                  "Type":  "Toggle",
                                  "registry":  [
                                                   {
                                                       "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
                                                       "Name":  "VerboseStatus",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "0",
                                                       "DefaultState":  "false"
                                                   }
                                               ],
                                  "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/verboselogon"
                              },
    "WPFToggleStartMenuRecommendations":  {
                                              "Content":  "Recommendations in Start Menu",
                                              "Description":  "If disabled, then you will not see recommendations in the Start Menu. WARNING: This will also disable Windows Spotlight on your Lock Screen as a side effect.",
                                              "category":  "Preferences",
                                              "panel":  "2",
                                              "Type":  "Toggle",
                                              "registry":  [
                                                               {
                                                                   "Path":  "HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Start",
                                                                   "Name":  "HideRecommendedSection",
                                                                   "Value":  "0",
                                                                   "Type":  "DWord",
                                                                   "OriginalValue":  "1",
                                                                   "DefaultState":  "true"
                                                               },
                                                               {
                                                                   "Path":  "HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Education",
                                                                   "Name":  "IsEducationEnvironment",
                                                                   "Value":  "0",
                                                                   "Type":  "DWord",
                                                                   "OriginalValue":  "1",
                                                                   "DefaultState":  "true"
                                                               },
                                                               {
                                                                   "Path":  "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer",
                                                                   "Name":  "HideRecommendedSection",
                                                                   "Value":  "0",
                                                                   "Type":  "DWord",
                                                                   "OriginalValue":  "1",
                                                                   "DefaultState":  "true"
                                                               }
                                                           ],
                                              "InvokeScript":  [
                                                                   "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                               ],
                                              "UndoScript":  [
                                                                 "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                             ],
                                              "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/startmenurecommendations"
                                          },
    "WPFToggleHideSettingsHome":  {
                                      "Content":  "Remove Settings Home Page",
                                      "Description":  "Removes the Home Page in the Windows Settings app.",
                                      "category":  "Preferences",
                                      "panel":  "2",
                                      "Type":  "Toggle",
                                      "registry":  [
                                                       {
                                                           "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer",
                                                           "Name":  "SettingsPageVisibility",
                                                           "Value":  "hide:home",
                                                           "Type":  "String",
                                                           "OriginalValue":  "show:home",
                                                           "DefaultState":  "false"
                                                       }
                                                   ],
                                      "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/hidesettingshome"
                                  },
    "WPFToggleMouseAcceleration":  {
                                       "Content":  "Mouse Acceleration",
                                       "Description":  "If enabled, the Cursor movement is affected by the speed of your physical mouse movements.",
                                       "category":  "Preferences",
                                       "panel":  "2",
                                       "Type":  "Toggle",
                                       "registry":  [
                                                        {
                                                            "Path":  "HKCU:\\Control Panel\\Mouse",
                                                            "Name":  "MouseSpeed",
                                                            "Value":  "1",
                                                            "Type":  "DWord",
                                                            "OriginalValue":  "0",
                                                            "DefaultState":  "true"
                                                        },
                                                        {
                                                            "Path":  "HKCU:\\Control Panel\\Mouse",
                                                            "Name":  "MouseThreshold1",
                                                            "Value":  "6",
                                                            "Type":  "DWord",
                                                            "OriginalValue":  "0",
                                                            "DefaultState":  "true"
                                                        },
                                                        {
                                                            "Path":  "HKCU:\\Control Panel\\Mouse",
                                                            "Name":  "MouseThreshold2",
                                                            "Value":  "10",
                                                            "Type":  "DWord",
                                                            "OriginalValue":  "0",
                                                            "DefaultState":  "true"
                                                        }
                                                    ],
                                       "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/mouseacceleration"
                                   },
    "WPFToggleStickyKeys":  {
                                "Content":  "Sticky Keys",
                                "Description":  "If enabled, Sticky Keys is activated. Sticky keys is an accessibility feature of some graphical user interfaces which assists users who have physical disabilities or help users reduce repetitive strain injury.",
                                "category":  "Preferences",
                                "panel":  "2",
                                "Type":  "Toggle",
                                "registry":  [
                                                 {
                                                     "Path":  "HKCU:\\Control Panel\\Accessibility\\StickyKeys",
                                                     "Name":  "Flags",
                                                     "Value":  "506",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "58",
                                                     "DefaultState":  "true"
                                                 }
                                             ],
                                "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/stickykeys"
                            },
    "WPFToggleNewOutlook":  {
                                "Content":  "New Outlook",
                                "Description":  "If disabled, it removes the new Outlook toggle, disables the new Outlook migration, and ensures the classic Outlook application is used.",
                                "category":  "Preferences",
                                "panel":  "2",
                                "Type":  "Toggle",
                                "registry":  [
                                                 {
                                                     "Path":  "HKCU:\\SOFTWARE\\Microsoft\\Office\\16.0\\Outlook\\Preferences",
                                                     "Name":  "UseNewOutlook",
                                                     "Value":  "1",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "0",
                                                     "DefaultState":  "true"
                                                 },
                                                 {
                                                     "Path":  "HKCU:\\Software\\Microsoft\\Office\\16.0\\Outlook\\Options\\General",
                                                     "Name":  "HideNewOutlookToggle",
                                                     "Value":  "0",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "1",
                                                     "DefaultState":  "true"
                                                 },
                                                 {
                                                     "Path":  "HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Options\\General",
                                                     "Name":  "DoNewOutlookAutoMigration",
                                                     "Value":  "0",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "0",
                                                     "DefaultState":  "false"
                                                 },
                                                 {
                                                     "Path":  "HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Preferences",
                                                     "Name":  "NewOutlookMigrationUserSetting",
                                                     "Value":  "0",
                                                     "Type":  "DWord",
                                                     "OriginalValue":  "\u003cRemoveEntry\u003e",
                                                     "DefaultState":  "true"
                                                 }
                                             ],
                                "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/newoutlook"
                            },
    "WPFToggleMultiplaneOverlay":  {
                                       "Content":  "Disable Multiplane Overlay",
                                       "Description":  "Disable the Multiplane Overlay which can sometimes cause issues with Graphics Cards.",
                                       "category":  "Preferences",
                                       "panel":  "2",
                                       "Type":  "Toggle",
                                       "registry":  [
                                                        {
                                                            "Path":  "HKLM:\\SOFTWARE\\Microsoft\\Windows\\Dwm",
                                                            "Name":  "OverlayTestMode",
                                                            "Value":  "5",
                                                            "Type":  "DWord",
                                                            "OriginalValue":  "\u003cRemoveEntry\u003e",
                                                            "DefaultState":  "false"
                                                        }
                                                    ],
                                       "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/multiplaneoverlay"
                                   },
    "WPFToggleHiddenFiles":  {
                                 "Content":  "Show Hidden Files",
                                 "Description":  "If enabled, Hidden Files will be shown.",
                                 "category":  "Preferences",
                                 "panel":  "2",
                                 "Type":  "Toggle",
                                 "registry":  [
                                                  {
                                                      "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                      "Name":  "Hidden",
                                                      "Value":  "1",
                                                      "Type":  "DWord",
                                                      "OriginalValue":  "0",
                                                      "DefaultState":  "false"
                                                  }
                                              ],
                                 "InvokeScript":  [
                                                      "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                  ],
                                 "UndoScript":  [
                                                    "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                ],
                                 "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/hiddenfiles"
                             },
    "WPFToggleShowExt":  {
                             "Content":  "Show File Extensions",
                             "Description":  "If enabled, File extensions (e.g., .txt, .jpg) are visible.",
                             "category":  "Preferences",
                             "panel":  "2",
                             "Type":  "Toggle",
                             "registry":  [
                                              {
                                                  "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                  "Name":  "HideFileExt",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "1",
                                                  "DefaultState":  "false"
                                              }
                                          ],
                             "InvokeScript":  [
                                                  "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                              ],
                             "UndoScript":  [
                                                "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                            ],
                             "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/showext"
                         },
    "WPFToggleTaskbarSearch":  {
                                   "Content":  "Search Button in Taskbar",
                                   "Description":  "If enabled, Search Button will be on the Taskbar.",
                                   "category":  "Preferences",
                                   "panel":  "2",
                                   "Type":  "Toggle",
                                   "registry":  [
                                                    {
                                                        "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
                                                        "Name":  "SearchboxTaskbarMode",
                                                        "Value":  "1",
                                                        "Type":  "DWord",
                                                        "OriginalValue":  "0",
                                                        "DefaultState":  "true"
                                                    }
                                                ],
                                   "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/taskbarsearch"
                               },
    "WPFToggleTaskView":  {
                              "Content":  "Task View Button in Taskbar",
                              "Description":  "If enabled, Task View Button in Taskbar will be shown.",
                              "category":  "Preferences",
                              "panel":  "2",
                              "Type":  "Toggle",
                              "registry":  [
                                               {
                                                   "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                   "Name":  "ShowTaskViewButton",
                                                   "Value":  "1",
                                                   "Type":  "DWord",
                                                   "OriginalValue":  "0",
                                                   "DefaultState":  "true"
                                               }
                                           ],
                              "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/taskview"
                          },
    "WPFToggleTaskbarAlignment":  {
                                      "Content":  "Center Taskbar Items",
                                      "Description":  "[Windows 11] If enabled, the Taskbar Items will be shown on the Center, otherwise the Taskbar Items will be shown on the Left.",
                                      "category":  "Preferences",
                                      "panel":  "2",
                                      "Type":  "Toggle",
                                      "registry":  [
                                                       {
                                                           "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
                                                           "Name":  "TaskbarAl",
                                                           "Value":  "1",
                                                           "Type":  "DWord",
                                                           "OriginalValue":  "0",
                                                           "DefaultState":  "true"
                                                       }
                                                   ],
                                      "InvokeScript":  [
                                                           "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                       ],
                                      "UndoScript":  [
                                                         "\r\n      Invoke-ClarkExplorerUpdate -action \"restart\"\r\n      "
                                                     ],
                                      "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/taskbaralignment"
                                  },
    "WPFToggleDetailedBSoD":  {
                                  "Content":  "Detailed BSoD",
                                  "Description":  "If enabled, you will see a detailed Blue Screen of Death (BSOD) with more information.",
                                  "category":  "Preferences",
                                  "panel":  "2",
                                  "Type":  "Toggle",
                                  "registry":  [
                                                   {
                                                       "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl",
                                                       "Name":  "DisplayParameters",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "0",
                                                       "DefaultState":  "false"
                                                   },
                                                   {
                                                       "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl",
                                                       "Name":  "DisableEmoticon",
                                                       "Value":  "1",
                                                       "Type":  "DWord",
                                                       "OriginalValue":  "0",
                                                       "DefaultState":  "false"
                                                   }
                                               ],
                                  "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/detailedbsod"
                              },
    "WPFToggleS3Sleep":  {
                             "Content":  "S3 Sleep",
                             "Description":  "Toggles between Modern Standby and S3 Sleep.",
                             "category":  "Preferences",
                             "panel":  "2",
                             "Type":  "Toggle",
                             "registry":  [
                                              {
                                                  "Path":  "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power",
                                                  "Name":  "PlatformAoAcOverride",
                                                  "Value":  "0",
                                                  "Type":  "DWord",
                                                  "OriginalValue":  "\u003cRemoveEntry\u003e",
                                                  "DefaultState":  "false"
                                              }
                                          ],
                             "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/s3sleep"
                         },
    "WPFOOSUbutton":  {
                          "Content":  "Run OO Shutup 10",
                          "category":  "z__Advanced",
                          "panel":  "1",
                          "Type":  "Button",
                          "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/oosubutton"
                      },
    "WPFchangedns":  {
                         "Content":  "DNS",
                         "category":  "z__Advanced",
                         "panel":  "1",
                         "Type":  "Combobox",
                         "ComboItems":  "Default DHCP Google Cloudflare Cloudflare_Malware Cloudflare_Malware_Adult Open_DNS Quad9 AdGuard_Ads_Trackers AdGuard_Ads_Trackers_Malware_Adult",
                         "link":  "https://clark.christitus.com/dev/tweaks/z--advanced-tweaks---caution/changedns"
                     },
    "WPFAddUltPerf":  {
                          "Content":  "Add and Activate Ultimate Performance Profile",
                          "category":  "Essential",
                          "panel":  "2",
                          "Type":  "Button",
                          "ButtonWidth":  "300",
                          "link":  "https://clark.christitus.com/dev/tweaks/performance-plans/addultperf"
                      },
    "WPFRemoveUltPerf":  {
                             "Content":  "Remove Ultimate Performance Profile",
                             "category":  "Essential",
                             "panel":  "2",
                             "Type":  "Button",
                             "ButtonWidth":  "300",
                             "link":  "https://clark.christitus.com/dev/tweaks/performance-plans/removeultperf"
                         },
    "WPFTweaksDisableExplorerAutoDiscovery":  {
                                                  "Content":  "Disable Explorer Automatic Folder Discovery",
                                                  "Description":  "Windows Explorer automatically tries to guess the type of the folder based on its contents, slowing down the browsing experience. WARNING! Will disable File Explorer grouping.",
                                                  "category":  "Essential",
                                                  "panel":  "1",
                                                  "InvokeScript":  [
                                                                       "\r\n      # Previously detected folders\r\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\r\n\r\n      # Folder types lookup table\r\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\r\n\r\n      # Flush Explorer view database\r\n      Remove-Item -Path $bags -Recurse -Force\r\n      Write-Host \"Removed $bags\"\r\n\r\n      Remove-Item -Path $bagMRU -Recurse -Force\r\n      Write-Host \"Removed $bagMRU\"\r\n\r\n      # Every folder\r\n      $allFolders = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\\AllFolders\\Shell\"\r\n\r\n      if (!(Test-Path $allFolders)) {\r\n        New-Item -Path $allFolders -Force\r\n        Write-Host \"Created $allFolders\"\r\n      }\r\n\r\n      # Generic view\r\n      New-ItemProperty -Path $allFolders -Name \"FolderType\" -Value \"NotSpecified\" -PropertyType String -Force\r\n      Write-Host \"Set FolderType to NotSpecified\"\r\n\r\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\r\n      "
                                                                   ],
                                                  "UndoScript":  [
                                                                     "\r\n      # Previously detected folders\r\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\r\n\r\n      # Folder types lookup table\r\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\r\n\r\n      # Flush Explorer view database\r\n      Remove-Item -Path $bags -Recurse -Force\r\n      Write-Host \"Removed $bags\"\r\n\r\n      Remove-Item -Path $bagMRU -Recurse -Force\r\n      Write-Host \"Removed $bagMRU\"\r\n\r\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\r\n      "
                                                                 ],
                                                  "link":  "https://clark.christitus.com/dev/tweaks/essential-tweaks/disableexplorerautodiscovery"
                                              },
    "WPFToggleDisableCrossDeviceResume":  {
                                              "Content":  "Cross-Device Resume",
                                              "Description":  "This tweak controls the Resume function in Windows 11 24H2 and later, which allows you to resume an activity from a mobile device and vice-versa.",
                                              "category":  "Preferences",
                                              "panel":  "2",
                                              "Type":  "Toggle",
                                              "registry":  [
                                                               {
                                                                   "Path":  "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\CrossDeviceResume\\Configuration",
                                                                   "Name":  "IsResumeAllowed",
                                                                   "Value":  "1",
                                                                   "Type":  "DWord",
                                                                   "OriginalValue":  "0",
                                                                   "DefaultState":  "true"
                                                               }
                                                           ],
                                              "link":  "https://clark.christitus.com/dev/tweaks/customize-preferences/disablecrossdeviceresume"
                                          }
}
'@ | ConvertFrom-Json
$inputXML = @'
<Window x:Class="Clarkity.MainWindow"

        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"

        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"

        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"

        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"

        xmlns:local="clr-namespace:Clarkity"

        mc:Ignorable="d"

        WindowStartupLocation="CenterScreen"

        UseLayoutRounding="True"

        WindowStyle="SingleBorderWindow"

        Width="1200"

        Height="820"

        MinWidth="800"

        MinHeight="600"

        Title="clark">

    <Window.Resources>

    <Style TargetType="ToolTip">

        <Setter Property="Background" Value="{DynamicResource ToolTipBackgroundColor}"/>

        <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

        <Setter Property="BorderBrush" Value="{DynamicResource BorderColor}"/>

        <Setter Property="MaxWidth" Value="{DynamicResource ToolTipWidth}"/>

        <Setter Property="BorderThickness" Value="1"/>

        <Setter Property="Padding" Value="2"/>

        <Setter Property="FontSize" Value="{DynamicResource ToolTipFontSize}"/>

        <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

        <!-- This ContentTemplate ensures that the content of the ToolTip wraps text properly for better readability -->

        <Setter Property="ContentTemplate">

            <Setter.Value>

                <DataTemplate>

                    <ContentPresenter Content="{TemplateBinding Content}">

                        <ContentPresenter.Resources>

                            <Style TargetType="TextBlock">

                                <Setter Property="TextWrapping" Value="Wrap"/>

                            </Style>

                        </ContentPresenter.Resources>

                    </ContentPresenter>

                </DataTemplate>

            </Setter.Value>

        </Setter>

    </Style>



    <Style TargetType="{x:Type MenuItem}">

        <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

        <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

        <Setter Property="FontSize" Value="{DynamicResource FontSize}"/>

        <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

        <Setter Property="Padding" Value="5,2,5,2"/>

        <Setter Property="BorderThickness" Value="0"/>

    </Style>



    <!--Scrollbar Thumbs-->

    <Style x:Key="ScrollThumbs" TargetType="{x:Type Thumb}">

        <Setter Property="Template">

            <Setter.Value>

                <ControlTemplate TargetType="{x:Type Thumb}">

                    <Grid x:Name="Grid">

                        <Rectangle HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto" Fill="Transparent" />

                        <Border x:Name="Rectangle1" CornerRadius="5" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto"  Background="{TemplateBinding Background}" />

                    </Grid>

                    <ControlTemplate.Triggers>

                        <Trigger Property="Tag" Value="Horizontal">

                            <Setter TargetName="Rectangle1" Property="Width" Value="Auto" />

                            <Setter TargetName="Rectangle1" Property="Height" Value="7" />

                        </Trigger>

                    </ControlTemplate.Triggers>

                </ControlTemplate>

            </Setter.Value>

        </Setter>

    </Style>



    <Style TargetType="TextBlock" x:Key="HoverTextBlockStyle">

        <Setter Property="Foreground" Value="{DynamicResource LinkForegroundColor}" />

        <Setter Property="TextDecorations" Value="Underline" />

        <Style.Triggers>

            <Trigger Property="IsMouseOver" Value="True">

                <Setter Property="Foreground" Value="{DynamicResource LinkHoverForegroundColor}" />

                <Setter Property="TextDecorations" Value="Underline" />

                <Setter Property="Cursor" Value="Hand" />

            </Trigger>

        </Style.Triggers>

    </Style>

    <Style x:Key="AppEntryBorderStyle" TargetType="Border">

        <Setter Property="BorderBrush" Value="Gray"/>

        <Setter Property="BorderThickness" Value="{DynamicResource AppEntryBorderThickness}"/>

        <Setter Property="CornerRadius" Value="2"/>

        <Setter Property="Padding" Value="{DynamicResource AppEntryMargin}"/>

        <Setter Property="Width" Value="{DynamicResource AppEntryWidth}"/>

        <Setter Property="VerticalAlignment" Value="Top"/>

        <Setter Property="Margin" Value="{DynamicResource AppEntryMargin}"/>

        <Setter Property="Cursor" Value="Hand"/>

        <Setter Property="Background" Value="{DynamicResource AppInstallUnselectedColor}"/>

    </Style>

    <Style x:Key="AppEntryCheckboxStyle" TargetType="CheckBox">

        <Setter Property="Background" Value="Transparent"/>

        <Setter Property="HorizontalAlignment" Value="Left"/>

        <Setter Property="VerticalAlignment" Value="Center"/>

        <Setter Property="Margin" Value="{DynamicResource AppEntryMargin}"/>

        <Setter Property="Template">

            <Setter.Value>

                <ControlTemplate TargetType="CheckBox">

                    <StackPanel Orientation="Horizontal">

                        <Grid Width="16" Height="16" Margin="0,0,8,0">

                            <Border x:Name="CheckBoxBorder"

                                    BorderBrush="{DynamicResource MainForegroundColor}"

                                    Background="{DynamicResource ButtonBackgroundColor}"

                                    BorderThickness="1"

                                    Width="12"

                                    Height="12"

                                    CornerRadius="2"/>

                        </Grid>

                        <ContentPresenter Content="{TemplateBinding Content}"

                                        VerticalAlignment="Center"

                                        HorizontalAlignment="Left"/>

                    </StackPanel>

                    <ControlTemplate.Triggers>

                        <Trigger Property="IsChecked" Value="True">

                            <Setter TargetName="CheckBoxBorder" Property="Background" Value="{DynamicResource ToggleButtonOnColor}"/>

                            <Setter TargetName="CheckBoxBorder" Property="BorderBrush" Value="{DynamicResource ToggleButtonOnColor}"/>

                        </Trigger>

                    </ControlTemplate.Triggers>

                </ControlTemplate>

            </Setter.Value>

        </Setter>

    </Style>

    <Style x:Key="AppEntryNameStyle" TargetType="TextBlock">

        <Setter Property="FontSize" Value="{DynamicResource AppEntryFontSize}"/>

        <Setter Property="FontWeight" Value="Bold"/>

        <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

        <Setter Property="VerticalAlignment" Value="Center"/>

        <Setter Property="Margin" Value="{DynamicResource AppEntryMargin}"/>

        <Setter Property="Background" Value="Transparent"/>

    </Style>

    <Style x:Key="AppEntryButtonStyle" TargetType="Button">

        <Setter Property="Width" Value="{DynamicResource IconButtonSize}"/>

        <Setter Property="Height" Value="{DynamicResource IconButtonSize}"/>

        <Setter Property="Margin" Value="{DynamicResource AppEntryMargin}"/>

        <Setter Property="Foreground" Value="{DynamicResource ButtonForegroundColor}"/>

        <Setter Property="Background" Value="{DynamicResource ButtonBackgroundColor}"/>

        <Setter Property="HorizontalAlignment" Value="Center"/>

        <Setter Property="VerticalAlignment" Value="Center"/>

        <Setter Property="ContentTemplate">

            <Setter.Value>

                <DataTemplate>

                    <TextBlock  Text="{Binding}"

                                FontFamily="Segoe MDL2 Assets"

                                FontSize="{DynamicResource IconFontSize}"

                                Background="Transparent"/>

                </DataTemplate>

            </Setter.Value>

        </Setter>

        <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="Button">

                        <Grid>

                            <Border x:Name="BackgroundBorder"

                                    Background="{TemplateBinding Background}"

                                    BorderBrush="{TemplateBinding BorderBrush}"

                                    BorderThickness="{DynamicResource ButtonBorderThickness}"

                                    CornerRadius="{DynamicResource ButtonCornerRadius}">

                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>

                            </Border>

                        </Grid>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsPressed" Value="True">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundPressedColor}"/>

                            </Trigger>

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter Property="Cursor" Value="Hand"/>

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundMouseoverColor}"/>

                            </Trigger>

                            <Trigger Property="IsEnabled" Value="False">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>

                                <Setter Property="Foreground" Value="DimGray"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>





    </Style>

    <Style TargetType="Button" x:Key="HoverButtonStyle">

        <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}" />

        <Setter Property="FontWeight" Value="Normal" />

        <Setter Property="FontSize" Value="{DynamicResource ButtonFontSize}" />

        <Setter Property="TextElement.FontFamily" Value="{DynamicResource ButtonFontFamily}"/>

        <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}" />

        <Setter Property="Template">

            <Setter.Value>

                <ControlTemplate TargetType="Button">

                    <Border Background="{TemplateBinding Background}">

                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>

                    </Border>

                    <ControlTemplate.Triggers>

                        <Trigger Property="IsMouseOver" Value="True">

                            <Setter Property="FontWeight" Value="Bold" />

                            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}" />

                            <Setter Property="Cursor" Value="Hand" />

                        </Trigger>

                    </ControlTemplate.Triggers>

                </ControlTemplate>

            </Setter.Value>

        </Setter>

    </Style>



    <!--ScrollBars-->

    <Style x:Key="{x:Type ScrollBar}" TargetType="{x:Type ScrollBar}">

        <Setter Property="Stylus.IsFlicksEnabled" Value="false" />

        <Setter Property="Foreground" Value="{DynamicResource ScrollBarBackgroundColor}" />

        <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}" />

        <Setter Property="Width" Value="6" />

        <Setter Property="Template">

            <Setter.Value>

                <ControlTemplate TargetType="{x:Type ScrollBar}">

                    <Grid x:Name="GridRoot" Width="7" Background="{TemplateBinding Background}" >

                        <Grid.RowDefinitions>

                            <RowDefinition Height="0.00001*" />

                        </Grid.RowDefinitions>



                        <Track x:Name="PART_Track" Grid.Row="0" IsDirectionReversed="true" Focusable="false">

                            <Track.Thumb>

                                <Thumb x:Name="Thumb" Background="{TemplateBinding Foreground}" Style="{DynamicResource ScrollThumbs}" />

                            </Track.Thumb>

                            <Track.IncreaseRepeatButton>

                                <RepeatButton x:Name="PageUp" Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="false" />

                            </Track.IncreaseRepeatButton>

                            <Track.DecreaseRepeatButton>

                                <RepeatButton x:Name="PageDown" Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="false" />

                            </Track.DecreaseRepeatButton>

                        </Track>

                    </Grid>



                    <ControlTemplate.Triggers>

                        <Trigger SourceName="Thumb" Property="IsMouseOver" Value="true">

                            <Setter Value="{DynamicResource ScrollBarHoverColor}" TargetName="Thumb" Property="Background" />

                        </Trigger>

                        <Trigger SourceName="Thumb" Property="IsDragging" Value="true">

                            <Setter Value="{DynamicResource ScrollBarDraggingColor}" TargetName="Thumb" Property="Background" />

                        </Trigger>



                        <Trigger Property="IsEnabled" Value="false">

                            <Setter TargetName="Thumb" Property="Visibility" Value="Collapsed" />

                        </Trigger>

                        <Trigger Property="Orientation" Value="Horizontal">

                            <Setter TargetName="GridRoot" Property="LayoutTransform">

                                <Setter.Value>

                                    <RotateTransform Angle="-90" />

                                </Setter.Value>

                            </Setter>

                            <Setter TargetName="PART_Track" Property="LayoutTransform">

                                <Setter.Value>

                                    <RotateTransform Angle="-90" />

                                </Setter.Value>

                            </Setter>

                            <Setter Property="Width" Value="Auto" />

                            <Setter Property="Height" Value="8" />

                            <Setter TargetName="Thumb" Property="Tag" Value="Horizontal" />

                            <Setter TargetName="PageDown" Property="Command" Value="ScrollBar.PageLeftCommand" />

                            <Setter TargetName="PageUp" Property="Command" Value="ScrollBar.PageRightCommand" />

                        </Trigger>

                    </ControlTemplate.Triggers>

                </ControlTemplate>

            </Setter.Value>

        </Setter>

        </Style>

        <Style TargetType="ComboBox">

            <Setter Property="Foreground" Value="{DynamicResource ComboBoxForegroundColor}" />

            <Setter Property="Background" Value="{DynamicResource ComboBoxBackgroundColor}" />

            <Setter Property="MinWidth"   Value="{DynamicResource ButtonWidth}" />

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="ComboBox">

                        <Grid>

                            <Border x:Name="OuterBorder"

                                    BorderBrush="{DynamicResource BorderColor}"

                                    BorderThickness="1"

                                    CornerRadius="{DynamicResource ButtonCornerRadius}"

                                    Background="{TemplateBinding Background}">

                                <ToggleButton x:Name="ToggleButton"

                                              Background="Transparent"

                                              BorderThickness="0"

                                              IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"

                                              ClickMode="Press">

                                    <Grid>

                                        <Grid.ColumnDefinitions>

                                            <ColumnDefinition Width="*"/>

                                            <ColumnDefinition Width="Auto"/>

                                        </Grid.ColumnDefinitions>

                                        <TextBlock Grid.Column="0"

                                                   Text="{TemplateBinding SelectionBoxItem}"

                                                   Foreground="{TemplateBinding Foreground}"

                                                   Background="Transparent"

                                                   HorizontalAlignment="Left" VerticalAlignment="Center"

                                                   Margin="6,3,2,3"/>

                                        <Path Grid.Column="1"

                                              Data="M 0,0 L 8,0 L 4,5 Z"

                                              Fill="{TemplateBinding Foreground}"

                                              Width="8" Height="5"

                                              VerticalAlignment="Center"

                                              HorizontalAlignment="Center"

                                              Stretch="Uniform"

                                              Margin="4,0,6,0"/>

                                    </Grid>

                                </ToggleButton>

                            </Border>

                            <Popup x:Name="Popup"

                                   IsOpen="{TemplateBinding IsDropDownOpen}"

                                   Placement="Bottom"

                                   Focusable="False"

                                   AllowsTransparency="True"

                                   PopupAnimation="Slide">

                                <Border x:Name="DropDownBorder"

                                        Background="{TemplateBinding Background}"

                                        BorderBrush="{DynamicResource BorderColor}"

                                        BorderThickness="1"

                                        CornerRadius="4">

                                    <ScrollViewer>

                                        <ItemsPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="4,2"/>

                                    </ScrollViewer>

                                </Border>

                            </Popup>

                        </Grid>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>

        <Style TargetType="Label">

            <Setter Property="Foreground" Value="{DynamicResource LabelboxForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource LabelBackgroundColor}"/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

        </Style>



        <!-- TextBlock template -->

        <Style TargetType="TextBlock">

            <Setter Property="FontSize" Value="{DynamicResource FontSize}"/>

            <Setter Property="Foreground" Value="{DynamicResource LabelboxForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource LabelBackgroundColor}"/>

        </Style>

        <!-- Toggle button template x:Key="TabToggleButton" -->

        <Style TargetType="{x:Type ToggleButton}">

            <Setter Property="Margin" Value="{DynamicResource ButtonMargin}"/>

            <Setter Property="Content" Value=""/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="ToggleButton">

                        <Grid>

                            <Border x:Name="ButtonGlow"

                                        Background="{TemplateBinding Background}"

                                        BorderBrush="{DynamicResource ButtonForegroundColor}"

                                        BorderThickness="{DynamicResource ButtonBorderThickness}"

                                        CornerRadius="{DynamicResource ButtonCornerRadius}">

                                <Grid>

                                    <Border x:Name="BackgroundBorder"

                                        Background="{TemplateBinding Background}"

                                        BorderBrush="{DynamicResource ButtonBackgroundColor}"

                                        BorderThickness="{DynamicResource ButtonBorderThickness}"

                                        CornerRadius="{DynamicResource ButtonCornerRadius}">

                                        <ContentPresenter

                                            HorizontalAlignment="Center"

                                            VerticalAlignment="Center"

                                            Margin="10,2,10,2"/>

                                    </Border>

                                </Grid>

                            </Border>

                        </Grid>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundMouseoverColor}"/>

                                <Setter Property="Effect">

                                    <Setter.Value>

                                        <DropShadowEffect Opacity="1" ShadowDepth="5" Color="{DynamicResource CButtonBackgroundMouseoverColor}" Direction="-100" BlurRadius="15"/>

                                    </Setter.Value>

                                </Setter>

                                <Setter Property="Panel.ZIndex" Value="2000"/>

                            </Trigger>

                            <Trigger Property="IsChecked" Value="True">

                                <Setter Property="BorderBrush" Value="Pink"/>

                                <Setter Property="BorderThickness" Value="2"/>

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>

                                <Setter Property="Effect">

                                    <Setter.Value>

                                        <DropShadowEffect Opacity="1" ShadowDepth="2" Color="{DynamicResource CButtonBackgroundMouseoverColor}" Direction="-111" BlurRadius="10"/>

                                    </Setter.Value>

                                </Setter>

                            </Trigger>

                            <Trigger Property="IsChecked" Value="False">

                                <Setter Property="BorderBrush" Value="Transparent"/>

                                <Setter Property="BorderThickness" Value="{DynamicResource ButtonBorderThickness}"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>

        <!-- Button Template -->

        <Style TargetType="Button">

            <Setter Property="Margin" Value="{DynamicResource ButtonMargin}"/>

            <Setter Property="Foreground" Value="{DynamicResource ButtonForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource ButtonBackgroundColor}"/>

            <Setter Property="Height" Value="{DynamicResource ButtonHeight}"/>

            <Setter Property="Width" Value="{DynamicResource ButtonWidth}"/>

            <Setter Property="FontSize" Value="{DynamicResource ButtonFontSize}"/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="Button">

                        <Grid>

                            <Border x:Name="BackgroundBorder"

                                    Background="{TemplateBinding Background}"

                                    BorderBrush="{TemplateBinding BorderBrush}"

                                    BorderThickness="{DynamicResource ButtonBorderThickness}"

                                    CornerRadius="{DynamicResource ButtonCornerRadius}">

                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10,2,10,2"/>

                            </Border>

                        </Grid>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsPressed" Value="True">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundPressedColor}"/>

                            </Trigger>

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundMouseoverColor}"/>

                            </Trigger>

                            <Trigger Property="IsEnabled" Value="False">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>

                                <Setter Property="Foreground" Value="DimGray"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>



        <Style x:Key="ToggleButtonStyle" TargetType="ToggleButton">

            <Setter Property="Margin" Value="{DynamicResource ButtonMargin}"/>

            <Setter Property="Foreground" Value="{DynamicResource ButtonForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource ButtonBackgroundColor}"/>

            <Setter Property="Height" Value="{DynamicResource ButtonHeight}"/>

            <Setter Property="Width" Value="{DynamicResource ButtonWidth}"/>

            <Setter Property="FontSize" Value="{DynamicResource ButtonFontSize}"/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="ToggleButton">

                        <Grid>

                            <Border x:Name="BackgroundBorder"

                                    Background="{TemplateBinding Background}"

                                    BorderBrush="{TemplateBinding BorderBrush}"

                                    BorderThickness="{DynamicResource ButtonBorderThickness}"

                                    CornerRadius="{DynamicResource ButtonCornerRadius}">

                                <Grid>

                                    <!-- Toggle Dot Background -->

                                    <Ellipse Width="8" Height="16"

                                            Fill="{DynamicResource ToggleButtonOnColor}"

                                            HorizontalAlignment="Right"

                                            VerticalAlignment="Top"

                                            Margin="0,3,5,0" />



                                    <!-- Toggle Dot with hover grow effect -->

                                    <Ellipse x:Name="ToggleDot"

                                            Width="8" Height="8"

                                            Fill="{DynamicResource ButtonForegroundColor}"

                                            HorizontalAlignment="Right"

                                            VerticalAlignment="Top"

                                            Margin="0,3,5,0"

                                            RenderTransformOrigin="0.5,0.5">

                                        <Ellipse.RenderTransform>

                                            <ScaleTransform ScaleX="1" ScaleY="1"/>

                                        </Ellipse.RenderTransform>

                                    </Ellipse>



                                    <!-- Content Presenter -->

                                    <ContentPresenter HorizontalAlignment="Center"

                                                    VerticalAlignment="Center"

                                                    Margin="10,2,10,2"/>

                                </Grid>

                            </Border>

                        </Grid>



                        <!-- Triggers for ToggleButton states -->

                        <ControlTemplate.Triggers>

                            <!-- Hover effect -->

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundMouseoverColor}"/>

                                <Trigger.EnterActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <!-- Animation to grow the dot when hovered -->

                                            <DoubleAnimation Storyboard.TargetName="ToggleDot"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)"

                                                            To="1.2" Duration="0:0:0.1"/>

                                            <DoubleAnimation Storyboard.TargetName="ToggleDot"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)"

                                                            To="1.2" Duration="0:0:0.1"/>

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.EnterActions>

                                <Trigger.ExitActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <!-- Animation to shrink the dot back to original size when not hovered -->

                                            <DoubleAnimation Storyboard.TargetName="ToggleDot"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)"

                                                            To="1.0" Duration="0:0:0.1"/>

                                            <DoubleAnimation Storyboard.TargetName="ToggleDot"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)"

                                                            To="1.0" Duration="0:0:0.1"/>

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.ExitActions>

                            </Trigger>



                            <!-- IsChecked state -->

                            <Trigger Property="IsChecked" Value="True">

                                <Setter TargetName="ToggleDot" Property="VerticalAlignment" Value="Bottom"/>

                                <Setter TargetName="ToggleDot" Property="Margin" Value="0,0,5,3"/>

                            </Trigger>



                            <!-- IsEnabled state -->

                            <Trigger Property="IsEnabled" Value="False">

                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{DynamicResource ButtonBackgroundSelectedColor}"/>

                                <Setter Property="Foreground" Value="DimGray"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>



        <Style x:Key="SearchBarClearButtonStyle" TargetType="Button">

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="FontSize" Value="{DynamicResource SearchBarClearButtonFontSize}"/>

            <Setter Property="Content" Value="X"/>

            <Setter Property="Height" Value="{DynamicResource SearchBarClearButtonFontSize}"/>

            <Setter Property="Width" Value="{DynamicResource SearchBarClearButtonFontSize}"/>

            <Setter Property="Background" Value="Transparent"/>

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="Padding" Value="0"/>

            <Setter Property="BorderBrush" Value="Transparent"/>

            <Setter Property="BorderThickness" Value="0"/>

            <Style.Triggers>

                <Trigger Property="IsMouseOver" Value="True">

                    <Setter Property="Foreground" Value="Red"/>

                    <Setter Property="Background" Value="Transparent"/>

                    <Setter Property="BorderThickness" Value="10"/>

                    <Setter Property="Cursor" Value="Hand"/>

                </Trigger>

            </Style.Triggers>

        </Style>

        <!-- Checkbox template -->

        <Style TargetType="CheckBox">

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

            <Setter Property="FontSize" Value="{DynamicResource FontSize}" />

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="TextElement.FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="CheckBox">

                        <Grid Background="{TemplateBinding Background}" Margin="{DynamicResource CheckBoxMargin}">

                            <BulletDecorator Background="Transparent">

                                <BulletDecorator.Bullet>

                                    <Grid Width="{DynamicResource CheckBoxBulletDecoratorSize}" Height="{DynamicResource CheckBoxBulletDecoratorSize}">

                                        <Border x:Name="Border"

                                                BorderBrush="{TemplateBinding BorderBrush}"

                                                Background="{DynamicResource ButtonBackgroundColor}"

                                                BorderThickness="1"

                                                Width="{DynamicResource CheckBoxBulletDecoratorSize *0.85}"

                                                Height="{DynamicResource CheckBoxBulletDecoratorSize *0.85}"

                                                Margin="1"

                                                SnapsToDevicePixels="True"/>

                                        <Viewbox x:Name="CheckMarkContainer"

                                                Width="{DynamicResource CheckBoxBulletDecoratorSize}"

                                                Height="{DynamicResource CheckBoxBulletDecoratorSize}"

                                                HorizontalAlignment="Center"

                                                VerticalAlignment="Center"

                                                Visibility="Collapsed">

                                            <Path x:Name="CheckMark"

                                                  Stroke="{DynamicResource ToggleButtonOnColor}"

                                                  StrokeThickness="1.5"

                                                  Data="M 0 5 L 5 10 L 12 0"

                                                  Stretch="Uniform"/>

                                        </Viewbox>

                                    </Grid>

                                </BulletDecorator.Bullet>

                                <ContentPresenter Margin="4,0,0,0"

                                                  HorizontalAlignment="Left"

                                                  VerticalAlignment="Center"

                                                  RecognizesAccessKey="True"/>

                            </BulletDecorator>

                        </Grid>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsChecked" Value="True">

                                <Setter TargetName="CheckMarkContainer" Property="Visibility" Value="Visible"/>

                            </Trigger>

                            <Trigger Property="IsMouseOver" Value="True">

                                <!--Setter TargetName="Border" Property="Background" Value="{DynamicResource ButtonBackgroundPressedColor}"/-->

                                <Setter Property="Foreground" Value="{DynamicResource ButtonBackgroundPressedColor}"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                 </Setter.Value>

            </Setter>

        </Style>

        <Style TargetType="RadioButton">

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

            <Setter Property="FontSize" Value="{DynamicResource FontSize}" />

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="RadioButton">

                        <StackPanel Orientation="Horizontal" Margin="{DynamicResource CheckBoxMargin}">

                            <Viewbox Width="{DynamicResource CheckBoxBulletDecoratorSize}" Height="{DynamicResource CheckBoxBulletDecoratorSize}">

                                <Grid Width="14" Height="14">

                                    <Ellipse x:Name="OuterCircle"

                                            Stroke="{DynamicResource ToggleButtonOffColor}"

                                            Fill="{DynamicResource ButtonBackgroundColor}"

                                            StrokeThickness="1"

                                            Width="14"

                                            Height="14"

                                            SnapsToDevicePixels="True"/>

                                    <Ellipse x:Name="InnerCircle"

                                            Fill="{DynamicResource ToggleButtonOnColor}"

                                            Width="8"

                                            Height="8"

                                            Visibility="Collapsed"

                                            HorizontalAlignment="Center"

                                            VerticalAlignment="Center"/>

                                </Grid>

                            </Viewbox>

                            <ContentPresenter Margin="4,0,0,0"

                                            VerticalAlignment="Center"

                                            RecognizesAccessKey="True"/>

                        </StackPanel>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsChecked" Value="True">

                                <Setter TargetName="InnerCircle" Property="Visibility" Value="Visible"/>

                            </Trigger>

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter TargetName="OuterCircle" Property="Stroke" Value="{DynamicResource ToggleButtonOnColor}"/>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>

        <Style x:Key="ToggleSwitchStyle" TargetType="CheckBox">

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="CheckBox">

                        <StackPanel>

                            <Grid>

                                <Border Width="45"

                                        Height="20"

                                        Background="#555555"

                                        CornerRadius="10"

                                        Margin="5,0"

                                />

                                <Border Name="WPFToggleSwitchButton"

                                        Width="25"

                                        Height="25"

                                        Background="Black"

                                        CornerRadius="12.5"

                                        HorizontalAlignment="Left"

                                />

                                <ContentPresenter Name="WPFToggleSwitchContent"

                                                  Margin="10,0,0,0"

                                                  Content="{TemplateBinding Content}"

                                                  VerticalAlignment="Center"

                                />

                            </Grid>

                        </StackPanel>

                        <ControlTemplate.Triggers>

                            <Trigger Property="IsChecked" Value="false">

                                <Trigger.ExitActions>

                                    <RemoveStoryboard BeginStoryboardName="WPFToggleSwitchLeft" />

                                    <BeginStoryboard x:Name="WPFToggleSwitchRight">

                                        <Storyboard>

                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"

                                                    Storyboard.TargetName="WPFToggleSwitchButton"

                                                    Duration="0:0:0:0"

                                                    From="0,0,0,0"

                                                    To="28,0,0,0">

                                            </ThicknessAnimation>

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.ExitActions>

                                <Setter TargetName="WPFToggleSwitchButton"

                                        Property="Background"

                                        Value="#fff9f4f4"

                                />

                            </Trigger>

                            <Trigger Property="IsChecked" Value="true">

                                <Trigger.ExitActions>

                                    <RemoveStoryboard BeginStoryboardName="WPFToggleSwitchRight" />

                                    <BeginStoryboard x:Name="WPFToggleSwitchLeft">

                                        <Storyboard>

                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"

                                                    Storyboard.TargetName="WPFToggleSwitchButton"

                                                    Duration="0:0:0:0"

                                                    From="28,0,0,0"

                                                    To="0,0,0,0">

                                            </ThicknessAnimation>

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.ExitActions>

                                <Setter TargetName="WPFToggleSwitchButton"

                                        Property="Background"

                                        Value="#ff060600"

                                />

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

        </Style>



        <Style x:Key="ColorfulToggleSwitchStyle" TargetType="{x:Type CheckBox}">

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="{x:Type ToggleButton}">

                        <Grid x:Name="toggleSwitch">



                        <Grid.ColumnDefinitions>

                            <ColumnDefinition Width="Auto"/>

                            <ColumnDefinition Width="Auto"/>

                        </Grid.ColumnDefinitions>



                        <Border Grid.Column="1" x:Name="Border" CornerRadius="8"

                                BorderThickness="1"

                                Width="34" Height="17">

                            <Ellipse x:Name="Ellipse" Fill="{DynamicResource MainForegroundColor}" Stretch="Uniform"

                                    Margin="2,2,2,1"

                                    HorizontalAlignment="Left" Width="10.8"

                                    RenderTransformOrigin="0.5, 0.5">

                                <Ellipse.RenderTransform>

                                    <ScaleTransform ScaleX="1" ScaleY="1" />

                                </Ellipse.RenderTransform>

                            </Ellipse>

                        </Border>

                        </Grid>



                        <ControlTemplate.Triggers>

                            <Trigger Property="IsMouseOver" Value="True">

                                <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource MainForegroundColor}" />

                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource LinkHoverForegroundColor}"/>

                                <Setter Property="Cursor" Value="Hand" />

                                <Setter Property="Panel.ZIndex" Value="1000"/>

                                <Trigger.EnterActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <DoubleAnimation Storyboard.TargetName="Ellipse"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)"

                                                            To="1.1" Duration="0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="Ellipse"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)"

                                                            To="1.1" Duration="0:0:0.1" />

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.EnterActions>

                                <Trigger.ExitActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <DoubleAnimation Storyboard.TargetName="Ellipse"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)"

                                                            To="1.0" Duration="0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="Ellipse"

                                                            Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)"

                                                            To="1.0" Duration="0:0:0.1" />

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.ExitActions>

                            </Trigger>

                            <Trigger Property="ToggleButton.IsChecked" Value="False">

                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource MainBackgroundColor}" />

                                <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource ToggleButtonOffColor}" />

                                <Setter TargetName="Ellipse" Property="Fill" Value="{DynamicResource ToggleButtonOffColor}" />

                            </Trigger>



                            <Trigger Property="ToggleButton.IsChecked" Value="True">

                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource ToggleButtonOnColor}" />

                                <Setter TargetName="Border" Property="BorderBrush" Value="{DynamicResource ToggleButtonOnColor}" />

                                <Setter TargetName="Ellipse" Property="Fill" Value="White" />



                                <Trigger.EnterActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <ThicknessAnimation Storyboard.TargetName="Ellipse"

                                                    Storyboard.TargetProperty="Margin"

                                                    To="18,2,2,2" Duration="0:0:0.1" />

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.EnterActions>

                                <Trigger.ExitActions>

                                    <BeginStoryboard>

                                        <Storyboard>

                                            <ThicknessAnimation Storyboard.TargetName="Ellipse"

                                                    Storyboard.TargetProperty="Margin"

                                                    To="2,2,2,1" Duration="0:0:0.1" />

                                        </Storyboard>

                                    </BeginStoryboard>

                                </Trigger.ExitActions>

                            </Trigger>

                        </ControlTemplate.Triggers>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

            <Setter Property="VerticalContentAlignment" Value="Center" />

        </Style>



        <Style x:Key="labelfortweaks" TargetType="{x:Type Label}">

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}" />

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}" />

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Style.Triggers>

                <Trigger Property="IsMouseOver" Value="True">

                    <Setter Property="Foreground" Value="White" />

                </Trigger>

            </Style.Triggers>

        </Style>



        <Style x:Key="BorderStyle" TargetType="Border">

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

            <Setter Property="BorderBrush" Value="{DynamicResource BorderColor}"/>

            <Setter Property="BorderThickness" Value="1"/>

            <Setter Property="CornerRadius" Value="5"/>

            <Setter Property="Padding" Value="5"/>

            <Setter Property="Margin" Value="5"/>

            <Setter Property="Effect">

                <Setter.Value>

                    <DropShadowEffect ShadowDepth="5" BlurRadius="5" Opacity="{DynamicResource BorderOpacity}" Color="{DynamicResource CBorderColor}"/>

                </Setter.Value>

            </Setter>

        </Style>



        <Style TargetType="TextBox">

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

            <Setter Property="BorderBrush" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="BorderThickness" Value="1"/>

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="FontSize" Value="{DynamicResource FontSize}"/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Padding" Value="5"/>

            <Setter Property="HorizontalAlignment" Value="Stretch"/>

            <Setter Property="VerticalAlignment" Value="Center"/>

            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>

            <Setter Property="CaretBrush" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="ContextMenu">

                <Setter.Value>

                    <ContextMenu>

                        <ContextMenu.Style>

                            <Style TargetType="ContextMenu">

                                <Setter Property="Template">

                                    <Setter.Value>

                                        <ControlTemplate TargetType="ContextMenu">

                                            <Border Background="{DynamicResource MainBackgroundColor}" BorderBrush="{DynamicResource BorderColor}" BorderThickness="1" CornerRadius="5" Padding="5">

                                                <StackPanel>

                                                    <MenuItem Command="Cut" Header="Cut"/>

                                                    <MenuItem Command="Copy" Header="Copy"/>

                                                    <MenuItem Command="Paste" Header="Paste"/>

                                                </StackPanel>

                                            </Border>

                                        </ControlTemplate>

                                    </Setter.Value>

                                </Setter>

                            </Style>

                        </ContextMenu.Style>

                    </ContextMenu>

                </Setter.Value>

            </Setter>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="TextBox">

                        <Border Background="{TemplateBinding Background}"

                                BorderBrush="{TemplateBinding BorderBrush}"

                                BorderThickness="{TemplateBinding BorderThickness}"

                                CornerRadius="5">

                            <Grid>

                                <ScrollViewer x:Name="PART_ContentHost" />

                            </Grid>

                        </Border>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

            <Setter Property="Effect">

                <Setter.Value>

                    <DropShadowEffect ShadowDepth="5" BlurRadius="5" Opacity="{DynamicResource BorderOpacity}" Color="{DynamicResource CBorderColor}"/>

                </Setter.Value>

            </Setter>

        </Style>

        <Style TargetType="PasswordBox">

            <Setter Property="Background" Value="{DynamicResource MainBackgroundColor}"/>

            <Setter Property="BorderBrush" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="BorderThickness" Value="1"/>

            <Setter Property="Foreground" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="FontSize" Value="{DynamicResource FontSize}"/>

            <Setter Property="FontFamily" Value="{DynamicResource FontFamily}"/>

            <Setter Property="Padding" Value="5"/>

            <Setter Property="HorizontalAlignment" Value="Stretch"/>

            <Setter Property="VerticalAlignment" Value="Center"/>

            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>

            <Setter Property="CaretBrush" Value="{DynamicResource MainForegroundColor}"/>

            <Setter Property="Template">

                <Setter.Value>

                    <ControlTemplate TargetType="PasswordBox">

                        <Border Background="{TemplateBinding Background}"

                                BorderBrush="{TemplateBinding BorderBrush}"

                                BorderThickness="{TemplateBinding BorderThickness}"

                                CornerRadius="5">

                            <Grid>

                                <ScrollViewer x:Name="PART_ContentHost" />

                            </Grid>

                        </Border>

                    </ControlTemplate>

                </Setter.Value>

            </Setter>

            <Setter Property="Effect">

                <Setter.Value>

                    <DropShadowEffect ShadowDepth="5" BlurRadius="5" Opacity="{DynamicResource BorderOpacity}" Color="{DynamicResource CBorderColor}"/>

                </Setter.Value>

            </Setter>

        </Style>

        <Style x:Key="ScrollVisibilityRectangle" TargetType="Rectangle">

            <Setter Property="Visibility" Value="Collapsed"/>

            <Style.Triggers>

                <MultiDataTrigger>

                    <MultiDataTrigger.Conditions>

                        <Condition Binding="{Binding Path=ComputedHorizontalScrollBarVisibility, ElementName=scrollViewer}" Value="Visible"/>

                        <Condition Binding="{Binding Path=ComputedVerticalScrollBarVisibility, ElementName=scrollViewer}" Value="Visible"/>

                    </MultiDataTrigger.Conditions>

                    <Setter Property="Visibility" Value="Visible"/>

                </MultiDataTrigger>

            </Style.Triggers>

        </Style>

    </Window.Resources>

    <Grid Background="{DynamicResource MainBackgroundColor}" ShowGridLines="False" Name="WPFMainGrid" Width="Auto" Height="Auto" HorizontalAlignment="Stretch">

        <Grid.RowDefinitions>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="*"/>

        </Grid.RowDefinitions>

        <Grid.ColumnDefinitions>

            <ColumnDefinition Width="*"/>

        </Grid.ColumnDefinitions>

        <!-- Offline banner -->

        <Border Name="WPFOfflineBanner" Grid.Row="0" Background="#8B0000" Visibility="Collapsed" Padding="6,4">

            <TextBlock Text="&#x26A0; Offline Mode - No Internet Connection" Foreground="White" FontWeight="Bold"

                HorizontalAlignment="Center" FontSize="13" Background="Transparent"/>

        </Border>

        <Grid Grid.Row="1" Background="{DynamicResource MainBackgroundColor}">

            <Grid.ColumnDefinitions>

                <ColumnDefinition Width="Auto"/> <!-- Navigation buttons -->

                <ColumnDefinition Width="*"/> <!-- Search bar and buttons -->

            </Grid.ColumnDefinitions>



            <!-- Navigation Buttons Panel -->

            <StackPanel Name="NavDockPanel" Orientation="Horizontal" Grid.Column="0" Margin="5,5,10,5">

                <StackPanel Name="NavLogoPanel" Orientation="Horizontal" HorizontalAlignment="Left" Background="{DynamicResource MainBackgroundColor}" SnapsToDevicePixels="True" Margin="10,0,20,0">

                </StackPanel>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonInstallBackgroundColor}" Foreground="white" FontWeight="Bold" Name="WPFTab1BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonInstallForegroundColor}" >

                            <Underline>I</Underline>nstall

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonTweaksBackgroundColor}" Foreground="{DynamicResource ButtonTweaksForegroundColor}" FontWeight="Bold" Name="WPFTab2BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonTweaksForegroundColor}">

                            <Underline>T</Underline>weaks

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonConfigBackgroundColor}" Foreground="{DynamicResource ButtonConfigForegroundColor}" FontWeight="Bold" Name="WPFTab3BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonConfigForegroundColor}">

                            <Underline>C</Underline>onfig

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonUpdatesBackgroundColor}" Foreground="{DynamicResource ButtonUpdatesForegroundColor}" FontWeight="Bold" Name="WPFTab4BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonUpdatesForegroundColor}">

                            <Underline>U</Underline>pdates

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonConfigBackgroundColor}" Foreground="{DynamicResource ButtonConfigForegroundColor}" FontWeight="Bold" Name="WPFTab6BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonConfigForegroundColor}">

                            <Underline>P</Underline>rofiles

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonConfigBackgroundColor}" Foreground="{DynamicResource ButtonConfigForegroundColor}" FontWeight="Bold" Name="WPFTab7BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonConfigForegroundColor}" Text="Tools"/>

                    </ToggleButton.Content>

                </ToggleButton>

                <ToggleButton Margin="0,0,5,0" Height="{DynamicResource TabButtonHeight}" Width="Auto" MinWidth="{DynamicResource TabButtonWidth}"

                    Background="{DynamicResource ButtonWin11ISOBackgroundColor}" Foreground="{DynamicResource ButtonWin11ISOForegroundColor}" FontWeight="Bold" Name="WPFTab5BT">

                    <ToggleButton.Content>

                        <TextBlock FontSize="{DynamicResource TabButtonFontSize}" Background="Transparent" Foreground="{DynamicResource ButtonWin11ISOForegroundColor}">

                            <Underline>W</Underline>in ISO Creator

                        </TextBlock>

                    </ToggleButton.Content>

                </ToggleButton>

            </StackPanel>



            <!-- Search Bar and Action Buttons -->

            <Grid Name="GridBesideNavDockPanel" Grid.Column="1" Background="{DynamicResource MainBackgroundColor}" ShowGridLines="False" Height="Auto">

                <Grid.ColumnDefinitions>

                    <ColumnDefinition Width="2*"/> <!-- Search bar area - priority space -->

                    <ColumnDefinition Width="Auto"/><!-- Buttons area -->

                </Grid.ColumnDefinitions>



                <Border Grid.Column="0" Margin="5,0,0,0" Width="{DynamicResource SearchBarWidth}" Height="{DynamicResource SearchBarHeight}" VerticalAlignment="Center" HorizontalAlignment="Left">

                    <Grid>

                        <TextBox

                            Width="{DynamicResource SearchBarWidth}"

                            Height="{DynamicResource SearchBarHeight}"

                            FontSize="{DynamicResource SearchBarTextBoxFontSize}"

                            VerticalAlignment="Center" HorizontalAlignment="Left"

                            BorderThickness="1"

                            Name="SearchBar"

                            Foreground="{DynamicResource MainForegroundColor}" Background="{DynamicResource MainBackgroundColor}"

                            Padding="3,3,30,0"

                            ToolTip="Press Ctrl-F and type app name to filter application list below. Press Esc to reset the filter">

                        </TextBox>

                        <TextBlock

                            VerticalAlignment="Center" HorizontalAlignment="Right"

                            FontFamily="Segoe MDL2 Assets"

                            Foreground="{DynamicResource ButtonBackgroundSelectedColor}"

                            FontSize="{DynamicResource IconFontSize}"

                            Margin="0,0,8,0" Width="Auto" Height="Auto">&#xE721;

                        </TextBlock>

                    </Grid>

                </Border>

                <Button Grid.Column="0"

                    VerticalAlignment="Center" HorizontalAlignment="Left"

                    Name="SearchBarClearButton"

                    Style="{StaticResource SearchBarClearButtonStyle}"

                    Margin="213,0,0,0" Visibility="Collapsed">

                </Button>



                <!-- Buttons Container -->

                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="5,5,5,5">

                    <Button Name="ThemeButton"

                        Style="{StaticResource HoverButtonStyle}"

                        BorderBrush="Transparent"

                    Background="{DynamicResource MainBackgroundColor}"

                    Foreground="{DynamicResource MainForegroundColor}"

                    FontSize="{DynamicResource SettingsIconFontSize}"

                    Width="{DynamicResource IconButtonSize}" Height="{DynamicResource IconButtonSize}"

                    HorizontalAlignment="Right" VerticalAlignment="Top"

                    Margin="0,0,2,0"

                    FontFamily="Segoe MDL2 Assets"

                    Content="N/A"

                    ToolTip="Change the clark UI theme (Advance Systems 4042)"

                />

                    <Popup Name="ThemePopup"

                    IsOpen="False"

                    PlacementTarget="{Binding ElementName=ThemeButton}" Placement="Bottom"

                    HorizontalAlignment="Right" VerticalAlignment="Top">

                    <Border Background="{DynamicResource MainBackgroundColor}" BorderBrush="{DynamicResource MainForegroundColor}" BorderThickness="1" CornerRadius="0" Margin="0">

                        <StackPanel Background="{DynamicResource MainBackgroundColor}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Auto" Name="AutoThemeMenuItem" Foreground="{DynamicResource MainForegroundColor}">

                                <MenuItem.ToolTip>

                                    <ToolTip Content="Follow the Windows Theme"/>

                                </MenuItem.ToolTip>

                            </MenuItem>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Dark" Name="DarkThemeMenuItem" Foreground="{DynamicResource MainForegroundColor}">

                                <MenuItem.ToolTip>

                                    <ToolTip Content="Use Dark Theme"/>

                                </MenuItem.ToolTip>

                            </MenuItem>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Light" Name="LightThemeMenuItem" Foreground="{DynamicResource MainForegroundColor}">

                                <MenuItem.ToolTip>

                                    <ToolTip Content="Use Light Theme"/>

                                </MenuItem.ToolTip>

                            </MenuItem>

                        </StackPanel>

                    </Border>

                </Popup>



                    <Button Name="FontScalingButton"

                        Style="{StaticResource HoverButtonStyle}"

                        BorderBrush="Transparent"

                    Background="{DynamicResource MainBackgroundColor}"

                    Foreground="{DynamicResource MainForegroundColor}"

                    FontSize="{DynamicResource SettingsIconFontSize}"

                    Width="{DynamicResource IconButtonSize}" Height="{DynamicResource IconButtonSize}"

                    HorizontalAlignment="Right" VerticalAlignment="Top"

                    Margin="0,0,2,0"

                    FontFamily="Segoe MDL2 Assets"

                    Content="&#xE8D3;"

                    ToolTip="Adjust Font Scaling for Accessibility"

                />

                    <Popup Name="FontScalingPopup"

                    IsOpen="False"

                    PlacementTarget="{Binding ElementName=FontScalingButton}" Placement="Bottom"

                    HorizontalAlignment="Right" VerticalAlignment="Top">

                    <Border Background="{DynamicResource MainBackgroundColor}" BorderBrush="{DynamicResource MainForegroundColor}" BorderThickness="1" CornerRadius="0" Margin="0">

                        <StackPanel Background="{DynamicResource MainBackgroundColor}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" MinWidth="200">

                            <TextBlock Text="Font Scaling"

                                       FontSize="{DynamicResource ButtonFontSize}"

                                       Foreground="{DynamicResource MainForegroundColor}"

                                       HorizontalAlignment="Center"

                                       Margin="10,5,10,5"

                                       FontWeight="Bold"/>

                            <Separator Margin="5,0,5,5"/>

                            <StackPanel Orientation="Horizontal" Margin="10,5,10,10">

                                <TextBlock Text="Small"

                                           FontSize="{DynamicResource ButtonFontSize}"

                                           Foreground="{DynamicResource MainForegroundColor}"

                                           VerticalAlignment="Center"

                                           Margin="0,0,10,0"/>

                                <Slider Name="FontScalingSlider"

                                        Minimum="0.75" Maximum="2.0"

                                        Value="1.25"

                                        TickFrequency="0.25"

                                        TickPlacement="BottomRight"

                                        IsSnapToTickEnabled="True"

                                        Width="120"

                                        VerticalAlignment="Center"/>

                                <TextBlock Text="Large"

                                           FontSize="{DynamicResource ButtonFontSize}"

                                           Foreground="{DynamicResource MainForegroundColor}"

                                           VerticalAlignment="Center"

                                           Margin="10,0,0,0"/>

                            </StackPanel>

                            <TextBlock Name="FontScalingValue"

                                       Text="125%"

                                       FontSize="{DynamicResource ButtonFontSize}"

                                       Foreground="{DynamicResource MainForegroundColor}"

                                       HorizontalAlignment="Center"

                                       Margin="10,0,10,5"/>

                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="10,0,10,10">

                                <Button Name="FontScalingResetButton"

                                        Content="Reset"

                                        Style="{StaticResource HoverButtonStyle}"

                                        Width="60" Height="25"

                                        Margin="5,0,5,0"/>

                                <Button Name="FontScalingApplyButton"

                                        Content="Apply"

                                        Style="{StaticResource HoverButtonStyle}"

                                        Width="60" Height="25"

                                        Margin="5,0,5,0"/>

                            </StackPanel>

                        </StackPanel>

                    </Border>

                </Popup>



                    <Button Name="SettingsButton"

                        Style="{StaticResource HoverButtonStyle}"

                        BorderBrush="Transparent"

                    Background="{DynamicResource MainBackgroundColor}"

                    Foreground="{DynamicResource MainForegroundColor}"

                    FontSize="{DynamicResource SettingsIconFontSize}"

                    Width="{DynamicResource IconButtonSize}" Height="{DynamicResource IconButtonSize}"

                    HorizontalAlignment="Right" VerticalAlignment="Top"

                    Margin="0,0,2,0"

                    FontFamily="Segoe MDL2 Assets"

                    Content="&#xE713;"/>

                    <Popup Name="SettingsPopup"

                    IsOpen="False"

                    PlacementTarget="{Binding ElementName=SettingsButton}" Placement="Bottom"

                    HorizontalAlignment="Right" VerticalAlignment="Top">

                    <Border Background="{DynamicResource MainBackgroundColor}" BorderBrush="{DynamicResource MainForegroundColor}" BorderThickness="1" CornerRadius="0" Margin="0">

                        <StackPanel Background="{DynamicResource MainBackgroundColor}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Import" Name="ImportMenuItem" Foreground="{DynamicResource MainForegroundColor}">

                                <MenuItem.ToolTip>

                                    <ToolTip Content="Import Configuration from exported file."/>

                                </MenuItem.ToolTip>

                            </MenuItem>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Export" Name="ExportMenuItem" Foreground="{DynamicResource MainForegroundColor}">

                                <MenuItem.ToolTip>

                                    <ToolTip Content="Export Selected Elements and copy execution command to clipboard."/>

                                </MenuItem.ToolTip>

                            </MenuItem>

                            <Separator/>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="About" Name="AboutMenuItem" Foreground="{DynamicResource MainForegroundColor}"/>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Documentation" Name="DocumentationMenuItem" Foreground="{DynamicResource MainForegroundColor}"/>

                            <MenuItem FontSize="{DynamicResource ButtonFontSize}" Header="Sponsors" Name="SponsorMenuItem" Foreground="{DynamicResource MainForegroundColor}"/>

                        </StackPanel>

                    </Border>

                </Popup>



                </StackPanel>

            </Grid>

        </Grid>



        <TabControl Name="WPFTabNav" Background="Transparent" Width="Auto" Height="Auto" BorderBrush="Transparent" BorderThickness="0" Grid.Row="2" Grid.Column="0" Padding="-1">

            <TabItem Header="Install" Visibility="Collapsed" Name="WPFTab1">

                <Grid Background="Transparent" >



                    <Grid Grid.Row="0" Grid.Column="0" Margin="{DynamicResource TabContentMargin}">

                        <Grid.ColumnDefinitions>

                            <ColumnDefinition Width="Auto" />

                            <ColumnDefinition Width="*" />

                        </Grid.ColumnDefinitions>



                        <Grid Name="appscategory" Grid.Column="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">

                        </Grid>



                        <Grid Name="appspanel" Grid.Column="1" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">

                        </Grid>

                    </Grid>

                </Grid>

            </TabItem>

            <TabItem Header="Tweaks" Visibility="Collapsed" Name="WPFTab2">

                <Grid>

                    <!-- Main content area with a ScrollViewer -->

                    <Grid.RowDefinitions>

                        <RowDefinition Height="*" />

                        <RowDefinition Height="Auto" />

                    </Grid.RowDefinitions>



                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Grid.Row="0" Margin="{DynamicResource TabContentMargin}">

                        <Grid Background="Transparent">

                            <Grid.RowDefinitions>

                                <RowDefinition Height="Auto"/>

                                <RowDefinition Height="*"/>

                                <RowDefinition Height="Auto"/>

                            </Grid.RowDefinitions>



                            <StackPanel Background="{DynamicResource MainBackgroundColor}" Orientation="Vertical" Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Margin="5">

                                <Label Content="Recommended Selections:" FontSize="{DynamicResource FontSize}" VerticalAlignment="Center" Margin="2"/>

                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2,0,0">

                                    <Button Name="WPFstandard" Content=" Standard " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                                    <Button Name="WPFminimal" Content=" Minimal " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                                    <Button Name="WPFClearTweaksSelection" Content=" Clear " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                                    <Button Name="WPFGetInstalledTweaks" Content=" Get Installed Tweaks " Margin="2" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                                </StackPanel>

                            </StackPanel>



                            <Grid Name="tweakspanel" Grid.Row="1">

                                <!-- Your tweakspanel content goes here -->

                            </Grid>



                            <Border Grid.ColumnSpan="2" Grid.Row="2" Grid.Column="0" Style="{StaticResource BorderStyle}">

                                <StackPanel Background="{DynamicResource MainBackgroundColor}" Orientation="Horizontal" HorizontalAlignment="Left">

                                    <TextBlock Padding="10">

                                        Note: Hover over items to get a better description. Please be careful as many of these tweaks will heavily modify your system.

                                        <LineBreak/>Recommended selections are for normal users and if you are unsure do NOT check anything else!

                                    </TextBlock>

                                </StackPanel>

                            </Border>

                        </Grid>

                    </ScrollViewer>

                    <Border Grid.Row="1" Background="{DynamicResource MainBackgroundColor}" BorderBrush="{DynamicResource BorderColor}" BorderThickness="1" CornerRadius="5" HorizontalAlignment="Stretch" Padding="10">

                        <WrapPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center" Grid.Column="0">

                            <Button Name="WPFTweaksbutton" Content="Run Tweaks" Margin="5" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                            <Button Name="WPFUndoall" Content="Undo Selected Tweaks" Margin="5" Width="{DynamicResource ButtonWidth}" Height="{DynamicResource ButtonHeight}"/>

                        </WrapPanel>

                    </Border>

                </Grid>

            </TabItem>

            <TabItem Header="Config" Visibility="Collapsed" Name="WPFTab3">

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Margin="{DynamicResource TabContentMargin}">

                    <Grid Name="featurespanel" Grid.Row="1" Background="Transparent">

                    </Grid>

                </ScrollViewer>

            </TabItem>

            <TabItem Header="Updates" Visibility="Collapsed" Name="WPFTab4">

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="{DynamicResource TabContentMargin}">

                    <Grid Background="Transparent" MaxWidth="{Binding ActualWidth, RelativeSource={RelativeSource AncestorType=ScrollViewer}}">

                        <Grid.RowDefinitions>

                            <RowDefinition Height="Auto"/>  <!-- Row for update action cards -->

                            <RowDefinition Height="Auto"/>  <!-- Row for Windows Version -->

                        </Grid.RowDefinitions>



                        <!-- Update action cards -->

                        <Grid Grid.Row="0">

                            <Grid.ColumnDefinitions>

                                <ColumnDefinition Width="*"/>

                                <ColumnDefinition Width="*"/>

                                <ColumnDefinition Width="*"/>

                                <ColumnDefinition Width="*"/>

                                <ColumnDefinition Width="*"/>

                            </Grid.ColumnDefinitions>



                            <!-- Default Settings -->

                            <Border Grid.Column="0" Style="{StaticResource BorderStyle}">

                                <StackPanel>

                                    <Button Name="WPFUpdatesdefault"

                                            FontSize="{DynamicResource ConfigTabButtonFontSize}"

                                            Content="Default Settings"

                                            Margin="10,5"

                                            Padding="10"/>

                                    <TextBlock Margin="10"

                                             TextWrapping="Wrap"

                                             Foreground="{DynamicResource MainForegroundColor}">

                                        <Run FontWeight="Bold">Default Windows Update Configuration</Run>

                                        <LineBreak/>

                                         - No modifications to Windows defaults

                                        <LineBreak/>

                                         - Removes any custom update settings

                                        <LineBreak/><LineBreak/>

                                        <Run FontStyle="Italic" FontSize="11">Note: This resets your Windows Update settings to default out of the box settings. It removes ANY policy or customization that has been done to Windows Update.</Run>

                                    </TextBlock>

                                </StackPanel>

                            </Border>



                            <!-- Security Settings -->

                            <Border Grid.Column="1" Style="{StaticResource BorderStyle}">

                                <StackPanel>

                                    <Button Name="WPFUpdatessecurity"

                                            FontSize="{DynamicResource ConfigTabButtonFontSize}"

                                            Content="Security Settings"

                                            Margin="10,5"

                                            Padding="10"/>

                                    <TextBlock Margin="10"

                                             TextWrapping="Wrap"

                                             Foreground="{DynamicResource MainForegroundColor}">

                                        <Run FontWeight="Bold">Balanced Security Configuration</Run>

                                        <LineBreak/>

                                         - Feature updates delayed by 365 days

                                        <LineBreak/>

                                         - Security updates installed after 4 days

                                        <LineBreak/>

                                         - Prevents Windows Update from installing drivers

                                        <LineBreak/><LineBreak/>

                                        <Run FontWeight="SemiBold">Feature Updates:</Run> New features and potential bugs

                                        <LineBreak/>

                                        <Run FontWeight="SemiBold">Security Updates:</Run> Critical security patches

                                    <LineBreak/><LineBreak/>

                                    <Run FontStyle="Italic" FontSize="11">Note: This only applies to Pro systems that can use group policy.</Run>

                                    </TextBlock>

                                </StackPanel>

                            </Border>



                            <!-- Disable Updates -->

                            <Border Grid.Column="2" Style="{StaticResource BorderStyle}">

                                <StackPanel>

                                    <Button Name="WPFUpdatesdisable"

                                            FontSize="{DynamicResource ConfigTabButtonFontSize}"

                                            Content="Disable All Updates"

                                            Foreground="Red"

                                            Margin="10,5"

                                            Padding="10"/>

                                    <TextBlock Margin="10"

                                             TextWrapping="Wrap"

                                             Foreground="{DynamicResource MainForegroundColor}">

                                        <Run FontWeight="Bold" Foreground="Red">!! Not Recommended !!</Run>

                                        <LineBreak/>

                                         - Disables ALL Windows Updates

                                        <LineBreak/>

                                         - Increases security risks

                                        <LineBreak/>

                                         - Only use for isolated systems

                                        <LineBreak/><LineBreak/>

                                        <Run FontStyle="Italic" FontSize="11">Warning: Your system will be vulnerable without security updates.</Run>

                                    </TextBlock>

                                </StackPanel>

                            </Border>



                            <!-- Update Destroyer -->

                            <Border Grid.Column="3" Style="{StaticResource BorderStyle}">

                                <StackPanel>

                                    <Button Name="WPFUpdateDestroyer"

                                            FontSize="{DynamicResource ConfigTabButtonFontSize}"

                                            Content="Update Destroyer"

                                            Foreground="Red"

                                            Margin="10,5"

                                            Padding="10"/>

                                    <TextBlock Margin="10"

                                             TextWrapping="Wrap"

                                             Foreground="{DynamicResource MainForegroundColor}">

                                        <Run FontWeight="Bold" Foreground="OrangeRed">Use with caution.</Run>

                                        <LineBreak/>

                                         - Disables core Windows Update services and scheduled tasks

                                        <LineBreak/>

                                         - Intended for advanced troubleshooting or isolated/offline systems

                                        <LineBreak/>

                                         - Can break normal Windows Update behavior until reverted

                                        <LineBreak/><LineBreak/>

                                        <Run FontStyle="Italic" FontSize="11">Runs: tools\UpdateDestroyer.bat</Run>

                                    </TextBlock>

                                </StackPanel>

                            </Border>



                            <!-- Update Destroyer Undo -->

                            <Border Grid.Column="4" Style="{StaticResource BorderStyle}">

                                <StackPanel>

                                    <Button Name="WPFUpdateDestroyerUndo"

                                            FontSize="{DynamicResource ConfigTabButtonFontSize}"

                                            Content="Update Destroyer Undo"

                                            Margin="10,5"

                                            Padding="10"/>

                                    <TextBlock Margin="10"

                                             TextWrapping="Wrap"

                                             Foreground="{DynamicResource MainForegroundColor}">

                                        <Run FontWeight="Bold">Restore update components.</Run>

                                        <LineBreak/>

                                         - Re-enables Windows Update services, tasks, and policy defaults

                                        <LineBreak/>

                                         - Use this after Update Destroyer when you need updates working again

                                        <LineBreak/>

                                         - Reboot is recommended after running undo

                                        <LineBreak/><LineBreak/>

                                        <Run FontStyle="Italic" FontSize="11">Runs: tools\UpdateDestroyerUndo.bat</Run>

                                    </TextBlock>

                                </StackPanel>

                            </Border>

                        </Grid>



                        <!-- Future Implementation: Add Windows Version to updates panel -->

                        <Grid Name="updatespanel" Grid.Row="1" Background="Transparent">

                        </Grid>

                    </Grid>

                </ScrollViewer>

            </TabItem>

            <TabItem Header="Profiles" Visibility="Collapsed" Name="WPFTab6">

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Margin="{DynamicResource TabContentMargin}">

                    <Grid Name="profilespanel" Grid.Row="1" Background="Transparent">

                    </Grid>

                </ScrollViewer>

            </TabItem>

            <TabItem Header="Tools" Visibility="Collapsed" Name="WPFTab7">

                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Margin="{DynamicResource TabContentMargin}">

                    <StackPanel Orientation="Vertical" Background="Transparent">

                        <TextBlock Margin="0,0,0,14"

                                   TextWrapping="Wrap"

                                   FontSize="{DynamicResource FontSize}"

                                   Foreground="{DynamicResource MainForegroundColor}">

                            <Run FontWeight="Bold">Built-in utilities</Run>

                            <LineBreak/>

                            <Run>Open a tool to run it in a separate window. Hover a button to see a short description.</Run>

                        </TextBlock>

                        <Grid Name="toolspanel" Background="Transparent" MinWidth="400">

                        </Grid>

                    </StackPanel>

                </ScrollViewer>

            </TabItem>

            <TabItem Header="Win11ISO" Visibility="Collapsed" Name="WPFTab5">

                <Grid Name="Win11ISOPanel" Margin="{DynamicResource TabContentMargin}" Background="Transparent">

                    <Grid.RowDefinitions>

                        <RowDefinition Height="*"/>     <!-- Steps 1-4 -->

                        <RowDefinition Height="8"/>     <!-- Drag handle -->

                        <RowDefinition Height="*"/>     <!-- Log / Status -->

                    </Grid.RowDefinitions>



                    <!-- Steps 1-4 -->
                    <ScrollViewer Grid.Row="0"
                                  VerticalScrollBarVisibility="Auto"
                                  HorizontalScrollBarVisibility="Disabled">
                    <StackPanel Margin="0,0,5,0">



                            <!-- ????????? STEP 1 : Select Windows 10/11 ISO ????????????????????????????????????????????? -->

                            <Grid Name="WPFWin11ISOSelectSection" Margin="5" HorizontalAlignment="Left" MinWidth="{DynamicResource ButtonWidth}">

                                <Grid.ColumnDefinitions>

                                    <ColumnDefinition Width="*"/>

                                    <ColumnDefinition Width="*"/>

                                </Grid.ColumnDefinitions>



                                <!-- Left: File Selector -->

                                <StackPanel Grid.Column="0" Margin="5,5,15,5">

                                    <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                               Foreground="{DynamicResource MainForegroundColor}" Margin="0,0,0,8">

                                        Step 1 - Select Windows 10 or 11 ISO

                                    </TextBlock>

                                    <TextBlock FontSize="{DynamicResource FontSize}" Foreground="{DynamicResource MainForegroundColor}"

                                               TextWrapping="Wrap" Margin="0,0,0,6">

                                        Browse to your locally saved Windows 10 or Windows 11 ISO file. Only official ISOs

                                        downloaded from Microsoft are supported.

                                    </TextBlock>

                                    <TextBlock FontSize="{DynamicResource FontSize}" Foreground="{DynamicResource MainForegroundColor}"

                                               TextWrapping="Wrap" Margin="0,0,0,12" FontStyle="Italic">

                                        <Run FontWeight="Bold">NOTE:</Run> This is only meant for Fresh and New Windows installs.

                                    </TextBlock>

                                    <Grid>

                                        <Grid.ColumnDefinitions>

                                            <ColumnDefinition Width="*"/>

                                            <ColumnDefinition Width="Auto"/>

                                        </Grid.ColumnDefinitions>

                                        <TextBox Grid.Column="0"

                                                 Name="WPFWin11ISOPath"

                                                 IsReadOnly="True"

                                                 VerticalAlignment="Center"

                                                 Padding="6,4"

                                                 Margin="0,0,6,0"

                                                 Text="No ISO selected..."

                                                 Foreground="{DynamicResource MainForegroundColor}"

                                                 Background="{DynamicResource MainBackgroundColor}"/>

                                        <Button Grid.Column="1"

                                                Name="WPFWin11ISOBrowseButton"

                                                Content="Browse"

                                                Width="Auto" Padding="12,0"

                                                Height="{DynamicResource ButtonHeight}"/>

                                    </Grid>

                                    <TextBlock Name="WPFWin11ISOFileInfo"

                                               FontSize="{DynamicResource FontSize}"

                                               Foreground="{DynamicResource MainForegroundColor}"

                                               Margin="0,8,0,0"

                                               TextWrapping="Wrap"

                                               Visibility="Collapsed"/>

                                </StackPanel>



                                <!-- Right: Download guidance -->

                                <Border Grid.Column="1"

                                        Background="{DynamicResource MainBackgroundColor}"

                                        BorderBrush="{DynamicResource BorderColor}"

                                        BorderThickness="1" CornerRadius="5"

                                        Margin="5" Padding="15">

                                    <StackPanel>

                                        <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                                   Foreground="OrangeRed" Margin="0,0,0,10">

                                            !!WARNING!! You must use an official Microsoft ISO

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,8">

                                            Download a Windows 10 or Windows 11 ISO directly from Microsoft.

                                            Third-party, pre-modified, or unofficial images are not supported

                                            and may produce broken results.

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,6">

                                            On the Microsoft download page, choose:

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="12,0,0,12">

                                            - Edition  : Windows 10 or Windows 11 (your choice)

                                            <LineBreak/>- Language : your preferred language

                                            <LineBreak/>- Architecture : 64-bit (x64)

                                        </TextBlock>

                                        <StackPanel Orientation="Horizontal">

                                        <Button Name="WPFWin11ISODownloadLink"

                                                Content="Windows 11 - Microsoft download"

                                                HorizontalAlignment="Left"

                                                Width="Auto" Padding="12,0"

                                                Height="{DynamicResource ButtonHeight}"/>

                                        <Button Name="WPFWin10ISODownloadLink"

                                                Content="Windows 10 - Microsoft download"

                                                HorizontalAlignment="Left"

                                                Width="Auto" Padding="12,0" Margin="8,0,0,0"

                                                Height="{DynamicResource ButtonHeight}"/>

                                        </StackPanel>

                                        <Separator Margin="0,12,0,10"/>

                                        <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                                   Foreground="{DynamicResource MainForegroundColor}" Margin="0,0,0,8">

                                            Direct ISO download by version

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,8">

                                            Choose Windows version and release, then clark downloads the ISO. If you set a mirror URL in config\isomirrors.json (e.g. Internet Archive), that is tried first; if the download fails or the slot is empty, Fido is used to resolve Microsoft???s link. Optionally place Fido.ps1 in the repo tools folder so the helper does not need to be fetched from GitHub.

                                        </TextBlock>

                                        <Grid Margin="0,0,0,8">

                                            <Grid.ColumnDefinitions>

                                                <ColumnDefinition Width="*"/>

                                                <ColumnDefinition Width="8"/>

                                                <ColumnDefinition Width="*"/>

                                            </Grid.ColumnDefinitions>

                                            <ComboBox Name="WPFWinISODownloadProductComboBox"

                                                      Grid.Column="0"

                                                      Foreground="{DynamicResource MainForegroundColor}"

                                                      Background="{DynamicResource MainBackgroundColor}"

                                                      ToolTip="Windows product"/>

                                            <ComboBox Name="WPFWinISODownloadVersionComboBox"

                                                      Grid.Column="2"

                                                      Foreground="{DynamicResource MainForegroundColor}"

                                                      Background="{DynamicResource MainBackgroundColor}"

                                                      ToolTip="Windows release version"/>

                                        </Grid>

                                        <ComboBox Name="WPFWinISODownloadLanguageComboBox"
                                                  Foreground="{DynamicResource MainForegroundColor}"
                                                  Background="{DynamicResource MainBackgroundColor}"
                                                  ToolTip="Windows ISO language (default: en-US)"
                                                  Margin="0,0,0,8"/>

                                        <Button Name="WPFWinISODownloadDirectButton"

                                                Content="Download Selected ISO Version"

                                                HorizontalAlignment="Left"

                                                Width="Auto" Padding="12,0"

                                                Height="{DynamicResource ButtonHeight}"/>

                                        <StackPanel Orientation="Horizontal" Margin="0,8,0,0">

                                            <Button Name="WPFWinISODownloadPauseButton"

                                                    Content="Pause"

                                                    HorizontalAlignment="Left"

                                                    Width="Auto" Padding="12,0"

                                                    Height="{DynamicResource ButtonHeight}"

                                                    IsEnabled="False"/>

                                            <Button Name="WPFWinISODownloadStopButton"

                                                    Content="Stop"

                                                    HorizontalAlignment="Left"

                                                    Width="Auto" Padding="12,0" Margin="8,0,0,0"

                                                    Height="{DynamicResource ButtonHeight}"

                                                    IsEnabled="False"/>

                                        </StackPanel>

                                        <ProgressBar Name="WPFWinISODownloadProgressBar"

                                                     Minimum="0"

                                                     Maximum="100"

                                                     Value="0"

                                                     Height="18"

                                                     Margin="0,10,0,0"

                                                     Visibility="Collapsed"/>

                                        <TextBlock Name="WPFWinISODownloadProgressText"

                                                   Text=""

                                                   Margin="0,6,0,0"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   Visibility="Collapsed"/>

                                    </StackPanel>

                                </Border>

                            </Grid>



                            <!-- ????????? STEP 2 : Mount & Verify ISO ???????????????????????????????????????????????????????????? -->

                            <Grid Name="WPFWin11ISOMountSection"

                                  Margin="5"

                                  Visibility="Collapsed"

                                  HorizontalAlignment="Left" MinWidth="{DynamicResource ButtonWidth}">

                                <Grid.ColumnDefinitions>

                                    <ColumnDefinition Width="Auto"/>

                                    <ColumnDefinition Width="*"/>

                                </Grid.ColumnDefinitions>



                                <StackPanel Grid.Column="0" Margin="0,0,20,0" VerticalAlignment="Top">

                                    <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                               Foreground="{DynamicResource MainForegroundColor}" Margin="0,0,0,8">

                                        Step 2 - Mount &amp; Verify ISO

                                    </TextBlock>

                                    <TextBlock FontSize="{DynamicResource FontSize}"

                                               Foreground="{DynamicResource MainForegroundColor}"

                                               TextWrapping="Wrap" Margin="0,0,0,12" MaxWidth="320">

                                        Mount the ISO and confirm it contains a valid Windows 10 or Windows 11

                                        install.wim before any modifications are made.

                                    </TextBlock>

                                    <Button Name="WPFWin11ISOMountButton"

                                            Content="Mount &amp; Verify ISO"

                                            HorizontalAlignment="Left"

                                            Width="Auto" Padding="12,0"

                                            Height="{DynamicResource ButtonHeight}"/>

                                    <CheckBox Name="WPFWin11ISOInjectDrivers"

                                              Content="Inject current system drivers"

                                              FontSize="{DynamicResource FontSize}"

                                              Foreground="{DynamicResource MainForegroundColor}"

                                              IsChecked="False"

                                              Margin="0,8,0,0"

                                              ToolTip="Exports all drivers from this machine and injects them into install.wim and boot.wim. Recommended for systems with unsupported NVMe or network controllers."/>

                                </StackPanel>



                                <!-- Verification results panel -->

                                <Border Grid.Column="1"

                                        Name="WPFWin11ISOVerifyResultPanel"

                                        Background="{DynamicResource MainBackgroundColor}"

                                        BorderBrush="{DynamicResource BorderColor}"

                                        BorderThickness="1" CornerRadius="5"

                                        Padding="12" Margin="0,0,0,0"

                                        Visibility="Collapsed">

                                    <StackPanel>

                                        <TextBlock Name="WPFWin11ISOMountDriveLetter"

                                                   FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   Margin="0,0,0,4"/>

                                        <TextBlock Name="WPFWin11ISOArchLabel"

                                                   FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   Margin="0,0,0,4"/>

                                        <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   Margin="0,6,0,4">

                                            Editions to be processed:

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,4">

                                            &#x2713; Home

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,4">

                                            &#x2713; Home Single Language

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,8">

                                            &#x2713; Pro

                                        </TextBlock>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   FontStyle="Italic"

                                                   TextWrapping="Wrap" Margin="0,0,0,0" MaxWidth="220">

                                            All editions will be modified and kept in the final ISO.

                                        </TextBlock>

                                        <!-- ComboBox retained for internal use by mount/verify logic -->

                                        <ComboBox Name="WPFWin11ISOEditionComboBox"

                                                  Visibility="Collapsed"

                                                  FontSize="{DynamicResource FontSize}"

                                                  Foreground="{DynamicResource MainForegroundColor}"

                                                  Background="{DynamicResource MainBackgroundColor}"

                                                  HorizontalAlignment="Left"

                                                  Margin="0,0,0,0"/>

                                    </StackPanel>

                                </Border>

                            </Grid>



                            <!-- ????????? STEP 3 : Modify install.wim ??????????????????????????????????????????????????????????????? -->

                            <StackPanel Name="WPFWin11ISOModifySection"

                                        Margin="5"

                                        Visibility="Collapsed"

                                        HorizontalAlignment="Left" MinWidth="{DynamicResource ButtonWidth}">

                                <TextBlock FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                           Foreground="{DynamicResource MainForegroundColor}" Margin="0,0,0,8">

                                    Step 3 - Modify install.wim

                                </TextBlock>

                                <TextBlock FontSize="{DynamicResource FontSize}"

                                           Foreground="{DynamicResource MainForegroundColor}"

                                           TextWrapping="Wrap" Margin="0,0,0,12">

                                    All three editions (Home, Home Single Language, Pro) will be

                                    extracted, modified (bloatware removed, tweaks applied, ASYS setup

                                    injected), and repackaged into a single ISO. Your autounattend.xml

                                    and setup scripts are included automatically. This process may take

                                    20-40 minutes depending on your hardware.

                                </TextBlock>

                                <Button Name="WPFWin11ISOModifyButton"

                                        Content="Run Windows ISO Modification and Creator"

                                        HorizontalAlignment="Left"

                                        Width="Auto" Padding="12,0"

                                        Height="{DynamicResource ButtonHeight}"/>

                            </StackPanel>



                            <!-- ????????? STEP 4 : Output Options ??????????????????????????????????????????????????????????????????????????? -->

                            <StackPanel Name="WPFWin11ISOOutputSection"

                                        Margin="5"

                                        Visibility="Collapsed"

                                        HorizontalAlignment="Left" MinWidth="{DynamicResource ButtonWidth}">

                                <!-- Header row: title + Clean & Reset button -->

                                <Grid Margin="0,0,0,12">

                                    <Grid.ColumnDefinitions>

                                        <ColumnDefinition Width="*"/>

                                        <ColumnDefinition Width="Auto"/>

                                    </Grid.ColumnDefinitions>

                                    <TextBlock Grid.Column="0" FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                               Foreground="{DynamicResource MainForegroundColor}"

                                               VerticalAlignment="Center">

                                        Step 4 - Output: What would you like to do with the modified image?

                                    </TextBlock>

                                    <Button Grid.Column="1"

                                            Name="WPFWin11ISOCleanResetButton"

                                            Content="Clean &amp; Reset"

                                            Foreground="OrangeRed"

                                            Width="Auto" Padding="12,0"

                                            Height="{DynamicResource ButtonHeight}"

                                            ToolTip="Delete the temporary working directory and reset the interface back to Step 1"

                                            Margin="12,0,0,0"/>

                                </Grid>



                                <!-- ?????? Choice prompt buttons ?????? -->

                                <Grid Margin="0,0,0,12">

                                    <Grid.ColumnDefinitions>

                                        <ColumnDefinition Width="*"/>

                                        <ColumnDefinition Width="16"/>

                                        <ColumnDefinition Width="*"/>

                                    </Grid.ColumnDefinitions>

                                    <Button Grid.Column="0"

                                            Name="WPFWin11ISOChooseISOButton"

                                            Content="Save as an ISO File"

                                            HorizontalAlignment="Stretch"

                                            Width="Auto" Padding="12,0"

                                            Height="{DynamicResource ButtonHeight}"/>

                                    <Button Grid.Column="2"

                                            Name="WPFWin11ISOChooseUSBButton"

                                            Content="Write Directly to a USB Drive (ERASES DRIVE)"

                                            Foreground="OrangeRed"

                                            HorizontalAlignment="Stretch"

                                            Width="Auto" Padding="12,0"

                                            Height="{DynamicResource ButtonHeight}"/>

                                </Grid>



                                <!-- ?????? USB write sub-panel (revealed on USB choice) ?????? -->

                                <Border Name="WPFWin11ISOOptionUSB"

                                        Style="{StaticResource BorderStyle}"

                                        Visibility="Collapsed"

                                        Margin="0,8,0,0">

                                    <StackPanel>

                                        <TextBlock FontSize="{DynamicResource FontSize}"

                                                   Foreground="{DynamicResource MainForegroundColor}"

                                                   TextWrapping="Wrap" Margin="0,0,0,8">

                                            <Run FontWeight="Bold" Foreground="OrangeRed">!! All data on the selected USB drive will be permanently erased !!</Run>

                                            <LineBreak/>

                                            Select a removable USB drive below, then click Erase &amp; Write.

                                        </TextBlock>

                                        <!-- USB drive selector row -->

                                        <Grid Margin="0,0,0,8">

                                            <Grid.ColumnDefinitions>

                                                <ColumnDefinition Width="*"/>

                                                <ColumnDefinition Width="Auto"/>

                                            </Grid.ColumnDefinitions>

                                            <ComboBox Grid.Column="0"

                                                      Name="WPFWin11ISOUSBDriveComboBox"

                                                      Foreground="{DynamicResource MainForegroundColor}"

                                                      Background="{DynamicResource MainBackgroundColor}"

                                                      VerticalAlignment="Center"

                                                      Margin="0,0,6,0"/>

                                            <Button Grid.Column="1"

                                                    Name="WPFWin11ISORefreshUSBButton"

                                                    Content="Refresh"

                                                    Width="Auto" Padding="8,0"

                                                    Height="{DynamicResource ButtonHeight}"/>

                                        </Grid>

                                        <Button Name="WPFWin11ISOWriteUSBButton"

                                                Content="Erase &amp; Write to USB"

                                                Foreground="OrangeRed"

                                                HorizontalAlignment="Stretch"

                                                Width="Auto" Padding="12,0"

                                                Height="{DynamicResource ButtonHeight}"

                                                Margin="0,0,0,10"/>

                                    </StackPanel>

                                </Border>

                            </StackPanel>



                    </StackPanel>
                    </ScrollViewer>



                    <GridSplitter Grid.Row="1"
                                  Height="8"
                                  HorizontalAlignment="Stretch"
                                  VerticalAlignment="Center"
                                  ResizeDirection="Rows"
                                  ResizeBehavior="PreviousAndNext"
                                  Background="{DynamicResource BorderColor}"
                                  ShowsPreview="True"
                                  Cursor="SizeNS"
                                  ToolTip="Drag to resize the status log"/>

                    <!-- Status Log (fills remaining height) -->

                    <Grid Grid.Row="2" Margin="5">

                        <Grid.RowDefinitions>

                            <RowDefinition Height="Auto"/>

                            <RowDefinition Height="*"/>

                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0"

                                   FontSize="{DynamicResource FontSize}" FontWeight="Bold"

                                   Foreground="{DynamicResource MainForegroundColor}"

                                   Margin="0,0,0,4">

                            Status Log

                        </TextBlock>

                        <TextBox Grid.Row="1"

                                 Name="WPFWin11ISOStatusLog"

                                 IsReadOnly="True"

                                 TextWrapping="Wrap"

                                 VerticalScrollBarVisibility="Visible"

                                 VerticalAlignment="Stretch"

                                 MinHeight="140"

                                 Padding="6"

                                 Background="{DynamicResource MainBackgroundColor}"

                                 Foreground="{DynamicResource MainForegroundColor}"

                                 BorderBrush="{DynamicResource BorderColor}"

                                 BorderThickness="1"

                                 Text="Ready. Please select a Windows 10 or Windows 11 ISO to begin."/>

                    </Grid>



                </Grid>

            </TabItem>

        </TabControl>

    </Grid>

</Window>


'@
$WinUtilAutounattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
        <WillShowUI>Never</WillShowUI>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UILanguageFallback>en-US</UILanguageFallback>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>3</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>4</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>5</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>6</Order>
          <Path>reg add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>7</Order>
          <Path>reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>User</FullName>
        <Organization>Advanced Systems</Organization>
        <ProductKey>
          <Key></Key>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
      </UserData>
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>EFI</Type>
              <Size>300</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>MSR</Type>
              <Size>16</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Label>System</Label>
              <Format>FAT32</Format>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order>
              <PartitionID>3</PartitionID>
              <Label>Windows</Label>
              <Format>NTFS</Format>
              <Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <ComputerName>%%COMPUTERNAME%%</ComputerName>
      <TimeZone>Singapore Standard Time</TimeZone>
    </component>
    <component name="Microsoft-Windows-Security-SPP-UX"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <SkipAutoActivation>true</SkipAutoActivation>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UILanguageFallback>en-US</UILanguageFallback>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>TECH</Name>
            <DisplayName>TECH</DisplayName>
            <Description>Advanced Systems Administrator</Description>
            <Group>Administrators</Group>
            <Password>
              <Value>MQAyAFAAYQBzAHMAdwBvAHIAZAA=</Value>
              <PlainText>false</PlainText>
            </Password>
          </LocalAccount>
          <LocalAccount wcm:action="add">
            <Name>%%USERNAME%%</Name>
            <DisplayName>%%USERNAME%%</DisplayName>
            <Description>Main User Account</Description>
            <Group>Administrators</Group>
            <Password>
              <Value>QQBTAFkAUwBQAGEAcwBzAHcAbwByAGQA</Value>
              <PlainText>false</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>%%USERNAME%%</Username>
        <LogonCount>99</LogonCount>
        <Password>
          <Value>QQBTAFkAUwBQAGEAcwBzAHcAbwByAGQA</Value>
          <PlainText>false</PlainText>
        </Password>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Setup\master.ps1"</CommandLine>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
'@
# Create enums

Add-Type @"

public enum PackageManagers

{

    Winget,

    Choco

}

"@



# SPDX-License-Identifier: MIT

# Set the maximum number of threads for the RunspacePool to the number of threads on the machine

$maxthreads = [int]$env:NUMBER_OF_PROCESSORS



# Create a new session state for parsing variables into our runspace

$hashVars = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync',$sync,$Null

$debugVar = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DebugPreference',$DebugPreference,$Null

$uiVar = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'PARAM_NOUI',$PARAM_NOUI,$Null

$offlineVar = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'PARAM_OFFLINE',$PARAM_OFFLINE,$Null

$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()



# Add the variable to the session state

$InitialSessionState.Variables.Add($hashVars)

$InitialSessionState.Variables.Add($debugVar)

$InitialSessionState.Variables.Add($uiVar)

$InitialSessionState.Variables.Add($offlineVar)



# Get every private function and add them to the session state (Win11ISO* = ISO tab log + download helpers used inside runspaces)

$functions = Get-ChildItem function:\ | Where-Object { $_.Name -imatch 'clark|WPF|Win11ISO' }

foreach ($function in $functions) {

    $functionDefinition = Get-Content function:\$($function.name)

    $functionEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $($function.name), $functionDefinition



    $initialSessionState.Commands.Add($functionEntry)

}



# Create the runspace pool

$sync.runspace = [runspacefactory]::CreateRunspacePool(

    1,                      # Minimum thread count

    $maxthreads,            # Maximum thread count

    $InitialSessionState,   # Initial session state

    $Host                   # Machine to create runspaces on

)



# Open the RunspacePool instance

$sync.runspace.Open()



# Create classes for different exceptions



class WingetFailedInstall : Exception {

    [string]$additionalData

    WingetFailedInstall($Message) : base($Message) {}

}



class ChocoFailedInstall : Exception {

    [string]$additionalData

    ChocoFailedInstall($Message) : base($Message) {}

}



class GenericException : Exception {

    [string]$additionalData

    GenericException($Message) : base($Message) {}

}



# Load the configuration files



$sync.configs.applicationsHashtable = @{}

$sync.configs.applications.PSObject.Properties | ForEach-Object {

    $sync.configs.applicationsHashtable[$_.Name] = $_.Value

}



Set-Preferences



if ($sync.preferences.activeprofile -and -not $PARAM_CONFIG) {

    try {

        Import-ClarkProfile -Name $sync.preferences.activeprofile

        Write-Host "Loaded active profile '$($sync.preferences.activeprofile)'"

    } catch {

        Write-Warning "Unable to load active profile '$($sync.preferences.activeprofile)': $($_.Exception.Message)"

    }

}



if ($PARAM_NOUI) {

    Show-ASYSLogo

    if ($PARAM_CONFIG -and -not [string]::IsNullOrWhiteSpace($PARAM_CONFIG)) {

        Write-Host "Running config file tasks..."

        Invoke-WPFImpex -type "import" -Config $PARAM_CONFIG

        if ($PARAM_RUN) {

            Invoke-ClarkAutoRun

        } else {

            Write-Host "Did you forget to add '--Run'?";

        }

        $sync.runspace.Dispose()

        $sync.runspace.Close()

        [System.GC]::Collect()

        Stop-Transcript

        exit 1

    } else {

        Write-Host "Cannot automatically run without a config file provided."

        $sync.runspace.Dispose()

        $sync.runspace.Close()

        [System.GC]::Collect()

        Stop-Transcript

        exit 1

    }

}



$inputXML = $inputXML `
    -replace 'mc:Ignorable="d"', '' `
    -replace '\s+x:Class="[^"]*"', '' `
    -replace "x:N", 'N' `
    -replace '^<Win.*', '<Window'



[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')

[xml]$XAML = $inputXML



# Read the XAML file

$readerOperationSuccessful = $false # There's more cases of failure then success.

$reader = (New-Object System.Xml.XmlNodeReader $xaml)

try {

    $sync["Form"] = [Windows.Markup.XamlReader]::Load( $reader )

    $readerOperationSuccessful = $true

} catch [System.Management.Automation.MethodInvocationException] {

    Write-Host "We ran into a problem with the XAML code.  Check the syntax for this control..." -ForegroundColor Red

    Write-Host $error[0].Exception.Message -ForegroundColor Red



    If ($error[0].Exception.Message -like "*button*") {

        write-Host "Ensure your &lt;button in the `$inputXML does NOT have a Click=ButtonClick property.  PS can't handle this`n`n`n`n" -ForegroundColor Red

    }

} catch {

    Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed." -ForegroundColor Red

}



if (-NOT ($readerOperationSuccessful)) {

    Write-Host "Failed to parse xaml content using Windows.Markup.XamlReader's Load Method." -ForegroundColor Red

    Write-Host "Quitting clark..." -ForegroundColor Red

    $sync.runspace.Dispose()

    $sync.runspace.Close()

    [System.GC]::Collect()

    exit 1

}



# Setup the Window to follow listen for windows Theme Change events and update the clark theme

# throttle logic needed, because windows seems to send more than one theme change event per change

$lastThemeChangeTime = [datetime]::MinValue

$debounceInterval = [timespan]::FromSeconds(2)

$sync.Form.Add_Loaded({

    $interopHelper = New-Object System.Windows.Interop.WindowInteropHelper $sync.Form

    $hwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($interopHelper.Handle)

    $hwndSource.AddHook({

        param (

            [System.IntPtr]$hwnd,

            [int]$msg,

            [System.IntPtr]$wParam,

            [System.IntPtr]$lParam,

            [ref]$handled

        )

        # Check for the Event WM_SETTINGCHANGE (0x1001A) and validate that Button shows the icon for "Auto" => [char]0xF08C

        if (($msg -eq 0x001A) -and $sync.ThemeButton.Content -eq [char]0xF08C) {

            $currentTime = [datetime]::Now

            if ($currentTime - $lastThemeChangeTime -gt $debounceInterval) {

                Invoke-ClarkThemeChange -theme "Auto"

                $script:lastThemeChangeTime = $currentTime

                $handled = $true

            }

        }

        return 0

    })

})



Invoke-ClarkThemeChange -theme $sync.preferences.theme





# Now call the function with the final merged config

Invoke-WPFUIElements -configVariable $sync.configs.appnavigation -targetGridName "appscategory" -columncount 1

Initialize-WPFUI -targetGridName "appscategory"



Initialize-WPFUI -targetGridName "appspanel"



Invoke-WPFUIElements -configVariable $sync.configs.tweaks -targetGridName "tweakspanel" -columncount 2



Invoke-WPFUIElements -configVariable $sync.configs.feature -targetGridName "featurespanel" -columncount 2



Invoke-WPFUIElements -configVariable $sync.configs.profiles -targetGridName "profilespanel" -columncount 1



if ($sync.configs.tools) {

    Invoke-WPFUIElements -configVariable $sync.configs.tools -targetGridName "toolspanel" -columncount 2

}



# Future implementation: Add Windows Version to updates panel

#Invoke-WPFUIElements -configVariable $sync.configs.updates -targetGridName "updatespanel" -columncount 1



#===========================================================================

# Store Form Objects In PowerShell

#===========================================================================



$xaml.SelectNodes("//*[@Name]") | ForEach-Object {$sync["$("$($psitem.Name)")"] = $sync["Form"].FindName($psitem.Name)}



#Persist Package Manager preference across clark restarts

$sync.ChocoRadioButton.Add_Checked({

    $sync.preferences.packagemanager = [PackageManagers]::Choco

    Set-Preferences -save

})

$sync.WingetRadioButton.Add_Checked({

    $sync.preferences.packagemanager = [PackageManagers]::Winget

    Set-Preferences -save

})



switch ($sync.preferences.packagemanager) {

    "Choco" {$sync.ChocoRadioButton.IsChecked = $true; break}

    "Winget" {$sync.WingetRadioButton.IsChecked = $true; break}

}



$sync.keys | ForEach-Object {

    if($sync.$psitem) {

        if($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "ToggleButton") {

            $sync["$psitem"].Add_Click({

                [System.Object]$Sender = $args[0]

                Invoke-WPFButton $Sender.name

            })

        }



        if($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "Button") {

            # ISO Creator tab: dedicated Add_Click handlers are registered later; skip generic Invoke-WPFButton.

            if ($psitem -notmatch '^WPFWin.*ISO') {

                $sync["$psitem"].Add_Click({

                    [System.Object]$Sender = $args[0]

                    Invoke-WPFButton $Sender.name

                })

            }

        }



        if ($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "TextBlock") {

            if ($sync["$psitem"].Name.EndsWith("Link")) {

                $sync["$psitem"].Add_MouseUp({

                    [System.Object]$Sender = $args[0]

                    $tag = $Sender.Tag

                    if ($tag -and ($tag.PSObject.Properties.Name -contains 'ItemTitle')) {

                        Show-ASYSItemInfoPopup -ItemTitle $(if ($tag.ItemTitle) { $tag.ItemTitle } else { "Information" }) -Description $tag.Description -Link $tag.Link

                    } elseif ($Sender.ToolTip) {

                        Show-ASYSItemInfoPopup -ItemTitle "Information" -Description "$($Sender.ToolTip)" -Link $null

                    }

                })

            }



        }

    }

}



#===========================================================================

# Setup background config

#===========================================================================



# Load computer information in the background

Invoke-WPFRunspace -ScriptBlock {

    try {

        $ProgressPreference = "SilentlyContinue"

        $sync.ConfigLoaded = $False

        $sync.ComputerInfo = Get-ComputerInfo

        $sync.ConfigLoaded = $True

    }

    finally{

        $ProgressPreference = $oldProgressPreference

    }



} | Out-Null



#===========================================================================

# Setup and Show the Form

#===========================================================================



# Print the logo

Show-ASYSLogo



# Progress bar in taskbaritem > Set-ClarkProgressbar

$sync["Form"].TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo

Set-ClarkTaskbaritem -state "None"



# Set the titlebar

$sync["Form"].title = $sync["Form"].title + " " + $sync.version

# Set the commands that will run when the form is closed

$sync["Form"].Add_Closing({

    $sync.runspace.Dispose()

    $sync.runspace.Close()

    [System.GC]::Collect()

})



# Attach the event handler to the Click event

$sync.SearchBarClearButton.Add_Click({

    $sync.SearchBar.Text = ""

    $sync.SearchBarClearButton.Visibility = "Collapsed"



    # Focus the search bar after clearing the text

    $sync.SearchBar.Focus()

    $sync.SearchBar.SelectAll()

})



# add some shortcuts for people that don't like clicking

$commonKeyEvents = {

    # Prevent shortcuts from executing if a process is already running

    if ($sync.ProcessRunning -eq $true) {

        return

    }



    # Handle key presses of single keys

    switch ($_.Key) {

        "Escape" { $sync.SearchBar.Text = "" }

    }

    # Handle Alt key combinations for navigation

    if ($_.KeyboardDevice.Modifiers -eq "Alt") {

        $keyEventArgs = $_

        switch ($_.SystemKey) {

            "I" { Invoke-WPFButton "WPFTab1BT"; $keyEventArgs.Handled = $true } # Navigate to Install tab and suppress Windows Warning Sound

            "T" { Invoke-WPFButton "WPFTab2BT"; $keyEventArgs.Handled = $true } # Navigate to Tweaks tab

            "C" { Invoke-WPFButton "WPFTab3BT"; $keyEventArgs.Handled = $true } # Navigate to Config tab

            "U" { Invoke-WPFButton "WPFTab4BT"; $keyEventArgs.Handled = $true } # Navigate to Updates tab

            "P" { Invoke-WPFButton "WPFTab6BT"; $keyEventArgs.Handled = $true } # Navigate to Profiles tab

            "W" { Invoke-WPFButton "WPFTab5BT"; $keyEventArgs.Handled = $true } # Navigate to Win11ISO tab

        }

    }

    # Handle Ctrl key combinations for specific actions

    if ($_.KeyboardDevice.Modifiers -eq "Ctrl") {

        switch ($_.Key) {

            "F" { $sync.SearchBar.Focus() } # Focus on the search bar

            "Q" { $this.Close() } # Close the application

        }

    }

}

$sync["Form"].Add_PreViewKeyDown($commonKeyEvents)



$sync["Form"].Add_MouseLeftButtonDown({

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings", "Theme", "FontScaling")

    # When native window chrome is enabled, dragging should be handled by the title bar.
    if ($sync["Form"].WindowStyle -eq [System.Windows.WindowStyle]::None) {
        $sync["Form"].DragMove()
    }

})



$sync["Form"].Add_MouseDoubleClick({

    if ($sync["Form"].WindowStyle -ne [System.Windows.WindowStyle]::None) {
        return
    }

    if ($_.OriginalSource.Name -eq "NavDockPanel" -or

        $_.OriginalSource.Name -eq "GridBesideNavDockPanel") {

            if ($sync["Form"].WindowState -eq [Windows.WindowState]::Normal) {

                $sync["Form"].WindowState = [Windows.WindowState]::Maximized

            } else {

                $sync["Form"].WindowState = [Windows.WindowState]::Normal

            }

    }

})



$sync["Form"].Add_StateChanged({

    if ($null -eq $sync.WPFMaximizeButton) { return }

    if ($sync.Form.WindowState -eq [Windows.WindowState]::Maximized) {

        $sync.WPFMaximizeButton.Content = [char]0xE923

        $sync.WPFMaximizeButton.ToolTip = "Restore down"

    } else {

        $sync.WPFMaximizeButton.Content = [char]0xE922

        $sync.WPFMaximizeButton.ToolTip = "Maximize"

    }

})



$sync["Form"].Add_Deactivated({

    Write-Debug "clark lost focus"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings", "Theme", "FontScaling")

})



$sync["Form"].Add_ContentRendered({

    Invoke-ClarkFontScaling -ScaleFactor 1.25

    # Load the Windows Forms assembly

    Add-Type -AssemblyName System.Windows.Forms

    $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen

    # Check if the primary screen is found

    if ($primaryScreen) {

        # Use working area so the window stays fully visible with taskbar/title bar.
        $workArea = $primaryScreen.WorkingArea
        $screenWidth = $workArea.Width
        $screenHeight = $workArea.Height



        # Print the screen size

        Write-Debug "Primary Monitor Width: $screenWidth pixels"

        Write-Debug "Primary Monitor Height: $screenHeight pixels"



        # Compare with the primary monitor size

        if ($sync.Form.ActualWidth -gt $screenWidth -or $sync.Form.ActualHeight -gt $screenHeight) {

            Write-Debug "The specified width and/or height is greater than the primary monitor size."

            $sync.Form.Left = $workArea.Left
            $sync.Form.Top = $workArea.Top

            $sync.Form.Width = $screenWidth

            $sync.Form.Height = $screenHeight

        } else {

            Write-Debug "The specified width and height are within the primary monitor size limits."

        }

    } else {

        Write-Debug "Unable to retrieve information about the primary monitor."

    }



    if ($PARAM_OFFLINE) {

        # Show offline banner

        $sync.WPFOfflineBanner.Visibility = [System.Windows.Visibility]::Visible



        # Disable the install tab

        $sync.WPFTab1BT.IsEnabled = $false

        $sync.WPFTab1BT.Opacity = 0.5

        $sync.WPFTab1BT.ToolTip = "Internet connection required for installing applications"



        # Disable install-related buttons

        $sync.WPFInstall.IsEnabled = $false

        $sync.WPFUninstall.IsEnabled = $false

        $sync.WPFInstallUpgrade.IsEnabled = $false

        $sync.WPFGetInstalled.IsEnabled = $false



        # Show offline indicator

        Write-Host "Offline mode detected - Install tab disabled" -ForegroundColor Yellow



        # Optionally switch to a different tab if install tab was going to be default

        Invoke-WPFTab "WPFTab2BT"  # Switch to Tweaks tab instead

    } else {

        # Online - ensure install tab is enabled

        $sync.WPFTab1BT.IsEnabled = $true

        $sync.WPFTab1BT.Opacity = 1.0

        $sync.WPFTab1BT.ToolTip = $null

        Invoke-WPFTab "WPFTab1BT"  # Default to install tab

    }



    if ($sync["WPFWinISODownloadProductComboBox"]) {

        $sync["WPFWinISODownloadProductComboBox"].Items.Clear()

        [void]$sync["WPFWinISODownloadProductComboBox"].Items.Add("Windows 11")

        [void]$sync["WPFWinISODownloadProductComboBox"].Items.Add("Windows 10")

        $sync["WPFWinISODownloadProductComboBox"].SelectedIndex = 0

        Set-ClarkISODirectDownloadVersions
        Set-ClarkISODirectDownloadLanguages

    }



    $sync["Form"].Focus()



   if ($PARAM_CONFIG -and -not [string]::IsNullOrWhiteSpace($PARAM_CONFIG)) {

        Write-Host "Running config file tasks..."

        Invoke-WPFImpex -type "import" -Config $PARAM_CONFIG

        if ($PARAM_RUN) {

            Invoke-ClarkAutoRun

        }

    }



})



# The SearchBarTimer is used to delay the search operation until the user has stopped typing for a short period

# This prevents the ui from stuttering when the user types quickly as it dosnt need to update the ui for every keystroke



$searchBarTimer = New-Object System.Windows.Threading.DispatcherTimer

$searchBarTimer.Interval = [TimeSpan]::FromMilliseconds(300)

$searchBarTimer.IsEnabled = $false



$searchBarTimer.add_Tick({

    $searchBarTimer.Stop()

    switch ($sync.currentTab) {

        "Install" {

            Find-AppsByNameOrDescription -SearchString $sync.SearchBar.Text

        }

        "Tweaks" {

            Find-TweaksByNameOrDescription -SearchString $sync.SearchBar.Text

        }

    }

})

$sync["SearchBar"].Add_TextChanged({

    if ($sync.SearchBar.Text -ne "") {

        $sync.SearchBarClearButton.Visibility = "Visible"

    } else {

        $sync.SearchBarClearButton.Visibility = "Collapsed"

    }

    if ($searchBarTimer.IsEnabled) {

        $searchBarTimer.Stop()

    }

    $searchBarTimer.Start()

})



$sync["Form"].Add_Loaded({

    param($e)

    $sync.Form.MinWidth = "900"

    $sync["Form"].MaxWidth = [Double]::PositiveInfinity

    $sync["Form"].MaxHeight = [Double]::PositiveInfinity

})



$NavLogoPanel = $sync["Form"].FindName("NavLogoPanel")

$navBrand = New-Object Windows.Controls.TextBlock

$navBrand.Text = "clark"

$navBrand.FontStyle = [Windows.FontStyles]::Italic

$navBrand.VerticalAlignment = [Windows.VerticalAlignment]::Center

$navBrand.SetResourceReference([Windows.Controls.Control]::FontSizeProperty, "HeaderFontSize")

$navBrand.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, "MainForegroundColor")

$navBrand.Margin = New-Object Windows.Thickness(2, 0, 0, 0)

$NavLogoPanel.Children.Add($navBrand) | Out-Null





if (Test-Path "$clarkdir\logo.ico") {

    $sync["logorender"] = "$clarkdir\logo.ico"

} else {

    $sync["logorender"] = (Invoke-ClarkAssets -Type "Logo" -Size 90 -Render)

}

$sync["checkmarkrender"] = (Invoke-ClarkAssets -Type "checkmark" -Size 512 -Render)

$sync["warningrender"] = (Invoke-ClarkAssets -Type "warning" -Size 512 -Render)



Set-ClarkTaskbaritem -overlay "logo"



$sync["Form"].Add_Activated({

    Set-ClarkTaskbaritem -overlay "logo"

})



$sync["ThemeButton"].Add_Click({

    Write-Debug "ThemeButton clicked"

    Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Hide"; "Theme" = "Toggle"; "FontScaling" = "Hide" }

})

$sync["AutoThemeMenuItem"].Add_Click({

    Write-Debug "About clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Theme")

    Invoke-ClarkThemeChange -theme "Auto"

})

$sync["DarkThemeMenuItem"].Add_Click({

    Write-Debug "Dark Theme clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Theme")

    Invoke-ClarkThemeChange -theme "Dark"

})

$sync["LightThemeMenuItem"].Add_Click({

    Write-Debug "Light Theme clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Theme")

    Invoke-ClarkThemeChange -theme "Light"

})



$sync["SettingsButton"].Add_Click({

    Write-Debug "SettingsButton clicked"

    Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Toggle"; "Theme" = "Hide"; "FontScaling" = "Hide" }

})

$sync["ImportMenuItem"].Add_Click({

    Write-Debug "Import clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")

    Invoke-WPFImpex -type "import"

})

$sync["ExportMenuItem"].Add_Click({

    Write-Debug "Export clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")

    Invoke-WPFImpex -type "export"

})

$sync["AboutMenuItem"].Add_Click({

    Write-Debug "About clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")



    $authorInfo = @"

Author   : <a href="https://github.com/ChrisTitusTech">@ChrisTitusTech</a>

UI       : <a href="https://github.com/MyDrift-user">@MyDrift-user</a>, <a href="https://github.com/Marterich">@Marterich</a>

Runspace : <a href="https://github.com/DeveloperDurp">@DeveloperDurp</a>, <a href="https://github.com/Marterich">@Marterich</a>

GitHub   : <a href="https://github.com/ChrisTitusTech/clark">ChrisTitusTech/clark</a>

Version  : <a href="https://github.com/ChrisTitusTech/clark/releases/tag/$($sync.version)">$($sync.version)</a>

"@

    Show-CustomDialog -Title "About" -Message $authorInfo

})

$sync["DocumentationMenuItem"].Add_Click({

    Write-Debug "Documentation clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")

    Start-Process "https://clark.christitus.com/"

})

$sync["SponsorMenuItem"].Add_Click({

    Write-Debug "Sponsors clicked"

    Invoke-WPFPopup -Action "Hide" -Popups @("Settings")



    $authorInfo = @"

<a href="https://github.com/sponsors/ChrisTitusTech">Current sponsors for ChrisTitusTech:</a>

"@

    $authorInfo += "`n"

    try {

        $sponsors = Invoke-ClarkSponsors

        foreach ($sponsor in $sponsors) {

            $authorInfo += "<a href=`"https://github.com/sponsors/ChrisTitusTech`">$sponsor</a>`n"

        }

    } catch {

        $authorInfo += "An error occurred while fetching or processing the sponsors: $_`n"

    }

    Show-CustomDialog -Title "Sponsors" -Message $authorInfo -EnableScroll $true

})



# Font Scaling Event Handlers

$sync["FontScalingButton"].Add_Click({

    Write-Debug "FontScalingButton clicked"

    Invoke-WPFPopup -PopupActionTable @{ "Settings" = "Hide"; "Theme" = "Hide"; "FontScaling" = "Toggle" }

})



$sync["FontScalingSlider"].Add_ValueChanged({

    param($slider)

    $percentage = [math]::Round($slider.Value * 100)

    $sync.FontScalingValue.Text = "$percentage%"

})



$sync["FontScalingResetButton"].Add_Click({

    Write-Debug "FontScalingResetButton clicked"

    $sync.FontScalingSlider.Value = 1.25

    $sync.FontScalingValue.Text = "125%"

})



$sync["FontScalingApplyButton"].Add_Click({

    Write-Debug "FontScalingApplyButton clicked"

    $scaleFactor = $sync.FontScalingSlider.Value

    Invoke-ClarkFontScaling -ScaleFactor $scaleFactor

    Invoke-WPFPopup -Action "Hide" -Popups @("FontScaling")

})



# ?????? Win11ISO Tab button handlers ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????



$sync["WPFTab5BT"].Add_Click({

    $sync["Form"].Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ Invoke-ClarkISOCheckExistingWork }) | Out-Null

})



$sync["WPFWin11ISOBrowseButton"].Add_Click({

    Write-Debug "WPFWin11ISOBrowseButton clicked"

    Invoke-ClarkISOBrowse

})



$sync["WPFWin11ISODownloadLink"].Add_Click({

    Write-Debug "WPFWin11ISODownloadLink clicked"

    Start-Process "https://www.microsoft.com/software-download/windows11"

})



$sync["WPFWin10ISODownloadLink"].Add_Click({

    Write-Debug "WPFWin10ISODownloadLink clicked"

    Start-Process "https://www.microsoft.com/software-download/windows10"

})



$sync["WPFWinISODownloadProductComboBox"].Add_SelectionChanged({

    Set-ClarkISODirectDownloadVersions

})



$sync["WPFWinISODownloadDirectButton"].Add_Click({

    Write-Debug "WPFWinISODownloadDirectButton clicked"

    Invoke-ClarkISODirectDownload

})



$sync["WPFWinISODownloadPauseButton"].Add_Click({

    Write-Debug "WPFWinISODownloadPauseButton clicked"

    Invoke-ClarkISODirectDownloadPauseToggle

})



$sync["WPFWinISODownloadStopButton"].Add_Click({

    Write-Debug "WPFWinISODownloadStopButton clicked"

    Invoke-ClarkISODirectDownloadStop

})



$sync["WPFWin11ISOMountButton"].Add_Click({

    Write-Debug "WPFWin11ISOMountButton clicked"

    Invoke-ClarkISOMountAndVerify

})



$sync["WPFWin11ISOModifyButton"].Add_Click({

    Write-Debug "WPFWin11ISOModifyButton clicked"

    Invoke-ClarkISOModify

})



$sync["WPFWin11ISOChooseISOButton"].Add_Click({

    Write-Debug "WPFWin11ISOChooseISOButton clicked"

    $sync["WPFWin11ISOOptionUSB"].Visibility = "Collapsed"

    Invoke-ClarkISOExport

})



$sync["WPFWin11ISOChooseUSBButton"].Add_Click({

    Write-Debug "WPFWin11ISOChooseUSBButton clicked"

    $sync["WPFWin11ISOOptionUSB"].Visibility = "Visible"

    Invoke-ClarkISORefreshUSBDrives

})



$sync["WPFWin11ISORefreshUSBButton"].Add_Click({

    Write-Debug "WPFWin11ISORefreshUSBButton clicked"

    Invoke-ClarkISORefreshUSBDrives

})



$sync["WPFWin11ISOWriteUSBButton"].Add_Click({

    Write-Debug "WPFWin11ISOWriteUSBButton clicked"

    Invoke-ClarkISOWriteUSB

})



$sync["WPFWin11ISOCleanResetButton"].Add_Click({

    Write-Debug "WPFWin11ISOCleanResetButton clicked"

    Invoke-ClarkISOCleanAndReset

})



# ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????



$sync["Form"].ShowDialog() | out-null

Stop-Transcript


