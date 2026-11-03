<#
    .SYNOPSIS
    This function is responsible for writing the log data to the logging directory.

    .PARAMETER Directory
    The directory where log files will be written.
#>

Function Write-Log
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        [ValidateNotNullOrEmpty()]
        $Message
    )

    # Ensure the cache directory exists
    if ($false -eq (Test-Path -Path $script:LogDirectory -PathType Container))
    {
        Set-LogPath -Directory $script:LogDirectory -File $script:LogFile
    }

    # Because multiple jobs can attempt to write to the same file at the same time, this may sometimes fail.
    $Retries = 10
    do
    {
        try
        {
            $Message | Out-File -Append -FilePath "$script:LogDirectory\$script:LogFile" -Width 2000
            $Retries = 0
        }
        catch
        {
            $Retries --
            if ($Retries -eq 0)
            {
                # This does not need to be a terminating error.
                # Additionally, logging this does not make sense so it's being sent directly to the Error stream.
                Write-Error "Failed to log message: '$Message'"
            }
            else
            {
                Start-Sleep -Milliseconds 100
            }
        }
    }
    While ($Retries -gt 0)
}