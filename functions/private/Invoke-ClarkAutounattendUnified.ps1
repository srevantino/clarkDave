function Get-ClarkAutounattendForBuild {
    <#
    .SYNOPSIS
        Returns autounattend XML for UEFI, Legacy, or Auto (unified) firmware mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('UEFI', 'Legacy', 'Auto')]
        [string]$FirmwareMode = 'Auto',

        [Parameter()]
        [string]$ToolsRoot = ''
    )

    if (-not $ToolsRoot) {
        $pathCandidates = @(
            (Join-Path $PSScriptRoot '..\..\tools'),
            (Join-Path $PSScriptRoot '..\tools'),
            (Join-Path $PSScriptRoot 'tools')
        )
        $ToolsRoot = $pathCandidates |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
    }

    if (-not $ToolsRoot) { return $null }

    $fileName = switch ($FirmwareMode) {
        'Legacy' { 'autounattend-legacy.xml' }
        'UEFI'   { 'autounattend.xml' }
        default  { 'autounattend-unified.xml' }
    }

    $path = Join-Path $ToolsRoot $fileName
    if (-not (Test-Path -LiteralPath $path)) {
        if ($FirmwareMode -eq 'Auto') {
            $path = Join-Path $ToolsRoot 'autounattend.xml'
        }
        if (-not (Test-Path -LiteralPath $path)) { return $null }
    }

    Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

