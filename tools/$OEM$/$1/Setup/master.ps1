# ==============================================================================
#   Advanced Systems — Windows Setup Orchestrator
#   master.ps1  |  VERSION: 0.2
# ==============================================================================
#
#   PHASES:
#     Phase 0 — Privacy, dark mode, wallpaper, region, taskbar,
#               file explorer, desktop shortcuts, startup apps
#     Phase 1 — App installs (Microsoft 365, Chrome, UltraViewer, Sidebar)
#     Phase 2 — Windows Updates → reboot
#     Phase 3 — Windows Updates → reboot
#     Phase 4 — Windows Updates → reboot (final)
#     Phase 5 — AHK (Chrome extensions, Sidebar buttons)
#     Phase 6 — Cleanup
#
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Paths ─────────────────────────────────────────────────────────────────────
$SetupRoot = "C:\Setup"
$LogFile   = "$SetupRoot\setup.log"
$FlagFile  = "$SetupRoot\phase.txt"
$TaskName  = "ASYS_SetupResume"

# ── Logging ───────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $line
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Log "  SET  $Path\$Name = $Value"
    } catch {
        Write-Log "  FAIL $Path\$Name  $_" "WARN"
    }
}

# ── Ensure setup folder exists ────────────────────────────────────────────────
if (-not (Test-Path $SetupRoot)) { New-Item -ItemType Directory -Path $SetupRoot -Force | Out-Null }

Write-Log "========================================================"
Write-Log "master.ps1 started  v0.2"
Write-Log "Running as: $env:USERNAME  |  Computer: $env:COMPUTERNAME"
Write-Log "========================================================"

# Ensure the main user account remains in the local Administrators group.
try {
    $currentUser = $env:USERNAME
    if ($currentUser -and $currentUser -ne 'TECH') {
        $adminMembers = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
            ForEach-Object { ($_.Name -split '\\')[-1] })
        if ($currentUser -notin $adminMembers) {
            Add-LocalGroupMember -Group 'Administrators' -Member $currentUser -ErrorAction Stop
            Write-Log "Main user '$currentUser' added to Administrators."
        } else {
            Write-Log "Main user '$currentUser' is already an Administrator."
        }
    }
} catch {
    Write-Log "Could not verify Administrator membership for main user: $_" 'WARN'
}

# ── Read phase flag ───────────────────────────────────────────────────────────
$currentPhase = 0
if (Test-Path $FlagFile) {
    try { $currentPhase = [int](Get-Content $FlagFile -Raw).Trim() } catch { $currentPhase = 0 }
}
Write-Log "Current phase: $currentPhase"


