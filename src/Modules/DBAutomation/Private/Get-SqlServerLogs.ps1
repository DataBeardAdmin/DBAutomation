function Get-SqlServerLogs
{
    [CmdletBinding(DefaultParameterSetName = 'ReturnResults')]
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
        $OffsetString,

        [Parameter(ParameterSetName = 'StoreResults', Mandatory = $true)]
        [String]
        $TargetSqlServer,

        [Parameter(ParameterSetName = 'StoreResults', Mandatory = $true)]
        [String]
        $TargetSqlDatabase
    )

    if ($PSCmdlet.ParameterSetName -eq 'StoreResults')
    {
        $TargetServer = Connect-SqlServer -SqlServer $TargetSqlServer -Verbose:$VerbosePreference
        Sync-SqlSysMessages -Server $Server -TargetServer $TargetServer -TargetSqlDatabase $TargetSqlDatabase -Verbose:$VerbosePreference

        $SysMsgParams = @{
            Server = $TargetServer
            DatabaseName = $TargetSqlDatabase
            QueryString = 'EXEC [dbo].[Get_LogImport_sysmessages]'
            WithResults = $true
            ResultsType = 'DataTable'
        }

        Write-Message -Stream 'Verbose' -Message "Getting [LogImport_sysmessages] from server [$TargetSqlServer]."

        # Execute the query
        $SysMessages = Invoke-SqlQuery @SysMsgParams -Verbose:$VerbosePreference
    }
    else
    {
        $SysMessages = Get-SqlSysMessages -Server $Server

        $Column = New-Object -TypeName System.Data.DataColumn -ArgumentList 'SysMessageID'
        $SysMessages.Columns.Add($Column)

        for ( $i = 0; $i -lt $SysMessages.Rows.Count; $i++ )
        {
            $SysMessages.Rows[$i].SysMessageID = $i + 1
        }
    }

    $SqlServer = $Server.ConnectionContext.ServerInstance

    $SqlLogList = $Server.EnumErrorLogs()

    $OldestLog = $SqlLogList | Where-Object CreateDate -GE $FilterStartTime | Sort-Object -Property CreateDate | Select-Object -First 1 -ExpandProperty ArchiveNo
    $NewestLog = $SqlLogList | Where-Object CreateDate -GE $FilterEndTime | Sort-Object -Property CreateDate | Select-Object -First 1 -ExpandProperty ArchiveNo

    $FilteredSqlLogList = @($SqlLogList | Where-Object { $_.ArchiveNo -ge $NewestLog -and $_.ArchiveNo -le $OldestLog })
    $LogCount = $FilteredSqlLogList.Count
    if ($LogCount -eq 0)
    {
        Write-Message -Stream 'Verbose' -Message 'No SQL Server Logs found during the specified time.'
    }
    else
    {
        $SqlConnection = Get-SqlConnectionObject -Server $Server

        try
        {
            $Transaction = $SqlConnection.BeginTransaction()

            $TempTableParams = @{
                Connection = $sqlConnection
                DatabaseName = 'tempdb'
                QueryString = 'CREATE TABLE #LogImport_sysmessages(
                    [SysMessageID] [INT] NOT NULL,
                    [message_id] [INT] NOT NULL,
                    [language_id] [SMALLINT] NOT NULL,
                    [severity] [TINYINT] NULL,
                    [text] [NVARCHAR](2048) NOT NULL,
                    PRIMARY KEY CLUSTERED ([SysMessageID])
                )'
                Transaction = $Transaction
            }

            Write-Message -Stream 'Debug' -Message 'Creating temp table #LogImport_sysmessages'

            # Execute the query
            Invoke-SqlQuery @TempTableParams -Verbose:$VerbosePreference

            #Export-SqlBulkData clears the InputObject. Since this is useful for general cleanliness, we are making a copy of the data for re-use.
            $SysMessages2 = $SysMessages.Copy()
            Export-SqlBulkData -SqlConnection $SqlConnection -DatabaseName 'tempdb' -InputObject $SysMessages2 -DestinationTable '#LogImport_sysmessages' -Transaction $Transaction -Verbose:$false

            $LogNumber = 0
            foreach ($SqlLogFile in $FilteredSqlLogList)
            {
                Write-Progress -ParentId 1 -Id 2 -Activity "Importing SQL Server Error log #$($SqlLogFile.ArchiveNo)" -PercentComplete ($LogNumber / $LogCount * 100)
                Write-Message -Stream 'Verbose' -Message "Importing SQL Server Error log #$($SqlLogFile.ArchiveNo)"

                # We're doing this in SQL vs. SMO as the SQL engine is more efficient at matching using the join query below.
                $QueryParameters = @{
                    SqlArchiveNo = $SqlLogFile.ArchiveNo
                    FilterStartTime = $FilterStartTime
                    FilterEndTime = $FilterEndTime
                }
                $QueryString = "
                    CREATE TABLE #ErrorLogs
                    (
                        LogID INT IDENTITY,
                        LogDate DATETIME,
                        ProcessInfo VARCHAR(25),
                        LogEntry NVARCHAR(4000),
                        PRIMARY KEY CLUSTERED ([LogID])
                    )

                    INSERT INTO #ErrorLogs
                    EXEC sys.xp_readerrorlog
                        @SqlArchiveNo, --change to 0 for current errorlog
                        1, --type of log (1=SqlServer,2=SqlAgent)
                        NULL, --search for string 1
                        NULL, --search for string 2
                        @FilterStartTime, --StartTime
                        @FilterEndTime, --EndTime
                        'ASC'

                    UPDATE #ErrorLogs
                    SET LogEntry = SUBSTRING(LogEntry, 1, LEN(LogEntry) - 2)
                    WHERE LogID = SCOPE_IDENTITY()
                    AND LogEntry LIKE '%' + CHAR(13) + CHAR(10)

                    ;with ErrorLogs AS (SELECT LogID, LogDate, ProcessInfo, LogEntry, MIN(m.SysMessageID) AS SysMessageID
                    FROM #ErrorLogs e
                    LEFT JOIN #LogImport_sysmessages m
                    ON e.LogEntry LIKE m.text
                    GROUP BY e.LogID, e.LogDate, e.ProcessInfo, e.LogEntry)
                    SELECT e.LogDate,
                            e.LogID,
                            m.SysMessageID,
                            CASE
                                WHEN e.LogEntry LIKE 'Error:%'
                                        AND LEAD(LogEntry, 1, '') OVER (PARTITION BY LogDate, ProcessInfo ORDER BY e.LogID) LIKE '%No user action is required.'
                                    THEN 'Information'
                                WHEN e.LogEntry LIKE '%No user action is required.'
                                        OR e.LogEntry LIKE 'DbMgrPartnerCommitPolicy%'
                                        OR e.LogEntry LIKE '[[]DbMgrPartnerCommitPolicy%'
                                        OR (e.ProcessInfo = 'Server' AND e.LogEntry LIKE 'The Service Broker endpoint is in disabled or stopped state.%')
                                    THEN 'Information'
                                WHEN ISNULL(CONVERT(INT, CASE WHEN LogEntry LIKE 'Error:%Severity%State%' THEN SUBSTRING(LogEntry, CHARINDEX('Severity: ', LogEntry) + 10, CHARINDEX('State: ', LogEntry) - CHARINDEX('Severity: ', LogEntry) - 12) ELSE NULL END), m.severity) >= 20
                                    THEN 'Critical'
                                WHEN ISNULL(CONVERT(INT, CASE WHEN LogEntry LIKE 'Error:%Severity%State%' THEN SUBSTRING(LogEntry, CHARINDEX('Severity: ', LogEntry) + 10, CHARINDEX('State: ', LogEntry) - CHARINDEX('Severity: ', LogEntry) - 12) ELSE NULL END), m.severity) >= 16
                                    THEN 'Error'
                                WHEN ISNULL(CONVERT(INT, CASE WHEN LogEntry LIKE 'Error:%Severity%State%' THEN SUBSTRING(LogEntry, CHARINDEX('Severity: ', LogEntry) + 10, CHARINDEX('State: ', LogEntry) - CHARINDEX('Severity: ', LogEntry) - 12) ELSE NULL END), m.severity) > 10
                                    THEN 'Warning'
                                WHEN ISNULL(CONVERT(INT, CASE WHEN LogEntry LIKE 'Error:%Severity%State%' THEN SUBSTRING(LogEntry, CHARINDEX('Severity: ', LogEntry) + 10, CHARINDEX('State: ', LogEntry) - CHARINDEX('Severity: ', LogEntry) - 12) ELSE NULL END), m.severity) <= 10
                                    THEN 'Information'
                                    ELSE 'Information'
                                END AS LogSeverity,
                            ProcessInfo,
                            LogEntry
                    FROM ErrorLogs e
                    LEFT JOIN #LogImport_sysmessages m
                    ON e.SysMessageID = m.SysMessageID
                    ORDER BY e.LogID

                    DROP TABLE #ErrorLogs"

                $MsgParams = @{
                    Connection = $sqlConnection
                    DatabaseName = 'tempdb'
                    QueryString = $QueryString
                    QueryParameters = $QueryParameters
                    Transaction = $Transaction
                    CommandTimeout = 600
                }

                Write-Message -Stream 'Debug' -Message 'Getting log results from SQL and matching sys.messages.'

                # Execute the query
                $SqlLogs = @(Invoke-SqlQuery @MsgParams -WithResults -Verbose:$VerbosePreference)

                $LogRecordCount = $SqlLogs.Count
                if ($LogRecordCount -eq 0)
                {
                    Write-Message -Stream 'Verbose' -Message 'No SQL Server Logs found during the specified time.'
                }
                else
                {
                    $i = 0
                    foreach ($SqlLog in $SqlLogs)
                    {
                        #Write-Progress is a bit expensive, but it provides user feedback. Reducing the workload by providing feedback less often.
                        if ($i % 100 -eq 0)
                        {
                            Write-Progress -ParentId 2 -Id 3 -Activity "Parsing SQL Server Logs ($i/$LogRecordCount)" -PercentComplete ($i / $LogRecordCount * 100)
                        }
                        $LogTime = [DateTime]::SpecifyKind($SqlLog.LogDate, 'Unspecified')

                        [PSCustomObject] @{
                            LogTime = [DateTimeOffset]::new($LogTime, $OffsetString)
                            RecordId = $SqlLog.LogID
                            MachineName = $SqlServer
                            LogSeverity = $SqlLog.LogSeverity
                            LogName = 'SqlServerLog'
                            LogInfo = $SqlLog.ProcessInfo
                            LogEntry = $SqlLog.LogEntry
                            SysMessageID = $SqlLog.SysMessageID
                        }

                        $i++
                    }
                    Write-Progress -ParentId 2 -Id 3 -Activity 'Parsing SQL Server Logs' -Completed
                }
                $LogNumber++
            }
            $TempTableParams = @{
                Connection = $sqlConnection
                DatabaseName = 'tempdb'
                QueryString = 'DROP TABLE #LogImport_sysmessages'
                Transaction = $Transaction
            }

            Write-Message -Stream 'Debug' -Message 'Dropping temp table #LogImport_sysmessages'

            # Execute the query
            Invoke-SqlQuery @TempTableParams -Verbose:$VerbosePreference

            $Transaction.Commit()
        }
        catch
        {
            $Message = 'Error parsing SQL logs. ({0})' -f $_.Exception.ToString()
            $Transaction.Rollback()
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
        finally
        {
            $Transaction.Dispose()
        }

        Write-Progress -ParentId 1 -Id 2 -Activity 'Importing SQL Server Logs' -Completed
    }
}
