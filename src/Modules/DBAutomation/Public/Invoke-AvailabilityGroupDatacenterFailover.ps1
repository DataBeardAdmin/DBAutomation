function Invoke-AvailabilityGroupDataCenterFailover
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

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter()]
        [string]
        $TargetSqlServer
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    if ($PSCmdlet.ParameterSetName -in @('ComputerName', 'SqlServer'))
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -eq 'ServerObject')
    {
        $SqlServer = $Server.ConnectionContext.ServerInstance
    }

    if ($false -eq [string]::IsNullOrEmpty($TargetSqlServer))
    {
        $TargetServer = Connect-SqlServer -SqlServer $TargetSqlServer -Verbose:$VerbosePreference
        if ($TargetServer.ConnectionContext.TrueName -eq $Server.ConnectionContext.TrueName)
        {
            $Message = @"
The target server [$TargetSqlServer] is the same as the current server provided [$SqlServer].
Please provide a different [SqlServer] or [TargetSqlServer] for failover.
"@
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }

    $AvailabilityGroups = $Server | Get-AvailabilityGroup -ExcludeDistributed -Verbose:$VerbosePreference

    $GetAvailabilityReplicaProperties = @{
        Properties = @(
            'Name',
            'AvailabilityMode',
            'FailoverMode',
            'Role',
            'AvailabilityReplicaServerName'
        )
        Verbose = $VerbosePreference
    }

    foreach ($AvailabilityGroup in $AvailabilityGroups)
    {
        Write-Message -Stream 'Verbose' -Message "Processing Availability Group: [$($AvailabilityGroup.Name)]"
        if ($AvailabilityGroup.PrimaryReplicaServerName -ne $Server.ConnectionContext.TrueName)
        {
            $Message = @"
The server [$SqlServer] is not the primary replica for Availability Group [$($AvailabilityGroup.Name)].
Please connect to the primary replica server [$($AvailabilityGroup.PrimaryReplicaServerName)] instead.
No failover will be performed as changes cannot be made from this server!
"@
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
        $Listener = $AvailabilityGroup.AvailabilityGroupListeners[0].Name
        $SqlServerName = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServerName
        if ($Listener -eq $SqlServerName)
        {
            $Message = 'Please connect to one of the member servers instead of the listener of the Availability Group.'
            Write-Message -Stream 'Log' -Message $Message
            Write-Message -Stream 'Debug' -Message "Availability Group Listener: [$Listener]; Connection: [$SqlServer]"
            throw $Message
        }

        # We need to cache the current state as we'll be changing the state of the replicas as we go
        $ReplicaProperties = @()
        $AsynchronousReplicasFound = $false
        foreach ($AvailabilityReplica in $AvailabilityGroup.availabilityReplicas | Sort-Object -Property Name)
        {
            $Results = $AvailabilityReplica |
                Get-AvailabilityReplicaProperties @GetAvailabilityReplicaProperties

            $ReplicaProperties += $Results

            if ($results.Role -eq 'Primary')
            {
                $Message = "Current primary replica: [$($results.Name)]."
                Write-Message -Stream 'Verbose' -Message $Message
            }
            if ($Results.AvailabilityMode -eq 'AsynchronousCommit')
            {
                $AsynchronousReplicasFound = $true
                if ($true -eq [string]::IsNullOrEmpty($TargetSqlServer) -and $Results.Role -ne 'Primary')
                {
                    $TargetSqlServer = $Results.AvailabilityReplicaServerName
                    $Message = "Target server for failover not provided.  Setting target to [$TargetSqlServer] based on asynchronous replica [$($Results.Name)]."
                    Write-Message -Stream 'Information' -Message $Message
                }
                $Message = "Changing replica [$($Results.Name)] to Synchronous commit, Automatic failover."
                Write-Message -Stream 'Information' -Message $Message

                $SetAvailabilityReplicaProperties = @{
                    AvailabilityGroup = $AvailabilityGroup
                    AvailabilityReplicaName = $Results.Name
                    Properties = @{
                        AvailabilityMode = 'SynchronousCommit'
                        FailoverMode = 'Automatic'
                    }
                    Verbose = $VerbosePreference
                }

                Set-AvailabilityReplicaProperties @SetAvailabilityReplicaProperties
            }
        }

        if ($true -eq $AsynchronousReplicasFound)
        {
            $WaitAvailabilityGroupSync = @{
                Server = $Server
                AvailabilityGroupName = $AvailabilityGroup.Name
                TimeoutSeconds = 1800
                Verbose = $VerbosePreference
            }

            Wait-AvailabilityGroupSync @WaitAvailabilityGroupSync

            $SetAvailabilityReplicaPrimary = @{
                SqlServer = $TargetSqlServer
                Role = 'Primary'
                AvailabilityGroupName = $AvailabilityGroup.Name
                Verbose = $VerbosePreference
            }
            Set-AvailabilityReplica @SetAvailabilityReplicaPrimary

            foreach ($Replica in $ReplicaProperties | Where-Object { $_.AvailabilityMode -eq 'SynchronousCommit' })
            {
                $Message = "Changing replica [$($Replica.Name)] to Asynchronous commit, Manual failover."
                Write-Message -Stream 'Information' -Message $Message

                $SetAvailabilityReplicaProperties = @{
                    SqlServer = $TargetSqlServer
                    AvailabilityGroupName = $AvailabilityGroup.Name
                    AvailabilityReplicaName = $Replica.Name
                    Properties = @{
                        AvailabilityMode = 'AsynchronousCommit'
                        FailoverMode = 'Manual'
                    }
                    Verbose = $VerbosePreference
                }

                Set-AvailabilityReplicaProperties @SetAvailabilityReplicaProperties
            }
        }
        else
        {
            Write-Message -Stream 'Warning' -Message "No asynchronous replicas found for Availability Group [$($AvailabilityGroup.Name)].  No failover will be performed."
        }
    }
}