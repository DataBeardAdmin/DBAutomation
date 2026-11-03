<#
    .SYNOPSIS
    This function will get connection options for new connections to SQL server using Connect-SqlServer.
#>

Function Get-SqlConnectionOptions
{
    [CmdletBinding()]
    param
    (
    )

    return $script:ConnectionOptions
}