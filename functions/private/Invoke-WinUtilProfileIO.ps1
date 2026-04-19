function Get-WinUtilProfileDocument {
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

function Invoke-WinUtilProfileExportToPath {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )
    $doc = Get-WinUtilProfileDocument
    ($doc | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $LiteralPath -Encoding UTF8
}

function Invoke-WinUtilProfileImportFromObject {
    <#
    .SYNOPSIS
        Applies profile data from ConvertFrom-Json (flat array or schema document).
    #>
    param(
        [Parameter(Mandatory)]
        $ProfileObject
    )
    Update-WinUtilSelections -flatJson $ProfileObject
}
