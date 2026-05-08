function Invoke-WPFSSHServer {

    <#



    .SYNOPSIS

        Invokes the OpenSSH Server install in a runspace



  #>



    Invoke-WPFRunspace -ScriptBlock {



        Invoke-ClarkSSHServer



        Write-Host "======================================="

        Write-Host "--     OpenSSH Server installed!    ---"

        Write-Host "======================================="

    }

}

