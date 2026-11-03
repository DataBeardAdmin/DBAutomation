<#
    .SYNOPSIS
    The purpose of this function is to collect various error logs for a given server or cluster and return them together for easier review.

    .DESCRIPTION
    This function collects error logs from the target Listener (this can e a stand-alone server or cluster network name).
    The logs logs to be collected are:
        1. Cluster logs (if applicable)
        2. Windows System Logs
        3. Windows Application Logs
        4. SQL Server logs (if applicable)
        5. SQL Agent logs (if applicable)
    Once collected, the output will be sorted by log date for further review.

    .PARAMETER ComputerName
    The computer you are gathering logs from.

    .PARAMETER InstanceName
    The name of the instance you are gathering logs from.

    .PARAMETER SqlServer
    Specifies a connection to SQL. This can be either a stand-alone server, an Availability Group listener, or a
    Failover Cluster Instance. If a cluster network name is passed in and ExcludeClusterExpansion is not specified,
    all nodes of the cluster will be reviewed.

    .PARAMETER StartTime
    DateTime specifying the beginning of the range for which log capturing will occur.

    .PARAMETER EndTime
    DateTime specifying the end of the range for which log capturing will occur.

    .PARAMETER SendTo
    Where the collected logs should be sent. Possible values: 'Console', 'Disk', 'SQL'.

    .PARAMETER TargetFilePath
    The file path to store the logs collected.

    .PARAMETER TargetSqlServer
    If Logging to SQL, The SQL Server which will be used to store the logs collected.

    .PARAMETER TargetSqlDatabase
    If Logging to SQL, The database on the TargetSqlServer which will be used to store the logs collected.

    .PARAMETER ExcludeClusterExpansion
    If Listener is a cluster network name, only collect logs from the currently active node. Do NOT look at any other nodes.

    .PARAMETER ExcludeWinSysLogs
    Do NOT collect Windows System error logs.

    .PARAMETER ExcludeWinAppLogs
    Do NOT collect Windows Application error logs.

    .PARAMETER ExcludeClusterLogs
    If the Listener is a member of a cluster, do NOT collect cluster logs.

    .PARAMETER ExcludeSqlServerLogs
    If the server(s) reviewed contain SQL Server instances, do NOT collect SQL Server logs.

    .PARAMETER ExcludeSqlAgentLogs
    If the server(s) reviewed contain SQL Server instances, do NOT collect SQL Server Agent logs.

    .PARAMETER UseClientTime
    This switch will return the results formatted in the caller's timezone.

    .NOTES
    #TODO: Provide the required schema for logging to SQL.

    .EXAMPLE
    Get-AllLogs -SqlServer 'ClusterName' -StartTime 'MM/DD/YYYY HH:MM:SS' -EndTime 'MM/DD/YYYY HH:MM:SS' -Verbose
#>

