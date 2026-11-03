function Start-SqlInstance
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    $SqlServerDNSName = $SqlServerInfo.SqlServerDNSName
    $ServiceName = $SqlServerInfo.AgtServiceName
    $Service = Get-Service -ComputerName $SqlServerDNSName -Name $ServiceName
    if ($Service.StartType -eq 'Disabled')
    {
        $ServiceName = $SqlServerInfo.SqlServiceName
        $Service = Get-Service -ComputerName $SqlServerDNSName -Name $ServiceName
    }

    if ($Service.Status -eq 'Stopped')
    {
        Write-Message -Stream 'Verbose' -Message "Bringing SQL server [$SqlServer] online."
        $Service | Start-Service
    }
}