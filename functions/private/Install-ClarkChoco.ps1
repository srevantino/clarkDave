function Install-ClarkChoco {



    <#



    .SYNOPSIS

        Installs Chocolatey if it is not already installed



    #>

    if ((Test-ClarkPackageManager -choco) -eq "installed") {

        return

    }



    Write-Host "Chocolatey is not installed. Installing now..."

    Invoke-WebRequest -Uri https://community.chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression

}

