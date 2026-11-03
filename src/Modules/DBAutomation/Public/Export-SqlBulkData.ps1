function Export-SqlBulkData
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(ParameterSetName = 'Connection', Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]
        $SqlConnection,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DatabaseName,

        [Parameter(Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
        [System.Data.DataTable]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DestinationTable,

        [System.Data.Common.DbTransaction]
        $Transaction,

        [Parameter()]
        [System.Int32]
        $BatchSize = 0
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $Server = Connect-SqlServer -ComputerName $ComputerName -InstanceName $InstanceName -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    # Check whether a new or existing connection will be used
    if ($PSCmdlet.ParameterSetName -ne 'Connection')
    {
        $SqlConnection = Get-SqlConnectionObject -Server $Server
    }

    # Initialize our bulk copy object
    if ($Transaction)
    {
        $SqlBulkCopyOptions = New-Object -TypeName System.Data.SqlClient.SqlBulkCopyOptions
        $bulkInsert = New-Object System.Data.SqlClient.SqlBulkCopy $SqlConnection, $SqlBulkCopyOptions, $Transaction
    }
    else
    {
        $bulkInsert = New-Object System.Data.SqlClient.SqlBulkCopy $SqlConnection
    }

    # Set object properties
    $bulkInsert.BatchSize = $BatchSize
    $bulkInsert.DestinationTableName = $DestinationTable

    # Create a column mapping based on the column names
    foreach ($column in $InputObject.Columns)
    {
        Write-Message -Stream 'Verbose' -Message ('Creating mapping for column {0}' -f $column.ColumnName)
        $bulkInsert.ColumnMappings.Add($column.ColumnName, $column.ColumnName) > $null
    }

    try
    {
        # Write the data to the Server
        $bulkInsert.WriteToServer($InputObject)
    }
    catch
    {
        $Message = 'Error writing bulk data to the server. ({0})' -f $_.Exception.ToString()
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    finally
    {
        $InputObject.Clear()
        $bulkInsert.Dispose()

        if ($PSCmdlet.ParameterSetName -eq 'NewConnection')
        {
            $SqlConnection.Close()
            $SqlConnection.Dispose()
        }
    }
}
