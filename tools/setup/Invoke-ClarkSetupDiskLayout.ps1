#Requires -Version 5.1

$here = $PSScriptRoot

. (Join-Path $here 'Invoke-ClarkSetupCommon.ps1')



function Get-FirmwareMode {

    try {

        $pe = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction Stop).PEFirmwareType

        if ($pe -eq 2) { return 'UEFI' }

        if ($pe -eq 1) { return 'Legacy' }

    } catch { }

    if ($env:firmware_type -eq 'UEFI') { return 'UEFI' }

    if ($env:firmware_type -eq 'BIOS') { return 'Legacy' }

    return 'UEFI'

}



function Get-TargetDisk { Select-ClarkTargetDisk }



function Invoke-DiskpartScript {

    param([string[]]$Lines, [int]$DiskNumber)

    $scriptPath = Join-Path $env:TEMP "clark-diskpart-$DiskNumber.txt"

    @("select disk $DiskNumber", 'clean') + $Lines | Set-Content -LiteralPath $scriptPath -Encoding ASCII

    $out = @(& diskpart.exe /s $scriptPath 2>&1 | ForEach-Object { $_.ToString() })

    $out | ForEach-Object { Write-ClarkSetupLog -Message $_ -LogName 'disk-layout.log' }

    if ($LASTEXITCODE -ne 0) { throw "diskpart failed: $($out -join '; ')" }

}



$firmware = Get-FirmwareMode

Write-ClarkSetupLog -Message "Firmware: $firmware" -LogName 'disk-layout.log'

$disk = Get-TargetDisk

Write-ClarkSetupLog -Message ("Disk {0}: {1:N0} bytes" -f $disk.Number, $disk.Size) -LogName 'disk-layout.log'



if ($firmware -eq 'UEFI') {

    Invoke-DiskpartScript -DiskNumber $disk.Number -Lines @(

        'convert gpt', 'create partition efi size=300', 'format fs=fat32 quick label=System',

        'create partition msr size=16', 'create partition primary', 'format fs=ntfs quick label=Windows'

    )

} else {

    Invoke-DiskpartScript -DiskNumber $disk.Number -Lines @(

        'convert mbr', 'create partition primary', 'format fs=ntfs quick label=Windows', 'active'

    )

}

