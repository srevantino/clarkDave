#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Invoke-ClarkSetupCommon.ps1')
try {
    $bootstrap = Join-Path $here 'Invoke-ClarkSetupBootstrap.ps1'
    if (-not (Test-Path -LiteralPath $bootstrap)) { throw "Missing: $bootstrap" }
    & $bootstrap
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Bootstrap exit code $LASTEXITCODE" }
} catch {
    Show-ClarkSetupError -Title 'Windows PE setup' -Message 'Clark automated setup failed before Windows could be installed.' -Detail $_.Exception.Message
    exit 1
}
