function Remove-ClarkAPPX {

    <#



    .SYNOPSIS

        Removes all APPX packages that match the given name



    .PARAMETER Name

        The name of the APPX package to remove



    .EXAMPLE

        Remove-ClarkAPPX -Name "Microsoft.Microsoft3DViewer"



    #>

    param (

        $Name

    )



    Write-Host "Removing $Name"

    Get-AppxPackage $Name -AllUsers | Remove-AppxPackage -AllUsers

    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Name | Remove-AppxProvisionedPackage -Online

}