function Get-AllLogs
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName,

        [Alias('Listener')]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(Mandatory = $true)]
        [DateTime]
        $StartTime,

        [Parameter()]
        [DateTime]
        $EndTime,

        [Parameter()]
        [ValidateSet('Console', 'Disk', 'SQL')]
        [String[]]
        $SendTo = @('Console'),

        [Parameter()]
        [String]
        $TargetFilePath,

        [Parameter()]
        [String]
        $TargetSqlServer,

        [Parameter()]
        [String]
        $TargetSqlDatabase,

        [Parameter()]
        [switch]
        $ExcludeClusterExpansion,

        [Parameter()]
        [switch]
        $ExcludeWinSysLogs,

        [Parameter()]
        [switch]
        $ExcludeWinAppLogs,

        [Parameter()]
        [switch]
        $ExcludeClusterLogs,

        [Parameter()]
        [switch]
        $ExcludeSqlServerLogs,

        [Parameter()]
        [switch]
        $ExcludeSqlAgentLogs,

        [Parameter()]
        [switch]
        $UseClientTime
    )

    $AssertLogTarget = @{
        SendTo = $SendTo
        TargetFilePath = $TargetFilePath
        TargetSqlServer = $TargetSqlServer
        TargetSqlDatabase = $TargetSqlDatabase
    }
    Assert-LogTarget @AssertLogTarget

    $LogName = @()
    if ($false -eq $ExcludeWinAppLogs.IsPresent)
    {
        $LogName += 'Application'
    }
    if ($false -eq $ExcludeWinSysLogs.IsPresent)
    {
        $LogName += 'System'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    #If the user passed in a SQL Instance name, split this out.
    $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    $SqlServerDNSName = $SqlServerInfo.SqlServerDNSName
    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $InstanceName = $SqlServerInfo.InstanceName
    }

    if ($false -eq $ExcludeClusterLogs.IsPresent -or $false -eq $ExcludeClusterExpansion.IsPresent)
    {
        #If anything is returned, the server has clustering configured.
        $Resources = Get-ClusterResourceByFilter -ComputerName $SqlServerDNSName -Type 'Network Name' -ErrorAction:SilentlyContinue
        if ($Resources)
        {
            Write-Message -Stream 'Debug' -Message 'Cluster detected'
            if ($false -eq $ExcludeClusterLogs.IsPresent)
            {
                $LogName += 'Microsoft-Windows-FailoverClustering*'
            }

            if ($ExcludeClusterExpansion.IsPresent)
            {
                $ComputerNames = $SqlServerDNSName
            }
            else
            {
                $clusterResource = $Resources |
                    Where-Object -FilterScript { $_.PrivateProperties.DnsName -eq $SqlServerInfo.SqlServerName }

                if ($clusterResource)
                {
                    #The Listener supplied is a Network Name in the cluster. Use the possible owners for this Network Name.
                    $ComputerNames = Get-ClusterResourcePossibleOwners -clusterResource $clusterResource -Verbose:$VerbosePreference
                }
                else
                {
                    #The listener supplied is not directly a Network Name, but is tied to the cluster in some form.
                    #Warn the user that the cluster will not be expanded as they didn't explicitly exclude cluster expansion.
                    Write-Message -Stream 'Warning' -Message "The listener parameter supplied resolved to [$SqlServerDNSName]. Clustering is configured but this was not a network name for the cluster, therefore the cluster nodes will not be expanded."
                    $ComputerNames = $SqlServerDNSName
                }
            }
        }
        else
        {
            $ComputerNames = $SqlServerDNSName
        }
    }
    else
    {
        $ComputerNames = $SqlServerDNSName
    }

    $SQLLogName = @()
    if ($false -eq $ExcludeSqlServerLogs.IsPresent)
    {
        $SQLLogName += 'SqlServer'
    }
    if ($false -eq $ExcludeSqlAgentLogs.IsPresent)
    {
        $SQLLogName += 'SqlAgent'
    }

    $Counter = 0
    $Logs = @()
    $ExcludeProviders = @()
    $SqlServerInstances = @()
    if ($SQLLogName.Count -gt 0)
    {
        #Return the SqlServer Instance(s)
        foreach ($ComputerName in $ComputerNames)
        {
            $SqlServerComponent = Find-SqlComponents -ComputerName $ComputerName -Product 'SqlServer' -Verbose:$VerbosePreference
            if ($false -eq [string]::IsNullOrEmpty($InstanceName))
            {
                #The user explicitly called out a SQL instance; we'll only look at this instance on the SQL side.
                $SqlServerComponent = $SqlServerComponent | Where-Object InstanceName -Match $InstanceName
            }

            foreach ($SqlInstance in $SqlServerComponent | Where-Object { $_.Cluster.IsClustered -eq $false })
            {
                $SqlServer = '{0}\{1}' -f $SqlInstance.TargetComputerName, $SqlInstance.InstanceName
                $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference

                $SqlServerInstances += @{
                    SqlServer = $SqlServerInfo.SqlServer
                    SqlServiceName = $SqlServerInfo.SqlServiceName
                }
            }
        }

        # We still have $SqlServerComponent loaded from the last server in $ComputerNames, no need to re-query.
        foreach ($SqlInstance in $SqlServerComponent | Where-Object { $_.Cluster.IsClustered -eq $true })
        {
            $SqlServer = '{0}\{1}' -f $SqlInstance.Cluster.ClusterName, $SqlInstance.InstanceName
            $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference

            $SqlServerInstances += @{
                SqlServer = $SqlServerInfo.SqlServer
                SqlServiceName = $SqlServerInfo.SqlServiceName
            }
        }

        foreach ($SqlServerInstance in $SqlServerInstances)
        {
            $SqlServer = $SqlServerInstance.SqlServer
            $SqlServiceName = $SqlServerInstance.SqlServiceName
            Write-Message -Stream 'Verbose' -Message "SQL Server Found ($SqlServer)"

            Write-Progress -Id 1 -Activity 'Log Collection' -Status "Working on Sql Server: $SqlServer" -CurrentOperation 'SQL Logs' -PercentComplete ($Counter / ($SqlServerInstances.Count + $ComputerNames.Count) * 100)
            # splat parameters to Get-SqlLogs
            $SqlLogsParams = @{
                SqlServer = $SqlServer
                SQLLogName = $SQLLogName
                StartTime = $StartTime
                UseClientTime = $UseClientTime.IsPresent
            }
            if ($EndTime)
            {
                $SqlLogsParams += @{
                    EndTime = $EndTime
                }
            }
            if ($SendTo -contains 'SQL')
            {
                $SqlLogsParams += @{
                    TargetSqlServer = $TargetSqlServer
                    TargetSqlDatabase = $TargetSqlDatabase
                }
            }
            $Logs += Get-SqlLogs @SqlLogsParams -Verbose:$VerbosePreference
            $ExcludeProviders += $SqlServiceName
            $Counter++
        }
    }

    foreach ($ComputerName in $ComputerNames)
    {
        Write-Progress -Id 1 -Activity 'Log Collection' -Status "Working on computer: $ComputerName" -CurrentOperation 'Windows Logs' -PercentComplete ($Counter / ($SqlServerInstances.Count + $ComputerNames.Count) * 100)
        if ($LogName.Count -gt 0)
        {
            Write-Message -Stream 'Verbose' -Message 'The following Windows logs will be imported:'
            foreach ($Log in $LogName)
            {
                Write-Message -Stream 'Verbose' -Message " +$Log"
            }

            # splat parameters to Get-WinLogs
            $WinLogsParams = @{
                ComputerName = $ComputerName
                LogName = $LogName
                StartTime = $StartTime
                ExcludeProviders = $ExcludeProviders
                UseClientTime = $UseClientTime.IsPresent
            }
            if ($EndTime)
            {
                $WinLogsParams += @{
                    EndTime = $EndTime
                }
            }
            $Logs += Get-WinLogs @WinLogsParams -Verbose:$VerbosePreference
        }
        $Counter++
        Write-Progress -Id 1 -Activity 'Log Collection' -Status "Finished computer: $ComputerName" -PercentComplete ($Counter / ($SqlServerInstances.Count + $ComputerNames.Count) * 100)
    }
    Write-Progress -Id 1 -Activity 'Log Collection' -Completed

    if ($Logs.Count -gt 0)
    {
        if ($UseClientTime.IsPresent)
        {
            foreach ($Log in $Logs)
            {
                $Log.LogTime = [DateTime]::SpecifyKind($Log.LogTime.LocalDateTime, 'local')
            }
        }

        $ExportLogs = @{
            SendTo = $SendTo
            TargetFilePath = $TargetFilePath
            TargetSqlServer = $TargetSqlServer
            TargetSqlDatabase = $TargetSqlDatabase
            Logs = $Logs
        }
        Export-Logs @ExportLogs -Verbose:$VerbosePreference
    }
    else
    {
        Write-Message -Stream 'Verbose' -Message 'No logs met the criteria entered.'
    }
}
