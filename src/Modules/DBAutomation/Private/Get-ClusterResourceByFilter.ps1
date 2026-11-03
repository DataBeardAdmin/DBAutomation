function Get-ClusterResourceByFilter
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [String]
        $Type
    )

    try
    {
        # Attempt to resolve to and FQDN
        $null = Split-SqlServer -SqlServer $ComputerName -Verbose:$VerbosePreference
    }
    catch
    {
        $Message = 'The value for ClusterInstanceName must be the fully-qualified domain name of the clustered SQL instance.'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($Type -match "`'" -or $Type -match '=')
    {
        $Message = 'Please validate the Type passed into Get-ClusterResourceByFilter.'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
        return
    }

    # Use CIM to get the cluster
    $clusterResourceParameters = @{
        ComputerName = $ComputerName
        Namespace = 'root/MSCluster'
        ClassName = 'MSCluster_Resource'
        Filter = "Type = '$Type'"
        Verbose = $false
    }

    Get-CimInstance @clusterResourceParameters
}
