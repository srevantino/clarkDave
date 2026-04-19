function Set-WinUtilDNS {
    <#

    .SYNOPSIS
        Sets DNS servers on selected network adapters (defaults to adapters in Up state).

    .PARAMETER DNSProvider
        Key from dns.json (e.g. Google, Cloudflare), DHCP, or Custom.

    .PARAMETER InterfaceIndex
        Optional list of adapter interface indexes. When omitted, uses all Up adapters unless AllAdapters is set.

    .PARAMETER AllAdapters
        When set, includes every Get-NetAdapter result (not only Up).

    .PARAMETER CustomPrimaryV4
    .PARAMETER CustomSecondaryV4
    .PARAMETER CustomPrimaryV6
    .PARAMETER CustomSecondaryV6
        Used when DNSProvider is Custom.

    .EXAMPLE
        Set-WinUtilDNS -DNSProvider "google"

    #>
    param(
        [string]$DNSProvider = "Default",
        [int[]]$InterfaceIndex = $null,
        [switch]$AllAdapters,
        [string]$CustomPrimaryV4,
        [string]$CustomSecondaryV4,
        [string]$CustomPrimaryV6,
        [string]$CustomSecondaryV6
    )

    if ($DNSProvider -eq "Default") {
        return
    }

    $useAddressFamily = $false
    try {
        $cmd = Get-Command Set-DnsClientServerAddress -ErrorAction Stop
        $useAddressFamily = $cmd.Parameters.ContainsKey("AddressFamily")
    } catch {
        $useAddressFamily = $false
    }

    try {
        $allNet = @(Get-NetAdapter -ErrorAction Stop)
        if ($InterfaceIndex -and $InterfaceIndex.Count -gt 0) {
            $Adapters = @($allNet | Where-Object { $InterfaceIndex -contains $_.ifIndex })
        } elseif ($AllAdapters) {
            $Adapters = $allNet
        } else {
            $Adapters = @($allNet | Where-Object { $_.Status -eq "Up" })
        }

        if ($Adapters.Count -eq 0) {
            Write-Warning "No network adapters matched the selection."
            return
        }

        Write-Host "DNS target: $DNSProvider - adapters:"
        Write-Host ($Adapters | Select-Object Name, InterfaceIndex, Status | Format-Table | Out-String)

        foreach ($Adapter in $Adapters) {
            $idx = $Adapter.ifIndex
            if ($DNSProvider -eq "DHCP") {
                if ($useAddressFamily) {
                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ResetServerAddresses -ErrorAction SilentlyContinue
                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ResetServerAddresses -ErrorAction SilentlyContinue
                } else {
                    Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction SilentlyContinue
                }
                continue
            }

            if ($DNSProvider -eq "Custom") {
                $v4 = @($CustomPrimaryV4, $CustomSecondaryV4 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $v6 = @($CustomPrimaryV6, $CustomSecondaryV6 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($v4.Count -eq 0 -and $v6.Count -eq 0) {
                    Write-Warning "Custom DNS selected but no addresses were provided."
                    continue
                }
                if ($useAddressFamily) {
                    if ($v4.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ServerAddresses $v4 -ErrorAction Stop
                    }
                    if ($v6.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ServerAddresses $v6 -ErrorAction Stop
                    }
                } else {
                    if ($v4.Count -gt 0) {
                        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $v4 -ErrorAction Stop
                    }
                    if ($v6.Count -gt 0) {
                        Write-Warning "IPv6 custom DNS may require a newer DnsClient module (AddressFamily)."
                    }
                }
                continue
            }

            $cfg = $sync.configs.dns.$DNSProvider
            if (-not $cfg) {
                Write-Warning "Unknown DNS provider key: $DNSProvider"
                continue
            }

            $v4p = [string]$cfg.Primary
            $v4s = [string]$cfg.Secondary
            $v6p = if ($cfg.PSObject.Properties.Name -contains "Primary6") { [string]$cfg.Primary6 } else { "" }
            $v6s = if ($cfg.PSObject.Properties.Name -contains "Secondary6") { [string]$cfg.Secondary6 } else { "" }

            if ($useAddressFamily) {
                Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ServerAddresses @($v4p, $v4s) -ErrorAction Stop
                if (-not [string]::IsNullOrWhiteSpace($v6p) -or -not [string]::IsNullOrWhiteSpace($v6s)) {
                    Set-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv6 -ServerAddresses @($v6p, $v6s) -ErrorAction SilentlyContinue
                }
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($v4p, $v4s) -ErrorAction Stop
            }
        }
    } catch {
        Write-Warning "Unable to set DNS: $($_.Exception.Message)"
        Write-Warning $_.ScriptStackTrace
    }
}
