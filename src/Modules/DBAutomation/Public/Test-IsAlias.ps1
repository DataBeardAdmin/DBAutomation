Function Test-IsAlias
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
        # This will tells me what the user plugged in (FQDN or not).
        $SqlServerInfo = Split-SqlServer -SqlServer $Server.ConnectionContext.ServerInstance -Verbose:$VerbosePreference
        # This will tell me what the connection actually resolves to (NOT FQDN).
        $SqlServerTrueInfo = Split-SqlServer -SqlServer $Server.ConnectionContext.TrueName -Verbose:$VerbosePreference
        if ($SqlServerInfo.SqlServer -ne $SqlServerTrueInfo.SqlServer)
        {
            if (Test-IsAGListener -Server $Server)
            {
                return $false
            }
            if (Test-IsClusterVNN -Server $Server)
            {
                return $false
            }
            if (Test-IsClusterName -Server $Server)
            {
                return $false
            }
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

        if ($SqlServerComponent.ComputerName -ne $SqlServerComponent.TargetComputerName)
        {
            if (Test-IsAGListener -SqlServerComponent $SqlServerComponent)
            {
                return $false
            }
            if (Test-IsClusterVNN -SqlServerComponent $SqlServerComponent)
            {
                return $false
            }
            if (Test-IsClusterName -SqlServerComponent $SqlServerComponent)
            {
                return $false
            }
            return $true
        }
    }

    return $false
}