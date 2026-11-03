Function Test-IsAGListener
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

        if ($Server.AvailabilityGroups.Count -gt 0 -and
                ($Server.AvailabilityGroups.AvailabilityGroupListeners | Where-Object Name -EQ $SqlServerInfo.SqlServerName))
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

        # Using the FQDN as this is stronger validation than just the base server.
        if ($SqlServerComponent.AvailabilityGroups.Listener -contains $SqlServerComponent.TargetComputerName)
        {
            return $true
        }
    }
    return $false
}