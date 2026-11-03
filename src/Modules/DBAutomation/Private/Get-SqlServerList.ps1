Function Get-SqlServerList
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
        $Server
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    if ($PSCmdlet.ParameterSetName -eq 'ServerObject')
    {
        $SqlServer = $Server.ConnectionContext.ServerInstance
    }

    $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    $SqlServer = $SqlServerInfo.SqlServer
    $SqlServerName = $SqlServerInfo.SqlServerName

    if ($PSCmdlet.ParameterSetName -ne 'ServerObject')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if (Test-IsStandaloneSqlServer -Server $Server)
    {
        Write-Message -Stream 'Verbose' -Message "The listener [$SqlServerName] matches a stand-alone instance."
        return @($SqlServer)
    }
    elseif (Test-IsAGListener -Server $Server)
    {
        $AvailabilityGroup = $Server.AvailabilityGroups.AvailabilityGroupListeners |
            Where-Object Name -EQ $SqlServerName

        $AvailabilityGroupName = $AvailabilityGroup.Parent.Name

        Write-Message -Stream 'Verbose' -Message "The listener has been resolved to the AG [$AvailabilityGroupName]."

        $AvailabilityGroup = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName
        $AvailabilityGroup.AvailabilityReplicas.Refresh($true)

        # The sort will return async and then sync.
        $SecondaryAvailabilityReplicas = $AvailabilityGroup.AvailabilityReplicas |
            Where-Object -Property Role -EQ 'Secondary' |
            Sort-Object -Property 'AvailabilityMode'

        $PrimaryAvailabilityReplica = $AvailabilityGroup.AvailabilityReplicas |
            Where-Object -Property Role -EQ 'Primary'

        $Secondaries = foreach ($Secondary in $SecondaryAvailabilityReplicas)
        {
            $secondaryReplicaConnectionParams = @{
                Server = $Server
                AvailabilityGroupName = $AvailabilityGroupName
                AvailabilityReplicaName = $secondary.Name
            }

            Get-AvailabilityReplicaServerName @secondaryReplicaConnectionParams
        }

        $primaryReplicaConnectionParams = @{
            Server = $Server
            AvailabilityGroupName = $AvailabilityGroupName
            AvailabilityReplicaName = $PrimaryAvailabilityReplica.Name
        }

        $Primary = Get-AvailabilityReplicaServerName @primaryReplicaConnectionParams

        if ($Secondaries.Count -eq 0)
        {
            Write-Message -Stream 'Verbose' -Message "For the AG [$AvailabilityGroupName], the primary replica is [$Primary] and there are no secondaries."
        }
        else
        {
            Write-Message -Stream 'Verbose' -Message "For the AG [$AvailabilityGroupName], the primary replica is [$Primary] and the secondary replica(s) is/are: [$($Secondaries -join  '], [')]"
        }

        return @(@($Secondaries) + @($Primary))
    }
    elseif (Test-IsClusterVNN -Server $Server)
    {
        Write-Message -Stream 'Verbose' -Message "The listener [$SqlServerName] matches a clustered instance."
        return @($SqlServer)
    }
    elseif (Test-IsAlias -Server $Server)
    {
        $Message = "The target SQL Server [$SqlServer] resulted in a connection to [$($Server.ConnectionContext.TrueName)]. Please validate and fix!"
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    else
    {
        $Message = 'Unknown configuration. Only stand-alone, WSFC, and Availability Group configurations are supported!'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
}