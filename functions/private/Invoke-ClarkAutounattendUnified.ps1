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

    $setupDir = Join-Path $ToolsRoot 'setup'
    if (Test-Path -LiteralPath $setupDir) {
        Get-ChildItem -LiteralPath $setupDir -Filter '*.ps1' -File | ForEach-Object {
            $relPath = "Windows\Setup\Scripts\$($_.Name)"
            $existing = $autoDoc.SelectSingleNode("//sg:File[@path='$relPath']", $nsMgr)
            $fileNode = if ($existing) { $existing } else {
                $n = $autoDoc.CreateElement('File', $sgNs)
                [void]$n.SetAttribute('path', $relPath)
                [void]$extensionsNode.AppendChild($n)
                $n
            }
            $fileNode.RemoveAll()
            [void]$fileNode.SetAttribute('path', $relPath)
            [void]$fileNode.AppendChild($autoDoc.CreateCDataSection((Get-Content -LiteralPath $_.FullName -Raw)))
        }
    }

    $firstLogonSrc = Join-Path $setupDir 'Invoke-ClarkSetupFirstLogon.ps1'
    if (Test-Path -LiteralPath $firstLogonSrc) {
        $flNode = $autoDoc.SelectSingleNode("//sg:File[@path='C:\Setup\Invoke-ClarkSetupFirstLogon.ps1']", $nsMgr)
        if (-not $flNode) {
            $flNode = $autoDoc.CreateElement('File', $sgNs)
            [void]$flNode.SetAttribute('path', 'C:\Setup\Invoke-ClarkSetupFirstLogon.ps1')
            [void]$extensionsNode.AppendChild($flNode)
        }
        $flNode.RemoveAll()
        [void]$flNode.SetAttribute('path', 'C:\Setup\Invoke-ClarkSetupFirstLogon.ps1')
        [void]$flNode.AppendChild($autoDoc.CreateCDataSection((Get-Content -LiteralPath $firstLogonSrc -Raw)))
    }

    $masterScriptSource = Join-Path $ToolsRoot '$OEM$\$1\Setup\master.ps1'
    if (Test-Path -LiteralPath $masterScriptSource) {
        $masterNode = $autoDoc.SelectSingleNode("//sg:File[@path='C:\Setup\master.ps1']", $nsMgr)
        if (-not $masterNode) {
            $masterNode = $autoDoc.CreateElement('File', $sgNs)
            [void]$masterNode.SetAttribute('path', 'C:\Setup\master.ps1')
            [void]$extensionsNode.AppendChild($masterNode)
        }
        $masterNode.RemoveAll()
        [void]$masterNode.SetAttribute('path', 'C:\Setup\master.ps1')
        [void]$masterNode.AppendChild($autoDoc.CreateCDataSection((Get-Content -LiteralPath $masterScriptSource -Raw)))
    }

    $autoDoc.OuterXml
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
        New-Item -ItemType Directory -Path $setupDest -Force | Out-Null
        Copy-Item -Path (Join-Path $setupSrc '*') -Destination $setupDest -Recurse -Force
    }

    if (Test-Path -LiteralPath $driversSrc) {
        $driversDest = Join-Path $asysDest 'drivers'
        New-Item -ItemType Directory -Path $driversDest -Force | Out-Null
        Copy-Item -Path (Join-Path $driversSrc '*') -Destination $driversDest -Recurse -Force
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
