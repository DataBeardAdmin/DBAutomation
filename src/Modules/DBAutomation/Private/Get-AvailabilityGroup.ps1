function Get-AvailabilityGroup
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter()]
        [String[]]
        $Name,

        [Parameter()]
        [switch]
        $ExcludeDistributed
    )

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ([string]::IsNullOrEmpty($Name))
    {
        $AvailabilityGroups = $Server.AvailabilityGroups
    }
    else
    {
        $AvailabilityGroups = foreach ($AvailabilityGroup in $Name)
        {
            if ($Server.AvailabilityGroups.Contains($AvailabilityGroup))
            {
                $Server.AvailabilityGroups[$AvailabilityGroup]
            }
            else
            {
                $Message = "The specified Availability Group, [$AvailabilityGroup], does not exist."
                Write-Message -Stream 'Log' -Message $Message
                throw $Message
            }
        }
    }

    if ($ExcludeDistributed.IsPresent)
    {
        <#
            Remove Distributed Availability Groups. In testing, IsDistributedAvailabilityGroup is sometimes $null
            (for example, on the secondary) and AvailabilityReplicas (on the secondary) is an empty set (whereas on
            the "forwarder" you will see the Availability Group names), however the local server should always be a
            replica for non-distributed Availability Groups.
        #>
        $AvailabilityGroups = $AvailabilityGroups |
            Where-Object { $_.AvailabilityReplicas.Contains($Server.ConnectionContext.TrueName) }
    }

    return $AvailabilityGroups
}