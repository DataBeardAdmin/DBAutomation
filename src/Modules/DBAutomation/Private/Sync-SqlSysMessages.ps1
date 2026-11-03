function Sync-SqlSysMessages
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $TargetServer,

        [Parameter(Mandatory = $true)]
        [String]
        $TargetSqlDatabase
    )

    $Messages = Import-SqlSysMessages -Server $Server

    $SqlConnection = Get-SqlConnectionObject -Server $TargetServer

    try
    {
        $Transaction = $SqlConnection.BeginTransaction()

        $truncateParams = @{
            Connection = $sqlConnection
            DatabaseName = $TargetSqlDatabase
            QueryString = 'EXEC [dbo].[Truncate_Staging_Table] @TableName'
            QueryParameters = @{ TableName = '[dbo].[LogImport_sysmessages_Staging]' }
            Transaction = $Transaction
        }

        Write-Message -Stream 'Debug' -Message "Truncating table [LogImport_sysmessages_Staging] in database [$TargetSqlDatabase] on server [$TargetSqlServer]."

        # Execute the query
        Invoke-SqlQuery @truncateParams -Verbose:$VerbosePreference

        Export-SqlBulkData -SqlConnection $SqlConnection -DatabaseName $TargetSqlDatabase -InputObject $Messages -DestinationTable '[dbo].[LogImport_sysmessages_Staging]' -Transaction $Transaction -Verbose:$false

        $mergeParams = @{
            Connection = $sqlConnection
            DatabaseName = $TargetSqlDatabase
            QueryString = 'EXEC [dbo].[Merge_LogImport_sysmessages]'
            Transaction = $Transaction
        }

        Write-Message -Stream 'Debug' -Message "Merging table [LogImport_sysmessages_Staging] to [LogImport_sysmessages] in database [$TargetSqlDatabase] on server [$TargetSqlServer]."

        # Execute the query
        Invoke-SqlQuery @mergeParams -Verbose:$VerbosePreference

        $truncateParams = @{
            Connection = $sqlConnection
            DatabaseName = $TargetSqlDatabase
            QueryString = 'EXEC [dbo].[Truncate_Staging_Table] @TableName'
            QueryParameters = @{ TableName = '[dbo].[LogImport_sysmessages_Staging]' }
            Transaction = $Transaction
        }

        Write-Message -Stream 'Debug' -Message "Truncating table [LogImport_sysmessages_Staging] in database [$TargetSqlDatabase]."

        # Execute the query
        Invoke-SqlQuery @truncateParams -Verbose:$VerbosePreference

        $Transaction.Commit()
    }
    catch
    {
        $Message = 'Error loading [LogImport_sysmessages] table. ({0})' -f $_.Exception.ToString()
        $Transaction.Rollback()
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    finally
    {
        $Transaction.Dispose()
    }
}
