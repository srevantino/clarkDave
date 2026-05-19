#Requires -Version 5.1
<#
.SYNOPSIS
    Legacy helper — ISO Creator is wired in Invoke-ClarkISO.ps1. Re-run only if you reverted that file.
#>
param([string]$RepoRoot = 'D:\files\software\dev\clarkTypes\clarkDave')
Write-Host "Clark ISO Creator wiring is built into Invoke-ClarkISO.ps1. Run .\Compile.ps1 to rebuild A-SYS_clark.ps1."
Write-Host "Repo: $RepoRoot"
