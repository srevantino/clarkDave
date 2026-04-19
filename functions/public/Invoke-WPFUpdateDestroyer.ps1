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
