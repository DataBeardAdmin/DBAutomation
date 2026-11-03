<#
    .SYNOPSIS
    This function is responsible for changing the logging directory for the current session.

    .PARAMETER Directory
    The directory where log files will be written.

    .PARAMETER File
    The file name for logs to be written in.

    .PARAMETER EnableLogging
    This switch will turn logging on for this session.

    .PARAMETER NoLog
    This switch will bypass logging for the output in this function.
#>

Function Set-LogPath
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [String]
        $Directory = "$env:LOCALAPPDATA\DBAutomation\Logs",

        [Parameter()]
        [String]
        $File = "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_$($PID).txt",

        [Alias('LoggingEnabled')]
        [Parameter()]
        [switch]
        $EnableLogging,

        [Parameter()]
        [switch]
        $NoLog
    )

    # Ensure the cache directory exists
    if ($false -eq (Test-Path -Path $Directory -PathType Container))
    {
        Write-Message -Stream 'Debug' -Message "Creating directory [$Directory]" -NoLog:$NoLog.IsPresent
        New-Item -Path $Directory -ItemType Directory -Force > $null
    }

    #Log to the old path that we are changing the logging directory.
    Write-Message -Stream 'Verbose' -Message "Logging to file: $Directory\$File" -NoLog:$NoLog.IsPresent

    $script:LogDirectory = $Directory
    $script:LogFile = $File

    if ($EnableLogging.IsPresent)
    {
        Enable-Logging -NoLog:$NoLog.IsPresent -Verbose:$VerbosePreference
    }
}