#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Invoke-ClarkSetupCommon.ps1')

if (-not (Find-ClarkAsysRoot)) {
    Show-ClarkSetupError -Title 'ASYS payload missing' -Message @(
        'Could not find \asys on the install media.'
        'Rebuild the ISO with Clark (Auto firmware mode).'
        'On Ventoy use WIMBOOT (Ctrl+W) if setup fails.'
    ) -join "`n"
    exit 1
}

Invoke-ClarkSetupPhase -PhaseName 'Platform drivers' -Action { & (Join-Path $here 'Invoke-ClarkSetupPlatformDrivers.ps1') }
Invoke-ClarkSetupPhase -PhaseName 'Disk layout (UEFI/Legacy)' -Action { & (Join-Path $here 'Invoke-ClarkSetupDiskLayout.ps1') }
Invoke-ClarkSetupPhase -PhaseName 'Post-layout verification' -Action {
    $vol = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' -and $_.DriveType -eq 'Fixed' } |
        Sort-Object Size -Descending | Select-Object -First 1
    if (-not $vol) { throw 'No NTFS fixed volume after disk layout.' }
    Write-ClarkSetupLog -Message ("Target: {0}:\" -f $vol.DriveLetter) -LogName 'bootstrap.log'
}
