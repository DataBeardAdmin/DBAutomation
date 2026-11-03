function Get-ClusterNodesByNetworkName
{
    [CmdletBinding()]
    param
    (
        [Alias('VirtualNetworkName')]
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName
    )

    try
    {
        # Attempt to resolve to and FQDN
        $ClusterInfo = Split-SqlServer -SqlServer $ComputerName -Verbose:$VerbosePreference
        $clusterComputerName = $ClusterInfo.SqlServerName
    }
    catch
    {
        $Message = 'The value for VirtualNetworkName failed to resolve in DNS. Please verify the spelling and ensure a fully-qualified clustered server was provided.'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    Write-Message -Stream 'Verbose' -Message "Getting cluster resource for Network Name [$ComputerName]"
    # Get the cluster resource for this SQL Server instance
    $clusterResource = Get-ClusterResourceByFilter -ComputerName $ComputerName -Type 'Network Name' | 
        Where-Object -FilterScript { $_.PrivateProperties.DnsName -eq $clusterComputerName }

    # If not clustered, throw an exception
    if ($null -eq $clusterResource)
    {
        $Message = "Clustered instance [$clusterComputerName] could not be found."
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
        return
    }

    Get-ClusterResourcePossibleOwners -clusterResource $clusterResource -Verbose:$VerbosePreference
}
