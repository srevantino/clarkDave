function Invoke-WPFHardwareSummary {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $text = Get-WinUtilHardwareSummaryData

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Clark - Hardware summary"
    $form.Size = New-Object System.Drawing.Size(760, 560)
    $form.StartPosition = "CenterScreen"

    $tv = New-Object System.Windows.Forms.TreeView
    $tv.Dock = "Fill"
    $tv.HideSelection = $false
    $current = $null
    foreach ($line in ($text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^=== (.+) ===$') {
            $current = $tv.Nodes.Add($matches[1])
            continue
        }
        if ($null -eq $current) { continue }
        [void]$current.Nodes.Add($line)
    }
    $tv.ExpandAll()

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = "Bottom"
    $panel.WrapContents = $true
    $panel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $panel.AutoSize = $true
    $panel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $panel.Padding = New-Object System.Windows.Forms.Padding(6, 4, 6, 6)

    function Save-HtmlReport {
        param([string]$Path)
        $esc = [System.Net.WebUtility]::HtmlEncode($text)
        $html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Clark hardware</title>
<style>body{font-family:Segoe UI,Arial;margin:16px;}pre{white-space:pre-wrap}</style></head>
<body><h1>Clark hardware summary</h1><pre>$esc</pre></body></html>
"@
        Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
        return $Path
    }

    function Invoke-EdgeHeadless {
        param([string[]]$Arguments)
        $candidates = @(
            (Join-Path ${env:ProgramFiles} "Microsoft\Edge\Application\msedge.exe"),
            (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe")
        )
        $edge = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $edge) {
            throw "Microsoft Edge (msedge.exe) not found. Save as HTML instead."
        }
        $p = Start-Process -FilePath $edge -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
        return $p.ExitCode
    }

    $btnPdf = New-Object System.Windows.Forms.Button
    $btnPdf.Text = "Export PDF..."
    $btnPdf.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnPdf.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "PDF|*.pdf"
        $sfd.FileName = "clark-hardware.pdf"
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $htmlPath = Join-Path $env:TEMP ("clark-hw-{0}.html" -f [Guid]::NewGuid().ToString("n"))
        try {
            $null = Save-HtmlReport -Path $htmlPath
            $uri = ([Uri]$htmlPath).AbsoluteUri
            Invoke-EdgeHeadless -Arguments @(
                "--headless=new",
                "--disable-gpu",
                "--no-first-run",
                "--disable-extensions",
                "--print-to-pdf=$($sfd.FileName)",
                $uri
            ) | Out-Null
            if (-not (Test-Path -LiteralPath $sfd.FileName)) {
                throw "PDF was not created."
            }
            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export PDF", "OK", "Error")
        } finally {
            Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
        }
    })
    [void]$panel.Controls.Add($btnPdf)

    $btnPng = New-Object System.Windows.Forms.Button
    $btnPng.Text = "Export PNG..."
    $btnPng.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnPng.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "PNG|*.png"
        $sfd.FileName = "clark-hardware.png"
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $htmlPath = Join-Path $env:TEMP ("clark-hw-{0}.html" -f [Guid]::NewGuid().ToString("n"))
        try {
            $null = Save-HtmlReport -Path $htmlPath
            $uri = ([Uri]$htmlPath).AbsoluteUri
            Invoke-EdgeHeadless -Arguments @(
                "--headless=new",
                "--disable-gpu",
                "--window-size=1280,2000",
                "--screenshot=$($sfd.FileName)",
                $uri
            ) | Out-Null
            if (-not (Test-Path -LiteralPath $sfd.FileName)) {
                throw "PNG was not created."
            }
            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export PNG", "OK", "Error")
        } finally {
            Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
        }
    })
    [void]$panel.Controls.Add($btnPng)

    $btnHtml = New-Object System.Windows.Forms.Button
    $btnHtml.Text = "Export HTML..."
    $btnHtml.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnHtml.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "HTML|*.html"
        $sfd.FileName = "clark-hardware.html"
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            Save-HtmlReport -Path $sfd.FileName | Out-Null
            [System.Windows.Forms.MessageBox]::Show("Saved:`n$($sfd.FileName)", "clark", "OK", "Information")
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Export HTML", "OK", "Error")
        }
    })
    [void]$panel.Controls.Add($btnHtml)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnClose.Add_Click({ $form.Close() })
    [void]$panel.Controls.Add($btnClose)

    Set-WinFormsButtonFullText -Button @($btnPdf, $btnPng, $btnHtml, $btnClose)

    [void]$form.Controls.Add($panel)
    [void]$form.Controls.Add($tv)
    [void]$form.ShowDialog()
}