# ==============================================================================
#   STEP 1 — Register in Task Scheduler (runs every time, re-registers cleanly)
# ==============================================================================
Write-Log "Registering Task Scheduler entry..."
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    $Action    = New-ScheduledTaskAction -Execute "powershell.exe" `
                     -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SetupRoot\master.ps1`""
    $Trigger   = New-ScheduledTaskTrigger -AtLogOn
    $Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                     -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 3)
    $Principal = New-ScheduledTaskPrincipal -UserId "BUILTIN\Administrators" `
                     -RunLevel Highest -LogonType Group
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
        -Settings $Settings -Principal $Principal -Force | Out-Null
    Write-Log "Task Scheduler entry registered: $TaskName"

    # Main user password is set by autounattend (default: 1) and is not cleared here.
} catch {
    Write-Log "ERROR registering Task Scheduler: $_" "ERROR"
}


# ==============================================================================
#   PHASES 0-6 — COMMENTED OUT
#   Windows installation is being validated first.
#   Uncomment Phase 0 when ready to test post-install configuration.
#   Then uncomment each subsequent phase once the previous one is confirmed working.
# ==============================================================================

# # ==============================================================================
# #   PHASE 0  All registry tweaks and Windows configuration
# # ==============================================================================
# if ($currentPhase -eq 0) {
#     Write-Log "--- PHASE 0 START ---"


#     # --------------------------------------------------------------------------
#     #   0.1  Privacy Settings (all 6 data collection options)
#     # --------------------------------------------------------------------------
#     Write-Log "0.1 Privacy settings..."

#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"             "Enabled"                                        0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"                     "TailoredExperiencesWithDiagnosticDataEnabled"    0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"                               "RestrictImplicitInkCollection"                  1
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization"                               "RestrictImplicitTextCollection"                 1
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore"              "HarvestContacts"                                0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Personalization\Settings"                           "AcceptedPrivacyPolicy"                          0
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"    "AllowTelemetry"                                 0
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"    "MaxTelemetryAllowed"                            0
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"                   "AllowTelemetry"                                 0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" "String"
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" "String"
#     Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"        "Status"                                         0
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Settings\FindMyDevice"                             "LocationSyncEnabled"                            0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"                                        "NumberOfSIUFInPeriod"                           0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"       "HasAccepted"                                    0


#     # --------------------------------------------------------------------------
#     #   0.2  Personalisation  Dark Mode
#     # --------------------------------------------------------------------------
#     Write-Log "0.2 Dark mode..."

#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme"      0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme"   0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "ColorPrevalence"        0


#     # --------------------------------------------------------------------------
#     #   0.3  Wallpaper  Static image for both lock screen and desktop
#     #        TODO: Replace $wallpaperImage with your custom image path once decided.
#     #              Drop the image into C:\Setup\ and update the path below.
#     #              Both lock screen and desktop will use the same image.
#     # --------------------------------------------------------------------------
#     Write-Log "0.3 Wallpaper and lock screen (static)..."

#     # ── Wallpaper image path ───────────────────────────────────────────────────
#     # Using the default Windows wallpaper as placeholder.
#     # Replace this path with your custom image when ready.
#     $wallpaperImage = "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg"
#     # Fallback in case img0.jpg is missing (Win 11 uses img19.jpg)
#     if (-not (Test-Path $wallpaperImage)) {
#         $wallpaperImage = "$env:SystemRoot\Web\Wallpaper\Windows\img19.jpg"
#     }

#     # ── Desktop wallpaper  static picture ────────────────────────────────────
#     if (Test-Path $wallpaperImage) {
#         Set-Reg "HKCU:\Control Panel\Desktop" "Wallpaper"      $wallpaperImage "String"
#         Set-Reg "HKCU:\Control Panel\Desktop" "WallpaperStyle" "10"            "String"  # Fill
#         Set-Reg "HKCU:\Control Panel\Desktop" "TileWallpaper"  "0"             "String"
#         & RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters ,1 ,True
#         Write-Log "  Desktop wallpaper set: $wallpaperImage"
#     } else {
#         Write-Log "  Wallpaper image not found — skipping desktop wallpaper." "WARN"
#     }

#     # ── Lock screen  static picture  disable Spotlight completely ─────────────
#     # Disable Spotlight / rotating lock screen
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled"        0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled"               0
#     # Disable Windows Spotlight for lock screen via policy
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoChangingLockScreen" 0
#     # Set static lock screen image via policy (applies to all users)
#     if (Test-Path $wallpaperImage) {
#         Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "LockScreenImage" $wallpaperImage "String"
#         Write-Log "  Lock screen set to static image: $wallpaperImage"
#     }
#     # Also set via current user personalization path (belt and braces)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lock Screen" "SlideshowEnabled" 0


#     # --------------------------------------------------------------------------
#     #   0.4  Region  Malaysia  Date format DD-MM-YYYY  Timezone UTC+8
#     # --------------------------------------------------------------------------
#     Write-Log "0.4 Region and timezone..."

#     Set-Reg "HKCU:\Control Panel\International" "sCountry"        "Malaysia"  "String"
#     Set-Reg "HKCU:\Control Panel\International" "sLanguage"       "ENG"       "String"
#     Set-Reg "HKCU:\Control Panel\International" "LocaleName"      "ms-MY"     "String"
#     Set-Reg "HKCU:\Control Panel\International" "sShortDate"      "dd-MM-yyyy" "String"
#     Set-Reg "HKCU:\Control Panel\International" "sLongDate"       "dd-MM-yyyy" "String"
#     Set-Reg "HKCU:\Control Panel\International" "sDate"           "-"         "String"
#     Set-Reg "HKCU:\Control Panel\International" "iDate"           "1"         "String"  # 1 = day-month-year order
#     Set-Reg "HKCU:\Control Panel\International" "iFirstDayOfWeek" "0"         "String"
#     Set-Reg "HKCU:\Control Panel\International" "sCurrency"       "RM"        "String"
#     Set-Reg "HKCU:\Control Panel\International" "sThousand"       ","         "String"
#     Set-Reg "HKCU:\Control Panel\International" "sDecimal"        "."         "String"

#     try {
#         Set-TimeZone -Id "Singapore Standard Time"
#         Write-Log "  Timezone: Singapore Standard Time (UTC+8)"
#     } catch {
#         & tzutil /s "Singapore Standard Time"
#         Write-Log "  Timezone set via tzutil"
#     }


#     # --------------------------------------------------------------------------
#     #   0.5  Taskbar
#     #        Search: icon only
#     #        Remove: News/Widgets, Task View, Chat/Teams
#     #        Win 11 alignment: left
#     #        Pins: Edge (left) then File Explorer (right)
#     #        Quick Settings: Internet, Bluetooth, Night Light only
#     # --------------------------------------------------------------------------
#     Write-Log "0.5 Taskbar..."

#     # Search icon only (0=off 1=icon 2=bar 3=full)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 1

#     # Remove Widgets (Win 11) and News feeds (Win 10)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa"           0
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"           "EnableFeeds"          0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds"             "IsFeedsAvailable"     0

#     # Hide Task View and Chat buttons
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton"   0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn"            0

#     # Win 11: left align taskbar (0=left 1=centre)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl"            0

#     # Taskbar pins: Edge + File Explorer only via layout XML
#     $taskbarLayout = @"
# <?xml version="1.0" encoding="utf-8"?>
# <LayoutModificationTemplate
#     xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
#     xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
#     xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
#     Version="1">
#   <CustomTaskbarLayoutCollection PinListPlacement="Replace">
#     <defaultlayout:TaskbarLayout>
#       <taskbar:TaskbarPinList>
#         <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk"/>
#         <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\File Explorer.lnk"/>
#       </taskbar:TaskbarPinList>
#     </defaultlayout:TaskbarLayout>
#   </CustomTaskbarLayoutCollection>
# </LayoutModificationTemplate>
# "@
#     $layoutPath = "$env:SystemRoot\TaskbarLayoutModification.xml"
#     $taskbarLayout | Out-File -FilePath $layoutPath -Encoding UTF8 -Force
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "StartLayoutFile" $layoutPath "String"
#     Write-Log "  Taskbar layout XML written: Edge + File Explorer pinned"

#     # Quick Settings tiles: Internet, Bluetooth, Night Light
#     $quickPath = "HKCU:\Control Panel\Quick Actions\Control Center\QuickActionsStateCapture"
#     if (-not (Test-Path $quickPath)) { New-Item -Path $quickPath -Force | Out-Null }
#     $tiles = '["Microsoft.QuickAction.Network","Microsoft.QuickAction.Bluetooth","Microsoft.QuickAction.NightLight"]'
#     Set-ItemProperty -Path $quickPath -Name "PinnedSlots" -Value $tiles -Type String -Force
#     Write-Log "  Quick Settings tiles: Internet, Bluetooth, Night Light"




#     # --------------------------------------------------------------------------
#     #   0.7  Desktop Shortcuts
#     #        Left  (top to bottom):    This PC, Recycle Bin, Edge, Chrome,
#     #                                  Word, PowerPoint, Excel
#     #        Right (bottom to top):    Sidebar, Network, UltraViewer
#     #
#     #        Chrome, Word, PowerPoint, Excel, UltraViewer, Sidebar shortcuts
#     #        are added in Phase 1 after apps install.
#     # --------------------------------------------------------------------------
#     Write-Log "0.7 Desktop shortcuts..."

#     $desktopPath  = [Environment]::GetFolderPath("Desktop")
#     $publicDesktop = "$env:PUBLIC\Desktop"

#     # Remove all default shortcuts
#     Remove-Item "$desktopPath\*.lnk"   -Force -ErrorAction SilentlyContinue
#     Remove-Item "$publicDesktop\*.lnk" -Force -ErrorAction SilentlyContinue

#     # Show This PC and Recycle Bin on desktop, hide Network icon
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" 0  # This PC
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{645FF040-5081-101B-9F08-00AA002F954E}" 0  # Recycle Bin
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" 1  # Network (hide system icon; shortcut used instead)

#     function New-Shortcut {
#         param([string]$Name, [string]$Target, [string]$Args = "", [string]$Icon = "")
#         $sh   = New-Object -ComObject WScript.Shell
#         $link = $sh.CreateShortcut("$desktopPath\$Name.lnk")
#         $link.TargetPath = $Target
#         if ($Args) { $link.Arguments = $Args }
#         if ($Icon) { $link.IconLocation = $Icon }
#         $link.Save()
#         Write-Log "  Shortcut: $Name"
#     }

#     # Edge
#     $edgePath = "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
#     if (-not (Test-Path $edgePath)) { $edgePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
#     if (Test-Path $edgePath) { New-Shortcut "Microsoft Edge" $edgePath }

#     # Network
#     New-Shortcut "Network" "explorer.exe" "shell:::{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" "%SystemRoot%\system32\imageres.dll,157"

#     # Chrome, Office, UltraViewer, Sidebar shortcuts added in Phase 1 after install

#     # Save desktop icon positions script for Phase 1 (runs after all apps installed)
#     $posScript = @'
# Add-Type @"
# using System;
# using System.Runtime.InteropServices;
# using System.Windows.Forms;
# using System.Text;
# public class DesktopPos {
#     [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lp, string wp);
#     [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cn, string wn);
#     [DllImport("user32.dll")] public static extern bool SendMessage(IntPtr h, uint m, IntPtr w, ref POINT l);
#     [DllImport("user32.dll")] public static extern int SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder sb);
#     [DllImport("user32.dll")] public static extern int SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
#     [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
#     public const uint LVM_SETITEMPOSITION = 0x100F;
#     public const uint LVM_GETITEMCOUNT    = 0x1004;
#     public const uint LVM_GETITEMTEXT     = 0x102D;  // LVM_GETITEMTEXTW (unicode)
#     public static int GetItemCount(IntPtr lv) {
#         return SendMessage(lv, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
#     }
#     public static string GetItemName(IntPtr lv, int idx) {
#         var sb = new StringBuilder(260);
#         SendMessage(lv, LVM_GETITEMTEXT, (IntPtr)idx, sb);
#         return sb.ToString();
#     }
#     public static void SetPos(IntPtr lv, int idx, int x, int y) {
#         POINT pt = new POINT { X = x, Y = y };
#         SendMessage(lv, LVM_SETITEMPOSITION, (IntPtr)idx, ref pt);
#     }
# }
# "@ -Language CSharp

# # ── Locate the desktop ListView ───────────────────────────────────────────────
# $progman  = [DesktopPos]::FindWindow("Progman", $null)
# $shelldll = [DesktopPos]::FindWindowEx($progman, [IntPtr]::Zero, "SHELLDLL_DefView", $null)
# $lv       = [DesktopPos]::FindWindowEx($shelldll, [IntPtr]::Zero, "SysListView32", $null)

# if ($lv -eq [IntPtr]::Zero) {
#     Write-Host "Desktop listview not found. Relaunch after login."
#     exit 1
# }

# $sw = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width
# $sh = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height

# # ── Build a name → index map ──────────────────────────────────────────────────
# $count   = [DesktopPos]::GetItemCount($lv)
# $nameMap = @{}
# for ($i = 0; $i -lt $count; $i++) {
#     $n = [DesktopPos]::GetItemName($lv, $i)
#     if ($n) { $nameMap[$n] = $i }
# }
# Write-Host "Desktop icons found ($count): $($nameMap.Keys -join ', ')"

# # ── Position helper ───────────────────────────────────────────────────────────
# function Set-IconPos {
#     param([string]$Name, [int]$X, [int]$Y)
#     # Try exact name first, then partial match
#     $idx = if ($nameMap.ContainsKey($Name)) {
#         $nameMap[$Name]
#     } else {
#         ($nameMap.Keys | Where-Object { $_ -like "*$Name*" } | Select-Object -First 1) |
#             ForEach-Object { $nameMap[$_] }
#     }
#     if ($null -ne $idx) {
#         [DesktopPos]::SetPos($lv, $idx, $X, $Y)
#         Write-Host "  Positioned: $Name (index $idx) -> ($X, $Y)"
#     } else {
#         Write-Host "  Not found on desktop: $Name"
#     }
# }

# # ── Disable auto-arrange so positions stick ───────────────────────────────────
# # Sends LVM_SETEXTENDEDLISTVIEWSTYLE to clear the auto-arrange flag
# # Easier: set via registry and restart explorer (already done in master.ps1)

# # ── Icon grid settings ────────────────────────────────────────────────────────
# $leftX   = 30                   # Left column X position
# $rightX  = $sw - 90             # Right column X position
# $topY    = 40                   # Starting Y for left column
# $gap     = 90                   # Vertical gap between icons

# # ── LEFT COLUMN  top to bottom ───────────────────────────────────────────────
# # Order: This PC, Recycle Bin, Edge, Chrome, Word, PowerPoint, Excel
# $leftIcons = @(
#     "This PC",
#     "Recycle Bin",
#     "Microsoft Edge",
#     "Google Chrome",
#     "Word",
#     "PowerPoint",
#     "Excel"
# )
# for ($i = 0; $i -lt $leftIcons.Count; $i++) {
#     Set-IconPos -Name $leftIcons[$i] -X $leftX -Y ($topY + $i * $gap)
# }

# # ── RIGHT COLUMN  bottom to top ──────────────────────────────────────────────
# # Order (bottom to top): Sidebar, Network, UltraViewer
# $rightIcons = @(
#     "Sidebar",       # bottom
#     "Network",       # middle
#     "UltraViewer"    # top
# )
# for ($i = 0; $i -lt $rightIcons.Count; $i++) {
#     $y = $sh - 50 - ($i * $gap)
#     Set-IconPos -Name $rightIcons[$i] -X $rightX -Y $y
# }

# Write-Host "Desktop icon positioning complete."
# '@
#     $posScript | Out-File -FilePath "$SetupRoot\Set-DesktopIconPositions.ps1" -Encoding UTF8 -Force
#     Write-Log "  Icon position script saved (name-based lookup)."


#     # --------------------------------------------------------------------------
#     #   0.8  Startup Apps  Disable OneDrive and Teams autostart
#     # --------------------------------------------------------------------------
#     Write-Log "0.8 Startup apps..."

#     Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive"                     -ErrorAction SilentlyContinue
#     Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Teams"                        -ErrorAction SilentlyContinue
#     Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "com.squirrel.Teams.Teams"     -ErrorAction SilentlyContinue
#     Write-Log "  OneDrive and Teams autostart disabled."


#     # --------------------------------------------------------------------------
#     #   Disable Windows Defender Cloud Protection and Sample Submission
#     # --------------------------------------------------------------------------
#     Write-Log "0.8b Disabling cloud protection and sample submission..."
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" "SpynetReporting"        0
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" "SubmitSamplesConsent"   2   # 2 = Never send
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"          "TamperProtection"       0
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"          "DisableAntiSpyware"     0   # Keep AV on, just cloud off
#     Write-Log "  Cloud protection and sample submission disabled."


#     # --------------------------------------------------------------------------
#     #   Disable Microsoft Update (Office updates through Windows Update)
#     # --------------------------------------------------------------------------
#     Write-Log "0.8c Disabling Microsoft Update..."
#     try {
#         $musm = New-Object -ComObject Microsoft.Update.ServiceManager
#         $musm.RemoveService("7971f918-a847-4430-9279-4a52d1efe18d") 2>$null
#         Write-Log "  Microsoft Update service removed."
#     } catch {
#         Write-Log "  Microsoft Update removal via COM failed (may not be registered yet): $_" "WARN"
#     }
#     Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "DisableWindowsUpdateAccess" 0
#     Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" "IncludeRecommendedUpdates" 0


#     # --------------------------------------------------------------------------
#     #   Microsoft Word settings via registry
#     #   - Document background: White (not dark/black)
#     #   - Ruler enabled
#     #   - AutoSave every 1 minute
#     # --------------------------------------------------------------------------
#     Write-Log "0.8d Word settings..."
#     # Word stores settings under version-specific key — covers Office 16 (M365/2019/2021/2024)
#     $wordKey = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Word\Options"
#     $wordView = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Word\Options\vpref"

#     # Document background white (DisableDarkMode in document area)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Office\16.0\Word\Options" "DisableDarkThemeDocumentBackground" 1
#     # Ruler visible (ShowRuler)
#     Set-Reg $wordKey "ShowRuler" 1
#     # AutoRecover / AutoSave every 1 minute (SaveInterval in minutes, value 1)
#     Set-Reg $wordKey "AutosaveInterval" 1
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Office\16.0\Word\Options" "BackgroundSave" 1
#     Write-Log "  Word: white document background, ruler on, autosave every 1 min."


#     # --------------------------------------------------------------------------
#     #   0.10 DNS Configuration
#     #        Preferred:  10.1.1.11
#     #        Alternate:  10.160.5.7
#     #        Applied to both Ethernet and Wi-Fi adapters.
#     # --------------------------------------------------------------------------
#     # --------------------------------------------------------------------------
#     #   0.9  Disable IPv6 on all network adapters (Ethernet + Wi-Fi)
#     #        Matches Image 2 — unchecks "Internet Protocol Version 6 (TCP/IPv6)"
#     # --------------------------------------------------------------------------
#     Write-Log "0.9 Disabling IPv6..."
#     try {
#         # Disable via registry for all adapters (survives driver reinstall)
#         Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisabledComponents" 0xFF

#         # Also disable via PowerShell cmdlet on currently active adapters
#         Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq "ms_tcpip6" } | ForEach-Object {
#             Disable-NetAdapterBinding -Name $_.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue
#             Write-Log "  IPv6 disabled on: $($_.Name)"
#         }
#         Write-Log "  IPv6 disabled on all adapters."
#     } catch {
#         Write-Log "  IPv6 disable error: $_" "WARN"
#     }


#     $dnsPrimary   = "10.1.1.11"
#     $dnsSecondary = "10.160.5.7"
#     $dnsServers   = @($dnsPrimary, $dnsSecondary)
#     Write-Log "0.10 Applying DNS: $dnsPrimary / $dnsSecondary"

#     # Ethernet
#     try {
#         $eth = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and $_.PhysicalMediaType -eq "802.3" }
#         if ($eth) {
#             $eth | ForEach-Object {
#                 Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $dnsServers
#                 Write-Log "  [Ethernet] $($_.Name) -> $($dnsServers -join ', ')"
#             }
#         } else { Write-Log "  [Ethernet] No active adapter found." "WARN" }
#     } catch { Write-Log "  [Ethernet] Error: $_" "WARN" }

#     # Wi-Fi
#     try {
#         $wifi = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and ($_.PhysicalMediaType -eq "Native 802.11" -or $_.PhysicalMediaType -eq "Wireless LAN") }
#         if ($wifi) {
#             $wifi | ForEach-Object {
#                 Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $dnsServers
#                 Write-Log "  [Wi-Fi] $($_.Name) -> $($dnsServers -join ', ')"
#             }
#         } else { Write-Log "  [Wi-Fi] No active adapter found." "WARN" }
#     } catch { Write-Log "  [Wi-Fi] Error: $_" "WARN" }

#     # Fallback: any remaining active physical adapters
#     try {
#         $covered = @(
#             (Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq "802.3" }).InterfaceIndex +
#             (Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match "802.11|Wireless" }).InterfaceIndex
#         )
#         $rest = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and $_.InterfaceIndex -notin $covered }
#         $rest | ForEach-Object {
#             Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ServerAddresses $dnsServers
#             Write-Log "  [Other] $($_.Name) -> $($dnsServers -join ', ')"
#         }
#     } catch { Write-Log "  [Fallback] Error: $_" "WARN" }

#     Write-Log "  DNS configuration complete."


#     # --------------------------------------------------------------------------
#     #   Performance — Adjust for best performance (Image 3)
#     #   Sets VisualFXSetting = 2 (Adjust for best performance)
#     #   Disables all visual effects checkboxes
#     # --------------------------------------------------------------------------
#     Write-Log "0.11 Performance settings — adjust for best performance..."
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" 2

#     # Disable all individual visual effects
#     $perfKey = "HKCU:\Control Panel\Desktop"
#     Set-Reg $perfKey "UserPreferencesMask" ([byte[]](0x90,0x12,0x01,0x80)) "Binary"
#     Set-Reg $perfKey "DragFullWindows"     "0" "String"
#     Set-Reg $perfKey "FontSmoothing"       "0" "String"
#     Set-Reg "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" "String"
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations"    0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewAlphaSelect"  0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ListviewShadow"       0
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl"            0   # Already set but reinforce
#     # Disable window animations
#     Add-Type -AssemblyName System.Windows.Forms
#     [System.Windows.Forms.SystemInformation]::GetType() | Out-Null
#     Set-Reg "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String"
#     Write-Log "  Performance set to: Adjust for best performance."


#     # --------------------------------------------------------------------------
#     #   Workgroup — set to match computer name / username (Image 4)
#     # --------------------------------------------------------------------------
#     Write-Log "0.12 Setting workgroup..."
#     try {
#         $wg = $env:COMPUTERNAME
#         Add-Computer -WorkgroupName $wg -ErrorAction SilentlyContinue
#         Write-Log "  Workgroup set to: $wg"
#     } catch {
#         # Fallback via registry
#         Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "NV Domain" $env:COMPUTERNAME "String"
#         Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" "ComputerName" $env:COMPUTERNAME "String"
#         Write-Log "  Workgroup set via registry: $env:COMPUTERNAME" "WARN"
#     }


#     # --------------------------------------------------------------------------
#     #   0.6  File Explorer  restore to Windows defaults
#     #        General tab: Open to Quick Access, same window, double-click,
#     #                     show recent files + frequent folders in Quick Access
#     #        View tab:    Don't show hidden files, hide extensions,
#     #                     hide protected OS files — all Windows defaults
#     # --------------------------------------------------------------------------
#     Write-Log "0.6 File Explorer defaults..."

#     $explorerAdv = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "ShowFrequent"         1   # Show frequently used folders
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "ShowRecent"           0   # Don't show recently used files (Image 1)
#     Set-Reg $explorerAdv "SeparateProcess"      0   # Open each folder in same window
#     Set-Reg $explorerAdv "IconsOnly"            0   # Show thumbnails
#     Set-Reg $explorerAdv "LaunchTo"             2   # Open to Home (Win11) / Quick Access (Win10)
#     Set-Reg $explorerAdv "Hidden"               2   # Don't show hidden files
#     Set-Reg $explorerAdv "ShowSuperHidden"      0   # Hide protected OS files
#     Set-Reg $explorerAdv "HideFileExt"          1   # Hide extensions for known file types
#     Set-Reg $explorerAdv "HideMergeConflicts"   1   # Hide folder merge conflicts
#     Set-Reg $explorerAdv "HideDrivesWithNoMedia" 1  # Hide empty drives
#     Set-Reg $explorerAdv "AlwaysShowMenus"      0   # Don't always show menus
#     Set-Reg $explorerAdv "FolderContentsInfoTip" 1  # Display file size info in folder tips
#     Set-Reg $explorerAdv "FullPath"             0   # Don't show full path in title bar

#     # Win 11 additional privacy options (Image 1)
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "ShowRecommendedSection"          1   # Show recommended section
#     Set-Reg "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "ShowCloudFilesInQuickAccess"     1   # Include account-based insights

#     # Clear File Explorer history (MRU lists)
#     try {
#         Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"       -Name "*" -ErrorAction SilentlyContinue
#         Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"        -Name "*" -ErrorAction SilentlyContinue
#         Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"            -Name "*" -ErrorAction SilentlyContinue
#         Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU" -Name "*" -ErrorAction SilentlyContinue
#         # Trigger the shell to flush its MRU cache
#         $shell = New-Object -ComObject Shell.Application
#         $shell.MinimizeAll()
#         Start-Sleep -Milliseconds 500
#         Write-Log "  File Explorer history cleared."
#     } catch {
#         Write-Log "  File Explorer history clear error (non-critical): $_" "WARN"
#     }
#     Write-Log "  File Explorer configured."


#     # --------------------------------------------------------------------------
#     #   0.7  Chrome Extensions  force-install via registry policy
#     #        uBlock Origin + AdBlock
#     #        Chrome reads these keys on launch and auto-installs the extensions
#     #        silently. No user interaction required.
#     # --------------------------------------------------------------------------
#     Write-Log "0.7 Chrome extensions (force-install policy)..."

#     $chromeExtPath = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
#     if (-not (Test-Path $chromeExtPath)) { New-Item -Path $chromeExtPath -Force | Out-Null }

#     # uBlock Origin Lite  — Chrome Web Store ID: ddkjiahejlhfcafbddmgiahcphecmpfh
#     Set-ItemProperty -Path $chromeExtPath -Name "1" `
#         -Value "ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx" `
#         -Type String -Force

