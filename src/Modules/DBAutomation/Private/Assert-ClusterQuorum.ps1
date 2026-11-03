<#
    .SYNOPSIS
    This function will validate the nodes and quorum are online and healthy.

    .PARAMETER ComputerName
    The name of the cluster node that will be used to query the cluster.

    .NOTES
    State for Cluster Nodes defined:
    https://docs.microsoft.com/en-us/previous-versions/windows/desktop/cluswmi/mscluster-node
    State for Cluster Quorum defined:
    https://docs.microsoft.com/en-us/previous-versions/windows/desktop/cluswmi/mscluster-resource
#>

function Assert-ClusterQuorum
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName
    )

    $ClusterNodes = @{
        ComputerName = $ComputerName
        Namespace = 'Root\MSCluster'
        ClassName = 'MSCluster_Node'
        Filter = 'state=0'
    }

    # Get the cluster quorum resource name
    $Quorum = @{
        ComputerName = $ComputerName
        Namespace = 'Root\MSCluster'
        ClassName = 'MSCluster_ClusterToQuorumResource'
    }

    $QuorumFilter = (Get-WmiObject @Quorum).PartComponent
    $ClassName, $QuorumFilter = $QuorumFilter.split('.', 2)

    # Validate the quorum is online.
    $Quorum = @{
        ComputerName = $ComputerName
        Namespace = 'Root\MSCluster'
        ClassName = $ClassName
        Filter = "$QuorumFilter and state=2"
    }

    $QuorumVotes = @(Get-WmiObject @Quorum).Count
    $NodeVotes = (@(Get-WmiObject @ClusterNodes).DynamicWeight | Measure-Object -Sum).Sum

    Write-Message -Stream 'Debug' -Message "QuorumVotes: $QuorumVotes, NodeVotes: $NodeVotes"

    if ($QuorumVotes + $NodeVotes -lt 3)
    {
        if ($QuorumVotes -eq 0)
        {
            $Message = 'The quorum does not appear to be online!'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
        else
        {
            $Message = 'The cluster does not have enough votes to maintain health!'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }
}