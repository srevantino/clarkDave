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