#     # AdBlocker Ultimate  — Chrome Web Store ID: ohahllgiabjaoigichmmfljhkcfikeof
#     Set-ItemProperty -Path $chromeExtPath -Name "2" `
#         -Value "ohahllgiabjaoigichmmfljhkcfikeof;https://clients2.google.com/service/update2/crx" `
#         -Type String -Force

#     Write-Log "  uBlock Origin Lite and AdBlocker Ultimate force-install policy set."

#     # Pin both extensions in Chrome toolbar via ExtensionSettings policy
#     $chromeExtSettings = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings"
#     if (-not (Test-Path $chromeExtSettings)) { New-Item -Path $chromeExtSettings -Force | Out-Null }

#     # uBlock Origin Lite — pinned to toolbar
#     $ublockJson = '{"installation_mode":"force_installed","update_url":"https://clients2.google.com/service/update2/crx","toolbar_pin":"force_pinned"}'
#     Set-ItemProperty -Path $chromeExtSettings -Name "ddkjiahejlhfcafbddmgiahcphecmpfh" -Value $ublockJson -Type String -Force

#     # AdBlocker Ultimate — pinned to toolbar
#     $adblockJson = '{"installation_mode":"force_installed","update_url":"https://clients2.google.com/service/update2/crx","toolbar_pin":"force_pinned"}'
#     Set-ItemProperty -Path $chromeExtSettings -Name "ohahllgiabjaoigichmmfljhkcfikeof" -Value $adblockJson -Type String -Force

