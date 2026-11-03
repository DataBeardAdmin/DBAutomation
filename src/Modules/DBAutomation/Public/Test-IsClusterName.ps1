Function Test-IsClusterName
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(ParameterSetName = 'SqlServerComponent', Mandatory = $true)]
        [SqlServerComponent]
        $SqlServerComponent
    )

    if ($PSCmdlet.ParameterSetName -eq 'ServerObject')
    {
        $SqlServerInfo = Split-SqlServer -SqlServer $Server.ConnectionContext.ServerInstance -Verbose:$VerbosePreference
        if ($Server.ClusterName -eq $SqlServerInfo.SqlServerName)
        {
            return $true
        }
    }
    else
    {
        if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
        {
            $SqlServerComponent = Find-SqlComponents -ComputerName $ComputerName -Product 'SqlServer' -Verbose:$VerbosePreference
        }

        if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
        {
            $SqlServerDNSName = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServerDNSName
            $SqlServerComponent = Find-SqlComponents -ComputerName $SqlServerDNSName -Product 'SqlServer' -Verbose:$VerbosePreference
        }

        if ($SqlServerComponent.Cluster.BaseCluster -eq $SqlServerComponent.TargetComputerName)
        {
            return $true
        }
    }

    return $false
}