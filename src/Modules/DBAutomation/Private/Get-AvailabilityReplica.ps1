function Get-AvailabilityReplica
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]
        $AvailabilityGroup,

        [Parameter(Mandatory = $true)]
        [String]
        $Name
    )

    if ($AvailabilityGroup.AvailabilityReplicas.Contains($Name))
    {
        $AvailabilityGroup.AvailabilityReplicas[$Name]
    }
    else
    {
        $Message = "The supplied Availability Group does not contain an availability replica named [$Name]."
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
}