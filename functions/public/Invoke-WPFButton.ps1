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
        Set-WinUtilProgressBar  -label "" -percent 0
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