#     Write-Log "  Both extensions pinned to Chrome toolbar."
#     Write-Log "  Extensions will auto-install on Chrome's first launch."

#     # --------------------------------------------------------------------------
#     #   0.8  Chrome Bookmarks  staged for import
#     #        The HTML file must be in C:\Setup\chrome-bookmarks.html
#     #        (placed there by the $OEM$ folder injection from Clark)
#     # --------------------------------------------------------------------------
#     Write-Log "0.8 Chrome bookmarks..."
#     $bookmarksHtml = "$SetupRoot\chrome-bookmarks.html"
#     if (Test-Path $bookmarksHtml) {
#         Copy-Item -Path $bookmarksHtml -Destination "$SetupRoot\chrome-bookmarks-pending.html" -Force
#         Write-Log "  Bookmarks HTML staged at $SetupRoot\chrome-bookmarks-pending.html"
#         Write-Log "  Will be imported via --import-bookmarks flag when Chrome launches in Phase 5."
#     } else {
#         Write-Log "  chrome-bookmarks.html not found in C:\Setup\ - skipping." "WARN"
#     }



#     # --------------------------------------------------------------------------
#     #   0.13 Restart Explorer to apply all changes
#     # --------------------------------------------------------------------------
#     Write-Log "0.13 Restarting Explorer..."
#     Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
#     Start-Sleep -Seconds 4
#     Start-Process explorer
#     Start-Sleep -Seconds 4
#     Write-Log "  Explorer restarted."

