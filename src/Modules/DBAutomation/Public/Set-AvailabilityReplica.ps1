<#
    .SYNOPSIS
    Evaluates the Availability Group states and performs failovers as requested.

    .DESCRIPTION
    This function stands in as a push/pull mechanism for Availability Groups.
    From a pure technical perspective, Availability Groups are always "pulled" to a specified server in a failover.
    This function enables you to connect to a server currently in the primary role of an availability group and
    "push" the Availability Groups to either a specified secondary or the first available synchronous secondary.

    .PARAMETER ComputerName
    The computer running an instance of SQL that that you are connecting to.

    .PARAMETER InstanceName
    The name of the instance you are connecting to.

    .PARAMETER SqlServer
    The server that that you are connecting to.

    .PARAMETER Server
    In place of SqlServer, this is an SMO server object that can be passed in.

    .PARAMETER Role
    This parameter specifies whether the Availability Group(s) will be "pulled" *to* the specified SqlServer or
    "pushed" *from* the specified SqlServer.
    Possible values: Secondary or Primary.
    Default value: Secondary.

    .PARAMETER AvailabilityGroupName
    This parameter specifies the Availability Group(s) that should be moved.

    .PARAMETER TargetSqlServer
    This parameter is only used when Role is specified as 'Secondary'. This designates which secondary replica to
    move the Availability Group(s) to.

    .EXAMPLE
    #This will ensure that SqlServer01 is the secondary for *all* synchronous Availability Groups.
    Set-AvailabilityReplica -SqlServer 'SqlServer01' -Verbose -InformationAction 'Continue'

    .EXAMPLE
    #This will ensure that SqlServer01 is the primary for *all* synchronous Availability Groups.
    Set-AvailabilityReplica -SqlServer 'SqlServer01' -Role 'Primary' -Verbose -InformationAction 'Continue'

    .EXAMPLE
    #This will ensure that SqlServer01 is the secondary by moving all synchronous Availability Groups to SqlServer02.
    Set-AvailabilityReplica -SqlServer 'SqlServer01' -TargetSqlServer 'SqlServer02' -Verbose -InformationAction 'Continue'

