function Get-SqlAgentLogs
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(Mandatory = $true)]
        [DateTime]
        $FilterStartTime,

        [Parameter()]
        [DateTime]
        $FilterEndTime,

        [Parameter(Mandatory = $true)]
        [string]
        $OffsetString
    )

    $SqlServer = $Server.ConnectionContext.ServerInstance

    $SqlLogList = $Server.JobServer.EnumErrorLogs()

    $OldestLog = $SqlLogList | Where-Object CreateDate -GE $FilterStartTime | Sort-Object -Property CreateDate | Select-Object -First 1 -ExpandProperty ArchiveNo
    $NewestLog = $SqlLogList | Where-Object CreateDate -GE $FilterEndTime | Sort-Object -Property CreateDate | Select-Object -First 1 -ExpandProperty ArchiveNo

    $FilteredSqlLogList = @($SqlLogList | Where-Object { $_.ArchiveNo -ge $NewestLog -and $_.ArchiveNo -le $OldestLog })
    $LogCount = $FilteredSqlLogList.Count
    if ($LogCount -eq 0)
    {
        Write-Message -Stream 'Verbose' -Message 'No SQL Agent Logs found during the specified time.'
    }
    else
    {
        $LogNumber = 0
        foreach ($SqlLogFile in $FilteredSqlLogList)
        {
            Write-Progress -ParentId 1 -Id 2 -Activity "Importing SQL Agent Error log #$($SqlLogFile.ArchiveNo)" -PercentComplete ($LogNumber / $LogCount * 100)
            $RecordId = 1
            Write-Message -Stream 'Verbose' -Message "Importing SQL Agent Error log #$($SqlLogFile.ArchiveNo)"
            $SqlLogs = @($Server.JobServer.ReadErrorLog($SqlLogFile.ArchiveNo) | Where-Object { $_.LogDate -ge $FilterStartTime -and $_.LogDate -le $FilterEndTime })

            $LogRecordCount = $SqlLogs.Count
            if ($LogRecordCount -eq 0)
            {
                Write-Message -Stream 'Verbose' -Message 'No SQL Agent Logs found during the specified time.'
            }
            else
            {
                $i = 0
                foreach ($SqlLog in $SqlLogs)
                {
                    #Write-Progress is a bit expensive, but it provides user feedback. Reducing the workload by providing feedback less often.
                    if ($i % 100 -eq 0)
                    {
                        Write-Progress -ParentId 2 -Id 3 -Activity 'Parsing SQL Agent Logs' -PercentComplete ($i / $LogRecordCount * 100)
                    }
                    $LogTime = [DateTime]::SpecifyKind($SqlLog.LogDate, 'Unspecified')

                    switch ($SqlLog.ErrorLevel)
                    {
                        1 { $LogSeverity = 'Error' }
                        2 { $LogSeverity = 'Warning' }
                        3 { $LogSeverity = 'Information' }
                    }

                    [PSCustomObject] @{
                        LogTime = [DateTimeOffset]::new($LogTime, $OffsetString)
                        RecordId = $RecordId
                        MachineName = $SqlServer
                        LogSeverity = $LogSeverity
                        LogName = 'SqlAgentLog'
                        LogInfo = $null
                        LogEntry = $SqlLog.Text.Trim()
                    }

                    $RecordId++
                    $i++
                }
                Write-Progress -ParentId 2 -Id 3 -Activity 'Parsing SQL Agent Logs' -Completed
            }
            $LogNumber++
        }
        Write-Progress -ParentId 1 -Id 2 -Activity 'Importing SQL Agent Logs' -Completed
    }
}
