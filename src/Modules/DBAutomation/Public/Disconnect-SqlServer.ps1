<#
    .SYNOPSIS
    Closes open sessions to the specified SQL Server.

    .PARAMETER ComputerName
    The computer running an instance of SQL that that you are connecting to.

    .PARAMETER InstanceName
    The name of the instance you are connecting to.

    .PARAMETER SqlServer
    String containing the name of the SQL Server to disconnect. (Default = $env:COMPUTERNAME)

    .PARAMETER ClearConnectionPool
    When specified, clears the .NET connection pool for existing sessions to the server.
#>
function Disconnect-SqlServer
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter()]
        [Switch]
        $ClearConnectionPool
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    Write-Message -Stream 'Debug' -Message 'Begin Disconnect-SqlServer'
    if ($script:sessionCache)
    {
        Write-Message -Stream 'Debug' -Message 'Session cache found.'
        if ($script:sessionCache.ContainsKey($SqlServer))
        {
            Write-Message -Stream 'Debug' -Message "Found server '$SqlServer' in cache."
            $cachedSession = $script:sessionCache[$SqlServer]

            if ($ClearConnectionPool)
            {
                Remove-ConnectionPoolEntry -SqlConnection $cachedSession.ConnectionContext.SqlConnectionObject
            }

            Write-Message -Stream 'Verbose' -Message "Closing connection to '$SqlServer'."
            $cachedSession.ConnectionContext.SqlConnectionObject.Close()

            Write-Message -Stream 'Debug' -Message 'Removing entry from cache.'
            $script:sessionCache.Remove($SqlServer)
        }
    }
    Write-Message -Stream 'Debug' -Message 'End Disconnect-SqlServer'
}