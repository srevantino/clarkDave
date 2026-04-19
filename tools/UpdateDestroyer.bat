:: Update Destroyer (Apply)
:: Aggressively disables Windows Update components, blocks key update binaries, and applies policies that prevent automatic updates and Microsoft Store updates.
sc config wuauserv start= disabled
sc stop wuauserv
sc config UsoSvc start= disabled
sc stop UsoSvc
sc config DoSvc start= disabled
sc stop DoSvc

reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t REG_DWORD /d 4 /f

takeown /f "%WINDIR%\System32\usocoreworker.exe" /a
icacls "%WINDIR%\System32\usocoreworker.exe" /inheritance:r /deny "NT AUTHORITY\SYSTEM:(F)"

takeown /f "%WINDIR%\System32\wuaueng.dll" /a
icacls "%WINDIR%\System32\wuaueng.dll" /inheritance:r /deny "NT AUTHORITY\SYSTEM:(F)"

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v RemoveWindowsStore /t REG_DWORD /d 1 /f
