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