#     Write-Log "--- PHASE 0 COMPLETE ---"
#     "1" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#     $currentPhase = 1
# }


# # ==============================================================================
# #   PHASE 1  App Installation
# #   Chrome, UltraViewer, Microsoft 365 (Word, Excel, PowerPoint)
# # ==============================================================================
# if ($currentPhase -eq 1) {
#     Write-Log "--- PHASE 1: App installs ---"

#     # Wait for winget to be ready
#     function Wait-Winget {
#         $maxWait = 120; $waited = 0
#         while (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
#             Start-Sleep -Seconds 5; $waited += 5
#             if ($waited -ge $maxWait) {
#                 Write-Log "  winget not found — attempting App Installer update..." "WARN"
#                 try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch {}
#                 break
#             }
#         }
#     }

#     # Install via winget with retry
#     function Install-App {
#         param([string]$Name, [string]$WingetId, [int]$Retries = 3)
#         Write-Log "  Installing: $Name ($WingetId)..."
#         for ($i = 1; $i -le $Retries; $i++) {
#             & winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements --no-upgrade 2>&1 | Out-Null
#             if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
#                 Write-Log "  $Name installed successfully."
#                 return $true
#             }
#             Write-Log "  $Name attempt $i failed (exit $LASTEXITCODE) retrying..." "WARN"
#             Start-Sleep -Seconds 10
#         }
#         Write-Log "  $Name failed after $Retries attempts." "ERROR"
#         return $false
#     }

