<#
    .SYNOPSIS
    This function will resume a cluster node that was paused.

    .PARAMETER ComputerName
    The name of the cluster node that will be paused.

    .PARAMETER FailbackType
    The following options are allowed:
    NoFailback              Indicates that the failback process is not to be performed on the specified groups.
    FailbackImmediately     Indicates that the groups is to be failed back to the node.
    FailbackPolicy          Indicates that the failover policy for each group is to be used.

    .NOTES
    FailbackTypes further defined:
    https://docs.microsoft.com/en-us/previous-versions/windows/desktop/cluswmi/mscluster-node-resume
    https://docs.microsoft.com/en-us/windows/win32/api/clusapi/ne-clusapi-cluster_node_resume_failback_type
#>

function Resume-SqlClusterNode
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter()]
        [ValidateSet('NoFailback', 'FailbackImmediately', 'FailbackPolicy')]
        [String]
        $FailbackType = 'NoFailback'
    )

    $ClusterNodeStates = @{
        0 = 'Up'
        1 = 'Down'
        2 = 'Paused'
        3 = 'Joining'
    }

    $FailbackTypeCode = @{
        'NoFailback' = 0
        'FailbackImmediately' = 1
        'FailbackPolicy' = 2
    }

    $NodeName = (Split-SqlServer -SqlServer $ComputerName -Verbose:$VerbosePreference).SqlServerName

    $ClusterNodeWmi = @{
        ComputerName = $ComputerName
        ClassName = 'MSCluster_Node'
        Namespace = 'Root\MSCluster'
        Filter = "Name = '$NodeName'"
        ErrorAction = 'SilentlyContinue'
    }

    $StartTime = Get-Date
    $RetryInterval = 30
    while ($true)
    {
        # We're using WMI vs. CIM in this case as the CimInstance does not contain the Resume method.
        $ClusterNode = Get-WmiObject @ClusterNodeWmi
        if ($ClusterNode)
        {
            $ClusterNodeState = $ClusterNodeStates[[int]$ClusterNode.State]
            if ($ClusterNodeState -in @('Up', 'Paused'))
            {
                break
            }
            elseif ($ClusterNodeState -in @('Down', 'Joining'))
            {
                $Message = "Successfully queried node [$NodeName] (State: $ClusterNodeState)."
            }
        }
        else
        {
            # This condition has been observed when the cluster node is offline or the service has not yet started.
            $Message = "Error querying node [$NodeName]."
        }

        if ($RetryInterval -eq 30 -and ((Get-Date) - $StartTime).TotalMinutes -gt 5)
        {
            $RetryInterval = 60
            $Message = "$Message Manual remediation may be required."
        }

        Write-Message -Stream 'Warning' -Message "$Message Retrying in $RetryInterval seconds..."
        Start-Sleep -Seconds $RetryInterval
    }

    if ($ClusterNodeState -eq 'Up')
    {
        Write-Message -Stream 'Debug' -Message "Cluster node [$NodeName] is already resumed. No action taken."
    }
    elseif ($ClusterNodeState -eq 'Paused')
    {
        Write-Message -Stream 'Verbose' -Message "Resuming cluster node [$NodeName]"
        $ClusterNode.Resume($FailbackTypeCode[$FailbackType])
    }
    else
    {
        Write-Message -Stream 'Warning' -Message "Cluster node [$NodeName] state invalid. (State: $ClusterNodeState)."
    }
}