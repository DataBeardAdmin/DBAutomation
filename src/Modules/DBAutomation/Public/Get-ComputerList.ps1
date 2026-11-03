function Get-ComputerList
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ADForest', Mandatory = $true)]
        [String[]]
        $ActiveDirectoryIncludes,

        [Parameter(ParameterSetName = 'ADForest')]
        [String[]]
        $ActiveDirectoryExcludes,

        [Parameter(ParameterSetName = 'ADForest')]
        [String]
        $SourceDomain,

        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Alias('Listener')]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(ParameterSetName = 'Cluster', Mandatory = $true)]
        [String]
        $VirtualNetworkName,

        [Parameter(ParameterSetName = 'ReportServer', Mandatory = $true)]
        [String]
        $ReportServer

    )

    switch ($PSCmdlet.ParameterSetName)
    {
        'ADForest'
        {
            $Params = @{
                IncludedObjects = $ActiveDirectoryIncludes
                ExcludedObjects = $ActiveDirectoryExcludes
                SourceDomain = $SourceDomain
                ObjectType = 'Computer'
            }

            Get-ADForestObjects @Params -Verbose:$VerbosePreference | Select-Object -ExpandProperty FQDN
        }
        'ComputerName'
        {
            Get-SqlServerList -ComputerName $ComputerName -InstanceName $InstanceName -Verbose:$VerbosePreference
        }
        'SqlServer'
        {
            Get-SqlServerList -SqlServer $SqlServer -Verbose:$VerbosePreference
        }
        'ServerObject'
        {
            Get-SqlServerList -Server $Server -Verbose:$VerbosePreference
        }
        'Cluster'
        {
            Get-ClusterNodesByNetworkName -ComputerName $VirtualNetworkName -Verbose:$VerbosePreference
        }
        'ReportServer'
        {
            Get-ScaleOutReportServers -ReportServer $ReportServer -Verbose:$VerbosePreference
        }
        default
        {
            $Message = 'Unknown parameter set for Get-ComputerList!'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }
}