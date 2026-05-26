function Invoke-ClarkISOScript {

    <#

    .SYNOPSIS

        Applies Clark modifications to a mounted Windows 10 or Windows 11 install.wim image.



    .DESCRIPTION

        Removes AppX bloatware and OneDrive, optionally injects all drivers exported from

        the running system into install.wim and boot.wim (controlled by the

        -InjectCurrentSystemDrivers switch), applies offline registry tweaks (hardware

        bypass where applicable, privacy, OOBE, telemetry, update suppression), deletes CEIP/WU

        scheduled-task definition files, and optionally writes autounattend.xml to the ISO

        root and removes the support\ folder from the ISO contents directory.



        All setup scripts embedded in the autounattend.xml <Extensions><File> nodes are

        written directly into the WIM at their target paths under C:\Windows\Setup\Scripts\

        to ensure they survive Windows Setup stripping unrecognised-namespace XML elements

        from the Panther copy of the answer file.



        Mounting/dismounting the WIM is the caller's responsibility (e.g. Invoke-ClarkISO).



    .PARAMETER ScratchDir

        Mandatory. Full path to the directory where the Windows image is currently mounted.



    .PARAMETER ISOContentsDir

        Optional. Root directory of the extracted ISO contents. When supplied,

        autounattend.xml is written here and the support\ folder is removed.



    .PARAMETER AutoUnattendXml

        Optional. Full XML content for autounattend.xml. If empty, the OOBE bypass

        file is skipped and a warning is logged.



    .PARAMETER InjectCurrentSystemDrivers

        Optional. When $true, exports all drivers from the running system and injects

        them into install.wim and boot.wim index 2 (Windows Setup PE).

        Defaults to $false.



    .PARAMETER Log

        Optional ScriptBlock for progress/status logging. Receives a single [string] argument.



    .EXAMPLE

        Invoke-ClarkISOScript -ScratchDir "C:\Temp\wim_mount"



    .EXAMPLE

        $invokeIsoArgs = @{
            ScratchDir      = $mountDir
            ISOContentsDir  = $isoRoot
            AutoUnattendXml = (Get-Content .\tools\autounattend.xml -Raw)
            Log             = { param($m) Write-Host $m }
        }
        Invoke-ClarkISOScript @invokeIsoArgs



    .NOTES

        Author  : Chris Titus @christitustech

        GitHub  : https://github.com/ChrisTitusTech

    #>

    param (

        [Parameter(Mandatory)][string]$ScratchDir,

        [string]$ISOContentsDir = "",

        [string]$AutoUnattendXml = "",

        [bool]$InjectCurrentSystemDrivers = $false,

        [string]$DriverExportPath = "",

        [scriptblock]$Log = { param($m) Write-Output $m }

    )



    $adminSID   = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    try {
        $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
    } catch {
        $adminGroup = [System.Security.Principal.NTAccount]'BUILTIN\Administrators'
        & $Log "Warning: SID translation failed, using fallback '$($adminGroup.Value)': $($_.Exception.Message)"
    }



    function Set-ISOScriptReg {

        param ([string]$path, [string]$name, [string]$type, [string]$value)

        try {

            & reg add $path /v $name /t $type /d $value /f 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                & $Log "Warning: reg add failed (exit $LASTEXITCODE): $path\$name"
            }

        } catch {

            & $Log "Error setting registry value: $_"

        }

    }



    function Remove-ISOScriptReg {

        param ([string]$path)

        try {

            & reg delete $path /f 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                & $Log "Warning: reg delete failed (exit $LASTEXITCODE): $path"
            }

        } catch {

            & $Log "Error removing registry key: $_"

        }

    }



    function Add-DriversToImage {

        param ([string]$MountPath, [string]$DriverDir, [string]$Label = "image", [scriptblock]$Logger)

        & dism /English "/image:$MountPath" /Add-Driver "/Driver:$DriverDir" /Recurse 2>&1 |

            ForEach-Object { & $Logger "  dism[$Label]: $_" }

        if ($LASTEXITCODE -ne 0) {
            & $Logger "Warning: DISM /Add-Driver for '$Label' exited with code $LASTEXITCODE. Some drivers may not have been injected."
        }

    }



    function Invoke-BootWimInject {

        param ([string]$BootWimPath, [string]$DriverDir, [scriptblock]$Logger)

        Set-ItemProperty -Path $BootWimPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue

        $mountDir = Join-Path $env:TEMP "Clark_BootMount_$(Get-Random)"

        New-Item -Path $mountDir -ItemType Directory -Force | Out-Null

        try {

            & $Logger "Mounting boot.wim (index 2) for driver injection..."

            Mount-WindowsImage -ImagePath $BootWimPath -Index 2 -Path $mountDir -ErrorAction Stop | Out-Null

            Add-DriversToImage -MountPath $mountDir -DriverDir $DriverDir -Label "boot" -Logger $Logger

            & $Logger "Saving boot.wim..."

            Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null

            & $Logger "boot.wim driver injection complete."

        } catch {

            & $Logger "Warning: boot.wim driver injection failed: $_"

            try { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null } catch {}

        } finally {

            Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue

        }

    }



    # ── 1. Remove provisioned AppX packages ──────────────────────────────────

    & $Log "Removing provisioned AppX packages..."



    $dismAppxOutput = & dism /English "/image:$ScratchDir" /Get-ProvisionedAppxPackages 2>&1
    if ($LASTEXITCODE -ne 0) {
        & $Log "Warning: DISM /Get-ProvisionedAppxPackages failed (exit code $LASTEXITCODE). AppX removal will be skipped."
    }

    $packages = $dismAppxOutput |

        ForEach-Object { if ($_ -match 'PackageName : (.*)') { $matches[1] } }



    $packagePrefixes = @(

        'Clipchamp.Clipchamp',

        'Microsoft.BingNews',

        'Microsoft.BingSearch',

        'Microsoft.BingWeather',

        'Microsoft.MicrosoftOfficeHub',

        'Microsoft.MicrosoftSolitaireCollection',

        'Microsoft.OutlookForWindows',

        'Microsoft.Paint',

        'Microsoft.PowerAutomateDesktop',

        'Microsoft.StartExperiencesApp',

        'Microsoft.Todos',

        'Microsoft.Windows.DevHome',

        'Microsoft.WindowsFeedbackHub',

        'Microsoft.WindowsSoundRecorder',

        'Microsoft.ZuneMusic',

        'MicrosoftCorporationII.QuickAssist',

        'MSTeams'

    )



    $matchedPackages = @($packages | Where-Object { $pkg = $_; $packagePrefixes | Where-Object { $pkg -like "*$_*" } })
    $appxRemoveFailures = 0
    foreach ($appxPkg in $matchedPackages) {
        & $Log "  Removing AppX: $appxPkg"
        & dism /English "/image:$ScratchDir" /Remove-ProvisionedAppxPackage "/PackageName:$appxPkg" 2>&1 | ForEach-Object { & $Log "    $_" }
        if ($LASTEXITCODE -ne 0) {
            & $Log "  Warning: failed to remove $appxPkg (DISM exit code $LASTEXITCODE)."
            $appxRemoveFailures++
        }
    }
    & $Log "AppX removal complete: $($matchedPackages.Count - $appxRemoveFailures)/$($matchedPackages.Count) succeeded."



    # ── 2. Inject current system drivers (optional) ───────────────────────────

    if ($InjectCurrentSystemDrivers) {

        $driverExportRoot = $DriverExportPath
        $ownedExport = $false

        if (-not $driverExportRoot -or -not (Test-Path $driverExportRoot)) {
            & $Log "Exporting all drivers from running system..."
            $driverExportRoot = Join-Path $env:TEMP "Clark_DriverExport_$(Get-Random)"
            New-Item -Path $driverExportRoot -ItemType Directory -Force | Out-Null
            try {
                Export-WindowsDriver -Online -Destination $driverExportRoot -ErrorAction Stop | Out-Null
            } catch {
                & $Log "Error during driver export: $($_.Exception.Message). Cleaning up temp directory."
                Remove-Item -Path $driverExportRoot -Recurse -Force -ErrorAction SilentlyContinue
                throw
            }
            if (@(Get-ChildItem -Path $driverExportRoot -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) {
                & $Log "Warning: driver export produced no files — injection may be incomplete."
            }
            $ownedExport = $true
        } else {
            & $Log "Reusing pre-exported driver cache: $driverExportRoot"
        }

        try {

            & $Log "Injecting current system drivers into install.wim..."

            Add-DriversToImage -MountPath $ScratchDir -DriverDir $driverExportRoot -Label "install" -Logger $Log

            & $Log "install.wim driver injection complete."



            if ($ISOContentsDir -and (Test-Path $ISOContentsDir)) {

                $bootWim = Join-Path $ISOContentsDir "sources\boot.wim"

                if (Test-Path $bootWim) {

                    & $Log "Injecting current system drivers into boot.wim..."

                    Invoke-BootWimInject -BootWimPath $bootWim -DriverDir $driverExportRoot -Logger $Log

                } else {

                    & $Log "Warning: boot.wim not found - skipping boot.wim driver injection."

                }

            }

        } catch {

            & $Log "Error during driver export/injection: $_"

        } finally {

            if ($ownedExport) {
                Remove-Item -Path $driverExportRoot -Recurse -Force -ErrorAction SilentlyContinue
            }

        }

    } else {

        & $Log "Driver injection skipped."

    }



    # ── 3. Remove OneDrive ────────────────────────────────────────────────────

    & $Log "Removing OneDrive..."

    $onedriveExe = "$ScratchDir\Windows\System32\OneDriveSetup.exe"
    if (Test-Path $onedriveExe) {
        & takeown /f $onedriveExe 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $Log "Warning: takeown failed for OneDriveSetup.exe (exit $LASTEXITCODE)." }
        & icacls $onedriveExe /grant "$($adminGroup.Value):(F)" /T /C 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $Log "Warning: icacls failed for OneDriveSetup.exe (exit $LASTEXITCODE)." }
        Remove-Item -Path $onedriveExe -Force -ErrorAction SilentlyContinue
    } else {
        & $Log "OneDriveSetup.exe not present — skipping."
    }



    # ── 4. Registry tweaks ────────────────────────────────────────────────────

    & $Log "Loading offline registry hives..."

    $regHiveMap = @(
        @{ Key = 'zCOMPONENTS'; File = "$ScratchDir\Windows\System32\config\COMPONENTS" }
        @{ Key = 'zDEFAULT';    File = "$ScratchDir\Windows\System32\config\default" }
        @{ Key = 'zNTUSER';     File = "$ScratchDir\Users\Default\ntuser.dat" }
        @{ Key = 'zSOFTWARE';   File = "$ScratchDir\Windows\System32\config\SOFTWARE" }
        @{ Key = 'zSYSTEM';     File = "$ScratchDir\Windows\System32\config\SYSTEM" }
    )
    $regLoadFailed = $false
    foreach ($hive in $regHiveMap) {
        if (-not (Test-Path $hive.File)) {
            & $Log "ERROR: Registry hive file not found: $($hive.File). Aborting registry tweaks."
            $regLoadFailed = $true
            break
        }
        reg load "HKLM\$($hive.Key)" $hive.File 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $Log "ERROR: Failed to load HKLM\$($hive.Key) from $($hive.File) (exit code $LASTEXITCODE). Aborting registry tweaks."
            $regLoadFailed = $true
            break
        }
        & $Log "Loaded HKLM\$($hive.Key)"
    }

    if ($regLoadFailed) {
        & $Log "WARNING: Skipping registry tweaks due to hive load failure. Unloading any hives that were loaded..."
        foreach ($h in $regHiveMap) {
            reg unload "HKLM\$($h.Key)" 2>&1 | Out-Null
        }
    } else {

    & $Log "Bypassing system requirements..."

    Set-ISOScriptReg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV1' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache'  'SV2' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck'   'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck'       'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSYSTEM\Setup\MoSetup'   'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'



    & $Log "Disabling sponsored apps..."

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled'  'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled'     'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled'  'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed'      'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled'    'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled'          'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled'    'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\MRT'           'DontOfferThroughWUAU' 'REG_DWORD' '1'

    Remove-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'

    Remove-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent'       'REG_DWORD' '1'



    & $Log "Enabling local accounts on OOBE..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'



    if ($AutoUnattendXml) {

        try {
            # Normalize potential BOM/leading whitespace so XML declaration stays first.
            $normalizedAutoUnattendXml = $AutoUnattendXml.TrimStart([char]0xFEFF, [char]0x0009, [char]0x000A, [char]0x000D, [char]0x0020)

            $xmlDoc = [xml]::new()

            $xmlDoc.LoadXml($normalizedAutoUnattendXml)



            $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)

            $nsMgr.AddNamespace("sg", "https://schneegans.de/windows/unattend-generator/")



            $fileNodes = $xmlDoc.SelectNodes("//sg:File", $nsMgr)

            if ($fileNodes -and $fileNodes.Count -gt 0) {

                foreach ($fileNode in $fileNodes) {

                    $absPath  = $fileNode.GetAttribute("path")

                    $relPath  = $absPath -replace '^[A-Za-z]:[/\\]', ''

                    $destPath = [System.IO.Path]::GetFullPath((Join-Path $ScratchDir $relPath))
                    $scratchNorm = [System.IO.Path]::GetFullPath($ScratchDir).TrimEnd('\')
                    if (-not $destPath.StartsWith($scratchNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                        & $Log "WARNING: Skipping autounattend File node with path traversal outside mount directory: $absPath -> $destPath"
                        continue
                    }

                    New-Item -Path (Split-Path $destPath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null



                    $ext = [IO.Path]::GetExtension($destPath).ToLower()

                    $encoding = switch ($ext) {

                        { $_ -in '.ps1', '.xml' }        { [System.Text.Encoding]::UTF8 }

                        { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new($false, $true) }

                        default                          { [System.Text.Encoding]::Default }

                    }

                    [System.IO.File]::WriteAllBytes($destPath, ($encoding.GetPreamble() + $encoding.GetBytes($fileNode.InnerText.Trim())))

                    & $Log "Pre-staged setup script: $relPath"

                }

            } else {

                & $Log "Warning: no <Extensions><File> nodes found in autounattend.xml - setup scripts not pre-staged."

            }

            $autoUnattendXmlParsedOk = $true

        } catch {

            & $Log "Warning: could not pre-stage setup scripts from autounattend.xml: $_"

        }



        if ($autoUnattendXmlParsedOk -and $ISOContentsDir -and (Test-Path $ISOContentsDir)) {

            $isoDest = Join-Path $ISOContentsDir "autounattend.xml"

            Set-Content -Path $isoDest -Value $normalizedAutoUnattendXml -Encoding UTF8 -Force

            & $Log "Written autounattend.xml to ISO root ($isoDest)."

        } elseif (-not $autoUnattendXmlParsedOk -and $ISOContentsDir) {

            & $Log "WARNING: Skipping autounattend.xml write to ISO root — XML parsing failed earlier."

        }

    } else {

        & $Log "Warning: autounattend.xml content is empty - skipping OOBE bypass file."

    }



    & $Log "Disabling reserved storage..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'



    & $Log "Disabling BitLocker device encryption..."

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'



    & $Log "Disabling Chat icon..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'

    Set-ISOScriptReg 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'



    & $Log "Disabling OneDrive folder backup..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 'REG_DWORD' '1'



    & $Log "Disabling telemetry..."

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection'  'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'

    Set-ISOScriptReg 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'



    & $Log "Preventing installation of DevHome and Outlook..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate'      'workCompleted' 'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate'      'workCompleted' 'REG_DWORD' '1'

    Remove-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'

    Remove-ISOScriptReg 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'



    & $Log "Disabling Copilot..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'      'REG_DWORD' '1'

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer'       'DisableSearchBoxSuggestions' 'REG_DWORD' '1'



    & $Log "Preventing installation of Teams..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'



    & $Log "Preventing installation of new Outlook..."

    Set-ISOScriptReg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

    & $Log "Unloading offline registry hives..."

    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500

    $hiveNames = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')
    foreach ($hive in $hiveNames) {
        $maxRetries = 3
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            reg unload "HKLM\$hive" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            & $Log "Warning: reg unload HKLM\$hive failed (attempt $attempt/$maxRetries, exit code $LASTEXITCODE)."
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Seconds (1 * $attempt)
        }
        if ($LASTEXITCODE -ne 0) {
            & $Log "ERROR: Failed to unload HKLM\$hive after $maxRetries attempts. WIM save may fail or produce a corrupt image."
        }
    }

    } # end if (-not $regLoadFailed)

    # ── 5. Delete scheduled task definition files ─────────────────────────────

    & $Log "Deleting scheduled task definition files..."

    $tasksPath = "$ScratchDir\Windows\System32\Tasks"

    Remove-Item "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program"                  -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater"               -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Chkdsk\Proxy"                                            -Force -ErrorAction SilentlyContinue

    Remove-Item "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting"                  -Force -ErrorAction SilentlyContinue

    & $Log "Scheduled task files deleted."



    # ── 6. Remove ISO support folder ─────────────────────────────────────────

    if ($ISOContentsDir -and (Test-Path $ISOContentsDir)) {

        & $Log "Removing ISO support\ folder..."

        Remove-Item -Path (Join-Path $ISOContentsDir "support") -Recurse -Force -ErrorAction SilentlyContinue

        & $Log "ISO support\ folder removed."

    }

}

