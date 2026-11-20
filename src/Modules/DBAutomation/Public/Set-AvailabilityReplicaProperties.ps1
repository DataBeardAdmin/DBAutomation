function Set-AvailabilityReplicaProperties
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

        [Parameter(Mandatory = $true)]
        [hashtable]
        $Properties
    )

    $SupportedProperties = [AvailabilityReplicaWritableProperties].GetEnumNames()
    foreach ($key in $Properties.Keys)
    {
        if ($key -notin $SupportedProperties)
        {
            $Message = "Unsupported AvailabilityReplica property: $key"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
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
        $AvailabilityReplica = $AvailabilityGroup |
            Get-AvailabilityReplica -Name $AvailabilityReplicaName -Verbose:$VerbosePreference
        $SqlServer = (Split-SqlServer -SqlServer $AvailabilityGroup.Parent.Name -Verbose:$VerbosePreference).SqlServer
    }
    else
    {
        $AvailabilityGroup = $AvailabilityReplica.Parent
        $SqlServer = (Split-SqlServer -SqlServer $AvailabilityGroup.Parent.Name -Verbose:$VerbosePreference).SqlServer
        $AvailabilityReplicaName = $AvailabilityReplica.Name
    }

    # We need to refresh to ensure we're looking at the current state of the replica before making changes.
    $AvailabilityGroup.Refresh()

    if ($AvailabilityGroup.LocalReplicaRole -ne 'Primary')
    {
        $Message = @"
The server provided [$SqlServer] is not the primary replica.
Replica modifications must be made on the primary replica [$($AvailabilityGroup.PrimaryReplicaServerName)].
No changes were made.
"@
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    else
    {
        $ExistingProperties = $AvailabilityReplica |
            Get-AvailabilityReplicaProperties -Properties $Properties.Keys -Verbose:$VerbosePreference

        $PropertiesChanged = $false
        foreach ($key in $Properties.Keys)
        {
            if ($ExistingProperties[$key] -ne $Properties[$key])
            {
                $Message = "Changing [$key] from [$($ExistingProperties[$key])] to [$($Properties[$key])]."
                Write-message -Stream 'Verbose' -Message $Message
                $AvailabilityReplica.$key = $Properties[$key]
                $PropertiesChanged = $true
            }
        }

        if ($true -eq $PropertiesChanged)
        {
            $Message = "Altering replica [$AvailabilityReplicaName] properties."
            Write-Message -Stream 'Information' -Message $Message
            $AvailabilityReplica.Alter()
        }
        else
        {
            $Message = "No changes detected for replica [$AvailabilityReplicaName]."
            Write-Message -Stream 'Warning' -Message $Message
        }
    }
}