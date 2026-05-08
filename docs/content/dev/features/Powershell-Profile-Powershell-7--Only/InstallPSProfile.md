---

title: "Install CTT PowerShell Profile"

description: ""

---



```powershell {filename="functions/private/Invoke-ClarkInstallPSProfile.ps1",linenos=inline,linenostart=1}

function Invoke-ClarkInstallPSProfile {



    if (Test-Path $Profile) {

        Rename-Item $Profile -NewName ($Profile + '.bak')

    }



    Start-Process pwsh -ArgumentList '-Command "irm https://github.com/ChrisTitusTech/powershell-profile/raw/main/setup.ps1 | iex"'

}

```

