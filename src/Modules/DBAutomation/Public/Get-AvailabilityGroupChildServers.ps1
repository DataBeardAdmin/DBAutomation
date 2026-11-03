Function Get-AvailabilityGroupChildServers
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

        [Parameter(Mandatory = $true)]
        [string]
        $AvailabilityGroupName
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference

    Write-Message -Stream 'Verbose' -Message "Working on AG [$AvailabilityGroupName] for server [$SqlServer]"
    $DistributedAGs = $Server.AvailabilityGroups | Where-Object PrimaryReplicaServerName -EQ $AvailabilityGroupName

    if ($DistributedAGs.Count -gt 0)
    {
        # The following functions are private and won't be available to the job on module load.
        $RequiredFunctions = @(
            'Get-AvailabilityReplicaServerName'
            'Get-AvailabilityGroup'
            'Get-AvailabilityReplica'
            'Split-SqlServer'
            'Format-SqlInstanceName'
        )

        $LogConfiguration = Get-LoggingConfiguration
        $ArgumentList = @()
        foreach ($DistributedAG in $DistributedAGs)
        {
            $ArgumentList += [PSCustomObject]@{
                ScriptName = "GetDAGInfo[$($DistributedAG.Name)]"
                SqlServer = $SqlServer
                DistributedAGName = $DistributedAG.Name
                LogConfiguration = $LogConfiguration
                UserDebugPreference = $DebugPreference
                UserVerbosePreference = $VerbosePreference
            }
        }

        # splat parameters to Invoke-ParallelCommand
        $ParallelCommandParams = @{
            ArgumentList = $ArgumentList
            RequiredFunctions = $RequiredFunctions
            OutputResults = $true
        }

        Invoke-ParallelCommand @ParallelCommandParams -Script {
            param
            (
                $ArgumentObject
            )

            $ScriptName = $ArgumentObject.ScriptName
            $SqlServer = $ArgumentObject.SqlServer
            $DistributedAGName = $ArgumentObject.DistributedAGName

            #Initialize logging.
            $LogConfiguration = $ArgumentObject.LogConfiguration
            Import-Module 'DBAutomation'
            $LogConfiguration | Set-LoggingConfiguration -NoLog

            $DebugPreference = $ArgumentObject.UserDebugPreference
            $VerbosePreference = $ArgumentObject.UserVerbosePreference
            Write-Message -Stream 'Verbose' -Message "Begin [$ScriptName], working on Distributed AG [$DistributedAGName]"

            $Server = Connect-SqlServer -SqlServer $SqlServer

            $DistributedAG = $Server.AvailabilityGroups[$DistributedAGName]

            foreach ($Replica in $DistributedAG.AvailabilityReplicas | Where-Object { $_.Role -EQ 'Secondary' -or $_.Role -eq 'Unknown' })
            {
                Write-Message -Stream 'Debug' -Message "Get-AvailabilityReplicaServerName -SqlServer '$SqlServer' -AvailabilityGroupName '$DistributedAGName' -AvailabilityReplicaName '$($Replica.Name)'"
                $ReplicaName = Get-AvailabilityReplicaServerName -SqlServer $SqlServer -AvailabilityGroupName $DistributedAGName -AvailabilityReplicaName $Replica.Name
                if ($ReplicaName -ne $SqlServer)
                {
                    $ReplicaConnection = Connect-SqlServer -SqlServer $ReplicaName -Verbose:$VerbosePreference
                    if ($ReplicaConnection.ConnectionContext.TrueName -ne $Server.ConnectionContext.TrueName)
                    {
                        $RemoteAvailabilityGroupName = $($ReplicaConnection.AvailabilityGroups[$DistributedAG.Name].AvailabilityReplicas | Where-Object Role -EQ 'Secondary').Name
                        Write-Message -Stream 'Debug' -Message "Get-AvailabilityGroupChildServers -SqlServer '$ReplicaName' -AvailabilityGroupName '$RemoteAvailabilityGroupName'"
                        Get-AvailabilityGroupChildServers -SqlServer $ReplicaName -AvailabilityGroupName $RemoteAvailabilityGroupName
                    }
                }
            }
            Write-Message -Stream 'Verbose' -Message "End [$ScriptName]"
        } | Sort-Object { $_.LocalAGName }
    }
    else
    {
        return @(
            @{
                DAGs = @($($Server.AvailabilityGroups | Where-Object { $_.AvailabilityReplicas.Name -contains $AvailabilityGroupName }).Name) #Cannot use $DistributedAGs.Name as this is only populated for the primary.
                LocalAGName = $AvailabilityGroupName
                HostName = ((Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServerDNSName)
            }
        )
    }
}
