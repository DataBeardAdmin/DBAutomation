<#
    .SYNOPSIS
    This function will check for pending restart status and restart the server(s) as needed specified by decoding the listener.
    If the specified listener is an availability group, it will restart the secondary (for this listener) and then the primary.

    .PARAMETER ComputerName
    The computer running an instance of SQL that that you are connecting to.

    .PARAMETER InstanceName
    The name of the instance you are connecting to.

    .PARAMETER SqlServer
    Specifies a connection to SQL. This can be either a stand-alone server, an Availability Group listener, or a
    Failover Cluster Instance.

    .PARAMETER ReportServer
    Specifies a computer name to a Report Server.

    .PARAMETER ExpandReportServer
    When specified, the computer expansion function will take any member server and return all report servers. This is needed because
    scale out report server's cannot be defined by a traditional "listener" (outside of a load balancer which the report servers may or
    may not know about).

    .PARAMETER ClusterNode
    Specifies the computer name is a node of a WSFC, and not a SQL endpoint such as a cluster VNN.

    .PARAMETER SkipPendingRebootCheck
    When specified, the specified server(s) will be restarted without first checking if there's a pending reboot status.

    .PARAMETER Force
    When specified, the specified server(s) will be restarted without validating any prerequisites.
#>

Function Restart-SqlServer
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String[]]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Alias('Listener', 'VirtualNetworkName')]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String[]]
        $SqlServer,

        [Parameter(ParameterSetName = 'ReportServer', Mandatory = $true)]
        [String[]]
        $ReportServer,

        [Parameter(ParameterSetName = 'ReportServer')]
        [Switch]
        $ExpandReportServer,

        [Parameter(ParameterSetName = 'ClusterNode', Mandatory = $true)]
        [String[]]
        $ClusterNode,

        [Parameter()]
        [Switch]
        $SkipPendingRebootCheck,

        [Parameter()]
        [Switch]
        $Force
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServerList = foreach ($member in $ComputerName)
        {
            $SqlServerInstance = Format-SqlInstanceName -ComputerName $member -InstanceName $InstanceName
            Get-ComputerList -SqlServer $SqlServerInstance -Verbose:$VerbosePreference
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $SqlServerList = foreach ($member in $SqlServer)
        {
            Get-ComputerList -SqlServer $member -Verbose:$VerbosePreference
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ReportServer')
    {
        if ($ExpandReportServer.IsPresent)
        {
            $SqlServerList = foreach ($member in $ReportServer)
            {
                Get-ComputerList -ReportServer $member -Verbose:$VerbosePreference
            }
        }
        else
        {
            $SqlServerList = $ReportServer
        }
    }
    else
    {
        $SqlServerList = $ClusterNode
    }

    foreach ($SqlServerInstance in $SqlServerList)
    {
        $SqlServerDNSName = (Split-SqlServer -SqlServer $SqlServerInstance -Verbose:$VerbosePreference).SqlServerDNSName

        if ($Force.IsPresent -eq $false)
        {
            $Instances = Find-SqlComponents -ComputerName $SqlServerDNSName -Product 'SqlServer' -Verbose:$VerbosePreference
            if ($Instances)
            {
                # This validates if *any* instance on the specified server has HADR enabled.
                $IsHadrEnabled = @($Instances.IsHadrEnabled).Contains($true)
                # This validates if the specified server is a clustered SQL Instance.
                if ($PSCmdlet.ParameterSetName -eq 'ClusterNode')
                {
                    $IsClusteredInstance = $true
                }
                else
                {
                    $IsClusteredInstance = Test-IsClusterVNN -SqlServerComponent $Instances
                }
                $IsSqlServerInstalled = $true
            }
            else
            {
                $IsSqlServerInstalled = $false
            }
        }
        else
        {
            $IsSqlServerInstalled = $false
        }

        if ($IsClusteredInstance -and $PSCmdlet.ParameterSetName -ne 'ClusterNode')
        {
            $ComputerNames = Get-ComputerList -VirtualNetworkName $SqlServerDNSName -Verbose:$VerbosePreference
        }
        else
        {
            $ComputerNames = $SqlServerDNSName
        }

        foreach ($Computer in $ComputerNames)
        {
            if ($SkipPendingRebootCheck.IsPresent -or $Force.IsPresent)
            {
                $PendingReboot = @{ RebootPending = $true }
            }
            else
            {
                $PendingReboot = Get-PendingReboot -ComputerName $Computer -ErrorAction Stop -Verbose:$VerbosePreference
            }

            $ClusterNodeIsPaused = $false
            $ServerWasRestarted = $false

            do
            {
                try
                {
                    if ($PendingReboot.RebootPending)
                    {
                        if ($IsHadrEnabled -or $IsClusteredInstance)
                        {
                            Write-Message -Stream 'Verbose' -Message "Preparing to restart [$Computer]"
                            if ($false -eq $ClusterNodeIsPaused)
                            {
                                $Message = "Ensuring [$Computer] is not primary for any synchronous Availability Groups."
                                Write-Message -Stream 'Debug' -Message $Message
                                foreach ($Instance in $Instances)
                                {
                                    if ($Instance.IsHadrEnabled)
                                    {
                                        $InstanceName = $Instance.InstanceName
                                        if ($Instance.Cluster.IsClustered)
                                        {
                                            $SqlServerDNSName = $Instance.Cluster.ClusterName
                                        }

                                        $FormatSqlInstanceName = @{
                                            ComputerName = $SqlServerDNSName
                                            InstanceName = $InstanceName
                                        }
                                        $SqlServerInstance = Format-SqlInstanceName @FormatSqlInstanceName -Verbose:$VerbosePreference

                                        Set-AvailabilityReplica -SqlServer $SqlServerInstance -Role 'Secondary' -Verbose:$VerbosePreference
                                    }
                                }

                                Suspend-SqlClusterNode -ComputerName $Computer -DrainType 'Drain' -Verbose:$VerbosePreference
                                $ClusterNodeIsPaused = $true
                            }
                        }
                        Write-Message -Stream 'Information' -Message "Restarting [$Computer] now."
                        Write-Message -Stream 'Verbose' -Message "Restart started on [$Computer]"
                        Restart-Computer -ComputerName $Computer -Force -Wait -For 'PowerShell,Wmi' -ErrorAction Stop
                        Write-Message -Stream 'Verbose' -Message "Restart finished on [$Computer]"
                        $ServerWasRestarted = $true

                        Wait-ServerUp -ComputerName $Computer -Verbose:$VerbosePreference

                        $PendingReboot = Get-PendingReboot -ComputerName $Computer -ErrorAction Stop -Verbose:$VerbosePreference
                    }
                    else
                    {
                        Write-Message -Stream 'Verbose' -Message "[$Computer] does not have a reboot pending."
                    }
                }
                catch
                {
                    if ($ClusterNodeIsPaused)
                    {
                        Resume-SqlClusterNode -ComputerName $Computer
                        $ClusterNodeIsPaused = $false
                    }
                    $Message = $_
                    Write-Message -Stream 'Log' -Message $Message
                    throw $Message
                }
            } while ($PendingReboot.RebootPending -eq $true)

            if ($ServerWasRestarted -and $IsSqlServerInstalled)
            {
                if ($false -eq $IsClusteredInstance)
                {
                    #Ensure SQL is running.
                    Start-SqlInstance -SqlServer $SqlServerInstance
                }

                if ($ClusterNodeIsPaused)
                {
                    Resume-SqlClusterNode -ComputerName $Computer
                    $ClusterNodeIsPaused = $false
                }

                if ($IsHadrEnabled)
                {
                    #The server's Availability Groups have failed over and SQL has been restarted.
                    #There are some issues with refresh that Connect-SqlServer -Force will clear.
                    $Server = Connect-SqlServer -SqlServer $SqlServerInstance -Force -Verbose:$VerbosePreference
                    Wait-AvailabilityGroupSync -Server $Server
                }
            }
        }
    }
}