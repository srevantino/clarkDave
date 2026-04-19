function Show-ASYSLogo {
    <#
    .SYNOPSIS
        Displays the A-SYS_clark ASCII logo.
    .DESCRIPTION
        Prints the A-SYS_clark banner and product name to the console.
    .EXAMPLE
        Show-ASYSLogo
    #>

    $asciiArt = @"
    ___                _______  _______
   /   |              / ___/\ \/ / ___/
  / /| |    ______    \__ \  \  /\__ \
 / ___ |   /_____/   ___/ /  / /___/ /
/_/  |_|            /____/  /_//____/


====clark=====
=====Advance Systems 4042=====
"@

    Write-Host $asciiArt
}
