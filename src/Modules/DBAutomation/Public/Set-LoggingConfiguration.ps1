<#
    .SYNOPSIS
    This function is responsible for configuration logging for the current session.

    .PARAMETER Directory
    The directory where log files will be written.

    .PARAMETER File
    The file name for logs to be written in.

    .PARAMETER Disable
    This switch will turn logging off for this session.

    .PARAMETER NoLog
    This switch will bypass logging for the output in this function.

    .NOTES
    You can either pass in a hashtable for LogConfiguration, specify the Directory and/or File or disable logging.

    .EXAMPLE
    Set-LoggingConfiguration -Directory 'D:\DBAutomationLogs' -Verbose

    .EXAMPLE
    Set-LoggingConfiguration -Directory 'D:\DBAutomationLogs' -File 'SingleLogFile.txt' -Verbose

    .EXAMPLE
    Set-LoggingConfiguration -Verbose

    .EXAMPLE
    Set-LoggingConfiguration -Disable -Verbose

    .EXAMPLE
    $LogConfiguration = Get-LoggingConfiguration
    Start-Job -name 'AsyncProcess' -ScriptBlock {
        Import-Module 'DBAutomation'
        $LogConfiguration = $using:LogConfiguration
        $LogConfiguration | Set-LoggingConfiguration -NoLog
    }
#>

Function Set-LoggingConfiguration
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]
        $Directory = "$env:LOCALAPPDATA\DBAutomation\Logs",

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]
        $File = "$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')_$($PID).txt",

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [switch]
        $Disable,

        [Parameter()]
        [switch]
        $NoLog
    )

    #Initialize logging.
    if ($true -eq $Disable.IsPresent)
    {
        Disable-Logging -NoLog:$NoLog.IsPresent -Verbose:$VerbosePreference
    }
    else
    {
        $LogConfiguration = @{
            EnableLogging = $true
            Directory = $Directory
            File = $File
            NoLog = $NoLog.IsPresent
        }

        Set-LogPath @LogConfiguration -Verbose:$VerbosePreference
    }
}