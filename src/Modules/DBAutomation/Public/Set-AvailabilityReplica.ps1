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
Function Set-AvailabilityReplica
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
        $TargetSqlServer
    )

    if ($Role -eq 'Primary' -and $false -eq [string]::IsNullOrEmpty($TargetSqlServer))
    {
        $Message = 'When specifying the role [Primary], the TargetSqlServer will be ignored.'
        Write-Message -Stream 'Warning' -Message $Message
    }

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
    $AvailabilityGroups = Get-AvailabilityGroup -Server $Server -Name $AvailabilityGroupName |
        Where-Object -Property LocalReplicaRole -EQ $CurrentRole

    foreach ($AvailabilityGroup in $AvailabilityGroups)
    {
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
        # This test will pass if ANY replica is set to Synchronous. Further filtering is applied below.
        if ($AvailabilityReplicas.AvailabilityMode -eq 'SynchronousCommit')
        {
            if ($Role -eq 'Secondary')
            {
                Write-Message -Stream 'Verbose' -Message "Processing Availability Group: [$($AvailabilityGroup.Name)]"

                if ([String]::IsNullOrEmpty($TargetSqlServer))
                {
                    Write-Message -Stream 'Verbose' -Message "Searching for synchronous replicas with the role [$Role]"
                    $AvailabilityReplicas = $AvailabilityReplicas | Where-Object -FilterScript {
                        $_.AvailabilityMode -eq 'SynchronousCommit' -and
                        $_.Role -eq $Role
                    } | Sort-Object -Property Name

                    if ($AvailabilityReplicas.Count -gt 0)
                    {
                        foreach ($AvailabilityReplica in $AvailabilityReplicas)
                        {
                            $Message = "Replica [$($AvailabilityReplica.Name)] state [$($AvailabilityReplica.ConnectionState)]"
                            Write-Message -Stream 'Debug' -Message $Message
                        }

                        $GetAvailabilityReplicaServerName = @{
                            Server = $Server
                            AvailabilityGroupName = $AvailabilityGroup.Name
                            AvailabilityReplicaName = $AvailabilityReplicas[0].Name
                        }
                        $AvailabilityReplica = Get-AvailabilityReplicaServerName @GetAvailabilityReplicaServerName

                        $SetAvailabilityReplica = @{
                            SqlServer = $AvailabilityReplica
                            Role = 'Primary'
                            AvailabilityGroupName = $AvailabilityGroup.Name
                        }
                        Set-AvailabilityReplica @SetAvailabilityReplica -Verbose:$VerbosePreference
                    }
                }
                else
                {
                    $SetAvailabilityReplica = @{
                        SqlServer = $TargetSqlServer
                        Role = 'Primary'
                        AvailabilityGroupName = $AvailabilityGroup.Name
                    }
                    Set-AvailabilityReplica @SetAvailabilityReplica -Verbose:$VerbosePreference
                }
            }
            else
            {
                $SetAvailabilityGroupPrimary = @{
                    Server = $Server
                    AvailabilityGroupName = $AvailabilityGroup.Name
                }
                Set-AvailabilityGroupPrimary @SetAvailabilityGroupPrimary -Verbose:$VerbosePreference
            }
        }
    }

    # This is useful for recursive calls as all the AGs will be validated in the parent session.
    if ((Get-PSCallStack)[1].Command -ne $MyInvocation.MyCommand)
    {
        Write-Message -Stream 'Verbose' -Message 'Validating Availability Group failover status...'
        $Server.AvailabilityGroups.Refresh($true)
        $AvailabilityGroups = Get-AvailabilityGroup -Server $Server -Name $AvailabilityGroupName |
            Where-Object -FilterScript { $_.LocalReplicaRole -EQ $CurrentRole -and $false -eq $_.IsDistributedAvailabilityGroup }

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