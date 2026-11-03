<#
    .PARAMETER Directory
    This optional parameter can be used to specify the directory to write log entries to.

    .PARAMETER NoLog
    This switch will bypass logging for the output in this function.

    .SYNOPSIS
    This function is responsible for enabling logging for the current session.
#>

Function Enable-Logging
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [String]
        $Directory,

        [Parameter()]
        [switch]
        $NoLog
    )

    $script:LoggingEnabled = $true

    if ($false -eq [string]::IsNullOrEmpty($Directory))
    {
        Set-LogPath -Directory $Directory -NoLog:$NoLog.IsPresent -Verbose:$VerbosePreference
    }

    Write-Message -Stream 'Verbose' -Message 'Logging is enabled.' -NoLog:$NoLog.IsPresent
}