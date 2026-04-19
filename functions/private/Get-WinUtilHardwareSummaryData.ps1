function Get-WinUtilHardwareSummaryData {
    <#
    .SYNOPSIS
        Collects hardware strings for UI / export via CIM.
    #>
    $sb = [System.Text.StringBuilder]::new()

    $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)
    [void]$sb.AppendLine("=== CPU ===")
    foreach ($c in $cpu) {
        [void]$sb.AppendLine("$($c.Name)")
        [void]$sb.AppendLine("  Manufacturer: $($c.Manufacturer)  Cores: $($c.NumberOfCores)  Logical: $($c.NumberOfLogicalProcessors)")
    }

    $ram = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== Memory ===")
    if ($ram) {
        $totalGb = [math]::Round($ram.TotalPhysicalMemory / 1GB, 2)
        [void]$sb.AppendLine("Total visible: $totalGb GB")
    }
    foreach ($m in $modules) {
        $cap = [math]::Round($m.Capacity / 1GB, 2)
        [void]$sb.AppendLine("  $cap GB @ $($m.Speed) MHz  $($m.Manufacturer)  $($m.PartNumber)".Trim())
    }

    $gpu = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== Display adapters ===")
    foreach ($g in $gpu) {
        if ([string]::IsNullOrWhiteSpace($g.Name)) { continue }
        [void]$sb.AppendLine("$($g.Name)")
        [void]$sb.AppendLine("  Driver: $($g.DriverVersion)  RAM: $($g.AdapterRAM)  Status: $($g.Status)")
    }

    $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== Motherboard ===")
    if ($board) {
        [void]$sb.AppendLine("$($board.Manufacturer) $($board.Product)  ($($board.Version))")
        [void]$sb.AppendLine("  Serial: $($board.SerialNumber)")
    }

    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    if ($bios) {
        [void]$sb.AppendLine("BIOS: $($bios.SMBIOSBIOSVersion)  $($bios.ReleaseDate)")
    }

    $disks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== Disk drives ===")
    foreach ($d in $disks) {
        $sizeGb = if ($d.Size) { [math]::Round([double]$d.Size / 1GB, 0) } else { "?" }
        [void]$sb.AppendLine("$($d.Model)  $($sizeGb) GB  [$($d.InterfaceType)]  $($d.MediaType)")
    }

    $vols = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 3 })
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== Logical volumes ===")
    foreach ($v in $vols) {
        $free = [math]::Round($v.FreeSpace / 1GB, 1)
        $tot = [math]::Round($v.Size / 1GB, 1)
        [void]$sb.AppendLine("$($v.DeviceID)  $free / $tot GB free  $($v.VolumeName)  [$($v.FileSystem)]")
    }

    try {
        $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        if ($pd.Count -gt 0) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("=== PhysicalDisk (health) ===")
            foreach ($p in $pd) {
                [void]$sb.AppendLine("$($p.FriendlyName)  Health: $($p.HealthStatus)  Op: $($p.OperationalStatus)  Media: $($p.MediaType)")
            }
        }
    } catch { }

    return $sb.ToString()
}
