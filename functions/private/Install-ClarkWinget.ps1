function Install-ClarkWinget {

    <#



    .SYNOPSIS

        Installs WinGet if not already installed.



    .DESCRIPTION

        installs winGet if needed

    #>

    if ((Test-ClarkPackageManager -winget) -eq "installed") {

        return

    }



    Write-Host "WinGet is not installed. Installing now..." -ForegroundColor Red



    Install-PackageProvider -Name NuGet -Force

    Install-Module -Name Microsoft.WinGet.Client -Force

    Repair-WinGetPackageManager -AllUsers

}

