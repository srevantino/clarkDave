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
