<#
    .SYNOPSIS
    This function is responsible for directing all output to the correct streams and module log file (if enabled).

    .PARAMETER Message
    The message to output

    .PARAMETER Stream
    The stream to send the message to. Possible values:
    Information
    Verbose
    Debug
    Warning
    Error
    Log

    .PARAMETER NoLog
    This switch will bypass logging for the output in this function.
#>

Function Write-Message
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        [ValidateNotNullOrEmpty()]
        $Message,

        [Parameter()]
        [ValidateSet('Information', 'Verbose', 'Debug', 'Warning', 'Error', 'Log')]
        [String]
        $Stream = 'Log',

        [Parameter()]
        [switch]
        $NoLog
    )

    if ($NoLog.IsPresent -and $Stream -eq 'Log')
    {
        Write-Warning -Message 'Write-Message was called with NoLog and Stream type of Log!'
    }

    $LogDate = Get-Date -Format 'yyyy-MM-dd'
    $LogTime = Get-Date -Format 'HH:mm:ss.ffff'

    switch ( $Stream )
    {
        'Information'
        {
            Write-Information "[$LogTime]$Message"
        }

        'Verbose'
        {
            Write-Verbose "[$LogTime]$Message"
        }

        'Debug'
        {
            Write-Debug "[$LogTime]$Message"
        }

        'Warning'
        {
            Write-Warning "[$LogTime]$Message"
        }

        'Error'
        {
            Write-Error "[$LogTime]$Message"
        }
    }

    if ($script:LoggingEnabled -eq $true -and $false -eq $NoLog.IsPresent)
    {
        Write-Log "[$LogDate $LogTime][$Script:SessionId][$Stream]$Message"
    }
}