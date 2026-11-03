<#
    .PARAMETER NoLog
    This switch will bypass logging for the output in this function.

    .SYNOPSIS
    This function is responsible for disabling logging for the current session.
#>

Function Disable-Logging
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [switch]
        $NoLog
    )

    Write-Message -Stream 'Verbose' -Message 'Logging is disabled.' -NoLog:$NoLog.IsPresent

    $script:LoggingEnabled = $false
}