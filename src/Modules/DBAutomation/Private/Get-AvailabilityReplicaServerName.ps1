$script:AvailabilityReplicaServerNameCache = @{}

Function Get-AvailabilityReplicaServerName
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(Mandatory = $true)]
        [String]
        $AvailabilityGroupName,

        [Parameter(Mandatory = $true)]
        [String]
        $AvailabilityReplicaName
    )

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }
    else
    {
        $SqlServer = $Server.ConnectionContext.ServerInstance
    }

    if ($script:AvailabilityReplicaServerNameCache.Keys -contains $AvailabilityReplicaName)
    {
        $AvailabilityReplica = $script:AvailabilityReplicaServerNameCache[$AvailabilityReplicaName]
        $Message = "Pulled replica [$AvailabilityReplicaName] target [$AvailabilityReplica] from cache."
        Write-Message -Stream 'Debug' -Message $Message
    }
    else
    {
        $Message = "Determining replica [$AvailabilityReplicaName] connection."
        Write-Message -Stream 'Debug' -Message $Message

        $AvailabilityReplica = $Server |
            Get-AvailabilityGroup -Name $AvailabilityGroupName |
            Get-AvailabilityReplica -Name $AvailabilityReplicaName

        # Using Split-SqlServer may generate an error if the replica is a remote domain, so we're doing this manual.
        $SqlServerName, $InstanceName = $AvailabilityReplicaName.Split('\')
        if ([string]::IsNullOrEmpty($InstanceName))
        {
            $InstanceName = 'MSSQLSERVER'
        }

        $URI = $AvailabilityReplica.EndpointUrl -as [uri]
        $SqlServerDnsName = (Split-SqlServer -SqlServer $URI.DnsSafeHost -Verbose:$VerbosePreference).SqlServerDNSName

        $Message = "Validating if replica [$AvailabilityReplicaName] is accessible using [$SqlServerDNSName]."
        Write-Message -Stream 'Debug' -Message $Message

        $TestTcpPort = @{
            ComputerName = $SqlServerDNSName
            Port = 1433
        }
        $UrlAccessible = Test-TcpPort @TestTcpPort

        if ($false -eq $UrlAccessible)
        {
            $Message = "Attempting to discover real FQDN for replica [$AvailabilityReplicaName]."
            Write-Message -Stream 'Debug' -Message $Message
            $Domain = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).Domain
            $SqlServerDnsName = "$SqlServerName.$Domain"
        }

        try
        {
            $AvailabilityReplica = Format-SqlInstanceName -ComputerName $SqlServerDnsName -InstanceName $InstanceName
            $AvailabilityReplicaInfo = Split-SqlServer -SqlServer $AvailabilityReplica -Verbose:$VerbosePreference
            $AvailabilityReplica = $AvailabilityReplicaInfo.SqlServer
        }
        catch
        {
            $Message = "Failed to determine FQDN for replica [$AvailabilityReplicaName] on server [$SqlServer]"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        $script:AvailabilityReplicaServerNameCache += @{ "$AvailabilityReplicaName" = $AvailabilityReplica }
        $Message = "Added replica [$AvailabilityReplicaName] target [$AvailabilityReplica] to cache."
        Write-Message -Stream 'Debug' -Message $Message
    }

    return $AvailabilityReplica
}
