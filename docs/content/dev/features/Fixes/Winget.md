---

title: "WinGet Reinstall"

description: ""

---



```powershell {filename="functions/public/Invoke-WPFFixesWinget.ps1",linenos=inline,linenostart=1}

function Invoke-WPFFixesWinget {



    <#



    .SYNOPSIS

        Fixes WinGet by running `choco install winget`

    .DESCRIPTION

        BravoNorris for the fantastic idea of a button to reinstall WinGet

    #>

    # Install Choco if not already present

    try {

        Set-ClarkTaskbaritem -state "Indeterminate" -overlay "logo"

        Write-Host "==> Starting WinGet Repair"

        Install-ClarkWinget

    } catch {

        Write-Error "Failed to install WinGet: $_"

        Set-ClarkTaskbaritem -state "Error" -overlay "warning"

    } finally {

        Write-Host "==> Finished WinGet Repair"

        Set-ClarkTaskbaritem -state "None" -overlay "checkmark"

    }



}

```

