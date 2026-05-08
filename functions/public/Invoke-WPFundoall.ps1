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