#>
function Set-AvailabilityReplica
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

        [Parameter()]
        [ValidateSet('Secondary', 'Primary')]
        [string]
        $Role = 'Secondary',

        [Parameter()]
        [string[]]
        $AvailabilityGroupName,

        [Parameter()]
        [string]
        $TargetSqlServer,

        [Parameter()]
        [Switch]
        $AsyncFailover
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    if ($PSCmdlet.ParameterSetName -ne 'ServerObject')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }
    else
    {
        $SqlServer = $Server.ConnectionContext.ServerInstance
    }

    if ($false -eq [string]::IsNullOrEmpty($TargetSqlServer))
    {
        if ($Role -eq 'Primary')
        {
            $Message = 'When specifying the role [Primary], the TargetSqlServer will be ignored.'
            Write-Message -Stream 'Warning' -Message $Message
        }
        #         else
        #         {
        #             $TargetServer = Connect-SqlServer -SqlServer $TargetSqlServer -Verbose:$VerbosePreference
        #             if ($TargetServer.ConnectionContext.TrueName -eq $Server.ConnectionContext.TrueName)
        #             {
        #                 $Message = @"
        # The target server [$TargetSqlServer] is the same as the current server provided [$SqlServer].
        # Please provide a different [SqlServer] or [TargetSqlServer] for failover.
        # "@
        #                 Write-Message -Stream 'Log' -Message $Message
        #                 throw $Message
        #             }
        #         }
    }
    elseif ($AsyncFailover.IsPresent -and $Role -eq 'Secondary')
    {
        $Message = 'When specifying [AsyncFailover], the TargetSqlServer must be provided.'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($Role -eq 'Primary')
    {
        $TargetSqlServer = $SqlServer
    }

    $CurrentRole = switch ($Role)
    {
        'Secondary' { 'Primary' }
        'Primary' { 'Secondary' }
    }

    # Ensure this computer is not the (target role) replica for any Availability Groups
    # This reduces unnecessary output in recursive calls.
    if ((Get-PSCallStack)[1].Command -ne $MyInvocation.MyCommand)
    {
        $Message = "Gathering a list of Availability Groups with the role [$CurrentRole] on [$SqlServer]"
        Write-Message -Stream 'Verbose' -Message $Message
    }
    $Server.AvailabilityGroups.Refresh($true)
    $AvailabilityGroups = $Server |
        Get-AvailabilityGroup -Name $AvailabilityGroupName -ExcludeDistributed -Verbose:$VerbosePreference |
        Where-Object -Property LocalReplicaRole -EQ $CurrentRole

    if ($AsyncFailover.IsPresent -and $AvailabilityGroups.Count -eq 0)
    {
        $Message = @"
The server [$SqlServer] is already the [$Role] for all Availability Groups but [AsyncFailover] was specified.
No failover or replica changes will be performed.
"@
        Write-Message -Stream 'Warning' -Message $Message
    }

    foreach ($AvailabilityGroup in $AvailabilityGroups)
    {
        Write-Message -Stream 'Verbose' -Message "Processing Availability Group: [$($AvailabilityGroup.Name)]"
        $Listener = $AvailabilityGroup.AvailabilityGroupListeners[0].Name
        $SqlServerName = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServerName
        if ($Listener -eq $SqlServerName)
        {
            $Message = 'Please connect to one of the member servers instead of the listener of the Availability Group.'
            Write-Message -Stream 'Log' -Message $Message
            Write-Message -Stream 'Debug' -Message "Availability Group Listener: [$Listener]; Connection: [$SqlServer]"
            throw $Message
        }

        $AvailabilityGroup.AvailabilityReplicas.Refresh($true)
        $AvailabilityReplicas = $AvailabilityGroup.AvailabilityReplicas
        $FailoverPerformed = $false

        if ($false -eq [string]::IsNullOrEmpty($TargetSqlServer))
        {
            $TargetSqlServerHostName = (Split-SqlServer -SqlServer $TargetSqlServer -Verbose:$VerbosePreference).SqlServerName
            $TargetAvailabilityReplica = Get-AvailabilityReplica -AvailabilityGroup $AvailabilityGroup -Name $TargetSqlServerHostName
        }

        if ($AsyncFailover.IsPresent)
        {
            # We need to cache the current state as we'll be changing the state of the replicas as we go
            $ReplicaProperties = @()
            $AsynchronousReplicasFound = $false
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

            if ($TargetAvailabilityReplica.AvailabilityMode -eq 'SynchronousCommit')
            {
                $Message = @"
The target server [$TargetSqlServer] is [SynchronousCommit] for [$($AvailabilityGroup.Name)] but [AsyncFailover] was specified.
No failover or replica changes will be performed for this Availability Group.
"@
                Write-Message -Stream 'Warning' -Message $Message
                continue
            }
        }
        else
        {
            if ($TargetAvailabilityReplica.AvailabilityMode -eq 'AsynchronousCommit')
            {
                $Message = @"
The target server [$TargetSqlServer] is [AsynchronousCommit] for [$($AvailabilityGroup.Name)].
No failover or replica changes will be performed for this Availability Group unless [AsyncFailover] is specified.
"@
                Write-Message -Stream 'Warning' -Message $Message
                continue
            }
            elseif ($Role -eq 'Primary' -or $false -eq [string]::IsNullOrEmpty($TargetSqlServer))
            {
                $SetAvailabilityGroupPrimary = @{
                    SqlServer = $TargetSqlServer
                    AvailabilityGroupName = $AvailabilityGroup.Name
                }
                Set-AvailabilityGroupPrimary @SetAvailabilityGroupPrimary -Verbose:$VerbosePreference
                $FailoverPerformed = $true
            }
        }
        foreach ($AvailabilityReplica in $AvailabilityReplicas | Sort-Object -Property Name)
        {
            if ($false -eq $FailoverPerformed)
            {
                $Message = 'Replica [{0}] state [{1}] role [{2}] mode [{3}]' `
                    -f $AvailabilityReplica.Name, `
                    $AvailabilityReplica.ConnectionState, `
                    $AvailabilityReplica.Role, `
                    $AvailabilityReplica.AvailabilityMode
                Write-Message -Stream 'Debug' -Message $Message
            }
            if ($AsyncFailover.IsPresent)
            {
                $Results = $AvailabilityReplica |
                    Get-AvailabilityReplicaProperties @GetAvailabilityReplicaProperties

                $ReplicaProperties += $Results

                if ($Results.AvailabilityMode -eq 'AsynchronousCommit')
                {
                    $AsynchronousReplicasFound = $true
                    # if ($true -eq [string]::IsNullOrEmpty($TargetSqlServer) -and $Results.Role -ne 'Primary')
                    # {
                    #     $TargetSqlServer = $Results.AvailabilityReplicaServerName
                    #     $Message = "Target server for failover not provided.  Setting target to [$TargetSqlServer] based on asynchronous replica [$($Results.Name)]."
                    #     Write-Message -Stream 'Information' -Message $Message
                    # }
                    $Message = "Changing replica [$($Results.Name)] to Synchronous commit, Automatic failover."
                    Write-Message -Stream 'Information' -Message $Message

                    $GetAvailabilityReplicaServerName = @{
                        Server = $Server
                        AvailabilityGroupName = $AvailabilityGroup.Name
                        AvailabilityReplicaName = $AvailabilityGroup.PrimaryReplicaServerName
                    }
                    $PrimaryReplica = Get-AvailabilityReplicaServerName @GetAvailabilityReplicaServerName

                    $SetAvailabilityReplicaProperties = @{
                        SqlServer = $PrimaryReplica
                        AvailabilityGroupName = $AvailabilityGroup.Name
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
            else
            {
                if ($false -eq $FailoverPerformed -and
                    $AvailabilityReplica.Role -eq 'Secondary' -and
                    $AvailabilityReplica.AvailabilityMode -eq 'SynchronousCommit' -and
                    $Role -eq 'Secondary' -and
                    [String]::IsNullOrEmpty($TargetSqlServer))
                {
                    $TargetSqlServer = $AvailabilityReplica.Name
                    $GetAvailabilityReplicaServerName = @{
                        Server = $Server
                        AvailabilityGroupName = $AvailabilityGroup.Name
                        AvailabilityReplicaName = $TargetSqlServer
                    }
                    $AvailabilityReplica = Get-AvailabilityReplicaServerName @GetAvailabilityReplicaServerName

                    # $SetAvailabilityGroupPrimary = @{
                    #     SqlServer = $TargetSqlServer
                    #     AvailabilityGroupName = $AvailabilityGroup.Name
                    # }
                    # Set-AvailabilityGroupPrimary @SetAvailabilityGroupPrimary -Verbose:$VerbosePreference
                    $SetAvailabilityReplica = @{
                        SqlServer = $TargetSqlServer
                        Role = 'Primary'
                        AvailabilityGroupName = $AvailabilityGroup.Name
                    }
                    Set-AvailabilityReplica @SetAvailabilityReplica -Verbose:$VerbosePreference
                    $FailoverPerformed = $true
                }
            }
        }

        if ($AsyncFailover.IsPresent)
        {
            if ($true -eq $AsynchronousReplicasFound)
            {
                $WaitAvailabilityGroupSync = @{
                    SqlServer = $TargetSqlServer
                    AvailabilityGroupName = $AvailabilityGroup.Name
                    TimeoutSeconds = 1800
                    Verbose = $VerbosePreference
                }

                Wait-AvailabilityGroupSync @WaitAvailabilityGroupSync

                $SetAvailabilityReplica = @{
                    SqlServer = $TargetSqlServer
                    Role = 'Primary'
                    AvailabilityGroupName = $AvailabilityGroup.Name
                    Verbose = $VerbosePreference
                }
                Set-AvailabilityReplica @SetAvailabilityReplica

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
                $Message = "No asynchronous replicas found for Availability Group [$($AvailabilityGroup.Name)].  No failover will be performed."
                Write-Message -Stream 'Warning' -Message $Message
            }
        }
    }

    if ($false -eq $AsyncFailover.IsPresent)
    {
        # This is useful for recursive calls as all the AGs will be validated in the parent session.
        if ((Get-PSCallStack)[1].Command -ne $MyInvocation.MyCommand)
        {
            Write-Message -Stream 'Verbose' -Message 'Validating Availability Group failover status...'
            $Server.AvailabilityGroups.Refresh($true)
            $AvailabilityGroups = Get-AvailabilityGroup -Server $Server -Name $AvailabilityGroupName |
                Where-Object -FilterScript { $_.LocalReplicaRole -eq $CurrentRole -and $false -eq $_.IsDistributedAvailabilityGroup }

            if ($AvailabilityGroups.count -gt 0)
            {
                $AGsNotSynced = $false
                foreach ($AvailabilityGroup in $AvailabilityGroups)
                {
                    Write-Message -Stream 'Verbose' -Message "Processing Availability Group: [$($AvailabilityGroup.Name)]"

                    if (Get-AvailabilityGroupsNotSynchronized -Server $Server -AvailabilityGroupName $AvailabilityGroup.Name)
                    {
                        #The availability group is set to synchronous but has at least one database that is not synchronized
                        $Message = "Availability Group [$($AvailabilityGroup.Name)] has not failed over because the databases are not all in sync."
                        Write-Message -Stream 'Error' -Message $Message
                        $AGsNotSynced = $true
                    }
                    elseif ($AvailabilityGroup.AvailabilityReplicas.AvailabilityMode -eq 'AsynchronousCommit')
                    {
                        #At least one replica is set to asynchronous and requires manual intervention.
                        $Message = "Availability Group [$($AvailabilityGroup.Name)] is [AsynchronousCommit] and was not moved."
                        Write-Message -Stream 'Warning' -Message $Message
                    }
                    else
                    {
                        Write-Message -Stream 'Warning' -Message "Availability Group [$($AvailabilityGroup.Name)] has not failed over but the databases are all in sync. This *Should* fail over automatically when the reboot takes place."
                    }
                }
                if ($AGsNotSynced)
                {
                    throw "There are still Availability Groups hosted on the target server which couldn't be moved automatically."
                }
            }
            else
            {
                Write-Message -Stream 'Verbose' -Message 'All selected groups have been validated.'
            }
        }
    }
}