function Get-SqlLogs
{
    [CmdletBinding(DefaultParameterSetName = 'ReturnResults')]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter()]
        [ValidateSet('SqlServer', 'SqlAgent')]
        [String[]]
        $SQLLogName = @('SqlServer', 'SqlAgent'),

        [Parameter(Mandatory = $true)]
        [DateTime]
        $StartTime,

        [Parameter()]
        [DateTime]
        $EndTime,

        [Parameter(ParameterSetName = 'StoreResults', Mandatory = $true)]
        [String]
        $TargetSqlServer,

        [Parameter(ParameterSetName = 'StoreResults', Mandatory = $true)]
        [String]
        $TargetSqlDatabase,

        [Parameter()]
        [Boolean]
        $UseClientTime = $false
    )

    if ([String]::IsNullOrEmpty($EndTime))
    {
        $EndTime = Get-Date
    }

    $SqlServerDnsName = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServerDNSName

    $LocalOffset = Get-TimeZoneOffset
    $ServerOffset = Get-TimeZoneOffset -ComputerName $SqlServerDnsName

    if ($UseClientTime)
    {
        $FilterStartTime = $StartTime.AddMinutes($ServerOffset.UtcOffsetMins - $LocalOffset.UtcOffsetMins)
        $FilterEndTime = $EndTime.AddMinutes($ServerOffset.UtcOffsetMins - $LocalOffset.UtcOffsetMins)
    }
    else
    {
        $FilterStartTime = $StartTime
        $FilterEndTime = $EndTime
    }
    $OffsetString = $ServerOffset.OffsetString

    $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference

    if ($SQLLogName -contains 'SqlServer')
    {
        # splat parameters to Get-SqlServerLogs
        $SqlServerLogsParams = @{
            Server = $Server
            FilterStartTime = $FilterStartTime
            OffsetString = $OffsetString
        }
        if ($PSCmdlet.ParameterSetName -eq 'StoreResults')
        {
            $SqlServerLogsParams += @{
                TargetSqlServer = $TargetSqlServer
                TargetSqlDatabase = $TargetSqlDatabase
            }
        }
        if ($FilterEndTime)
        {
            $SqlServerLogsParams += @{
                FilterEndTime = $FilterEndTime
            }
        }
        Get-SqlServerLogs @SqlServerLogsParams -Verbose:$VerbosePreference
    }

    if ($SQLLogName -contains 'SqlAgent')
    {
        # splat parameters to Get-SqlAgentLogs
        $SqlAgentLogsParams = @{
            Server = $Server
            FilterStartTime = $FilterStartTime
            OffsetString = $OffsetString
        }
        if ($FilterEndTime)
        {
            $SqlAgentLogsParams += @{
                FilterEndTime = $FilterEndTime
            }
        }
        Get-SqlAgentLogs @SqlAgentLogsParams -Verbose:$VerbosePreference
    }
}
