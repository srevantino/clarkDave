function Set-Preferences{



    param(

        [switch]$save=$false

    )



    # TODO delete this function sometime later

    function Clean-OldPrefs{

        if (Test-Path -Path "$clarkdir\LightTheme.ini") {

            $sync.preferences.theme = "Light"

            Remove-Item -Path "$clarkdir\LightTheme.ini"

        }



        if (Test-Path -Path "$clarkdir\DarkTheme.ini") {

            $sync.preferences.theme = "Dark"

            Remove-Item -Path "$clarkdir\DarkTheme.ini"

        }



        # check old prefs, if its first line has no =, then absorb it as pm

        if (Test-Path -Path $iniPath) {

            $oldPM = Get-Content $iniPath

            if ($oldPM -notlike "*=*") {

                $sync.preferences.packagemanager = $oldPM

            }

        }



        if (Test-Path -Path "$clarkdir\preferChocolatey.ini") {

            $sync.preferences.packagemanager = "Choco"

            Remove-Item -Path "$clarkdir\preferChocolatey.ini"

        }

    }



    function Save-Preferences{

        $ini = ""

        foreach($key in $sync.preferences.Keys) {

            $pref = "$($key)=$($sync.preferences.$key)"

            Write-Debug "Saving pref: $($pref)"

            $ini = $ini + $pref + "`r`n"

        }

        $ini | Out-File $iniPath

    }



    function Load-Preferences{

        Clean-OldPrefs

        if (Test-Path -Path $iniPath) {

            $iniData = Get-Content "$clarkdir\preferences.ini"

            foreach ($line in $iniData) {

                if ($line -like "*=*") {

                    $arr = $line -split "=",-2

                    $key = $arr[0] -replace "\s",""

                    $value = $arr[1] -replace "\s",""

                    Write-Debug "Preference: Key = '$($key)' Value ='$($value)'"

                    $sync.preferences.$key = $value

                }

            }

        }



        # write defaults in case preferences dont exist

        if ($null -eq $sync.preferences.theme) {

            $sync.preferences.theme = "Auto"

        }

        if ($null -eq $sync.preferences.packagemanager) {

            $sync.preferences.packagemanager = "Winget"

        }

        if ($null -eq $sync.preferences.activeprofile) {

            $sync.preferences.activeprofile = ""

        }



        # convert packagemanager to enum

        if ($sync.preferences.packagemanager -eq "Choco") {

            $sync.preferences.packagemanager = [PackageManagers]::Choco

        }

        elseif ($sync.preferences.packagemanager -eq "Winget") {

            $sync.preferences.packagemanager = [PackageManagers]::Winget

        }

    }



    $iniPath = "$clarkdir\preferences.ini"



    if ($save) {

        Save-Preferences

    } else {

        Load-Preferences

    }

}

