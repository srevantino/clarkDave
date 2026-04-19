function Convert-WinUtilProfileInputToList {
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
