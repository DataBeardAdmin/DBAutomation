function Wait-AvailabilityReplicaConnection
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
        $AvailabilityGroupName,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [Int]
        $TimeoutSeconds = 600
    )

    $StartTime = [DateTime]::Now

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ([String]::IsNullOrEmpty($AvailabilityGroupName))
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -ExcludeDistributed
    }
    else
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName -ExcludeDistributed
    }

    do
    {
        $Connected = $true

        foreach ($AvailabilityGroup in $AvailabilityGroups)
        {
            $AvailabilityReplica = Get-AvailabilityReplica -AvailabilityGroup $AvailabilityGroup -Name $Server.ConnectionContext.TrueName
            $AvailabilityReplica.Refresh()
            if ($AvailabilityReplica.ConnectionState -ne 'Connected')
            {
                $Connected = $false
            }
        }
        if ($StartTime.AddSeconds($TimeoutSeconds) -lt [DateTime]::Now)
        {
            $Message = 'Timeout occurred waiting for all replicas to reconnect.'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        if ($false -eq $Connected)
        {
            Write-Message -Stream 'Verbose' -Message 'Waiting for all replicas to reconnect.'
            Start-Sleep -Seconds 5
        }
    }
    while ($Connected -eq $false)
}