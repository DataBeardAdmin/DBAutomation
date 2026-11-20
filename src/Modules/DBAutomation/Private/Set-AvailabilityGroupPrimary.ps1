function Set-AvailabilityGroupPrimary
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
        [string]
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

    $AvailabilityGroup = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName
    $availabilityGroup.Refresh($true)
    if ($AvailabilityGroup.LocalReplicaRole -eq 'Primary')
    {
        Write-Message -Stream 'Warning' -Message "The replica [$SqlServer] specified is already primary for Availability Group [$AvailabilityGroupName]!  No action was taken."
    }
    else
    {
        try
        {
            Wait-AvailabilityGroupSync -Server $Server -AvailabilityGroupName $AvailabilityGroupName

            Write-Message -Stream 'Information' -Message "Failing over AG [$AvailabilityGroupName] to replica [$SqlServer]"
            $AvailabilityGroup.Failover()
        }
        catch
        {
            Write-Message -Stream 'Warning' -Message 'Failover did not succeed. Waiting for Availability Groups to resynchronize.'
            Wait-AvailabilityGroupSync -Server $Server -AvailabilityGroupName $AvailabilityGroupName

            Write-Message -Stream 'Information' -Message "Second attempt to fail over AG [$AvailabilityGroupName] to replica [$SqlServer]"

            try
            {
                $AvailabilityGroup.Failover()
            }
            catch
            {
                Write-Message -Stream 'Warning' -Message "$AvailabilityGroupName`: $_"
            }
        }
    }
}