function Add-ClarkAutounattendExtensions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AutounattendXml,

        [Parameter(Mandatory)]
        [string]$ToolsRoot
    )

    $sgNs = 'https://schneegans.de/windows/unattend-generator/'
    $autoDoc = [xml]$AutounattendXml
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($autoDoc.NameTable)
    $nsMgr.AddNamespace('sg', $sgNs)

    $extensionsNode = $autoDoc.SelectSingleNode('//sg:Extensions', $nsMgr)
    if (-not $extensionsNode) {
        $extensionsNode = $autoDoc.CreateElement('Extensions', $sgNs)
        [void]$autoDoc.DocumentElement.AppendChild($extensionsNode)
    }

    function Set-AutounattendFileNode {
        param($Doc, $NsMgr, $SgNs, $ExtensionsNode, [string]$FilePath, [string]$Content)
        $escapedPath = $FilePath.Replace("'", "&apos;")
        $existing = $Doc.SelectSingleNode("//sg:File[@path='$escapedPath']", $NsMgr)
        $fileNode = if ($existing) { $existing } else {
            $n = $Doc.CreateElement('File', $SgNs)
            [void]$n.SetAttribute('path', $FilePath)
            [void]$ExtensionsNode.AppendChild($n)
            $n
        }
        $fileNode.IsEmpty = $true
        [void]$fileNode.SetAttribute('path', $FilePath)
        [void]$fileNode.AppendChild($Doc.CreateCDataSection($Content))
    }

    $setupDir = Join-Path $ToolsRoot 'setup'
    if (Test-Path -LiteralPath $setupDir) {
        Get-ChildItem -LiteralPath $setupDir -Filter '*.ps1' -File | ForEach-Object {
            $relPath = "Windows\Setup\Scripts\$($_.Name)"
            Set-AutounattendFileNode -Doc $autoDoc -NsMgr $nsMgr -SgNs $sgNs -ExtensionsNode $extensionsNode `
                -FilePath $relPath -Content (Get-Content -LiteralPath $_.FullName -Raw)
        }
    }

    $firstLogonSrc = Join-Path $setupDir 'Invoke-ClarkSetupFirstLogon.ps1'
    if (Test-Path -LiteralPath $firstLogonSrc) {
        Set-AutounattendFileNode -Doc $autoDoc -NsMgr $nsMgr -SgNs $sgNs -ExtensionsNode $extensionsNode `
            -FilePath 'C:\Setup\Invoke-ClarkSetupFirstLogon.ps1' -Content (Get-Content -LiteralPath $firstLogonSrc -Raw)
    }

    $masterScriptSource = Join-Path $ToolsRoot '$OEM$\$1\Setup\master.ps1'
    if (Test-Path -LiteralPath $masterScriptSource) {
        Set-AutounattendFileNode -Doc $autoDoc -NsMgr $nsMgr -SgNs $sgNs -ExtensionsNode $extensionsNode `
            -FilePath 'C:\Setup\master.ps1' -Content (Get-Content -LiteralPath $masterScriptSource -Raw)
    }

    $autoDoc.OuterXml
}

function Set-ClarkAutounattendInstallUx {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AutounattendXml)

    $doc = [xml]$AutounattendXml
    $ns = 'urn:schemas-microsoft-com:unattend'
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nsMgr.AddNamespace('u', $ns)

    $osImage = $doc.SelectSingleNode('//u:settings[@pass="windowsPE"]//u:ImageInstall/u:OSImage', $nsMgr)
    if ($osImage) {
        $willShow = $osImage.SelectSingleNode('u:WillShowUI', $nsMgr)
        if (-not $willShow) {
            $willShow = $doc.CreateElement('WillShowUI', $ns)
            [void]$osImage.PrependChild($willShow)
        }
        $willShow.InnerText = 'Always'
    }

    $setup = $doc.SelectSingleNode('//u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]', $nsMgr)
    if ($setup) {
        $runSync = $setup.SelectSingleNode('u:RunSynchronous', $nsMgr)
        if (-not $runSync) {
            $runSync = $doc.CreateElement('RunSynchronous', $ns)
            [void]$setup.InsertBefore($runSync, $setup.FirstChild)
        }
        $marker = 'Clark: custom install; do not auto-select OS variant'
        $existing = $runSync.SelectNodes('u:RunSynchronousCommand', $nsMgr) |
            Where-Object { $_.Description -and $_.Description.InnerText -like "*$marker*" } |
            Select-Object -First 1
        if (-not $existing) {
            $cmd = $doc.CreateElement('RunSynchronousCommand', $ns)
            [void]$cmd.SetAttribute('action', 'http://schemas.microsoft.com/WMIConfig/2002/State', 'add')
            $order = $doc.CreateElement('Order', $ns); $order.InnerText = '1'
            $desc = $doc.CreateElement('Description', $ns); $desc.InnerText = $marker
            $path = $doc.CreateElement('Path', $ns)
            $path.InnerText = 'reg add "HKLM\SYSTEM\Setup\MoSetup" /v UpgradeInstall /t REG_DWORD /d 0 /f & reg add "HKLM\SYSTEM\Setup" /v InstallationType /t REG_SZ /d Custom /f & reg delete "HKLM\SYSTEM\Setup\Upgrade" /f 2>nul'
            [void]$cmd.AppendChild($order); [void]$cmd.AppendChild($desc); [void]$cmd.AppendChild($path)
            [void]$runSync.PrependChild($cmd)
            foreach ($node in @($runSync.SelectNodes('u:RunSynchronousCommand', $nsMgr))) {
                if ($node -eq $cmd) { continue }
                $orderNode = $node.SelectSingleNode('u:Order', $nsMgr)
                if ($orderNode -and [int]$orderNode.InnerText -ge 1) {
                    $orderNode.InnerText = ([int]$orderNode.InnerText + 1).ToString()
                }
            }
        }
    }
    return $doc.OuterXml
}

function Copy-ClarkAsysIsoPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IsoContentsDir,

        [Parameter(Mandatory)]
        [string]$ToolsRoot
    )

    $asysDest = Join-Path $IsoContentsDir 'asys'
    $setupSrc = Join-Path $ToolsRoot 'setup'
    $driversSrc = Join-Path $ToolsRoot 'platform-drivers'

    if (Test-Path -LiteralPath $setupSrc) {
        $setupDest = Join-Path $asysDest 'setup'
        New-Item -ItemType Directory -Path $setupDest -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $setupSrc '*') -Destination $setupDest -Recurse -Force -ErrorAction Stop
    }

    if (Test-Path -LiteralPath $driversSrc) {
        $driversDest = Join-Path $asysDest 'drivers'
        New-Item -ItemType Directory -Path $driversDest -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path (Join-Path $driversSrc '*') -Destination $driversDest -Recurse -Force -ErrorAction Stop
    }
}

function Invoke-ClarkPrepareBuildAutounattend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('UEFI', 'Legacy', 'Auto')]
        [string]$FirmwareMode,

        [Parameter(Mandatory)]
        [string]$ToolsRoot,

        [Parameter(Mandatory)]
        [string]$MainUsername,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [scriptblock]$Log = { param($m) Write-Output $m }
    )

    $raw = Get-ClarkAutounattendForBuild -FirmwareMode $FirmwareMode -ToolsRoot $ToolsRoot
    if (-not $raw) {
        $missing = switch ($FirmwareMode) {
            'Legacy' { 'autounattend-legacy.xml' }
            'UEFI'   { 'autounattend.xml' }
            default  { 'autounattend-unified.xml' }
        }
        throw "Could not load $missing from $ToolsRoot"
    }

    & $Log "Autounattend: $FirmwareMode"
    if (Get-Command Set-ClarkAutounattendInstallUx -ErrorAction SilentlyContinue) {
        $raw = Set-ClarkAutounattendInstallUx -AutounattendXml $raw
        & $Log 'Autounattend install UX: always show edition picker; custom install path.'
    }
    $raw = Add-ClarkAutounattendExtensions -AutounattendXml $raw -ToolsRoot $ToolsRoot
    & $Log 'Autounattend Extensions applied (setup scripts + master.ps1).'

    $safeUser = [regex]::Replace($MainUsername, '[^\w\-\.]', '')
    if (-not $safeUser) { $safeUser = 'User' }
    $safePc = [regex]::Replace($ComputerName, '[^\w\-]', '')
    if (-not $safePc) { $safePc = 'ASYS-PC' }
    if ($safePc.Length -gt 15) { $safePc = $safePc.Substring(0, 15) }

    $raw.Replace('%%USERNAME%%', $safeUser).Replace('%%COMPUTERNAME%%', $safePc)
}

function Get-ClarkSelectedFirmwareMode {
    <#
    .SYNOPSIS
        Always Auto. Build dialog no longer offers forced UEFI/Legacy.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [System.Windows.Window]$DialogWindow = $null
    )
    return 'Auto'
}
