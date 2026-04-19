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
    $tabButtons = Get-WinUtilVariables -Type ToggleButton | Where-Object { $_ -match '^WPFTab\d+BT$' }
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
