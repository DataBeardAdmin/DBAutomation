function Stop-SqlInstance
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
        [string]
        $SqlServer
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }

    $SqlServerInfo = Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    $SqlServerDNSName = $SqlServerInfo.SqlServerDNSName
    $ServiceName = $SqlServerInfo.SqlServiceName
    $Service = Get-Service -ComputerName $SqlServerDNSName -Name $ServiceName
    if ($Service.Status -eq 'Running')
    {
        Write-Message -Stream 'Verbose' -Message "Taking SQL server [$SqlServer] offline."
        $Service | Stop-Service -Force
    }
}
