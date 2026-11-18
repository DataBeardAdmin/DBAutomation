function Wait-AvailabilityGroupSync
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

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    $Params = @{
        Server = $Server
    }

    if ($false -eq [String]::IsNullOrEmpty($AvailabilityGroupName))
    {
        $Params += @{
            AvailabilityGroupName = $AvailabilityGroupName
        }
    }

    $StartTime = [DateTime]::Now

    Wait-AvailabilityReplicaConnection @Params -TimeoutSeconds $TimeoutSeconds
    while (Get-AvailabilityGroupsNotSynchronized @Params)
    {
        if ($StartTime.AddSeconds($TimeoutSeconds - 30) -lt [DateTime]::Now)
        {
            Resume-SqlHadrDatabases @Params

            if ((Get-AvailabilityGroupsNotSynchronized @Params) -and
                $StartTime.AddSeconds($TimeoutSeconds) -lt [DateTime]::Now)
            {
                $Message = 'Timeout occurred waiting for Availability Group synchronization.'
                Write-Message -Stream 'Log' -Message $Message
                throw $Message
            }
            else
            {
                Write-Message -Stream 'Verbose' -Message 'Availability Groups not synchronized. Waiting for synchronization...'
                Start-Sleep -Seconds 30
            }
        }
        else
        {
            Write-Message -Stream 'Verbose' -Message 'Availability Groups not synchronized. Waiting for synchronization...'
            Start-Sleep -Seconds 30
        }
    }
}