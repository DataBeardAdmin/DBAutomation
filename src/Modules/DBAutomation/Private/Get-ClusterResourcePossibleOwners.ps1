function Get-ClusterResourcePossibleOwners
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]
        $clusterResource
    )

    # Initialize an empty array to store the node list
    $serverList = @()

    # Get the current owner
    $currentOwner = $clusterResource.OwnerNode
    Write-Message -Stream 'Verbose' -Message "Current owner is [$currentOwner]"

    Write-Message -Stream 'Debug' -Message 'Determining possible owners...'
    # Using the resource, get the possible owners
    $possibleOwners = $clusterResource | 
        Get-CimAssociatedInstance -Association 'MSCluster_ResourceToPossibleOwner' -KeyOnly -Verbose:$false

    # Build a collection of all owner nodes, tagging the current owner
    foreach ($node in $possibleOwners)
    {
        Write-Message -Stream 'Debug' -Message "Found node [$($node.Name)]"
        $serverList += [PSCustomObject]@{
            ServerName = "$($node.Name).$($clusterResource.PrivateProperties.DnsSuffix)"
            IsOwner = [int]($node.Name -eq $currentOwner)
        }
    }

    # Sort the list so the current owner is last and return
    return @(
        $serverList | 
            Sort-Object -Property IsOwner |
            Select-Object -ExpandProperty ServerName
    )
}
