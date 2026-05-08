function Set-ClarkTaskbaritem {

    <#



    .SYNOPSIS

        Modifies the Taskbaritem of the WPF Form



    .PARAMETER value

        Value can be between 0 and 1, 0 being no progress done yet and 1 being fully completed

        Value does not affect item without setting the state to 'Normal', 'Error' or 'Paused'

        Set-ClarkTaskbaritem -value 0.5



    .PARAMETER state

        State can be 'None' > No progress, 'Indeterminate' > inf. loading gray, 'Normal' > Gray, 'Error' > Red, 'Paused' > Yellow

        no value needed:

        - Set-ClarkTaskbaritem -state "None"

        - Set-ClarkTaskbaritem -state "Indeterminate"

        value needed:

        - Set-ClarkTaskbaritem -state "Error"

        - Set-ClarkTaskbaritem -state "Normal"

        - Set-ClarkTaskbaritem -state "Paused"



    .PARAMETER overlay

        Overlay icon to display on the taskbar item, there are the presets 'None', 'logo' and 'checkmark' or you can specify a path/link to an image file.

        A-SYS_clark logo preset:

        - Set-ClarkTaskbaritem -overlay "logo"

        Checkmark preset:

        - Set-ClarkTaskbaritem -overlay "checkmark"

        Warning preset:

        - Set-ClarkTaskbaritem -overlay "warning"

        No overlay:

        - Set-ClarkTaskbaritem -overlay "None"

        Custom icon (needs to be supported by WPF):

        - Set-ClarkTaskbaritem -overlay "C:\path\to\icon.png"



    .PARAMETER description

        Description to display on the taskbar item preview

        Set-ClarkTaskbaritem -description "This is a description"

    #>

    param (

        [string]$state,

        [double]$value,

        [string]$overlay,

        [string]$description

    )



    if ($value) {

        $sync["Form"].taskbarItemInfo.ProgressValue = $value

    }



    if ($state) {

        switch ($state) {

            'None' { $sync["Form"].taskbarItemInfo.ProgressState = "None" }

            'Indeterminate' { $sync["Form"].taskbarItemInfo.ProgressState = "Indeterminate" }

            'Normal' { $sync["Form"].taskbarItemInfo.ProgressState = "Normal" }

            'Error' { $sync["Form"].taskbarItemInfo.ProgressState = "Error" }

            'Paused' { $sync["Form"].taskbarItemInfo.ProgressState = "Paused" }

            default { throw "[Set-ClarkTaskbarItem] Invalid state" }

        }

    }



    if ($overlay) {

        switch ($overlay) {

            'logo' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["logorender"]

            }

            'checkmark' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["checkmarkrender"]

            }

            'warning' {

                $sync["Form"].taskbarItemInfo.Overlay = $sync["warningrender"]

            }

            'None' {

                $sync["Form"].taskbarItemInfo.Overlay = $null

            }

            default {

                if (Test-Path $overlay) {

                    $sync["Form"].taskbarItemInfo.Overlay = $overlay

                }

            }

        }

    }



    if ($description) {

        $sync["Form"].taskbarItemInfo.Description = $description

    }

}

