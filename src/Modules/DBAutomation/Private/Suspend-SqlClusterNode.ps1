<#
    .SYNOPSIS
    This function will pause a cluster node.

    .PARAMETER ComputerName
    The name of the cluster node that will be paused.

    .PARAMETER DrainType
    The following options are allowed:
    None            Indicates that the groups will not be moved from this node.
    Drain           Indicates that the groups will be failed over to another node.
    ForceDrain      Indicates that the groups will be failed over to another node even if this will
                    result in a failed state.

    .NOTES
    DrainType further defined:
    https://docs.microsoft.com/en-us/previous-versions/windows/desktop/cluswmi/mscluster-node-pause
#>

function Suspend-SqlClusterNode
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter()]
        [ValidateSet('None', 'Drain', 'ForceDrain')]
        [String]
        $DrainType = 'None'
    )

    Assert-ClusterQuorum -ComputerName $ComputerName -Verbose:$VerbosePreference

    $ClusterNodeStates = @{
        0 = 'Up'
        1 = 'Down'
        2 = 'Paused'
        3 = 'Joining'
    }

    $NodeDrainStatus = @{
        0 = 'NotInitiated'
        1 = 'InProgress'
        2 = 'Completed'
        3 = 'Failed'
    }

    $DrainTypeCode = @{
        'None' = 0
        'Drain' = 1
        'ForceDrain' = 2
    }

    $NodeName = (Split-SqlServer -SqlServer $ComputerName -Verbose:$VerbosePreference).SqlServerName

    Write-Message -Stream 'Verbose' -Message "Pausing cluster node [$NodeName]"

    if ($DrainType -eq 'ForceDrain')
    {
        $Message = 'ForceDrain was specified. All groups will be failed over to another node even if this will result in a failed state.'
        Write-Message -Stream 'Warning' -Message $Message
    }

    #We're using WMI vs. CIM in this case as the CimInstance does not contain the pause method.
    $ClusterNodeWmi = @{
        ComputerName = $ComputerName
        Namespace = 'Root\MSCluster'
        ClassName = 'MSCluster_Node'
        Filter = "Name = '$NodeName'"
    }

    $ClusterNode = Get-WmiObject @ClusterNodeWmi
    Write-Message -Stream 'Debug' -Message "Issuing pause command to [$NodeName] with drain type of [$DrainType]."
    $ClusterNode.Pause($DrainTypeCode[$DrainType])

    $UserWarned = $false
    if ($DrainType -eq 'Drain')
    {
        # Validate pause/drain has completed.
        $StartTime = Get-Date
        While ($true)
        {
            Start-Sleep -Seconds 5
            $ClusterNode = Get-WmiObject @ClusterNodeWmi
            $ClusterNodeState = $ClusterNodeStates[[int]$ClusterNode.State]
            $DrainState = $NodeDrainStatus[[int]$ClusterNode.NodeDrainStatus]
            Write-Message -Stream 'Debug' -Message "[$NodeName] state: $ClusterNodeState, Drain status: $DrainState."

            if ($ClusterNodeState -eq 'Paused' -and $DrainState -eq 'Completed')
            {
                break
            }
            elseif (((Get-Date) - $StartTime).TotalSeconds -gt 30 -and $false -eq $UserWarned)
            {
                Write-Message -Stream 'Warning' -Message "The drain for node [$NodeName] is taking longer than expected."
                $UserWarned = $true
            }
            elseif (((Get-Date) - $StartTime).TotalSeconds -gt 120)
            {
                try
                {
                    Write-Message -Stream 'Verbose' -Message "[$NodeName] took too long to drain. Attempting to resume."
                    Resume-SqlClusterNode -ComputerName $ComputerName
                }
                catch
                {
                    Write-Message -Stream 'Error' -Message "Failed to resume cluster node [$NodeName]."
                }
                finally
                {
                    $Message = "Failed to drain cluster node [$NodeName]."
                    Write-Message -Stream 'Log' -Message $Message
                    throw $Message
                }
            }
        }
    }

    Write-Message -Stream 'Debug' -Message "The node [$NodeName] has been paused."
}