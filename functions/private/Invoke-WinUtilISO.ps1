function Get-Win11ISOLogFilePath {
    if (-not $sync["Win11ISOGlobalLogPath"]) {
        $logDir = Join-Path $env:TEMP "ASYS_Win11ISO_Logs"
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $sync["Win11ISOGlobalLogPath"] = Join-Path $logDir ("ASYS_Win11ISO_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    }

    return $sync["Win11ISOGlobalLogPath"]
}

function Write-Win11ISOLogCore {
    <#
        .SYNOPSIS
            Append one ISO status line to file + WPF log. Safe from any thread (uses Form.Dispatcher.Invoke).
            Does not depend on Invoke-WPFUIThread so it can be dot-sourced into ISO worker runspaces.
        .NOTES
            Uses DispatcherOperationCallback + state argument so the line text is not lost when PowerShell
            converts scriptblocks to delegates (broken closure capture with [System.Action]).
    #>
    param([string]$Line)

    try {
        $logPath = Get-Win11ISOLogFilePath
        Add-Content -LiteralPath $logPath -Value $Line -ErrorAction SilentlyContinue
    } catch {}

    if ($PARAM_NOUI) {
        Write-Host $Line
        return
    }

    $win = $sync["Form"]
    if (-not $win) {
        Write-Host $Line
        return
    }

    try {
        [void]$win.Dispatcher.Invoke(
            [System.Windows.Threading.DispatcherPriority]::Normal,
            [System.Windows.Threading.DispatcherOperationCallback]{
                param($state)
                $appendLine = [string]$state
                $tb = $sync["WPFWin11ISOStatusLog"]
                if (-not $tb) { return $null }
                $current = [string]$tb.Text
                if ($current -eq "Ready. Please select a Windows 10 or Windows 11 ISO to begin.") {
                    $tb.Text = $appendLine
                } else {
                    $tb.Text += "`n$appendLine"
                }
                $tb.CaretIndex = $tb.Text.Length
                $tb.ScrollToEnd()
                return $null
            },
            $Line
        )
    } catch {
        Write-Host $Line
    }
}

function Add-Win11ISOStatusLogLineUIThread {
    <#
        .SYNOPSIS
            Append a line to the ISO status TextBox on the UI thread only. Call from click handlers (already on UI thread).
    #>
    param([string]$Line)

    $tb = $sync["WPFWin11ISOStatusLog"]
    if (-not $tb) { return }
    $current = [string]$tb.Text
    if ($current -eq "Ready. Please select a Windows 10 or Windows 11 ISO to begin.") {
        $tb.Text = $Line
    } else {
        $tb.Text += "`n$Line"
    }
    $tb.CaretIndex = $tb.Text.Length
    $tb.ScrollToEnd()
}

function Write-Win11ISOLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $line = "[$ts] $Message"
    Write-Win11ISOLogCore -Line $line
}

function Set-WinUtilISODownloadProgress {
    param(
        [int]$Percent,
        [string]$Text,
        [switch]$Hide
    )

    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $sync["WinISODownloadLastPercent"] = $safePercent

    Invoke-WPFUIThread -ScriptBlock {
        if (-not $sync["WPFWinISODownloadProgressBar"] -or -not $sync["WPFWinISODownloadProgressText"]) {
            return
        }

        if ($Hide) {
            $sync["WPFWinISODownloadProgressBar"].Visibility = "Collapsed"
            $sync["WPFWinISODownloadProgressText"].Visibility = "Collapsed"
            $sync["WPFWinISODownloadProgressBar"].Value = 0
            $sync["WPFWinISODownloadProgressText"].Text = ""
            return
        }

        $sync["WPFWinISODownloadProgressBar"].Visibility = "Visible"
        $sync["WPFWinISODownloadProgressText"].Visibility = "Visible"
        $sync["WPFWinISODownloadProgressBar"].Value = $safePercent
        $sync["WPFWinISODownloadProgressText"].Text = $Text
    }
}

function Set-WinUtilISODownloadControlState {
    param(
        [bool]$IsRunning,
        [bool]$IsPaused = $false
    )

    Invoke-WPFUIThread -ScriptBlock {
        if ($sync["WPFWinISODownloadDirectButton"]) {
            $sync["WPFWinISODownloadDirectButton"].IsEnabled = -not $IsRunning
        }
        if ($sync["WPFWinISODownloadPauseButton"]) {
            $sync["WPFWinISODownloadPauseButton"].IsEnabled = $IsRunning
            $sync["WPFWinISODownloadPauseButton"].Content = if ($IsPaused) { "Resume" } else { "Pause" }
        }
        if ($sync["WPFWinISODownloadStopButton"]) {
            $sync["WPFWinISODownloadStopButton"].IsEnabled = $IsRunning
        }
    }
}

function Test-WinUtilISODownloadStopRequested {
    if ($sync["WinISODownloadStopRequested"]) {
        throw "ISO download stopped by user."
    }
}

function Resume-WinUtilISOBitsJob {
    <#
        .SYNOPSIS
            Resumes a suspended BITS job without blocking indefinitely (sync Resume-BitsTransfer can hang after Suspend).
        Uses -Asynchronous then polls until the job leaves Suspended or times out.
    #>
    param(
        [Parameter(Mandatory)][string]$BitsJobId,
        [int]$WaitSeconds = 45
    )

    $job = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
    if (-not $job -or $job.JobState -ne "Suspended") {
        return $job
    }

    try {
        Resume-BitsTransfer -BitsJob $job -Asynchronous -ErrorAction Stop
    } catch {
        Write-Win11ISOLog "BITS Resume-BitsTransfer failed: $($_.Exception.Message)"
        try {
            $job2 = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
            if ($job2 -and $job2.JobState -eq "Suspended") {
                Resume-BitsTransfer -BitsJob $job2 -Asynchronous -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Milliseconds 250
        Test-WinUtilISODownloadStopRequested
        $job = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
        if (-not $job) {
            return $null
        }
    } while ($job.JobState -eq "Suspended" -and (Get-Date) -lt $deadline)

    return $job
}

function Invoke-WinUtilISODirectDownloadPauseToggle {
    if (-not $sync["WinISODownloadRunning"]) {
        return
    }

    $isPaused = [bool]$sync["WinISODownloadPauseRequested"]
    $newPausedState = -not $isPaused
    $sync["WinISODownloadPauseRequested"] = $newPausedState
    $sync["WinISODownloadIsPaused"] = $newPausedState

    if ($newPausedState) {
        Write-Win11ISOLog "ISO download paused."
        Set-WinUtilISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
    } else {
        Write-Win11ISOLog "ISO download resumed."
    }
    Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $newPausedState
}

function Invoke-WinUtilISODirectDownloadStop {
    if (-not $sync["WinISODownloadRunning"]) {
        return
    }

    $sync["WinISODownloadStopRequested"] = $true
    $sync["WinISODownloadPauseRequested"] = $false
    $sync["WinISODownloadIsPaused"] = $false
    Write-Win11ISOLog "Stop requested for ISO download..."

    $bitsJobId = [string]$sync["WinISODownloadBitsJobId"]
    if (-not [string]::IsNullOrWhiteSpace($bitsJobId)) {
        try {
            $bitsJob = Get-BitsTransfer -Id $bitsJobId -ErrorAction SilentlyContinue
            if ($bitsJob) {
                Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Show-WinUtilISOMessageBox {
    <#
        .SYNOPSIS
            Shows a WPF MessageBox on the UI thread. Required when calling from ISO worker runspaces;
            MessageBox from a pool thread can deadlock or freeze the app after the dialog closes.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.MessageBoxButton]$Button = 'OK',
        [System.Windows.MessageBoxImage]$Image = 'Information'
    )

    if ($PARAM_NOUI) {
        return [System.Windows.MessageBoxResult]::None
    }

    $win = $sync["Form"]
    if (-not $win) {
        return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Image)
    }

    $state = [pscustomobject]@{
        Body   = $Message
        Title  = $Title
        Button = $Button
        Image  = $Image
        Result = [System.Windows.MessageBoxResult]::None
    }
    [void]$win.Dispatcher.Invoke(
        [System.Windows.Threading.DispatcherPriority]::Normal,
        [System.Windows.Threading.DispatcherOperationCallback]{
            param($s)
            $o = $s
            $o.Result = [System.Windows.MessageBox]::Show($o.Body, $o.Title, $o.Button, $o.Image)
            return $null
        },
        $state
    )
    return $state.Result
}

function Get-WinUtilISODirectDownloadCatalog {
    # Passed to Fido.ps1 as -Rel. Fido matches with release.StartsWith(Rel) or Rel eq 'Latest'.
    # Microsoft/Fido refresh often drops older builds; stale labels (e.g. 24H2) make Fido exit before any URL is returned.
    return @{
        "Windows 11" = @("Latest", "25H2")
        "Windows 10" = @("Latest", "22H2")
    }
}

function Set-WinUtilISODirectDownloadVersions {
    if (-not $sync["WPFWinISODownloadProductComboBox"] -or -not $sync["WPFWinISODownloadVersionComboBox"]) {
        return
    }

    $catalog = Get-WinUtilISODirectDownloadCatalog
    $selectedProduct = [string]$sync["WPFWinISODownloadProductComboBox"].SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedProduct)) {
        $selectedProduct = "Windows 11"
    }

    $versions = @($catalog[$selectedProduct])
    if (-not $versions -or $versions.Count -eq 0) {
        $versions = @("Latest")
    }

    $sync["WPFWinISODownloadVersionComboBox"].Items.Clear()
    foreach ($version in $versions) {
        [void]$sync["WPFWinISODownloadVersionComboBox"].Items.Add($version)
    }
    $sync["WPFWinISODownloadVersionComboBox"].SelectedIndex = 0
}

function Get-WinUtilFidoScriptPath {
    # Prefer repo-shipped Fido (works offline / when GitHub is blocked); else cache under LocalAppData\asys\tools.
    if ($sync.PSScriptRoot) {
        $bundledFido = Join-Path $sync.PSScriptRoot "tools\Fido.ps1"
        if (Test-Path -LiteralPath $bundledFido) {
            return $bundledFido
        }
    }

    $toolsDir = Join-Path $sync.asysdir "tools"
    if (-not (Test-Path $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    }

    $fidoPath = Join-Path $toolsDir "Fido.ps1"
    if (-not (Test-Path $fidoPath)) {
        Write-Win11ISOLog "Downloading Fido helper script from GitHub..."
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1" -OutFile $fidoPath -UseBasicParsing
        Write-Win11ISOLog "Fido helper script downloaded."
    }

    return $fidoPath
}

function Get-WinUtilInternetArchiveIsoUrlFromConfig {
    param(
        [Parameter(Mandatory)][string]$WindowsProduct,
        [Parameter(Mandatory)][string]$WindowsRelease
    )

    try {
        $root = $sync.configs.isomirrors
        if (-not $root) { return $null }
        $urls = $root.internetArchiveIsoUrls
        if (-not $urls) { return $null }

        $prodNode = $null
        foreach ($p in $urls.PSObject.Properties) {
            if ($p.Name -eq $WindowsProduct) {
                $prodNode = $p.Value
                break
            }
        }
        if (-not $prodNode) { return $null }

        foreach ($r in $prodNode.PSObject.Properties) {
            if ($r.Name -eq $WindowsRelease) {
                $cand = [string]$r.Value
                if ([string]::IsNullOrWhiteSpace($cand)) { return $null }
                $cand = $cand.Trim()
                if ($cand -match '^https?://') { return $cand }
                return $null
            }
        }
    } catch {}

    return $null
}

function Initialize-WinUtilISODownloadTls {
    try {
        $p = [Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [Net.SecurityProtocolType]::Tls13 } catch {}
        [Net.ServicePointManager]::SecurityProtocol = $p
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }
}

function New-WinUtilISODownloadHttpClient {
    <#
        .SYNOPSIS
            HttpClient configured for large ISO downloads (not default 100s timeout), TLS 1.2+, redirects, and a normal browser User-Agent.
    #>
    Initialize-WinUtilISODownloadTls
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 16
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $handler.UseDefaultCredentials = $true

    $client = [System.Net.Http.HttpClient]::new($handler)
    try {
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    } catch {
        $client.Timeout = [TimeSpan]::FromDays(7)
    }
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    )
    [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept', '*/*')
    return $client
}

function Invoke-WinUtilISOBitsOrHttpDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$WindowsProduct = "",
        [string]$WindowsRelease = ""
    )

    $bitsDescription = if ($WindowsProduct) { "$WindowsProduct $WindowsRelease" } else { "ISO download" }

    try {
        Import-Module BitsTransfer -ErrorAction Stop
        $bitsJob = Start-BitsTransfer -Source $Url -Destination $Destination -DisplayName "clark ISO Download" -Description $bitsDescription -Asynchronous
        if (-not $bitsJob -or [string]::IsNullOrWhiteSpace([string]$bitsJob.JobId)) {
            throw "BITS did not return a transfer job (JobId empty)."
        }
        $bitsJobId = $bitsJob.JobId
        $sync["WinISODownloadBitsJobId"] = [string]$bitsJobId
        $downloadStart = Get-Date

        do {
            Start-Sleep -Seconds 1
            Test-WinUtilISODownloadStopRequested

            $bitsJob = Get-BitsTransfer -Id $bitsJobId -ErrorAction SilentlyContinue
            if (-not $bitsJob) {
                Test-WinUtilISODownloadStopRequested
                throw "BITS job was not found (it may have been cancelled or cleared). JobId: $bitsJobId"
            }

            if ($sync["WinISODownloadPauseRequested"] -eq $true) {
                if ($bitsJob.JobState -ne "Suspended") {
                    Suspend-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                }
                $sync["WinISODownloadIsPaused"] = $true
                Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $true
                Set-WinUtilISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    Start-Sleep -Milliseconds 500
                    Test-WinUtilISODownloadStopRequested
                }

                $bitsJob = Resume-WinUtilISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-WinUtilISODownloadStopRequested
                    throw "BITS job was not found after resume (it may have been cancelled). JobId: $bitsJobId"
                }
                $sync["WinISODownloadIsPaused"] = $false
                Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $false
            }

            if ($bitsJob -and $bitsJob.JobState -eq "Suspended" -and $sync["WinISODownloadPauseRequested"] -ne $true) {
                $bitsJob = Resume-WinUtilISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-WinUtilISODownloadStopRequested
                    throw "BITS job was not found while resuming. JobId: $bitsJobId"
                }
                if ($bitsJob.JobState -eq "Suspended") {
                    throw "Download resume did not complete (BITS remained suspended)."
                }
            }

            $bytesTotal = [double]$bitsJob.BytesTotal
            $bytesTransferred = [double]$bitsJob.BytesTransferred
            $percent = if ($bytesTotal -gt 0) { [int][Math]::Round(($bytesTransferred / $bytesTotal) * 100, 0) } else { 0 }

            $elapsedSeconds = [Math]::Max(1.0, ((Get-Date) - $downloadStart).TotalSeconds)
            $speedBps = if ($bytesTransferred -gt 0) { $bytesTransferred / $elapsedSeconds } else { 0.0 }
            $remainingBytes = [Math]::Max(0.0, $bytesTotal - $bytesTransferred)
            $etaText = if ($speedBps -gt 0 -and $bytesTotal -gt 0) {
                $etaSeconds = [int][Math]::Ceiling($remainingBytes / $speedBps)
                [TimeSpan]::FromSeconds($etaSeconds).ToString("hh\:mm\:ss")
            } else {
                "estimating..."
            }

            $downloadedMb = [Math]::Round($bytesTransferred / 1MB, 1)
            $totalMb = if ($bytesTotal -gt 0) { [Math]::Round($bytesTotal / 1MB, 1) } else { 0 }
            $label = if ($bytesTotal -gt 0) {
                "Downloading ISO... $percent% ($downloadedMb MB / $totalMb MB, ETA $etaText)"
            } else {
                "Downloading ISO... $percent% (ETA $etaText)"
            }

            Set-WinUtilProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
            Set-WinUtilISODownloadProgress -Percent $percent -Text $label
        } while ($bitsJob.JobState -in @("Queued", "Connecting", "Transferring", "Suspended"))

        Test-WinUtilISODownloadStopRequested
        if ($bitsJob.JobState -eq "Transferred") {
            Complete-BitsTransfer -BitsJob $bitsJob -ErrorAction Stop
        } elseif ($bitsJob.JobState -eq "Error") {
            $errorText = if ($bitsJob.ErrorDescription) { $bitsJob.ErrorDescription } else { "BITS download failed." }
            throw $errorText
        } else {
            throw "BITS download did not complete successfully. Final state: $($bitsJob.JobState)"
        }
    } catch {
        if ($sync["WinISODownloadStopRequested"] -or $_.Exception.Message -match "stopped by user") {
            try { Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "clark ISO Download" } | Remove-BitsTransfer -ErrorAction SilentlyContinue } catch {}
            if (Test-Path -LiteralPath $Destination) {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            }
            throw "ISO download stopped by user."
        }

        Write-Win11ISOLog "BITS path failed ($($_.Exception.Message)); using HTTP fallback."
        try { Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "clark ISO Download" } | Remove-BitsTransfer -ErrorAction SilentlyContinue } catch {}
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }

        Set-WinUtilProgressBar -Label "Downloading ISO via HTTP..." -Percent 15
        Set-WinUtilISODownloadProgress -Percent 5 -Text "Downloading ISO via HTTP..."

        $client = $null
        $response = $null
        $sourceStream = $null
        $targetStream = $null

        try {
            $client = New-WinUtilISODownloadHttpClient
            $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode()
            $totalBytes = [double]($response.Content.Headers.ContentLength | ForEach-Object { $_ })
            if (-not $totalBytes) { $totalBytes = 0.0 }

            $sourceStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $targetStream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = New-Object byte[] (1024 * 1024)
            $downloadedBytes = 0.0
            $lastUpdate = Get-Date
            $httpStart = Get-Date

            while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                Test-WinUtilISODownloadStopRequested

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    $sync["WinISODownloadIsPaused"] = $true
                    Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $true
                    Set-WinUtilISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
                    Start-Sleep -Milliseconds 500
                    Test-WinUtilISODownloadStopRequested
                }

                if ($sync["WinISODownloadIsPaused"]) {
                    $sync["WinISODownloadIsPaused"] = $false
                    Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $false
                }

                $targetStream.Write($buffer, 0, $read)
                $downloadedBytes += $read

                if (((Get-Date) - $lastUpdate).TotalMilliseconds -ge 1000) {
                    $percent = if ($totalBytes -gt 0) { [int][Math]::Round(($downloadedBytes / $totalBytes) * 100, 0) } else { 0 }
                    $elapsedSeconds = [Math]::Max(1.0, ((Get-Date) - $httpStart).TotalSeconds)
                    $speedBps = if ($downloadedBytes -gt 0) { $downloadedBytes / $elapsedSeconds } else { 0.0 }
                    $remainingBytes = [Math]::Max(0.0, $totalBytes - $downloadedBytes)
                    $etaText = if ($speedBps -gt 0 -and $totalBytes -gt 0) {
                        $etaSeconds = [int][Math]::Ceiling($remainingBytes / $speedBps)
                        [TimeSpan]::FromSeconds($etaSeconds).ToString("hh\:mm\:ss")
                    } else {
                        "estimating..."
                    }
                    $downloadedMb = [Math]::Round($downloadedBytes / 1MB, 1)
                    $totalMb = if ($totalBytes -gt 0) { [Math]::Round($totalBytes / 1MB, 1) } else { 0 }
                    $label = if ($totalBytes -gt 0) {
                        "Downloading ISO... $percent% ($downloadedMb MB / $totalMb MB, ETA $etaText)"
                    } else {
                        "Downloading ISO... $downloadedMb MB downloaded"
                    }
                    Set-WinUtilProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
                    Set-WinUtilISODownloadProgress -Percent $percent -Text $label
                    $lastUpdate = Get-Date
                }
            }
        } catch {
            if ($sync["WinISODownloadStopRequested"] -or $_.Exception.Message -match "stopped by user") {
                if (Test-Path -LiteralPath $Destination) {
                    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                }
                throw "ISO download stopped by user."
            }
            throw
        } finally {
            if ($targetStream) { $targetStream.Dispose() }
            if ($sourceStream) { $sourceStream.Dispose() }
            if ($response) { $response.Dispose() }
            if ($client) { $client.Dispose() }
        }
    } finally {
        $sync["WinISODownloadBitsJobId"] = $null
    }
}

function Test-WinUtilFidoMicrosoftAccessDenied {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '715-123130' -or
        $Text -match 'banned from using this service' -or
        $Text -match 'location hiding technologies' -or
        $Text -match 'unable to complete your request at this time'
}

function Get-WinUtilMicrosoftSoftwareDownloadUrl {
    param([string]$WindowsProduct)
    if ($WindowsProduct -match '11') {
        return 'https://www.microsoft.com/software-download/windows11'
    }
    return 'https://www.microsoft.com/software-download/windows10'
}

function Get-WinUtilDirectISODownloadUrl {
    param(
        [Parameter(Mandatory)]
        [string]$WindowsProduct,
        [Parameter(Mandatory)]
        [string]$WindowsRelease
    )

    $fidoPath = Get-WinUtilFidoScriptPath
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$fidoPath`"",
        "-Win", "`"$WindowsProduct`"",
        "-Rel", "`"$WindowsRelease`"",
        "-GetUrl"
    )

    $output = & powershell.exe @arguments 2>&1
    $outputText = ($output | ForEach-Object { "$_" }) -join ' '

    if ($LASTEXITCODE -ne 0) {
        if (Test-WinUtilFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-WinUtilMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request (message often includes 715-123130). " +
                "This usually happens with VPN/proxy/Tor, some datacenter or restricted networks, or regional limits - not a bug in clark.`n`n" +
                "What to try: disconnect VPN/proxy, use another network (e.g. home ISP or phone hotspot), wait and retry, or download the ISO in a browser from:`n$official"
            )
        }
        throw "Unable to get Microsoft ISO link for $WindowsProduct $WindowsRelease. Fido output: $outputText"
    }

    $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://.+\.iso(\?.*)?$' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)
    }

    if ([string]::IsNullOrWhiteSpace($url) -or $url -notmatch '^https?://') {
        if (Test-WinUtilFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-WinUtilMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request. " +
                "Try without VPN/proxy or use another network, or download from:`n$official"
            )
        }
        throw "No valid ISO URL was returned for $WindowsProduct $WindowsRelease."
    }

    return [string]$url.Trim()
}

function Invoke-WinUtilISODirectDownload {
    Add-Type -AssemblyName System.Windows.Forms

    $windowsProduct = [string]$sync["WPFWinISODownloadProductComboBox"].SelectedItem
    $windowsRelease = [string]$sync["WPFWinISODownloadVersionComboBox"].SelectedItem

    if ([string]::IsNullOrWhiteSpace($windowsProduct)) {
        $windowsProduct = "Windows 11"
    }
    if ([string]::IsNullOrWhiteSpace($windowsRelease)) {
        $windowsRelease = "Latest"
    }

    $fileName = if ($windowsProduct -match "11") {
        "Win11_$windowsRelease.iso"
    } else {
        "Win10_$windowsRelease.iso"
    }

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title = "Save downloaded ISO"
    $dlg.Filter = "ISO files (*.iso)|*.iso"
    $dlg.FileName = $fileName
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $destination = $dlg.FileName
    $sync["WinISODownloadRunning"] = $true
    $sync["WinISODownloadStopRequested"] = $false
    $sync["WinISODownloadPauseRequested"] = $false
    $sync["WinISODownloadIsPaused"] = $false
    $sync["WinISODownloadBitsJobId"] = $null
    Set-WinUtilISODownloadControlState -IsRunning $true -IsPaused $false
    Add-Win11ISOStatusLogLineUIThread "Starting direct download: $windowsProduct $windowsRelease -> $destination"

    Invoke-WPFRunspace -ParameterList @(("windowsProduct", $windowsProduct), ("windowsRelease", $windowsRelease), ("destination", $destination)) -ScriptBlock {
        param($windowsProduct, $windowsRelease, $destination)
        try {
            $sync.ProcessRunning = $true
            Set-WinUtilISODownloadProgress -Percent 0 -Text "Preparing download..."

            $archiveUrl = Get-WinUtilInternetArchiveIsoUrlFromConfig -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            $url = $null
            $triedArchive = $false

            if (-not [string]::IsNullOrWhiteSpace($archiveUrl)) {
                $url = $archiveUrl
                $triedArchive = $true
                Write-Win11ISOLog "Using mirror URL from config\\isomirrors.json for $windowsProduct $windowsRelease."
                Set-WinUtilProgressBar -Label "Downloading ISO (configured mirror)..." -Percent 15
            } else {
                Write-Win11ISOLog "No mirror URL in config for $windowsProduct $windowsRelease; resolving via Fido (Microsoft)..."
                Set-WinUtilProgressBar -Label "Resolving ISO URL (Fido)..." -Percent 10
                $url = Get-WinUtilDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
                Set-WinUtilProgressBar -Label "Starting ISO download..." -Percent 20
            }

            Write-Win11ISOLog "Download target: $destination"
            try {
                Invoke-WinUtilISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            } catch {
                if ($triedArchive) {
                    Write-Win11ISOLog "Mirror download failed ($($_.Exception.Message)); falling back to Fido (Microsoft)."
                    if (Test-Path -LiteralPath $destination) {
                        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                    }
                    Set-WinUtilProgressBar -Label "Resolving ISO URL (Fido fallback)..." -Percent 12
                    $url = Get-WinUtilDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
                    Write-Win11ISOLog "Fido URL resolved; starting download."
                    Set-WinUtilProgressBar -Label "Starting ISO download (Fido)..." -Percent 20
                    Invoke-WinUtilISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
                } else {
                    throw
                }
            }

            Set-WinUtilProgressBar -Label "Download complete" -Percent 100
            Set-WinUtilISODownloadProgress -Percent 100 -Text "Download complete: $destination"
            Write-Win11ISOLog "ISO download completed: $destination"
            $null = Show-WinUtilISOMessageBox -Message "ISO download complete:`n`n$destination" -Title "Download Complete" -Button OK -Image Information
        } catch {
            $errMsg = [string]$_.Exception.Message
            if ($errMsg -match "stopped by user") {
                Write-Win11ISOLog "ISO download stopped by user."
                Set-WinUtilISODownloadProgress -Percent 0 -Text "Download stopped."
                $null = Show-WinUtilISOMessageBox -Message "ISO download was stopped." -Title "Download Stopped" -Button OK -Image Information
                return
            }

            Write-Win11ISOLog "ERROR during direct ISO download: $_"
            Set-WinUtilISODownloadProgress -Percent 0 -Text "Download failed. Check the log for details."
            $officialPage = Get-WinUtilMicrosoftSoftwareDownloadUrl -WindowsProduct $windowsProduct
            if (Test-WinUtilFidoMicrosoftAccessDenied -Text $errMsg) {
                $prompt = "$errMsg`n`nOpen Microsoft's official download page in your browser?"
                $answer = Show-WinUtilISOMessageBox -Message $prompt -Title "Microsoft blocked automated download" -Button YesNo -Image Warning
                if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                    Start-Process $officialPage
                }
            } else {
                $null = Show-WinUtilISOMessageBox -Message "Direct ISO download failed:`n`n$errMsg" -Title "Download Error" -Button OK -Image Error
            }
        } finally {
            $sync.ProcessRunning = $false
            $sync["WinISODownloadRunning"] = $false
            $sync["WinISODownloadStopRequested"] = $false
            $sync["WinISODownloadPauseRequested"] = $false
            $sync["WinISODownloadIsPaused"] = $false
            $sync["WinISODownloadBitsJobId"] = $null
            Set-WinUtilProgressBar -Label "" -Percent 0
            Set-WinUtilISODownloadControlState -IsRunning $false -IsPaused $false
        }
    } | Out-Null
}

function Invoke-WinUtilISOBrowse {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Title            = "Select Windows 10 or Windows 11 ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso|All files (*.*)|*.*"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $isoPath    = $dlg.FileName
    $fileSizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 2)

    $sync["WPFWin11ISOPath"].Text           = $isoPath
    $sync["WPFWin11ISOFileInfo"].Text       = "File size: $fileSizeGB GB"
    $sync["WPFWin11ISOFileInfo"].Visibility = "Visible"
    $sync["WPFWin11ISOMountSection"].Visibility       = "Visible"
    $sync["WPFWin11ISOVerifyResultPanel"].Visibility  = "Collapsed"
    $sync["WPFWin11ISOModifySection"].Visibility      = "Collapsed"
    $sync["WPFWin11ISOOutputSection"].Visibility      = "Collapsed"

    $logPath = Get-Win11ISOLogFilePath
    Write-Win11ISOLog "ISO selected: $isoPath  ($fileSizeGB GB)"
    Write-Win11ISOLog "Logging to: $logPath"
}

function Invoke-WinUtilISOMountAndVerify {
    $isoPath = $sync["WPFWin11ISOPath"].Text

    if ([string]::IsNullOrWhiteSpace($isoPath) -or $isoPath -eq "No ISO selected...") {
        [System.Windows.MessageBox]::Show("Please select an ISO file first.", "No ISO Selected", "OK", "Warning")
        return
    }

    # Recover stuck UI if a previous run left flags set but the pipeline is gone or finished
    if ($sync["Win11ISOMountVerifyRunning"]) {
        $ar = $sync["_isoMountAsyncResult"]
        $psRef = $sync["_isoMountPowerShell"]
        if (-not $ar -and -not $psRef) {
            $sync["Win11ISOMountVerifyRunning"] = $false
            if ($sync["WPFWin11ISOMountButton"]) { $sync["WPFWin11ISOMountButton"].IsEnabled = $true }
        } elseif ($ar -and $ar.IsCompleted) {
            try {
                if ($psRef) { [void]$psRef.EndInvoke($ar); $psRef.Dispose() }
            } catch {}
            $sync["_isoMountPowerShell"] = $null
            $sync["_isoMountAsyncResult"] = $null
            $sync["Win11ISOMountVerifyRunning"] = $false
            if ($sync["WPFWin11ISOMountButton"]) { $sync["WPFWin11ISOMountButton"].IsEnabled = $true }
        } else {
            $tsBusy = (Get-Date).ToString("HH:mm:ss")
            Add-Win11ISOStatusLogLineUIThread -Line "[$tsBusy] Mount/verify is already running; please wait."
            return
        }
    }

    $tsClick = (Get-Date).ToString("HH:mm:ss")
    Add-Win11ISOStatusLogLineUIThread -Line "[$tsClick] Mount & verify - starting (watch this log for progress)..."

    $mountBtn = $sync["WPFWin11ISOMountButton"]
    if ($mountBtn) { $mountBtn.IsEnabled = $false }
    $sync["Win11ISOMountVerifyRunning"] = $true

    try {
        Write-Win11ISOLog "Starting mount and verify in the background (UI stays responsive)..."
        Set-WinUtilProgressBar -Label "Mounting ISO..." -Percent 10
    } catch {
        $sync["Win11ISOMountVerifyRunning"] = $false
        if ($mountBtn) { $mountBtn.IsEnabled = $true }
        [System.Windows.MessageBox]::Show(
            "Could not update the ISO status log (UI).`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Warning")
        return
    }

    $getLogDef  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDef = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",       $sync)
    $runspace.SessionStateProxy.SetVariable("isoPath",    $isoPath)
    $runspace.SessionStateProxy.SetVariable("getLogDef",  $getLogDef)
    $runspace.SessionStateProxy.SetVariable("logCoreDef", $logCoreDef)

    $ps = [Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function MountVerify-SetProgress {
            param([string]$Label, [int]$Percent)
            $win = $sync["Form"]
            if (-not $win) { return }
            # Stash on $sync so [System.Action] does not rely on broken PS delegate closure capture
            $sync["_isoUiProgLabel"] = $Label
            $sync["_isoUiProgPct"]   = $Percent
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pct = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pct -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pct, 5)
                    }
                }
            })
        }

        try {
            Write-Win11ISOLog "Mounting ISO: $isoPath"
            MountVerify-SetProgress "Mounting ISO..." 10

            Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop | Out-Null

            $deadline = (Get-Date).AddMinutes(5)
            do {
                Start-Sleep -Milliseconds 500
                $vol = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop | Get-Volume -ErrorAction SilentlyContinue
                if ($vol -and $vol.DriveLetter) { break }
                if ((Get-Date) -gt $deadline) {
                    throw "Timed out waiting for mounted ISO to receive a drive letter."
                }
            } while ($true)

            $driveLetter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter + ":"
            Write-Win11ISOLog "Mounted at drive $driveLetter"

            MountVerify-SetProgress "Verifying ISO contents..." 30

            $wimPath = Join-Path $driveLetter "sources\install.wim"
            $esdPath = Join-Path $driveLetter "sources\install.esd"

            if (-not (Test-Path $wimPath) -and -not (Test-Path $esdPath)) {
                Dismount-DiskImage -ImagePath $isoPath | Out-Null
                Write-Win11ISOLog "ERROR: install.wim/install.esd not found - not a valid Windows ISO."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "This does not appear to be a valid Windows ISO.`n`ninstall.wim / install.esd was not found.",
                        "Invalid ISO", "OK", "Error")
                })
                return
            }

            $activeWim = if (Test-Path $wimPath) { $wimPath } else { $esdPath }

            MountVerify-SetProgress "Reading image metadata..." 55
            $imageInfo = Get-WindowsImage -ImagePath $activeWim | Select-Object ImageIndex, ImageName

            $clientImages = $imageInfo | Where-Object {
                ($_.ImageName -match '\bWindows 10\b' -or $_.ImageName -match '\bWindows 11\b') -and
                $_.ImageName -notmatch 'Windows Server'
            }
            if (-not $clientImages) {
                Dismount-DiskImage -ImagePath $isoPath | Out-Null
                Write-Win11ISOLog "ERROR: No Windows 10 or Windows 11 client edition found in the image."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "No Windows 10 or Windows 11 client edition was found in this ISO.`n`nUse an official Windows 10 or Windows 11 ISO from Microsoft (not Windows Server).",
                        "Unsupported ISO", "OK", "Error")
                })
                return
            }

            $uiDriveLetter = $driveLetter
            $uiActiveWim   = $activeWim
            $uiImageInfo   = $imageInfo
            $uiIsoPath     = $isoPath

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["Win11ISOImageInfo"] = $uiImageInfo
                $sync["WPFWin11ISOMountDriveLetter"].Text = "Mounted at: $uiDriveLetter   |   Image file: $(Split-Path $uiActiveWim -Leaf)"
                $cb = $sync["WPFWin11ISOEditionComboBox"]
                $cb.Items.Clear()
                foreach ($img in $uiImageInfo) {
                    [void]$cb.Items.Add("$($img.ImageIndex): $($img.ImageName)")
                }
                if ($cb.Items.Count -gt 0) {
                    $proIndex = -1
                    for ($i = 0; $i -lt $cb.Items.Count; $i++) {
                        if ($cb.Items[$i] -match "Windows 1[01] Pro(?![\w ])") {
                            $proIndex = $i; break
                        }
                    }
                    $cb.SelectedIndex = if ($proIndex -ge 0) { $proIndex } else { 0 }
                }
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Visible"
                $sync["Win11ISODriveLetter"] = $uiDriveLetter
                $sync["Win11ISOWimPath"]     = $uiActiveWim
                $sync["Win11ISOImagePath"]   = $uiIsoPath
                $sync["WPFWin11ISOModifySection"].Visibility = "Visible"
            })

            MountVerify-SetProgress "ISO verified" 100
            Write-Win11ISOLog "ISO verified OK. Editions found: $($imageInfo.Count)"
        } catch {
            Write-Win11ISOLog "ERROR during mount/verify: $($_.Exception.Message)"
            Write-Win11ISOLog "ERROR details: $($_ | Out-String)"
            try {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
            } catch {}
            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show(
                    "An error occurred while mounting or verifying the ISO:`n`n$m",
                    "Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            MountVerify-SetProgress "" 0
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOMountButton"].IsEnabled = $true
                $sync["Win11ISOMountVerifyRunning"] = $false
            })
        }
    })

    try {
        # Keep strong references so the pipeline is not GC'd mid-flight.
        $sync["_isoMountPowerShell"] = $ps
        $sync["_isoMountAsyncResult"] = $ps.BeginInvoke()
    } catch {
        $sync["_isoMountPowerShell"] = $null
        $sync["_isoMountAsyncResult"] = $null
        try { $ps.Dispose() } catch {}
        $sync["Win11ISOMountVerifyRunning"] = $false
        $mountBtn.IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start mount/verify job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start mount/verify in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
}

function Invoke-WinUtilISOModify {
    $isoPath     = $sync["Win11ISOImagePath"]
    $driveLetter = $sync["Win11ISODriveLetter"]
    $wimPath     = $sync["Win11ISOWimPath"]

    if (-not $isoPath) {
        [System.Windows.MessageBox]::Show(
            "No verified ISO found. Please complete Steps 1 and 2 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    $selectedItem     = $sync["WPFWin11ISOEditionComboBox"].SelectedItem
    $selectedWimIndex = 1
    if ($selectedItem -and $selectedItem -match '^(\d+):') {
        $selectedWimIndex = [int]$Matches[1]
    } elseif ($sync["Win11ISOImageInfo"]) {
        $selectedWimIndex = $sync["Win11ISOImageInfo"][0].ImageIndex
    }
    $selectedEditionName = if ($selectedItem) { ($selectedItem -replace '^\d+:\s*', '') } else { "Unknown" }
    Write-Win11ISOLog "Selected edition: $selectedEditionName (Index $selectedWimIndex)"

    $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
    $sync["Win11ISOModifying"] = $true

    $existingWorkDir = Get-Item -Path (Join-Path $env:TEMP "ASYS_Win11ISO*") -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $workDir = if ($existingWorkDir) {
        Write-Win11ISOLog "Reusing existing temp directory: $($existingWorkDir.FullName)"
        $existingWorkDir.FullName
    } else {
        Join-Path $env:TEMP "ASYS_Win11ISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    $autounattendContent = if ($WinUtilAutounattendXml) {
        $WinUtilAutounattendXml
    } else {
        $toolsXml = Join-Path $PSScriptRoot "..\..\tools\autounattend.xml"
        if (Test-Path $toolsXml) { Get-Content $toolsXml -Raw } else { "" }
    }

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $injectDrivers = $sync["WPFWin11ISOInjectDrivers"].IsChecked -eq $true

    $runspace.SessionStateProxy.SetVariable("sync",                $sync)
    $runspace.SessionStateProxy.SetVariable("isoPath",             $isoPath)
    $runspace.SessionStateProxy.SetVariable("driveLetter",         $driveLetter)
    $runspace.SessionStateProxy.SetVariable("wimPath",             $wimPath)
    $runspace.SessionStateProxy.SetVariable("workDir",             $workDir)
    $runspace.SessionStateProxy.SetVariable("selectedWimIndex",    $selectedWimIndex)
    $runspace.SessionStateProxy.SetVariable("selectedEditionName", $selectedEditionName)
    $runspace.SessionStateProxy.SetVariable("autounattendContent", $autounattendContent)
    $runspace.SessionStateProxy.SetVariable("injectDrivers",       $injectDrivers)

    $isoScriptFuncDef = "function Invoke-WinUtilISOScript {`n" + ${function:Invoke-WinUtilISOScript}.ToString() + "`n}"
    $getLogDef        = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDef       = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"
    $runspace.SessionStateProxy.SetVariable("isoScriptFuncDef", $isoScriptFuncDef)
    $runspace.SessionStateProxy.SetVariable("getLogDef",        $getLogDef)
    $runspace.SessionStateProxy.SetVariable("logCoreDef",       $logCoreDef)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($isoScriptFuncDef))
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function Log($msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $msg"
            Write-Win11ISOLogCore -Line $line
            Add-Content -Path (Join-Path $workDir "ASYS_Win11ISO.log") -Value $line -ErrorAction SilentlyContinue
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOSelectSection"].Visibility = "Collapsed"
                $sync["WPFWin11ISOMountSection"].Visibility  = "Collapsed"
                $sync["WPFWin11ISOModifySection"].Visibility = "Collapsed"
            })

            Log "Global log file: $(Get-Win11ISOLogFilePath)"
            Log "Creating working directory: $workDir"
            $isoContents = Join-Path $workDir "iso_contents"
            $mountDir    = Join-Path $workDir "wim_mount"
            New-Item -ItemType Directory -Path $isoContents, $mountDir -Force | Out-Null
            SetProgress "Copying ISO contents..." 10

            Log "Copying ISO contents from $driveLetter to $isoContents..."
            & robocopy $driveLetter $isoContents /E /NFL /NDL /NJH /NJS | Out-Null
            Log "ISO contents copied."
            SetProgress "Mounting install.wim..." 25

            $localWim = Join-Path $isoContents "sources\install.wim"
            if (-not (Test-Path $localWim)) {
                $localEsd = Join-Path $isoContents "sources\install.esd"
                if (-not (Test-Path $localEsd)) {
                    throw "Neither install.wim nor install.esd was found in copied ISO contents."
                }

                # install.esd cannot be modified directly; export selected edition to writable install.wim first.
                SetProgress "Converting install.esd to install.wim..." 20
                Log "install.esd detected. Exporting selected edition (Index $selectedWimIndex) to install.wim..."
                Export-WindowsImage -SourceImagePath $localEsd -SourceIndex $selectedWimIndex -DestinationImagePath $localWim -ErrorAction Stop | Out-Null
                Log "install.esd converted to install.wim successfully."
                $selectedWimIndex = 1
                Log "Using index 1 in converted install.wim for servicing."
            }

            Set-ItemProperty -Path $localWim -Name IsReadOnly -Value $false

            Log "Mounting install.wim (Index ${selectedWimIndex}: $selectedEditionName) at $mountDir..."
            Mount-WindowsImage -ImagePath $localWim -Index $selectedWimIndex -Path $mountDir -ErrorAction Stop | Out-Null
            SetProgress "Modifying install.wim..." 45

            Log "Applying clark (Advance Systems 4042) modifications to install.wim..."
            Invoke-WinUtilISOScript -ScratchDir $mountDir -ISOContentsDir $isoContents -AutoUnattendXml $autounattendContent -InjectCurrentSystemDrivers $injectDrivers -Log { param($m) Log $m }

            SetProgress "Cleaning up component store (WinSxS)..." 56
            Log "Running DISM component store cleanup (/ResetBase)..."
            & dism /English "/image:$mountDir" /Cleanup-Image /StartComponentCleanup /ResetBase | ForEach-Object { Log $_ }
            Log "Component store cleanup complete."

            SetProgress "Saving modified install.wim..." 65
            Log "Dismounting and saving install.wim. This will take several minutes..."
            Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null
            Log "install.wim saved."

            SetProgress "Removing unused editions from install.wim..." 70
            Log "Exporting edition '$selectedEditionName' (Index $selectedWimIndex) to a single-edition install.wim..."
            $exportWim = Join-Path $isoContents "sources\install_export.wim"
            Export-WindowsImage -SourceImagePath $localWim -SourceIndex $selectedWimIndex -DestinationImagePath $exportWim -ErrorAction Stop | Out-Null
            Remove-Item -Path $localWim -Force
            Rename-Item -Path $exportWim -NewName "install.wim" -Force
            $localWim = Join-Path $isoContents "sources\install.wim"
            Log "Unused editions removed. install.wim now contains only '$selectedEditionName'."

            SetProgress "Dismounting source ISO..." 80
            Log "Dismounting original ISO..."
            Dismount-DiskImage -ImagePath $isoPath | Out-Null

            $sync["Win11ISOWorkDir"]           = $workDir
            $sync["Win11ISOContentsDir"]       = $isoContents
            $sync["Win11ISOBuiltEditionName"]  = $selectedEditionName

            SetProgress "Modification complete" 100
            Log "install.wim modification complete. Choose an output option in Step 4."

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["WPFWin11ISOOutputSection"].Visibility = "Visible"
            })
        } catch {
            Log "ERROR during modification: $($_.Exception.Message)"
            Log "ERROR details: $($_ | Out-String)"

            try {
                if (Test-Path $mountDir) {
                    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $mountDir }
                    if ($mountedImages) {
                        Log "Cleaning up: dismounting install.wim (discarding changes)..."
                        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            } catch { Log "Warning: could not dismount install.wim during cleanup: $_" }

            try {
                $mountedISO = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                if ($mountedISO -and $mountedISO.Attached) {
                    Log "Cleaning up: dismounting source ISO..."
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
                }
            } catch { Log "Warning: could not dismount ISO during cleanup: $_" }

            try {
                if (Test-Path $workDir) {
                    Log "Cleaning up: removing temp directory $workDir..."
                    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            } catch { Log "Warning: could not remove temp directory during cleanup: $_" }

            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show(
                    "An error occurred during install.wim modification:`n`n$m",
                    "Modification Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            $sync["Win11ISOModifying"] = $false
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
                if ($sync["WPFWin11ISOOutputSection"].Visibility -ne "Visible") {
                    $sync["WPFWin11ISOSelectSection"].Visibility = "Visible"
                    $sync["WPFWin11ISOMountSection"].Visibility  = "Visible"
                    $sync["WPFWin11ISOModifySection"].Visibility = "Visible"
                }
            })
        }
    }) | Out-Null

    $script.BeginInvoke() | Out-Null
}

function Invoke-WinUtilISOCheckExistingWork {
    if ($sync["Win11ISOContentsDir"] -and (Test-Path $sync["Win11ISOContentsDir"])) { return }

    # Check if ISO modification is currently in progress
    if ($sync["Win11ISOModifying"]) {
        return
    }

    $existingWorkDir = Get-Item -Path (Join-Path $env:TEMP "ASYS_Win11ISO*") -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $existingWorkDir) { return }

    $isoContents = Join-Path $existingWorkDir.FullName "iso_contents"
    if (-not (Test-Path $isoContents)) { return }

    $sync["Win11ISOWorkDir"]     = $existingWorkDir.FullName
    $sync["Win11ISOContentsDir"] = $isoContents

    $sync["WPFWin11ISOSelectSection"].Visibility = "Collapsed"
    $sync["WPFWin11ISOMountSection"].Visibility  = "Collapsed"
    $sync["WPFWin11ISOModifySection"].Visibility = "Collapsed"
    $sync["WPFWin11ISOOutputSection"].Visibility = "Visible"

    $modified = $existingWorkDir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-Win11ISOLog "Existing working directory found: $($existingWorkDir.FullName)"
    Write-Win11ISOLog "Last modified: $modified - Skipping Steps 1-3 and resuming at Step 4."
    Write-Win11ISOLog "Click 'Clean & Reset' if you want to start over with a new ISO."

    [System.Windows.MessageBox]::Show(
        "A previous clark ISO working directory was found:`n`n$($existingWorkDir.FullName)`n`n(Last modified: $modified)`n`nStep 4 (output options) has been restored so you can save the already-modified image.`n`nClick 'Clean & Reset' in Step 4 if you want to start over.",
        "Existing Work Found", "OK", "Info")
}

function Invoke-WinUtilISOCleanAndReset {
    $workDir = $sync["Win11ISOWorkDir"]

    if ($workDir -and (Test-Path $workDir)) {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will delete the temporary working directory:`n`n$workDir`n`nAnd reset the interface back to the start.`n`nContinue?",
            "Clean & Reset", "YesNo", "Warning")
        if ($confirm -ne "Yes") { return }
    }

    $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $false

    $getLogDefClean  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDefClean = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",         $sync)
    $runspace.SessionStateProxy.SetVariable("workDir",      $workDir)
    $runspace.SessionStateProxy.SetVariable("getLogDef",    $getLogDefClean)
    $runspace.SessionStateProxy.SetVariable("logCoreDef",   $logCoreDefClean)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))

        function Log($msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $msg"
            Write-Win11ISOLogCore -Line $line
            if ($workDir) {
                Add-Content -Path (Join-Path $workDir "ASYS_Win11ISO.log") -Value $line -ErrorAction SilentlyContinue
            }
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            if ($workDir) {
                $mountDir = Join-Path $workDir "wim_mount"
                try {
                    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                                     Where-Object { $_.Path -like "$workDir*" }
                    if ($mountedImages) {
                        foreach ($img in $mountedImages) {
                            Log "Dismounting WIM at: $($img.Path) (discarding changes)..."
                            SetProgress "Dismounting WIM image..." 3
                            Dismount-WindowsImage -Path $img.Path -Discard -ErrorAction Stop | Out-Null
                            Log "WIM dismounted successfully."
                        }
                    } elseif (Test-Path $mountDir) {
                        Log "No mounted WIM reported by Get-WindowsImage. Running DISM /Cleanup-Wim as a precaution..."
                        SetProgress "Running DISM cleanup..." 3
                        & dism /English /Cleanup-Wim 2>&1 | ForEach-Object { Log $_ }
                    }
                } catch {
                    Log "Warning: could not dismount WIM cleanly. Attempting DISM /Cleanup-Wim fallback: $_"
                    try { & dism /English /Cleanup-Wim 2>&1 | ForEach-Object { Log $_ } } catch { Log "Warning: DISM /Cleanup-Wim also failed: $_" }
                }
            }

            if ($workDir -and (Test-Path $workDir)) {
                Log "Scanning files to delete in: $workDir"
                SetProgress "Scanning files..." 5

                $allFiles = @(Get-ChildItem -Path $workDir -File -Recurse -Force -ErrorAction SilentlyContinue)
                $allDirs  = @(Get-ChildItem -Path $workDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending)
                $total   = $allFiles.Count
                $deleted = 0

                Log "Found $total files to delete."

                foreach ($f in $allFiles) {
                    try { Remove-Item -Path $f.FullName -Force -ErrorAction Stop } catch { Log "WARNING: could not delete $($f.FullName): $_" }
                    $deleted++
                    if ($deleted % 100 -eq 0 -or $deleted -eq $total) {
                        $pct = [math]::Round(($deleted / [Math]::Max($total, 1)) * 85) + 5
                        SetProgress "Deleting files in $($f.Directory.Name)... ($deleted / $total)" $pct
                    }
                }

                foreach ($d in $allDirs) {
                    try { Remove-Item -Path $d.FullName -Force -ErrorAction SilentlyContinue } catch {}
                }

                try { Remove-Item -Path $workDir -Recurse -Force -ErrorAction Stop } catch {}

                if (Test-Path $workDir) {
                    Log "WARNING: some items could not be deleted in $workDir"
                } else {
                    Log "Temp directory deleted successfully."
                }
            } else {
                Log "No temp directory found - resetting UI."
            }

            SetProgress "Resetting UI..." 95
            Log "Resetting interface..."

            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync["Win11ISOWorkDir"]     = $null
                $sync["Win11ISOContentsDir"] = $null
                $sync["Win11ISOImagePath"]   = $null
                $sync["Win11ISODriveLetter"] = $null
                $sync["Win11ISOWimPath"]     = $null
                $sync["Win11ISOImageInfo"]        = $null
                $sync["Win11ISOUSBDisks"]         = $null
                $sync["Win11ISOBuiltEditionName"] = $null

                $sync["WPFWin11ISOPath"].Text                   = "No ISO selected..."
                $sync["WPFWin11ISOFileInfo"].Visibility          = "Collapsed"
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
                $sync["WPFWin11ISOOptionUSB"].Visibility         = "Collapsed"
                $sync["WPFWin11ISOOutputSection"].Visibility     = "Collapsed"
                $sync["WPFWin11ISOModifySection"].Visibility     = "Collapsed"
                $sync["WPFWin11ISOMountSection"].Visibility      = "Collapsed"
                $sync["WPFWin11ISOSelectSection"].Visibility     = "Visible"
                $sync["WPFWin11ISOModifyButton"].IsEnabled       = $true
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled   = $true

                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0

                $sync["WPFWin11ISOStatusLog"].Text   = "Ready. Please select a Windows 10 or Windows 11 ISO to begin."
            })
        } catch {
            Log "ERROR during Clean & Reset: $_"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $true
            })
        }
    }) | Out-Null

    $script.BeginInvoke() | Out-Null
}

function Invoke-WinUtilISOExport {
    $contentsDir = $sync["Win11ISOContentsDir"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        [System.Windows.MessageBox]::Show(
            "No modified ISO content found.  Please complete Steps 1-3 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $builtName = $sync["Win11ISOBuiltEditionName"]
    $isoBase   = if ($builtName -match '\bWindows 10\b') {
        "Win10_Modified_$(Get-Date -Format 'yyyyMMdd').iso"
    } elseif ($builtName -match '\bWindows 11\b') {
        "Win11_Modified_$(Get-Date -Format 'yyyyMMdd').iso"
    } else {
        "Win_Modified_$(Get-Date -Format 'yyyyMMdd').iso"
    }

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title            = "Save Modified Windows ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso"
    $dlg.FileName         = $isoBase
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $outputISO = $dlg.FileName

    # Locate oscdimg.exe (Windows ADK or winget per-user install)
    $oscdimg = Get-ChildItem "C:\Program Files (x86)\Windows Kits" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName
    if (-not $oscdimg) {
        $oscdimg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                   Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $oscdimg) {
        Write-Win11ISOLog "oscdimg.exe not found. Attempting to install via winget..."
        try {
            # First ensure winget is installed and operational
            Install-WinUtilWinget

            $winget = Get-Command winget -ErrorAction Stop
            $result = & $winget install -e --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements 2>&1
            Write-Win11ISOLog "winget output: $result"
            $oscdimg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                       Select-Object -First 1 -ExpandProperty FullName
        } catch {
            Write-Win11ISOLog "winget not available or install failed: $_"
        }

        if (-not $oscdimg) {
            Write-Win11ISOLog "oscdimg.exe still not found after install attempt."
            [System.Windows.MessageBox]::Show(
                "oscdimg.exe could not be found or installed automatically.`n`nPlease install it manually:`n  winget install -e --id Microsoft.OSCDIMG`n`nOr install the Windows ADK from:`nhttps://learn.microsoft.com/windows-hardware/get-started/adk-install",
                "oscdimg Not Found", "OK", "Warning")
            return
        }
        Write-Win11ISOLog "oscdimg.exe installed successfully."
    }

    $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $false

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("sync",        $sync)
    $runspace.SessionStateProxy.SetVariable("contentsDir", $contentsDir)
    $runspace.SessionStateProxy.SetVariable("outputISO",   $outputISO)
    $runspace.SessionStateProxy.SetVariable("oscdimg",     $oscdimg)

    $getLogDefEx  = "function Get-Win11ISOLogFilePath {`n" + ${function:Get-Win11ISOLogFilePath}.ToString() + "`n}"
    $logCoreDefEx = "function Write-Win11ISOLogCore {`n" + ${function:Write-Win11ISOLogCore}.ToString() + "`n}"
    $runspace.SessionStateProxy.SetVariable("getLogDef",  $getLogDefEx)
    $runspace.SessionStateProxy.SetVariable("logCoreDef", $logCoreDefEx)

    $script = [Management.Automation.PowerShell]::Create()
    $script.Runspace = $runspace
    $script.AddScript({
        . ([scriptblock]::Create($getLogDef))
        . ([scriptblock]::Create($logCoreDef))
        function Write-Win11ISOLog {
            param([string]$Message)
            $ts = (Get-Date).ToString("HH:mm:ss")
            Write-Win11ISOLogCore -Line "[$ts] $Message"
        }

        function SetProgress($label, $pct) {
            $win = $sync["Form"]
            if (-not $win) { return }
            $sync["_isoUiProgLabel"] = $label
            $sync["_isoUiProgPct"]   = $pct
            $win.Dispatcher.Invoke([System.Action]{
                $lbl = [string]$sync["_isoUiProgLabel"]
                $pc  = [int]$sync["_isoUiProgPct"]
                if ($sync.progressBarTextBlock) {
                    $sync.progressBarTextBlock.Text    = $lbl
                    $sync.progressBarTextBlock.ToolTip = $lbl
                }
                if ($sync.ProgressBar) {
                    if ($pc -le 0) {
                        $sync.ProgressBar.Value = 0
                    } else {
                        $sync.ProgressBar.Value = [Math]::Max($pc, 5)
                    }
                }
            })
        }

        try {
            Write-Win11ISOLog "Exporting to ISO: $outputISO"
            SetProgress "Building ISO..." 10

            $bootData    = "2#p0,e,b`"$contentsDir\boot\etfsboot.com`"#pEF,e,b`"$contentsDir\efi\microsoft\boot\efisys.bin`""
            $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-bootdata:$bootData", "-l`"CTOS_MODIFIED`"", "`"$contentsDir`"", "`"$outputISO`"")

            Write-Win11ISOLog "Running oscdimg..."

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $oscdimg
            $psi.Arguments              = $oscdimgArgs -join " "
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi
            $proc.Start() | Out-Null

            # Stream stdout line-by-line as oscdimg runs
            while (-not $proc.StandardOutput.EndOfStream) {
                $line = $proc.StandardOutput.ReadLine()
                if ($line.Trim()) { Write-Win11ISOLog $line }
            }

            $proc.WaitForExit()

            # Flush any stderr after process exits
            $stderr = $proc.StandardError.ReadToEnd()
            foreach ($line in ($stderr -split "`r?`n")) {
                if ($line.Trim()) { Write-Win11ISOLog "[stderr]$line" }
            }

            if ($proc.ExitCode -eq 0) {
                SetProgress "ISO exported" 100
                Write-Win11ISOLog "ISO exported successfully: $outputISO"
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show("ISO exported successfully!`n`n$outputISO", "Export Complete", "OK", "Info")
                })
            } else {
                Write-Win11ISOLog "oscdimg exited with code $($proc.ExitCode)."
                $sync["Form"].Dispatcher.Invoke([System.Action]{
                    [System.Windows.MessageBox]::Show(
                        "oscdimg exited with code $($proc.ExitCode).`nCheck the status log for details.",
                        "Export Error", "OK", "Error")
                })
            }
        } catch {
            Write-Win11ISOLog "ERROR during ISO export: $($_.Exception.Message)"
            Write-Win11ISOLog "ERROR details: $($_ | Out-String)"
            $sync["__isoLastErrorMessage"] = "$($_.Exception.Message)"
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $m = [string]$sync["__isoLastErrorMessage"]
                [System.Windows.MessageBox]::Show("ISO export failed:`n`n$m", "Error", "OK", "Error")
            })
        } finally {
            Start-Sleep -Milliseconds 800
            $sync["Form"].Dispatcher.Invoke([System.Action]{
                $sync.progressBarTextBlock.Text    = ""
                $sync.progressBarTextBlock.ToolTip = ""
                $sync.ProgressBar.Value            = 0
                $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true
            })
        }
    }) | Out-Null

    $script.BeginInvoke() | Out-Null
}
