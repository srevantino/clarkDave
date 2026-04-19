function Invoke-WinUtilTweaks {
    <#

    .SYNOPSIS
        Invokes the function associated with each provided checkbox

    .PARAMETER CheckBox
        The checkbox to invoke

    .PARAMETER undo
        Indicates whether to undo the operation contained in the checkbox

    .PARAMETER KeepServiceStartup
        Indicates whether to override the startup of a service with the one given from WinUtil,
        or to keep the startup of said service, if it was changed by the user, or another program, from its default value.
    #>

    param(
        $CheckBox,
        $undo = $false,
        $KeepServiceStartup = $true
    )

    Write-Debug "Tweaks: $($CheckBox)"
    $executedAction = $false
    $tweakConfig = $sync.configs.tweaks.$CheckBox

    # Skip Windows 11-only tweaks on Windows 10 hosts.
    # This keeps imports/autoruns usable across both OS generations.
    if (-not $sync.ContainsKey("OSBuildNumber")) {
        $buildNumber = [System.Environment]::OSVersion.Version.Build
        try {
            $regBuild = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction Stop).CurrentBuildNumber
            if ($regBuild -match '^\d+$') {
                $buildNumber = [int]$regBuild
            }
        } catch {
            Write-Debug "Falling back to Environment OS build: $buildNumber"
        }
        $sync.OSBuildNumber = $buildNumber
    }

    $isWindows11OnlyTweak = $false
    if ($tweakConfig -and $tweakConfig.PSObject.Properties.Name -contains "Description") {
        $descriptionText = [string]$tweakConfig.Description
        if (
            $descriptionText -match '\[Windows\s*11\]' -or
            $descriptionText -match 'Windows 11\s+\d{2}H\d+\s+and later' -or
            $descriptionText -match 'Windows 11\s+only'
        ) {
            $isWindows11OnlyTweak = $true
        }
    }

    if ($isWindows11OnlyTweak -and [int]$sync.OSBuildNumber -lt 22000) {
        Write-Warning "Skipping $CheckBox because it requires Windows 11. Current OS build: $($sync.OSBuildNumber)."
        return
    }

    if (-not $undo) {
        Save-WinUtilRollbackSnapshot -CheckBox $CheckBox
    }

    if($undo) {
        $Values = @{
            Registry = "OriginalValue"
            ScheduledTask = "OriginalState"
            Service = "OriginalType"
            ScriptType = "UndoScript"
        }

    } else {
        $Values = @{
            Registry = "Value"
            ScheduledTask = "State"
            Service = "StartupType"
            OriginalService = "OriginalType"
            ScriptType = "InvokeScript"
        }
    }
    if($sync.configs.tweaks.$CheckBox.ScheduledTask) {
        $executedAction = $true
        $sync.configs.tweaks.$CheckBox.ScheduledTask | ForEach-Object {
            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.ScheduledTask))"
            Set-WinUtilScheduledTask -Name $psitem.Name -State $psitem.$($values.ScheduledTask)
        }
    }
    if($sync.configs.tweaks.$CheckBox.service) {
        $executedAction = $true
        Write-Debug "KeepServiceStartup is $KeepServiceStartup"
        $sync.configs.tweaks.$CheckBox.service | ForEach-Object {
            $changeservice = $true

        # The check for !($undo) is required, without it the script will throw an error for accessing unavailable member, which's the 'OriginalService' Property
            if($KeepServiceStartup -AND !($undo)) {
                try {
                    # Check if the service exists
                    $service = Get-Service -Name $psitem.Name -ErrorAction Stop
                    if(!($service.StartType.ToString() -eq $psitem.$($values.OriginalService))) {
                        Write-Debug "Service $($service.Name) was changed in the past to $($service.StartType.ToString()) from it's original type of $($psitem.$($values.OriginalService)), will not change it to $($psitem.$($values.service))"
                        $changeservice = $false
                    }
                } catch [System.ServiceProcess.ServiceNotFoundException] {
                    Write-Warning "Service $($psitem.Name) was not found."
                }
            }

            if($changeservice) {
                Write-Debug "$($psitem.Name) and state is $($psitem.$($values.service))"
                Set-WinUtilService -Name $psitem.Name -StartupType $psitem.$($values.Service)
            }
        }
    }
    if($sync.configs.tweaks.$CheckBox.registry) {
        $executedAction = $true
        $sync.configs.tweaks.$CheckBox.registry | ForEach-Object {
            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.registry))"
            if (($psitem.Path -imatch "hku") -and !(Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
                $null = (New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS)
                if (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue) {
                    Write-Debug "HKU drive created successfully."
                } else {
                    Write-Debug "Failed to create HKU drive."
                }
            }
            Set-WinUtilRegistry -Name $psitem.Name -Path $psitem.Path -Type $psitem.Type -Value $psitem.$($values.registry)
        }
    }
    if($sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {
        $executedAction = $true
        $sync.configs.tweaks.$CheckBox.$($values.ScriptType) | ForEach-Object {
            Write-Debug "$($psitem) and state is $($psitem.$($values.ScriptType))"
            $Scriptblock = [scriptblock]::Create($psitem)
            Invoke-WinUtilScript -ScriptBlock $scriptblock -Name $CheckBox
        }
    }

    if(!$undo) {
        if($sync.configs.tweaks.$CheckBox.appx) {
            $sync.configs.tweaks.$CheckBox.appx | ForEach-Object {
                Write-Debug "UNDO $($psitem.Name)"
                Remove-WinUtilAPPX -Name $psitem
            }
        }

    }

    if ($undo -and -not $executedAction) {
        Invoke-WinUtilRollbackLatest -CheckBox $CheckBox | Out-Null
    }
}