#     # Create desktop shortcut
#     function New-Shortcut {
#         param([string]$Name, [string]$Target, [string]$Args = "", [string]$Icon = "")
#         $dp   = [Environment]::GetFolderPath("Desktop")
#         $sh   = New-Object -ComObject WScript.Shell
#         $link = $sh.CreateShortcut("$dp\$Name.lnk")
#         $link.TargetPath = $Target
#         if ($Args) { $link.Arguments   = $Args }
#         if ($Icon) { $link.IconLocation = $Icon }
#         $link.Save()
#         Write-Log "  Shortcut: $Name"
#     }

#     Wait-Winget

#     # 1.1 Google Chrome
#     Install-App "Google Chrome" "Google.Chrome"
#     $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
#     if (-not (Test-Path $chromePath)) { $chromePath = "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe" }
#     if (Test-Path $chromePath) { New-Shortcut "Google Chrome" $chromePath }

#     # 1.2 UltraViewer
#     Install-App "UltraViewer" "UltraViewer.UltraViewer"
#     $uvPath = "$env:ProgramFiles\UltraViewer\UltraViewer_Desktop.exe"
#     if (-not (Test-Path $uvPath)) { $uvPath = "$env:ProgramFiles (x86)\UltraViewer\UltraViewer_Desktop.exe" }
#     if (Test-Path $uvPath) { New-Shortcut "UltraViewer" $uvPath }

