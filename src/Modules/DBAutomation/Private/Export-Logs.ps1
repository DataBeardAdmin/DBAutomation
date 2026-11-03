function Export-Logs
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Console', 'Disk', 'SQL')]
        [String[]]
        $SendTo,

        [Parameter()]
        [String]
        $TargetFilePath,

        [Parameter()]
        [String]
        $TargetSqlServer,

        [Parameter()]
        [String]
        $TargetSqlDatabase,

        [Parameter()]
        [PSObject[]]
        $Logs
    )

    $AssertLogTarget = @{
        SendTo = $SendTo
        TargetFilePath = $TargetFilePath
        TargetSqlServer = $TargetSqlServer
        TargetSqlDatabase = $TargetSqlDatabase
    }
    Assert-LogTarget @AssertLogTarget

    Write-Message -Stream 'Verbose' -Message 'Processing all logs. For large collections, this may take some time.'
    $Logs = $Logs | Sort-Object -Property LogTime, RecordId, MachineName, LogName, LogInfo

    if ($SendTo -contains 'SQL')
    {
        $Logs = $Logs |
            Select-Object -Property LogTime, MachineName, LogSeverity, LogName, LogInfo, LogEntry, SysMessageID

        Write-Message -Stream 'Verbose' -Message "Exporting logs to TargetSqlDatabase: $TargetSqlDatabase on TargetSqlServer: $TargetSqlServer"

        $LogServer = Connect-SqlServer -SqlServer $TargetSqlServer -Verbose:$VerbosePreference

        $SqlConnection = Get-SqlConnectionObject -Server $LogServer

        try
        {
            $Transaction = $SqlConnection.BeginTransaction()

            $truncateParams = @{
                Connection = $sqlConnection
                DatabaseName = $TargetSqlDatabase
                QueryString = 'EXEC dbo.Truncate_Staging_Table @TableName'
                QueryParameters = @{TableName = '[dbo].[LogImport_Staging]' }
                Transaction = $Transaction
            }

            Write-Message -Stream 'Debug' -Message "Truncating table [LogImport_Staging] in database [$TargetSqlDatabase]."

            # Execute the query
            Invoke-SqlQuery @truncateParams -Verbose:$VerbosePreference

            $MappingOverride = [PSCustomObject] @{
                LogTime = 'DateTimeOffset'
                MachineName = 'string'
                LogSeverity = 'string'
                LogName = 'string'
                LogInfo = 'string'
                LogEntry = 'string'
                SysMessageID = 'string' #Int does not support null.
            }
            $LogDataTable = ConvertTo-DataTable -InputObject $Logs -MappingOverride $MappingOverride -Verbose:$VerbosePreference
            Export-SqlBulkData -SqlConnection $SqlConnection -DatabaseName $TargetSqlDatabase -InputObject $LogDataTable -DestinationTable '[dbo].[LogImport_Staging]' -Transaction $Transaction -Verbose:$false

            $Transaction.Commit()
        }
        catch
        {
            $Message = 'Error loading LogImport_Staging table, transaction rolled back. ({0})' -f $_.Exception.ToString()
            $Transaction.Rollback()
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
        finally
        {
            $Transaction.Dispose()
        }
    }
    else
    {
        $Logs = $Logs |
            Select-Object -Property LogTime, MachineName, LogSeverity, LogName, LogInfo, LogEntry
    }

    if ($SendTo -contains 'Disk')
    {
        Write-Message -Stream 'Verbose' -Message 'Writing logs to disk.'
        $Logs | Export-Clixml -Path $TargetFilePath
    }

    if ($SendTo -contains 'Console')
    {
        Write-Message -Stream 'Verbose' -Message 'Returning logs to console.'
        Write-Output $Logs
    }
}