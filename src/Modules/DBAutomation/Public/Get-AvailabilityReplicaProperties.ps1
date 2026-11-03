function Get-AvailabilityReplicaProperties
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

        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [String]
        $AvailabilityGroupName,

        [Parameter(ParameterSetName = 'AvailabilityGroup', Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]
        $AvailabilityGroup,

        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Parameter(ParameterSetName = 'AvailabilityGroup', Mandatory = $true)]
        [String]
        $AvailabilityReplicaName,

        [Parameter(ParameterSetName = 'AvailabilityReplica', Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]
        $AvailabilityReplica,

        [Parameter()]
        [AvailabilityReplicaAllProperties[]]
        $Properties = @([AvailabilityReplicaAllProperties].GetEnumNames()),

        [Parameter()]
        [switch]
        $WritableOnly
    )

    if ($WritableOnly.IsPresent)
    {
        $Properties = $Properties |
            Where-Object { $_ -in [AvailabilityReplicaWritableProperties].GetEnumNames() }
    }

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    if ($PSCmdlet.ParameterSetName -in @('ComputerName', 'SqlServer'))
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -in @('ComputerName', 'SqlServer', 'ServerObject'))
    {
        $AvailabilityGroup = $Server |
            Get-AvailabilityGroup -Name $AvailabilityGroupName -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -in @('ComputerName', 'SqlServer', 'ServerObject', 'AvailabilityGroup'))
    {
        if ($PSCmdlet.ParameterSetName -eq 'AvailabilityGroup')
        {
            $Server = Connect-SqlServer -SqlServer $AvailabilityGroup.Parent.Name -Verbose:$VerbosePreference
            $AvailabilityGroupName = $AvailabilityGroup.Name
        }
        $AvailabilityReplica = $AvailabilityGroup |
            Get-AvailabilityReplica -Name $AvailabilityReplicaName -Verbose:$VerbosePreference
    }
    else
    {
        $Server = Connect-SqlServer -SqlServer $AvailabilityReplica.Parent.Parent.Name -Verbose:$VerbosePreference
        $AvailabilityGroupName = $AvailabilityReplica.Parent.Name
        $AvailabilityReplicaName = $AvailabilityReplica.Name
    }

    # This Should not be needed, but we will refresh just in case.
    $AvailabilityReplica.Refresh()

    $ReturnProperties = @{}
    foreach ($key in $Properties | ForEach-Object { $_.ToString() } | Where-Object { $_ -ne 'AvailabilityReplicaServerName' })
    {
        $Message = "Getting property [$key] for replica [$AvailabilityReplicaName]."
        Write-message -Stream 'Debug' -Message $Message
        $ReturnProperties[$key] = $AvailabilityReplica.$key
    }
    if ($Properties -contains 'AvailabilityReplicaServerName')
    {
        $GetAvailabilityReplicaServerName = @{
            Server = $Server
            AvailabilityGroupName = $AvailabilityGroupName
            AvailabilityReplicaName = $AvailabilityReplica.Name
            Verbose = $VerbosePreference
        }

        $ReturnProperties['AvailabilityReplicaServerName'] = Get-AvailabilityReplicaServerName @GetAvailabilityReplicaServerName
    }

    return $ReturnProperties
}