#     # 1.3 Microsoft 365 via Office Deployment Tool
#     Write-Log "  Installing Microsoft 365..."
#     $odtDir    = "$SetupRoot\ODT"
#     $odtExe    = "$odtDir\setup.exe"
#     $odtConfig = "$odtDir\config.xml"
#     New-Item -ItemType Directory -Path $odtDir -Force | Out-Null

#     try {
#         [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#         Invoke-WebRequest -Uri "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17928-20156.exe" `
#             -OutFile "$odtDir\odt_installer.exe" -UseBasicParsing
#         Start-Process -FilePath "$odtDir\odt_installer.exe" -ArgumentList "/quiet /extract:$odtDir" -Wait -NoNewWindow
#         Write-Log "  ODT extracted."
#     } catch {
#         Write-Log "  ODT download failed: $_ - trying winget fallback..." "WARN"
#         Install-App "Microsoft 365" "Microsoft.Office"
#     }

#     $odtXml = @"
# <Configuration>
#   <Add OfficeClientEdition="64" Channel="Current">
#     <Product ID="O365BusinessRetail">
#       <Language ID="en-us"/>
#       <ExcludeApp ID="Access"/>
#       <ExcludeApp ID="Groove"/>
#       <ExcludeApp ID="Lync"/>
#       <ExcludeApp ID="OneDrive"/>
#       <ExcludeApp ID="OneNote"/>
#       <ExcludeApp ID="Outlook"/>
#       <ExcludeApp ID="Publisher"/>
#       <ExcludeApp ID="Teams"/>
#     </Product>
#   </Add>
#   <Updates Enabled="FALSE"/>
#   <Display Level="None" AcceptEULA="TRUE"/>
#   <Property Name="AUTOACTIVATE" Value="0"/>
#   <Property Name="FORCEAPPSHUTDOWN" Value="TRUE"/>
# </Configuration>
# "@
#     $odtXml | Out-File -FilePath $odtConfig -Encoding UTF8 -Force

#     if (Test-Path $odtExe) {
#         Write-Log "  Running ODT — this takes 10-20 minutes..."
#         $p = Start-Process -FilePath $odtExe -ArgumentList "/configure `"$odtConfig`"" -Wait -NoNewWindow -PassThru
#         if ($p.ExitCode -eq 0) { Write-Log "  Microsoft 365 installed." }
#         else { Write-Log "  ODT exit code: $($p.ExitCode)" "WARN" }
#     }

#     # Office shortcuts
#     $offRoot = "$env:ProgramFiles\Microsoft Office\root\Office16"
#     if (-not (Test-Path $offRoot)) { $offRoot = "$env:ProgramFiles (x86)\Microsoft Office\root\Office16" }
#     if (Test-Path "$offRoot\WINWORD.EXE") { New-Shortcut "Word"       "$offRoot\WINWORD.EXE" }
#     if (Test-Path "$offRoot\EXCEL.EXE") { New-Shortcut "Excel"      "$offRoot\EXCEL.EXE" }
#     if (Test-Path "$offRoot\POWERPNT.EXE") { New-Shortcut "PowerPoint" "$offRoot\POWERPNT.EXE" }

#     # Apply desktop icon positions now all shortcuts exist
#     Write-Log "  Applying desktop icon positions..."
#     Start-Sleep -Seconds 3
#     try { & powershell.exe -ExecutionPolicy Bypass -File "$SetupRoot\Set-DesktopIconPositions.ps1" }
#     catch { Write-Log "  Icon positioning error (non-critical): $_" "WARN" }

#     Write-Log "--- PHASE 1 COMPLETE ---"
#     "2" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#     $currentPhase = 2
# }


# # ==============================================================================
# #   PHASES 2-4  Windows Updates — full updates, auto-reboot, resume
# # ==============================================================================
# if ($currentPhase -in @(2,3,4)) {
#     Write-Log "--- PHASE $currentPhase: Windows Updates ---"

#     # Install PSWindowsUpdate if missing
#     if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
#         Write-Log "  Installing PSWindowsUpdate module..."
#         try {
#             Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
#             Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber | Out-Null
#             Write-Log "  PSWindowsUpdate installed."
#         } catch { Write-Log "  PSWindowsUpdate install failed: $_" "ERROR" }
#     }

#     # Re-enable Windows Update services (Clark disabled them during OOBE)
#     Write-Log "  Re-enabling Windows Update..."
#     Set-Service  -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
#     Set-Service  -Name UsoSvc   -StartupType Automatic -ErrorAction SilentlyContinue
#     Set-Service  -Name BITS     -StartupType Automatic -ErrorAction SilentlyContinue
#     Start-Service -Name wuauserv -ErrorAction SilentlyContinue
#     Start-Service -Name BITS     -ErrorAction SilentlyContinue

