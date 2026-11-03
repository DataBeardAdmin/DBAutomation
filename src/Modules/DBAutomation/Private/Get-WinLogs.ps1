function Get-WinLogs
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [String[]]
        $LogName,

        [Parameter(Mandatory = $true)]
        [DateTime]
        $StartTime,

        [Parameter()]
        [DateTime]
        $EndTime,

        [Parameter()]
        [Boolean]
        $UseClientTime = $false,

        [Parameter()]
        [String[]]
        $ExcludeProviders
    )

    $LocalOffset = Get-TimeZoneOffset
    $ServerOffset = Get-TimeZoneOffset -ComputerName $ComputerName
    if ($UseClientTime)
    {
        $FilterStartTime = $StartTime.AddMinutes($ServerOffset.UtcOffsetMins - $LocalOffset.UtcOffsetMins)
        $FilterEndTime = $EndTime.AddMinutes($ServerOffset.UtcOffsetMins - $LocalOffset.UtcOffsetMins)
    }
    else
    {
        $FilterStartTime = $StartTime
        $FilterEndTime = $EndTime
    }
    $TimeShift = $ServerOffset.UtcOffsetMins - $LocalOffset.UtcOffsetMins
    $offsetString = $ServerOffset.OffsetString

    Write-Message -Stream 'Verbose' -Message "Importing Windows logs for $ComputerName"
    try
    {
        [array]$WinLogs = Invoke-Command -ErrorAction:Stop -ComputerName $ComputerName -ScriptBlock {
            $FilterStartTime = $using:FilterStartTime
            $FilterEndTime = $using:FilterEndTime

            $FilterHashtable = @{
                LogName = [string[]]$using:LogName
                StartTime = $FilterStartTime
                Level = 1, 2, 3, 4
            }

            if ($FilterEndTime)
            {
                $FilterHashtable += @{
                    EndTime = $FilterEndTime
                }
            }

            Get-WinEvent -ComputerName $env:COMPUTERNAME -FilterHashtable $FilterHashtable -Verbose:$false -ErrorAction:Stop

            #Return information about restarts even though this is "informational"
            if ($using:LogName -contains 'System')
            {
                $FilterHashtable = @{
                    LogName = 'System'
                    ProviderName = 'User32'
                    StartTime = $FilterStartTime
                    Level = 4
                }

                if ($FilterEndTime)
                {
                    $FilterHashtable += @{
                        EndTime = $FilterEndTime
                    }
                }

                try
                {
                    Get-WinEvent -ComputerName $env:COMPUTERNAME -FilterHashtable $FilterHashtable -Verbose:$false -ErrorAction:Stop
                }
                catch
                {
                    if ($_ -NotMatch '^No events were found that match the specified selection criteria.')
                    {
                        throw -Message $_
                    }
                }
            }
        }

        Write-Message -Stream 'Verbose' -Message 'Parsing logs'
        $LogRecordCount = $WinLogs.Count
        $i = 0
        foreach ($WinLog in $WinLogs)
        {
            #Write-Progress is a bit expensive, but it provides user feedback. Reducing the workload by providing feedback less often.
            if ($i % 100 -eq 0)
            {
                Write-Progress -ParentId 1 -Id 2 -Activity 'Parsing Windows Logs' -PercentComplete ($i / $LogRecordCount * 100)
            }
            $LogEntry = $WinLog.Message
            if (-not [String]::IsNullOrEmpty($LogEntry))
            {
                $LogEntry = $LogEntry.Trim()
            }

            if ($WinLog.LogName -NotMatch 'Verbose$' -and $WinLog.ProviderName -NotIn $ExcludeProviders)
            {
                # The TimeCreated field was returned from the remote computer which may be in a different time zone.
                # To preserve this for storage, we're undoing PowerShell's localization for storage with a DateTimeOffset.
                $LogTime = [DateTime]::SpecifyKind($WinLog.TimeCreated.AddMinutes($TimeShift), 'Unspecified')

                [PSCustomObject] @{
                    LogTime = [DateTimeOffset]::new($LogTime.Ticks, $offsetString)
                    RecordId = $WinLog.RecordId
                    MachineName = $WinLog.MachineName
                    LogSeverity = $WinLog.LevelDisplayName
                    LogName = $WinLog.LogName
                    LogInfo = $WinLog.ProviderName
                    LogEntry = $LogEntry
                }
            }
            $i++
        }
        Write-Progress -ParentId 1 -Id 2 -Activity 'Parsing Windows Logs' -Completed
    }
    catch
    {
        if ($_ -match '^No events were found that match the specified selection criteria.')
        {
            Write-Message -Stream 'Verbose' -Message 'No Windows logs found during the specified time.'
        }
        else
        {
            Write-Message -Stream 'Error' -Message $_
        }
    }
}
