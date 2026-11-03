function Get-AvailabilityGroupParentServer
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

        [Parameter(Mandatory = $true)]
        [string]
        $AvailabilityGroupName,

        [Parameter()]
        [string]
        $ChildAvailabilityGroupName
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    if ($PSCmdlet.ParameterSetName -in @('ComputerName', 'SqlServer'))
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ([String]::IsNullOrEmpty($ChildAvailabilityGroupName))
    {
        $ChildAvailabilityGroupName = $AvailabilityGroupName
    }

    $DistributedAvailabilityGroups = $Server.AvailabilityGroups | Where-Object { $_.AvailabilityReplicas.Name | Where-Object { $_ -in $Server.AvailabilityGroups.Name } }

    if ($AvailabilityGroupName -in $DistributedAvailabilityGroups.AvailabilityReplicas.Name)
    {
        $AvailabilityGroupList = @($AvailabilityGroupName, $ChildAvailabilityGroupName) | Sort-Object -Unique

        $DistributedAvailabilityGroup = $DistributedAvailabilityGroups | Where-Object { $AvailabilityGroupName -in $_.AvailabilityReplicas.Name -and $_.PrimaryReplicaServerName -ne $AvailabilityGroupName }

        if ($DistributedAvailabilityGroup)
        {
            $AvailabilityReplica = $DistributedAvailabilityGroup.AvailabilityReplicas | Where-Object Name -NotIn $AvailabilityGroupList
            $AvailabilityReplica = Get-AvailabilityReplicaServerName -Server $Server -AvailabilityGroupName $DistributedAvailabilityGroup.Name -AvailabilityReplicaName $AvailabilityReplica.Name
            $AvailabilityGroupListener = (Split-SqlServer -SqlServer $AvailabilityReplica -Verbose:$VerbosePreference).SqlServerName

            $RemoteServer = Connect-SqlServer -SqlServer $AvailabilityReplica -Verbose:$VerbosePreference

            $RemoteAvailabilityGroupName = $($RemoteServer.AvailabilityGroups | Where-Object { $AvailabilityGroupListener -in $_.AvailabilityGroupListeners.Name }).Name

            Write-Message -Stream 'Debug' -Message "Get-AvailabilityGroupParentServer -SqlServer '$AvailabilityReplica' -AvailabilityGroupName '$RemoteAvailabilityGroupName' -ChildAvailabilityGroupName '$AvailabilityGroupName'"
            Get-AvailabilityGroupParentServer -SqlServer $AvailabilityReplica -AvailabilityGroupName $RemoteAvailabilityGroupName -ChildAvailabilityGroupName $AvailabilityGroupName
        }
        else
        {
            Get-AvailabilityReplicaServerName -Server $Server -AvailabilityGroupName $AvailabilityGroupName -AvailabilityReplicaName $Server.ConnectionContext.TrueName
        }
    }
    else
    {
        $AvailabilityGroup = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName
        Get-AvailabilityReplicaServerName -Server $Server -AvailabilityGroupName $AvailabilityGroupName -AvailabilityReplicaName $AvailabilityGroup.PrimaryReplicaServerName
    }
}