#     # Remove localhost WU redirect Clark set during OOBE
#     Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer"       -ErrorAction SilentlyContinue
#     Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -ErrorAction SilentlyContinue
#     Set-ItemProperty    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "UseWUServer" -Value 0 -ErrorAction SilentlyContinue

#     try {
#         Import-Module PSWindowsUpdate -Force
#         Write-Log "  Checking for updates (Phase $currentPhase)..."
#         $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot 2>&1
#         $updateCount = ($updates | Where-Object { $_ -match "KB" }).Count

#         if ($updateCount -gt 0) {
#             Write-Log "  Found $updateCount update(s) — installing..."
#             Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot:$false | ForEach-Object { Write-Log "  $_" }
#             $next = $currentPhase + 1
#             "$next" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#             Write-Log "  Rebooting for Phase $next..."
#             Start-Sleep -Seconds 5
#             Restart-Computer -Force
#             exit
#         } else {
#             Write-Log "  No updates found in Phase $currentPhase — advancing."
#             $next = $currentPhase + 1
#             "$next" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#             $currentPhase = $next
#         }
#     } catch {
#         Write-Log "  Update error Phase $currentPhase : $_" "ERROR"
#         $next = $currentPhase + 1
#         "$next" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#         $currentPhase = $next
#     }
# }


# # ==============================================================================
# #   PHASE 5  Chrome Bookmarks + Sidebar (placeholder)
# # ==============================================================================
# if ($currentPhase -eq 5) {
#     Write-Log "--- PHASE 5: Post-update tasks ---"

#     # Chrome bookmarks import
#     $bookmarksPending = "$SetupRoot\chrome-bookmarks-pending.html"
#     $chromePath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
#     if (-not (Test-Path $chromePath)) { $chromePath = "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe" }

#     if ((Test-Path $bookmarksPending) -and (Test-Path $chromePath)) {
#         Write-Log "  Importing Chrome bookmarks..."
#         try {
#             $proc = Start-Process -FilePath $chromePath `
#                 -ArgumentList "--import-bookmarks=`"$bookmarksPending`" --no-first-run --no-default-browser-check" `
#                 -PassThru
#             Start-Sleep -Seconds 8
#             $proc | Stop-Process -Force -ErrorAction SilentlyContinue
#             Remove-Item $bookmarksPending -Force -ErrorAction SilentlyContinue
#             Write-Log "  Chrome bookmarks imported."
#         } catch { Write-Log "  Bookmarks import error: $_" "WARN" }
#     } else {
#         Write-Log "  Chrome bookmarks skipped (file or Chrome not found)." "WARN"
#     }

#     # Sidebar — to be added when Sidebar details are provided
#     Write-Log "  Sidebar: pending (to be configured)."

#     Write-Log "--- PHASE 5 COMPLETE ---"
#     "6" | Out-File -FilePath $FlagFile -Encoding UTF8 -Force
#     $currentPhase = 6
# }


# # ==============================================================================
# #   PHASE 6  Cleanup
# # ==============================================================================
# if ($currentPhase -eq 6) {
#     Write-Log "--- PHASE 6: Cleanup ---"

#     # Main user stays in Administrators (no demotion to standard user).

#     # Remove Task Scheduler entry
#     Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
#     Write-Log "  Task Scheduler entry removed."

#     # Self-delete C:\Setup on next boot via one-shot SYSTEM task
#     $cmd = "Start-Sleep 5; Remove-Item -Path 'C:\Setup' -Recurse -Force -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName 'ASYS_Cleanup' -Confirm:`$false"
#     Register-ScheduledTask `
#         -TaskName  "ASYS_Cleanup" `
#         -Action    (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$cmd`"") `
#         -Trigger   (New-ScheduledTaskTrigger -AtStartup) `
#         -Settings  (New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)) `
#         -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount) `
#         -Force | Out-Null

#     Write-Log "========================================================"
#     Write-Log "ASYS SETUP COMPLETE. Machine is ready."
#     Write-Log "========================================================"
# }




# # ==============================================================================
# #   CONFIRMATION POPUP  (shown on Phase 0 first run only)
# # ==============================================================================
# if ($currentPhase -le 1) {
#     $waited = 0
#     while (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
#         Start-Sleep -Seconds 2; $waited += 2
#         if ($waited -ge 60) { break }
#     }
#     Start-Sleep -Seconds 3

#     try {
#         Add-Type -AssemblyName PresentationFramework
#         $msg = @"
# Advanced Systems  Setup Pipeline v0.2
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# PHASE 0 COMPLETE

#   Task Scheduler: ASYS_SetupResume registered
#   Privacy: all 6 options disabled
#   Dark mode: enabled
#   Wallpaper: Static image (lock screen + desktop)
#   Region: Malaysia  date DD-MM-YYYY
#   Timezone: Singapore Standard Time (UTC+8)
#   Taskbar: left aligned, search icon,
#            no news/widgets, Edge + Explorer pinned
#   Quick Settings: Internet, Bluetooth, Night Light
#   Chrome: uBlock Origin Lite + AdBlocker Ultimate set
#   Chrome bookmarks: staged for Phase 5 import
#   Desktop shortcuts: created
#   Startup: OneDrive and Teams autostart disabled

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# App installs and Windows Updates coming next.

# Log: C:\Setup\setup.log
# "@
#         [System.Windows.MessageBox]::Show(
#             $msg,
#             "ASYS Setup  Phase 0 Complete",
#             [System.Windows.MessageBoxButton]::OK,
#             [System.Windows.MessageBoxImage]::Information
#         ) | Out-Null
#         Write-Log "Confirmation popup dismissed."
#     } catch {
#         Write-Log "Popup error (non-critical): $_" "WARN"
#     }
# }

# Write-Log "master.ps1 run complete. Phase: $currentPhase"


Write-Log "master.ps1 run complete. All phases currently disabled pending Windows install validation."
