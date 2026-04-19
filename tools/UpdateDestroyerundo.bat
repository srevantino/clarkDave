:: Update Destroyer (Undo)
:: Reverts Update Destroyer changes by restoring file ACLs, removing update-blocking policies, and re-enabling core Windows Update services.
icacls "%WINDIR%\System32\usocoreworker.exe" /reset
icacls "%WINDIR%\System32\wuaueng.dll" /reset

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v RemoveWindowsStore /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t REG_DWORD /d 3 /f

sc config wuauserv start= demand
sc config UsoSvc start= delayed-auto
sc config DoSvc start= auto

sc start wuauserv
sc start UsoSvc
sc start DoSvc
