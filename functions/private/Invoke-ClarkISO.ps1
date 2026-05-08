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

function Set-ClarkISODownloadProgress {
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

function Set-ClarkISODownloadControlState {
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

function Test-ClarkISODownloadStopRequested {
    if ($sync["WinISODownloadStopRequested"]) {
        throw "ISO download stopped by user."
    }
}

function Resume-ClarkISOBitsJob {
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
        Test-ClarkISODownloadStopRequested
        $job = Get-BitsTransfer -Id $BitsJobId -ErrorAction SilentlyContinue
        if (-not $job) {
            return $null
        }
    } while ($job.JobState -eq "Suspended" -and (Get-Date) -lt $deadline)

    return $job
}

function Invoke-ClarkISODirectDownloadPauseToggle {
    if (-not $sync["WinISODownloadRunning"]) {
        return
    }

    $isPaused = [bool]$sync["WinISODownloadPauseRequested"]
    $newPausedState = -not $isPaused
    $sync["WinISODownloadPauseRequested"] = $newPausedState
    $sync["WinISODownloadIsPaused"] = $newPausedState

    if ($newPausedState) {
        Write-Win11ISOLog "ISO download paused."
        Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
    } else {
        Write-Win11ISOLog "ISO download resumed."
    }
    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $newPausedState
}

function Invoke-ClarkISODirectDownloadStop {
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

function Show-ClarkISOMessageBox {
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

function Get-ClarkDefaultFileDialogDirectory {
    # Prefer Downloads for ISO workflows; fallback to Desktop, then USERPROFILE.
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    if (-not [string]::IsNullOrWhiteSpace($downloads) -and (Test-Path -LiteralPath $downloads)) {
        return $downloads
    }

    $desktop = [System.Environment]::GetFolderPath("Desktop")
    if (-not [string]::IsNullOrWhiteSpace($desktop) -and (Test-Path -LiteralPath $desktop)) {
        return $desktop
    }

    return $env:USERPROFILE
}

function Get-ClarkISODirectDownloadCatalog {
    # Passed to Fido.ps1 as -Rel. Fido matches with release.StartsWith(Rel) or Rel eq 'Latest'.
    # Microsoft/Fido refresh often drops older builds; stale labels (e.g. 24H2) make Fido exit before any URL is returned.
    return @{
        "Windows 11" = @("Latest", "25H2")
        "Windows 10" = @("Latest", "22H2")
    }
}

function Set-ClarkISODirectDownloadVersions {
    if (-not $sync["WPFWinISODownloadProductComboBox"] -or -not $sync["WPFWinISODownloadVersionComboBox"]) {
        return
    }

    $catalog = Get-ClarkISODirectDownloadCatalog
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

function Get-ClarkISODirectDownloadLanguageCatalog {
    # Label shown to user + Fido language token.
    # Keep only US English to avoid locale confusion in downloads.
    return @(
        @{ Label = "English (US)"; FidoLanguage = "English" }
    )
}

function Set-ClarkISODirectDownloadLanguages {
    if (-not $sync["WPFWinISODownloadLanguageComboBox"]) {
        return
    }

    $languageCombo = $sync["WPFWinISODownloadLanguageComboBox"]
    $languageCombo.Items.Clear()

    $catalog = Get-ClarkISODirectDownloadLanguageCatalog
    foreach ($entry in $catalog) {
        [void]$languageCombo.Items.Add([string]$entry.Label)
    }

    # Default to US to avoid accidental UK/international downloads.
    $defaultLabel = "English (US)"
    $defaultIndex = [Array]::IndexOf(@($catalog | ForEach-Object { [string]$_.Label }), $defaultLabel)
    if ($defaultIndex -lt 0) { $defaultIndex = 0 }
    $languageCombo.SelectedIndex = $defaultIndex
}

function Get-ClarkSelectedISODirectDownloadLanguage {
    $selectedLabel = [string]$sync["WPFWinISODownloadLanguageComboBox"].SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedLabel)) {
        return "English"
    }

    $catalog = Get-ClarkISODirectDownloadLanguageCatalog
    $match = $catalog | Where-Object { [string]$_.Label -eq $selectedLabel } | Select-Object -First 1
    if ($match -and -not [string]::IsNullOrWhiteSpace([string]$match.FidoLanguage)) {
        return [string]$match.FidoLanguage
    }

    return "English"
}

function Get-ClarkFidoScriptPath {
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

function Get-ClarkInternetArchiveIsoUrlFromConfig {
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

function Initialize-ClarkISODownloadTls {
    try {
        $p = [Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [Net.SecurityProtocolType]::Tls13 } catch {}
        [Net.ServicePointManager]::SecurityProtocol = $p
    } catch {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    }
}

function New-ClarkISODownloadHttpClient {
    <#
        .SYNOPSIS
            HttpClient configured for large ISO downloads (not default 100s timeout), TLS 1.2+, redirects, and a normal browser User-Agent.
    #>
    Initialize-ClarkISODownloadTls
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

function Invoke-ClarkISOBitsOrHttpDownload {
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
            Test-ClarkISODownloadStopRequested

            $bitsJob = Get-BitsTransfer -Id $bitsJobId -ErrorAction SilentlyContinue
            if (-not $bitsJob) {
                Test-ClarkISODownloadStopRequested
                throw "BITS job was not found (it may have been cancelled or cleared). JobId: $bitsJobId"
            }

            if ($sync["WinISODownloadPauseRequested"] -eq $true) {
                if ($bitsJob.JobState -ne "Suspended") {
                    Suspend-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue
                }
                $sync["WinISODownloadIsPaused"] = $true
                Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $true
                Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    Start-Sleep -Milliseconds 500
                    Test-ClarkISODownloadStopRequested
                }

                $bitsJob = Resume-ClarkISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-ClarkISODownloadStopRequested
                    throw "BITS job was not found after resume (it may have been cancelled). JobId: $bitsJobId"
                }
                $sync["WinISODownloadIsPaused"] = $false
                Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
            }

            if ($bitsJob -and $bitsJob.JobState -eq "Suspended" -and $sync["WinISODownloadPauseRequested"] -ne $true) {
                $bitsJob = Resume-ClarkISOBitsJob -BitsJobId $bitsJobId
                if (-not $bitsJob) {
                    Test-ClarkISODownloadStopRequested
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

            Set-ClarkProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
            Set-ClarkISODownloadProgress -Percent $percent -Text $label
        } while ($bitsJob.JobState -in @("Queued", "Connecting", "Transferring", "Suspended"))

        Test-ClarkISODownloadStopRequested
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

        Set-ClarkProgressBar -Label "Downloading ISO via HTTP..." -Percent 15
        Set-ClarkISODownloadProgress -Percent 5 -Text "Downloading ISO via HTTP..."

        $client = $null
        $response = $null
        $sourceStream = $null
        $targetStream = $null

        try {
            $client = New-ClarkISODownloadHttpClient
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
                Test-ClarkISODownloadStopRequested

                while ($sync["WinISODownloadPauseRequested"] -eq $true) {
                    $sync["WinISODownloadIsPaused"] = $true
                    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $true
                    Set-ClarkISODownloadProgress -Percent ([int]$sync["WinISODownloadLastPercent"]) -Text "Download paused. Click Resume to continue."
                    Start-Sleep -Milliseconds 500
                    Test-ClarkISODownloadStopRequested
                }

                if ($sync["WinISODownloadIsPaused"]) {
                    $sync["WinISODownloadIsPaused"] = $false
                    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
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
                    Set-ClarkProgressBar -Label $label -Percent ([Math]::Max(5, $percent))
                    Set-ClarkISODownloadProgress -Percent $percent -Text $label
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

function Test-ClarkFidoMicrosoftAccessDenied {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '715-123130' -or
        $Text -match 'banned from using this service' -or
        $Text -match 'location hiding technologies' -or
        $Text -match 'unable to complete your request at this time'
}

function Get-ClarkMicrosoftSoftwareDownloadUrl {
    param([string]$WindowsProduct)
    if ($WindowsProduct -match '11') {
        return 'https://www.microsoft.com/software-download/windows11'
    }
    return 'https://www.microsoft.com/software-download/windows10'
}

function Get-ClarkDirectISODownloadUrl {
    param(
        [Parameter(Mandatory)]
        [string]$WindowsProduct,
        [Parameter(Mandatory)]
        [string]$WindowsRelease,
        [string]$WindowsLanguage = "English"
    )

    $fidoPath = Get-ClarkFidoScriptPath
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$fidoPath`"",
        "-Win", "`"$WindowsProduct`"",
        "-Rel", "`"$WindowsRelease`"",
        "-Lang", "`"$WindowsLanguage`"",
        "-GetUrl"
    )

    $output = & powershell.exe @arguments 2>&1
    $outputText = ($output | ForEach-Object { "$_" }) -join ' '

    if ($LASTEXITCODE -ne 0) {
        if (Test-ClarkFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request (message often includes 715-123130). " +
                "This usually happens with VPN/proxy/Tor, some datacenter or restricted networks, or regional limits - not a bug in clark.`n`n" +
                "What to try: disconnect VPN/proxy, use another network (e.g. home ISP or phone hotspot), wait and retry, or download the ISO in a browser from:`n$official"
            )
        }
        throw "Unable to get Microsoft ISO link for $WindowsProduct $WindowsRelease ($WindowsLanguage). Fido output: $outputText"
    }

    $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://.+\.iso(\?.*)?$' } | Select-Object -Last 1)
    if ([string]::IsNullOrWhiteSpace($url)) {
        $url = ($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)
    }

    if ([string]::IsNullOrWhiteSpace($url) -or $url -notmatch '^https?://') {
        if (Test-ClarkFidoMicrosoftAccessDenied -Text $outputText) {
            $official = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $WindowsProduct
            throw (
                "Microsoft blocked the automated ISO link request. " +
                "Try without VPN/proxy or use another network, or download from:`n$official"
            )
        }
        throw "No valid ISO URL was returned for $WindowsProduct $WindowsRelease ($WindowsLanguage)."
    }

    return [string]$url.Trim()
}

function Invoke-ClarkISODirectDownload {
    Add-Type -AssemblyName System.Windows.Forms

    $windowsProduct = [string]$sync["WPFWinISODownloadProductComboBox"].SelectedItem
    $windowsRelease = [string]$sync["WPFWinISODownloadVersionComboBox"].SelectedItem
    $windowsLanguage = Get-ClarkSelectedISODirectDownloadLanguage

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
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $destination = $dlg.FileName
    $sync["WinISODownloadRunning"] = $true
    $sync["WinISODownloadStopRequested"] = $false
    $sync["WinISODownloadPauseRequested"] = $false
    $sync["WinISODownloadIsPaused"] = $false
    $sync["WinISODownloadBitsJobId"] = $null
    Set-ClarkISODownloadControlState -IsRunning $true -IsPaused $false
    Add-Win11ISOStatusLogLineUIThread "Starting direct download: $windowsProduct $windowsRelease ($windowsLanguage) -> $destination"

    Invoke-WPFRunspace -ParameterList @(("windowsProduct", $windowsProduct), ("windowsRelease", $windowsRelease), ("windowsLanguage", $windowsLanguage), ("destination", $destination)) -ScriptBlock {
        param($windowsProduct, $windowsRelease, $windowsLanguage, $destination)
        try {
            $sync.ProcessRunning = $true
            Set-ClarkISODownloadProgress -Percent 0 -Text "Preparing download..."

            $archiveUrl = Get-ClarkInternetArchiveIsoUrlFromConfig -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            $url = $null
            $triedArchive = $false

            if (-not [string]::IsNullOrWhiteSpace($archiveUrl)) {
                $url = $archiveUrl
                $triedArchive = $true
                Write-Win11ISOLog "Using mirror URL from config\\isomirrors.json for $windowsProduct $windowsRelease."
                Set-ClarkProgressBar -Label "Downloading ISO (configured mirror)..." -Percent 15
            } else {
                Write-Win11ISOLog "No mirror URL in config for $windowsProduct $windowsRelease; resolving via Fido (Microsoft)..."
                Set-ClarkProgressBar -Label "Resolving ISO URL (Fido)..." -Percent 10
                $url = Get-ClarkDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease -WindowsLanguage $windowsLanguage
                Set-ClarkProgressBar -Label "Starting ISO download..." -Percent 20
            }

            Write-Win11ISOLog "Download target: $destination"
            try {
                Invoke-ClarkISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
            } catch {
                if ($triedArchive) {
                    Write-Win11ISOLog "Mirror download failed ($($_.Exception.Message)); falling back to Fido (Microsoft)."
                    if (Test-Path -LiteralPath $destination) {
                        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                    }
                    Set-ClarkProgressBar -Label "Resolving ISO URL (Fido fallback)..." -Percent 12
                    $url = Get-ClarkDirectISODownloadUrl -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease -WindowsLanguage $windowsLanguage
                    Write-Win11ISOLog "Fido URL resolved; starting download."
                    Set-ClarkProgressBar -Label "Starting ISO download (Fido)..." -Percent 20
                    Invoke-ClarkISOBitsOrHttpDownload -Url $url -Destination $destination -WindowsProduct $windowsProduct -WindowsRelease $windowsRelease
                } else {
                    throw
                }
            }

            Set-ClarkProgressBar -Label "Download complete" -Percent 100
            Set-ClarkISODownloadProgress -Percent 100 -Text "Download complete: $destination"
            Write-Win11ISOLog "ISO download completed: $destination"
            $null = Show-ClarkISOMessageBox -Message "ISO download complete:`n`n$destination" -Title "Download Complete" -Button OK -Image Information
        } catch {
            $errMsg = [string]$_.Exception.Message
            if ($errMsg -match "stopped by user") {
                Write-Win11ISOLog "ISO download stopped by user."
                Set-ClarkISODownloadProgress -Percent 0 -Text "Download stopped."
                $null = Show-ClarkISOMessageBox -Message "ISO download was stopped." -Title "Download Stopped" -Button OK -Image Information
                return
            }

            Write-Win11ISOLog "ERROR during direct ISO download: $_"
            Set-ClarkISODownloadProgress -Percent 0 -Text "Download failed. Check the log for details."
            $officialPage = Get-ClarkMicrosoftSoftwareDownloadUrl -WindowsProduct $windowsProduct
            if (Test-ClarkFidoMicrosoftAccessDenied -Text $errMsg) {
                $prompt = "$errMsg`n`nOpen Microsoft's official download page in your browser?"
                $answer = Show-ClarkISOMessageBox -Message $prompt -Title "Microsoft blocked automated download" -Button YesNo -Image Warning
                if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                    Start-Process $officialPage
                }
            } else {
                $null = Show-ClarkISOMessageBox -Message "Direct ISO download failed:`n`n$errMsg" -Title "Download Error" -Button OK -Image Error
            }
        } finally {
            $sync.ProcessRunning = $false
            $sync["WinISODownloadRunning"] = $false
            $sync["WinISODownloadStopRequested"] = $false
            $sync["WinISODownloadPauseRequested"] = $false
            $sync["WinISODownloadIsPaused"] = $false
            $sync["WinISODownloadBitsJobId"] = $null
            Set-ClarkProgressBar -Label "" -Percent 0
            Set-ClarkISODownloadControlState -IsRunning $false -IsPaused $false
        }
    } | Out-Null
}

function Invoke-ClarkISOBrowse {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Title            = "Select Windows 10 or Windows 11 ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso|All files (*.*)|*.*"
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory

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

function Invoke-ClarkISOMountAndVerify {
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
        Set-ClarkProgressBar -Label "Mounting ISO..." -Percent 10
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

function Invoke-ClarkISOModify {
    $isoPath     = $sync["Win11ISOImagePath"]
    $driveLetter = $sync["Win11ISODriveLetter"]
    $wimPath     = $sync["Win11ISOWimPath"]

    if (-not $isoPath) {
        [System.Windows.MessageBox]::Show(
            "No verified ISO found. Please complete Steps 1 and 2 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    # Keep internal edition index for any legacy code that reads it
    $selectedItem     = $sync["WPFWin11ISOEditionComboBox"].SelectedItem
    $selectedWimIndex = 1
    if ($selectedItem -and $selectedItem -match '^(\d+):') {
        $selectedWimIndex = [int]$Matches[1]
    } elseif ($sync["Win11ISOImageInfo"]) {
        $selectedWimIndex = $sync["Win11ISOImageInfo"][0].ImageIndex
    }
    $selectedEditionName = if ($selectedItem) { ($selectedItem -replace '^\d+:\s*', '') } else { "Unknown" }
    Write-Win11ISOLog "All editions (Home / Home SL / Pro) will be processed."
    Write-Win11ISOLog "Opening build configuration dialog..."

    # ── Pre-Build Dialog: ask username, computer name, driver injection ──────────
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    # Load saved usernames from Clark's own config folder
    $profilesPath   = Join-Path $PSScriptRoot "..\\..\\config\\iso-usernames.json"
    $savedUsernames = @()
    $defaultUsername = ""
    if (Test-Path $profilesPath) {
        try {
            $profileData     = Get-Content $profilesPath -Raw | ConvertFrom-Json
            $savedUsernames  = @($profileData.usernames)
            $defaultUsername = $profileData.default
        } catch { $savedUsernames = @(); $defaultUsername = "" }
    }

    # Determine Windows version from ISO
    $winVer = if ($selectedEditionName -match "Windows 10") { "10" } `
              elseif ($sync["Win11ISOImageInfo"] -and $sync["Win11ISOImageInfo"][0].ImageName -match "Windows 10") { "10" } `
              else { "11" }

    # Helper: save profiles back to Clark config
    function Save-Profiles {
        param([string[]]$Usernames, [string]$Default)
        $null = New-Item -ItemType Directory -Path (Split-Path $profilesPath) -Force
        @{ usernames = $Usernames; default = $Default } | ConvertTo-Json | Set-Content $profilesPath -Encoding UTF8
    }

    # Build WPF dialog
    [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ASYS ISO Build Configuration"
        SizeToContent="WidthAndHeight"
        MinWidth="440" MaxWidth="520"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#1e1e1e">
    <Window.Resources>
        <!-- Force dark system brushes inside this dialog so default control templates stay readable -->
        <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlLightBrushKey}" Color="#3b3b3b"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlDarkBrushKey}" Color="#1f1f1f"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.GrayTextBrushKey}" Color="#c7c7c7"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2b5f8a"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#ffffff"/>
        <SolidColorBrush x:Key="{x:Static SystemColors.HotTrackBrushKey}" Color="#ffffff"/>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#555"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#2a2a2a"/>
                    <Setter Property="Foreground" Value="#b5b5b5"/>
                    <Setter Property="BorderBrush" Value="#444"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#dddddd"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#9a9a9a"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#555"/>
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="ItemTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <TextBlock Text="{Binding}" Foreground="White"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="#2d2d2d"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="HorizontalContentAlignment" Value="Left"/>
                        <Style.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter Property="Background" Value="#3a3a3a"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#2b5f8a"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#2a2a2a"/>
                    <Setter Property="Foreground" Value="#b5b5b5"/>
                    <Setter Property="BorderBrush" Value="#444"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#c7c7c7"/>
                    <Setter Property="Background" Value="#505050"/>
                    <Setter Property="BorderBrush" Value="#6f6f6f"/>
                    <Setter Property="Opacity" Value="1"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>
    <StackPanel Margin="24,20,24,20">
        <TextBlock Text="ISO Build Configuration" FontSize="16" FontWeight="Bold"
                   Foreground="White" Margin="0,0,0,16"/>

        <!-- Username row -->
        <TextBlock Text="Main Account Username:" Foreground="#cccccc" FontSize="13" Margin="0,0,0,4"/>
        <Grid Margin="0,0,0,4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBox x:Name="TxtUsername" Grid.Column="0" Padding="6,4"
                     Background="#2d2d2d" Foreground="White" BorderBrush="#555"/>
            <ComboBox x:Name="CmbSaved" Grid.Column="2" Width="150"
                      IsEditable="False"
                      Background="#2d2d2d" Foreground="White" BorderBrush="#555"
                      ToolTip="Saved usernames">
                <ComboBox.Resources>
                    <SolidColorBrush x:Key="{x:Static SystemColors.WindowBrushKey}" Color="#2d2d2d"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#2d2d2d"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.WindowTextBrushKey}" Color="#ffffff"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.ControlTextBrushKey}" Color="#ffffff"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#2b5f8a"/>
                    <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#ffffff"/>
                </ComboBox.Resources>
                <ComboBox.ItemContainerStyle>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="#2d2d2d"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="Padding" Value="6,3"/>
                        <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                        <Style.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter Property="Background" Value="#3a3a3a"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#2b5f8a"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </ComboBox.ItemContainerStyle>
                <ComboBox.Template>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="ComboBorder"
                                    Background="#2d2d2d"
                                    BorderBrush="#555"
                                    BorderThickness="1"
                                    SnapsToDevicePixels="True">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="24"/>
                                    </Grid.ColumnDefinitions>
                                    <ContentPresenter Grid.Column="0"
                                                      Margin="6,2,4,2"
                                                      VerticalAlignment="Center"
                                                      HorizontalAlignment="Left"
                                                      Content="{TemplateBinding SelectionBoxItem}"
                                                      ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                      ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                                                      TextElement.Foreground="White"/>
                                    <Border Grid.Column="1"
                                            Background="#2d2d2d"
                                            BorderBrush="#555"
                                            BorderThickness="1,0,0,0">
                                        <TextBlock Text="&#xE70D;"
                                                   FontFamily="Segoe MDL2 Assets"
                                                   Foreground="#cccccc"
                                                   FontSize="10"
                                                   HorizontalAlignment="Center"
                                                   VerticalAlignment="Center"/>
                                    </Border>
                                </Grid>
                            </Border>
                            <Popup Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide">
                                <Border Background="#2d2d2d"
                                        BorderBrush="#555"
                                        BorderThickness="1"
                                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                                    <ScrollViewer Margin="0"
                                                  SnapsToDevicePixels="True"
                                                  MaxHeight="240">
                                        <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ComboBorder" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </ComboBox.Template>
            </ComboBox>
        </Grid>

        <!-- Saved username management -->
        <StackPanel Orientation="Horizontal" Margin="0,2,0,4">
            <CheckBox x:Name="ChkSave" Content="Save this username"
                      Foreground="#cccccc" FontSize="12" IsChecked="True" Margin="0,0,16,0"/>
            <Button x:Name="BtnSetDefault" Content="Set as Default" FontSize="11"
                    Background="#2b5f8a" Foreground="White" BorderBrush="#4d8fc1"
                    Padding="8,3" Margin="0,0,8,0"
                    ToolTip="Set selected saved username as the default (pre-filled next time)"/>
            <Button x:Name="BtnDelete" Content="Delete" FontSize="11"
                    Background="#7a2f2f" Foreground="White" BorderBrush="#a84f4f"
                    Padding="8,3"
                    ToolTip="Remove selected saved username from the list"/>
        </StackPanel>
        <TextBlock x:Name="TxtProfileStatus" FontSize="11" Foreground="#888"
                   Margin="0,0,0,12" Text=""/>

        <!-- Computer name -->
        <TextBlock Text="Computer Name:" Foreground="#cccccc" FontSize="13" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtComputer" Padding="6,4" Margin="0,0,0,14"
                 Background="#2d2d2d" Foreground="White" BorderBrush="#555"
                 Text="ASYS-PC"/>

        <!-- Driver injection -->
        <CheckBox x:Name="ChkDrivers" Content="Inject current system drivers into ISO"
                  Foreground="#cccccc" FontSize="12" Margin="0,0,0,16"/>

        <!-- Deployment Mode -->
        <TextBlock Text="Deployment Mode:" Foreground="#cccccc" FontSize="13"
                   FontWeight="SemiBold" Margin="0,0,0,6"/>
        <RadioButton x:Name="RbWindowsOnly" GroupName="DeployMode"
                     Content="Windows installation only"
                     Foreground="#cccccc" FontSize="12" Margin="0,0,0,4"
                     ToolTip="ISO installs Windows with no additional scripts or configuration"/>
        <RadioButton x:Name="RbFullDeploy" GroupName="DeployMode"
                     Content="Full ASYS deployment (Windows + all setup scripts)"
                     Foreground="#cccccc" FontSize="12" Margin="0,0,0,16"
                     IsChecked="True"
                     ToolTip="Includes master.ps1, Stage 2 and Stage 3 scripts in the ISO"/>

        <!-- Action buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancel"  Content="Cancel"   Width="90" Height="32"
                    Margin="0,0,10,0" Background="#5a5a5a" Foreground="White" BorderBrush="#808080" IsCancel="True"/>
            <Button x:Name="BtnProceed" Content="Start Build" Width="110" Height="32"
                    Background="#0078d4" Foreground="White" BorderBrush="#1f96f2" IsDefault="True"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    $dlgReader       = [System.Xml.XmlNodeReader]::new($dialogXaml)
    $dlgWindow       = [System.Windows.Markup.XamlReader]::Load($dlgReader)
    $txtUser         = $dlgWindow.FindName("TxtUsername")
    $cmbSaved        = $dlgWindow.FindName("CmbSaved")
    $chkSave         = $dlgWindow.FindName("ChkSave")
    $txtComp         = $dlgWindow.FindName("TxtComputer")
    $chkDrivers      = $dlgWindow.FindName("ChkDrivers")
    $btnCancel       = $dlgWindow.FindName("BtnCancel")
    $btnProceed      = $dlgWindow.FindName("BtnProceed")
    $rbWindowsOnly   = $dlgWindow.FindName("RbWindowsOnly")
    $rbFullDeploy    = $dlgWindow.FindName("RbFullDeploy")
    $btnSetDefault   = $dlgWindow.FindName("BtnSetDefault")
    $btnDelete       = $dlgWindow.FindName("BtnDelete")
    $txtStatus       = $dlgWindow.FindName("TxtProfileStatus")

    # Populate saved usernames dropdown
    if ($savedUsernames.Count -gt 0) {
        $cmbSaved.ItemsSource   = [System.Collections.ObjectModel.ObservableCollection[string]]$savedUsernames
        $cmbSaved.SelectedIndex = 0
        # Pre-fill with default if set, otherwise first saved
        $txtUser.Text = if ($defaultUsername -and $defaultUsername -in $savedUsernames) { $defaultUsername } else { $savedUsernames[0] }
        $txtStatus.Text = if ($defaultUsername) { "Default: $defaultUsername" } else { "" }
    } else {
        $txtStatus.Text = "No saved usernames yet."
    }

    # Sync dropdown selection to text box
    $cmbSaved.Add_SelectionChanged({
        if ($cmbSaved.SelectedItem) { $txtUser.Text = $cmbSaved.SelectedItem }
    })

    # Set as Default button
    $btnSetDefault.Add_Click({
        $selected = $cmbSaved.SelectedItem
        if ($selected) {
            $defaultUsername = $selected
            Save-Profiles -Usernames $savedUsernames -Default $defaultUsername
            $txtStatus.Text = "Default set: $defaultUsername"
            $txtUser.Text   = $defaultUsername
        }
    })

    # Delete button
    $btnDelete.Add_Click({
        $selected = $cmbSaved.SelectedItem
        if ($selected) {
            $savedUsernames = @($savedUsernames | Where-Object { $_ -ne $selected })
            $newDefault = if ($defaultUsername -eq $selected) { "" } else { $defaultUsername }
            Save-Profiles -Usernames $savedUsernames -Default $newDefault
            $defaultUsername = $newDefault
            $cmbSaved.ItemsSource   = [System.Collections.ObjectModel.ObservableCollection[string]]$savedUsernames
            if ($savedUsernames.Count -gt 0) {
                $cmbSaved.SelectedIndex = 0
                $txtUser.Text = $savedUsernames[0]
                $txtStatus.Text = if ($newDefault) { "Default: $newDefault" } else { "Deleted. No default set." }
            } else {
                $cmbSaved.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[string]]@()
                $txtUser.Text   = ""
                $txtStatus.Text = "No saved usernames."
            }
        }
    })

    # Use Window.Tag/DialogResult (shared object state) to avoid event-scope variable issues.
    $dlgWindow.Tag = "none"
    $btnProceed.Add_Click({
        $dlgWindow.Tag = "proceed"
        try { $dlgWindow.DialogResult = $true } catch {}
    })
    $btnCancel.Add_Click({
        $dlgWindow.Tag = "cancel"
        try { $dlgWindow.DialogResult = $false } catch {}
    })
    $dialogResult = $dlgWindow.ShowDialog()
    $dlgAction = [string]$dlgWindow.Tag
    if ([string]::IsNullOrWhiteSpace($dlgAction) -or $dlgAction -eq "none") {
        if ($dialogResult -eq $true) {
            $dlgAction = "proceed"
        } elseif ($dialogResult -eq $false) {
            $dlgAction = "cancel"
        } else {
            $dlgAction = "dismissed"
        }
    }

    if ($dlgAction -ne "proceed") {
        Write-Win11ISOLog "ISO modification cancelled from build configuration dialog. Action: $dlgAction"
        $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
        $sync["Win11ISOModifying"] = $false
        return
    }

    $mainUsername = ($txtUser.Text).Trim()
    $computerName = ($txtComp.Text).Trim()
    if (-not $mainUsername) { $mainUsername = "User" }
    if (-not $computerName) { $computerName = "ASYS-PC" }
    $injectDriversDialog = $chkDrivers.IsChecked -eq $true
    $fullDeploy          = $rbFullDeploy.IsChecked -eq $true
    Write-Win11ISOLog "Deployment mode: $(if ($fullDeploy) { "Full ASYS Deployment" } else { "Windows Only" })"
    Write-Win11ISOLog "Build configuration accepted. Preparing ISO modification job..."

    # Save username if requested
    if ($chkSave.IsChecked -and $mainUsername -and $mainUsername -notin $savedUsernames) {
        $savedUsernames  = @(@($mainUsername) + $savedUsernames | Select-Object -Unique | Select-Object -First 10)
        # Keep existing default or set first entry as default if none set
        if (-not $defaultUsername) { $defaultUsername = $mainUsername }
        Save-Profiles -Usernames $savedUsernames -Default $defaultUsername
        Write-Win11ISOLog "Username saved to Clark config: $mainUsername (default: $defaultUsername)"
    }
    Write-Win11ISOLog "Build config — Username: $mainUsername | Computer: $computerName | Drivers: $injectDriversDialog"

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

    $pathCandidates = @(
        (Join-Path $PSScriptRoot "tools"),
        (Join-Path $PSScriptRoot "..\tools"),
        (Join-Path $PSScriptRoot "..\..\tools")
    )
    $toolsRoot = $pathCandidates |
        ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    $autounattendRaw = if ($ClarkAutounattendXml) {
        $ClarkAutounattendXml
    } else {
        $toolsXml = if ($toolsRoot) { Join-Path $toolsRoot "autounattend.xml" } else { "" }
        if (Test-Path $toolsXml) { Get-Content $toolsXml -Raw } else { "" }
    }

    # Ensure autounattend carries pre-staged setup scripts used by Invoke-ClarkISOScript.
    $masterScriptSource = if ($toolsRoot) { Join-Path $toolsRoot "`$OEM`$\`$1\Setup\master.ps1" } else { "" }
    if ($autounattendRaw -and (Test-Path $masterScriptSource)) {
        try {
            $autoDoc = [xml]$autounattendRaw
            $sgNs = "https://schneegans.de/windows/unattend-generator/"
            $nsMgr = New-Object System.Xml.XmlNamespaceManager($autoDoc.NameTable)
            $nsMgr.AddNamespace("sg", $sgNs)

            $extensionsNode = $autoDoc.SelectSingleNode("//sg:Extensions", $nsMgr)
            if (-not $extensionsNode) {
                $extensionsNode = $autoDoc.CreateElement("Extensions", $sgNs)
                [void]$autoDoc.DocumentElement.AppendChild($extensionsNode)
            }

            $masterNode = $autoDoc.SelectSingleNode("//sg:File[@path='C:\Setup\master.ps1']", $nsMgr)
            if (-not $masterNode) {
                $masterNode = $autoDoc.CreateElement("File", $sgNs)
                [void]$masterNode.SetAttribute("path", "C:\Setup\master.ps1")
                [void]$extensionsNode.AppendChild($masterNode)
            }

            $masterNode.RemoveAll()
            [void]$masterNode.SetAttribute("path", "C:\Setup\master.ps1")
            $masterContent = Get-Content -LiteralPath $masterScriptSource -Raw
            [void]$masterNode.AppendChild($autoDoc.CreateCDataSection($masterContent))
            $autounattendRaw = $autoDoc.OuterXml
            Write-Win11ISOLog "Autounattend Extensions staging enabled for C:\Setup\master.ps1."
        } catch {
            Write-Win11ISOLog "Warning: failed to append autounattend Extensions file node for master.ps1: $_"
        }
    }

    # Inject username and computer name into autounattend.xml placeholders
    $autounattendContent = $autounattendRaw -replace "%%USERNAME%%", $mainUsername -replace "%%COMPUTERNAME%%", $computerName

    # Resolve $OEM$ folder path from whichever script location is active (compiled/uncompiled)
    $oemFolderSource = if ($toolsRoot) { Join-Path $toolsRoot "`$OEM`$" } else { "" }

    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()
    $injectDrivers = $injectDriversDialog  # Set by pre-build dialog

    $runspace.SessionStateProxy.SetVariable("sync",                $sync)
    $runspace.SessionStateProxy.SetVariable("isoPath",             $isoPath)
    $runspace.SessionStateProxy.SetVariable("driveLetter",         $driveLetter)
    $runspace.SessionStateProxy.SetVariable("wimPath",             $wimPath)
    $runspace.SessionStateProxy.SetVariable("workDir",             $workDir)
    $runspace.SessionStateProxy.SetVariable("selectedWimIndex",    $selectedWimIndex)
    $runspace.SessionStateProxy.SetVariable("selectedEditionName", $selectedEditionName)
    $runspace.SessionStateProxy.SetVariable("autounattendContent", $autounattendContent)
    $runspace.SessionStateProxy.SetVariable("injectDrivers",       $injectDrivers)
    $runspace.SessionStateProxy.SetVariable("oemFolderSource",     $oemFolderSource)
    $runspace.SessionStateProxy.SetVariable("fullDeploy",          $fullDeploy)

    $isoScriptFuncDef = "function Invoke-ClarkISOScript {`n" + ${function:Invoke-ClarkISOScript}.ToString() + "`n}"
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
            Log "ISO modification worker started."
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
            # ── Handle ESD: export Home/Pro editions to writable install.wim ──────
            $localWim = Join-Path $isoContents "sources\install.wim"
            if (-not (Test-Path $localWim)) {
                $localEsd = Join-Path $isoContents "sources\install.esd"
                if (-not (Test-Path $localEsd)) {
                    throw "Neither install.wim nor install.esd was found in copied ISO contents."
                }
                SetProgress "Reading editions from install.esd..." 18
                Log "install.esd detected. Reading available editions..."
                $esdEditions = Get-WindowsImage -ImagePath $localEsd
                $esdTargets  = @($esdEditions | Where-Object { $_.ImageName -match "\\bHome Single Language\\b|\\bHome$|\\bPro$" } | Sort-Object ImageIndex)
                if ($esdTargets.Count -eq 0) { $esdTargets = @($esdEditions | Sort-Object ImageIndex) }
                Log "Exporting $($esdTargets.Count) edition(s) from ESD to install.wim..."
                $esdIdx = 0
                foreach ($esdEd in $esdTargets) {
                    $esdIdx++
                    $pctEsd = [int](18 + ($esdIdx / $esdTargets.Count) * 6)
                    SetProgress "Converting ESD: $($esdEd.ImageName) ($esdIdx/$($esdTargets.Count))..." $pctEsd
                    Log "  Exporting: $($esdEd.ImageName) (ESD Index $($esdEd.ImageIndex))..."
                    Export-WindowsImage -SourceImagePath $localEsd -SourceIndex $esdEd.ImageIndex -DestinationImagePath $localWim -ErrorAction Stop | Out-Null
                }
                Log "ESD conversion complete. install.wim now contains $esdIdx edition(s)."
            }

            # ── Determine target editions (Home, Home SL, Pro) in install.wim ────────
            Set-ItemProperty -Path $localWim -Name IsReadOnly -Value $false
            Log "Reading editions from install.wim..."
            $allWimEditions    = @(Get-WindowsImage -ImagePath $localWim)
            # Match only exact target editions: Home, Home Single Language, Pro
            $targetWimEditions = @($allWimEditions | Where-Object { $_.ImageName -match "\bHome Single Language\b|\bHome$|\bPro$" } | Sort-Object ImageIndex)
            if ($targetWimEditions.Count -eq 0) {
                Log "Warning: no Home/Pro editions found — processing all editions."
                $targetWimEditions = $allWimEditions | Sort-Object ImageIndex
            }
            $editionCount = $targetWimEditions.Count
            Log "Will process $editionCount edition(s): $(($targetWimEditions | ForEach-Object { $_.ImageName }) -join ", ")"

            function Test-MountPathActive {
                param([string]$Path)
                $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue)
                if ($mounted.Count -eq 0) { return $false }
                $target = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
                return @($mounted | Where-Object {
                    try {
                        [System.IO.Path]::GetFullPath($_.Path).TrimEnd('\') -ieq $target
                    } catch { $false }
                }).Count -gt 0
            }

            # ── Apply ASYS modifications to each edition ──────────────────────────────
            $edIdx = 0
            foreach ($edition in $targetWimEditions) {
                $edIdx++
                $pctStart = [int](25 + (($edIdx - 1) / $editionCount) * 50)
                $pctEnd   = [int](25 + ($edIdx / $editionCount) * 50)

                # Defensive cleanup in case a previous iteration left the mount active.
                if (Test-MountPathActive -Path $mountDir) {
                    Log "Warning: stale mount detected at $mountDir. Discarding before next mount..."
                    Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
                    Start-Sleep -Seconds 1
                }

                SetProgress "[$edIdx/$editionCount] Mounting: $($edition.ImageName)..." $pctStart
                Log "--- Edition $edIdx/${editionCount}: $($edition.ImageName) (Index $($edition.ImageIndex)) ---"
                Log "Mounting install.wim at $mountDir..."
                Mount-WindowsImage -ImagePath $localWim -Index $edition.ImageIndex -Path $mountDir -ErrorAction Stop | Out-Null

                SetProgress "[$edIdx/$editionCount] Modifying: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.25))
                Log "Applying ASYS modifications..."
                # Only inject autounattend.xml to ISO root on the first pass (it's ISO-level, not per-edition)
                $isoInjectDir = if ($edIdx -eq 1) { $isoContents } else { "" }
                Invoke-ClarkISOScript -ScratchDir $mountDir -ISOContentsDir $isoInjectDir -AutoUnattendXml $autounattendContent -InjectCurrentSystemDrivers $injectDrivers -Log { param($m) Log $m }

                SetProgress "[$edIdx/$editionCount] WinSxS cleanup: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.65))
                Log "Running DISM component store cleanup (/ResetBase)..."
                & dism /English "/image:$mountDir" /Cleanup-Image /StartComponentCleanup /ResetBase | ForEach-Object { Log $_ }
                Log "Component store cleanup complete."

                SetProgress "[$edIdx/$editionCount] Saving: $($edition.ImageName)..." ([int]($pctStart + ($pctEnd - $pctStart) * 0.9))
                Log "Dismounting and saving install.wim (this takes several minutes)..."
                try {
                    Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop | Out-Null
                } catch {
                    Log "Warning: standard dismount-save failed, attempting fallback commit. Details: $($_.Exception.Message)"
                    & dism /English /Unmount-Image "/MountDir:$mountDir" /Commit | ForEach-Object { Log $_ }
                    if (Test-MountPathActive -Path $mountDir) {
                        throw "Fallback commit dismount failed; mount path is still active: $mountDir"
                    }
                }
                Log "Edition '$($edition.ImageName)' saved successfully."
            }

            # ── Inject $OEM$ folder (contains master.ps1 and Setup files) ─────────────
            # ── Strip unused editions ────────────────────────────────────────
            # Export only Home, Home SL, Pro to a fresh WIM
            SetProgress "Stripping unused editions from install.wim..." 76
            Log "Stripping unused editions (keeping Home / Home Single Language / Pro)..."
            $localWimStrip  = Join-Path $isoContents "sources\install.wim"
            $strippedWim    = Join-Path $isoContents "sources\install_stripped.wim"
            $finalEditions  = @(Get-WindowsImage -ImagePath $localWimStrip | Where-Object {
                $_.ImageName -match "\bHome Single Language\b|\bHome$|\bPro$"
            } | Sort-Object ImageIndex)
            foreach ($fe in $finalEditions) {
                Log "  Exporting to stripped WIM: $($fe.ImageName)..."
                Export-WindowsImage -SourceImagePath $localWimStrip -SourceIndex $fe.ImageIndex `
                    -DestinationImagePath $strippedWim -ErrorAction Stop | Out-Null
            }
            Remove-Item $localWimStrip -Force
            Rename-Item $strippedWim $localWimStrip
            Log "Strip complete. Final WIM: $(($finalEditions | ForEach-Object { $_.ImageName }) -join ", ")"

            if ($fullDeploy) {
                Log "Injecting OEM folder (Full ASYS Deployment mode)..."
                if ($oemFolderSource -and (Test-Path $oemFolderSource)) {
                    $oemFolderDest = Join-Path $isoContents "`$OEM`$"
                    Copy-Item -Path $oemFolderSource -Destination $oemFolderDest -Recurse -Force
                    Log "OEM folder injected: $oemFolderSource -> $oemFolderDest"
                } else {
                    Log "Warning: tools\`$OEM`$ folder not found at '$oemFolderSource' — skipping OEM injection."
                }
            } else {
                Log "Windows Only mode selected — skipping OEM injection. No setup scripts will be included."
            }


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

    try {
        # Keep strong references so the background pipeline is not GC'd before it completes.
        $sync["_isoModifyPowerShell"] = $script
        $sync["_isoModifyAsyncResult"] = $script.BeginInvoke()
        Write-Win11ISOLog "ISO modification started in the background. Progress will stream in this log."
    } catch {
        $sync["_isoModifyPowerShell"] = $null
        $sync["_isoModifyAsyncResult"] = $null
        try { $script.Dispose() } catch {}
        $sync["Win11ISOModifying"] = $false
        $sync["WPFWin11ISOModifyButton"].IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start ISO modification job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start ISO modification in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
}

function Invoke-ClarkISOCheckExistingWork {
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

function Invoke-ClarkISOCleanAndReset {
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

function Invoke-ClarkISOExport {
    try {
    $contentsDir = $sync["Win11ISOContentsDir"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        [System.Windows.MessageBox]::Show(
            "No modified ISO content found.  Please complete Steps 1-3 first.",
            "Not Ready", "OK", "Warning")
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    # Determine Windows version from image info
    $builtName  = $sync["Win11ISOBuiltEditionName"]
    $isoWinVer  = if ($builtName -match "\bWindows 10\b") { "10" } `
                  elseif ($builtName -match "\bWindows 11\b") { "11" } `
                  else {
                      $imgInfo = $sync["Win11ISOImageInfo"]
                      if ($imgInfo -and $imgInfo[0].ImageName -match "Windows 10") { "10" } else { "11" }
                  }
    # Format: W10-HhsP or W11-HhsP (Home, Home Single Language, Pro)
    $isoBase    = "W$isoWinVer-HhsP.iso"

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title            = "Save Modified Windows ISO"
    $dlg.Filter           = "ISO files (*.iso)|*.iso"
    $dlg.FileName         = $isoBase
    $dlg.InitialDirectory = Get-ClarkDefaultFileDialogDirectory

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $outputISO = $dlg.FileName

    # Locate oscdimg.exe (prefer common ADK paths first, then fallback search)
    $oscdimg = $null
    $oscdimgCandidates = @(
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    foreach ($candidate in $oscdimgCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $oscdimg = $candidate
            break
        }
    }
    if (-not $oscdimg -and (Test-Path "C:\Program Files (x86)\Windows Kits")) {
        $oscdimg = Get-ChildItem "C:\Program Files (x86)\Windows Kits" -Recurse -Depth 10 -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $oscdimg) {
        $oscdimg = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -match 'Microsoft\.OSCDIMG' } |
                   Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $oscdimg) {
        Write-Win11ISOLog "oscdimg.exe not found. Attempting to install via winget..."
        try {
            # First ensure winget is installed and operational
            Install-ClarkWinget

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
            $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-bootdata:$bootData", "-l`"ASYS_MODIFIED`"", "`"$contentsDir`"", "`"$outputISO`"")

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

    try {
        # Keep strong references so background export is not GC'd unexpectedly.
        $sync["_isoExportPowerShell"] = $script
        $sync["_isoExportAsyncResult"] = $script.BeginInvoke()
        Write-Win11ISOLog "ISO export started in the background. Progress will stream in this log."
    } catch {
        $sync["_isoExportPowerShell"] = $null
        $sync["_isoExportAsyncResult"] = $null
        try { $script.Dispose() } catch {}
        $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true
        Write-Win11ISOLog "ERROR: Could not start ISO export job: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(
            "Could not start ISO export in the background:`n`n$($_.Exception.Message)",
            "ISO Creator", "OK", "Error")
    }
    } catch {
        try { Write-Win11ISOLog "FATAL in Invoke-ClarkISOExport: $($_.Exception.Message)" } catch {}
        [System.Windows.MessageBox]::Show(
            "Unexpected error while preparing ISO export:`n`n$($_.Exception.Message)",
            "ISO Export Error", "OK", "Error")
    }
}

