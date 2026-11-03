function Get-AvailabilityGroupsNotSynchronized
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

        [Parameter()]
        [String]
        $AvailabilityGroupName
    )

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }
    else
    {
        $SqlServer = $Server.ConnectionContext.ServerInstance
    }

    if ($false -eq [String]::IsNullOrEmpty($AvailabilityGroupName))
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName -ExcludeDistributed
    }
    else
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -ExcludeDistributed
    }

    $SynchronousAvailabilityGroupsNotSynced = @()
    foreach ($AvailabilityGroup in $AvailabilityGroups)
    {
        # Availability Groups with 0 databases report unhealthy. We will not be looking at these.
        if ($AvailabilityGroup.AvailabilityDatabases.Count -gt 0)
        {
            $Message = "Validating synchronization status for [$($AvailabilityGroup.Name)] on [$SqlServer]."
            Write-Message -Stream 'Verbose' -Message $Message

            $AvailabilityReplica = Get-AvailabilityReplica -AvailabilityGroup $AvailabilityGroup -Name $Server.ConnectionContext.TrueName
            $AvailabilityReplica.Refresh()
            if ($AvailabilityReplica.AvailabilityMode -eq 'Unknown' -or ($AvailabilityReplica.AvailabilityMode -eq 'SynchronousCommit' -and $AvailabilityReplica.RollupSynchronizationState -ne 'Synchronized'))
            {
                Write-Message -Stream 'Verbose' -Message "Availability Group not in synchronized: [$($AvailabilityGroup.Name)]"
                $SynchronousAvailabilityGroupsNotSynced += $AvailabilityGroup.Name
            }
        }
    }

    return $SynchronousAvailabilityGroupsNotSynced
}