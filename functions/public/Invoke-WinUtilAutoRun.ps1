function Invoke-WinUtilAutoRun {
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
                $bak = Invoke-WinUtilPreTweakRegistryExport
                foreach ($m in @($bak.Messages)) { Write-Host $m }
            } catch {
                Write-Warning "Pre-toggle registry backup failed: $($_.Exception.Message)"
            }
        }

        for ($i = 0; $i -lt $Toggles.Count; $i++) {
            Invoke-WinUtilTweaks $Toggles[$i]
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
