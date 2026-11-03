<#
    .SYNOPSIS
    This function will validate the computer is online and healthy.

    .PARAMETER ComputerName
    The name of the computer that will be tested.

#>

function Wait-ServerUp
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName
    )

    Wait-CBSInstall -ComputerName $ComputerName -Verbose:$VerbosePreference
    Wait-CcmExec -ComputerName $ComputerName -Verbose:$VerbosePreference
    #TODO: Add any additional services that should be checked as a standard. Possibly a 'Test-ServiceStatus' function?
}