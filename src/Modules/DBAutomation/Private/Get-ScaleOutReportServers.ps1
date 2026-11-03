function Get-ScaleOutReportServers
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $ReportServer
    )

    $ReportServer = (Split-SqlServer -SqlServer $ReportServer -Verbose:$VerbosePreference).SqlServerDNSName

    $NameSpaces = Get-SqlCimNamespaces -ComputerName $ReportServer -Product 'ReportServer'

    $MachineNames = foreach ($NameSpaceConfiguration in $NameSpaces)
    {
        $FQDN = (Split-SqlServer -SqlServer $ReportServer -Verbose:$VerbosePreference).Domain
        #We're using Get-WmiObject here instead of Get-CimInstance as the CimInstance does not have the 'ListReportServersInDatabase' method
        $Configuration = Get-WmiObject -ComputerName $ReportServer -Namespace $NameSpaceConfiguration -Class MSReportServer_ConfigurationSetting
        foreach ($MachineName in $Configuration.ListReportServersInDatabase().MachineNames)
        {
            (Split-SqlServer -SqlServer "$MachineName.$FQDN" -Verbose:$VerbosePreference).SqlServerDNSName
        }
    }

    if ($MachineNames | Where-Object { $_ -eq $ReportServer })
    {
        if ($MachineNames.Count -gt 1)
        {
            Write-Message -Stream 'Verbose' -Message "Found additional scale-out report server(s): $($($MachineNames | Where-Object {$_ -ne $ReportServer}) -join ', ')"
        }
        #This is to preserve the order of the report servers with the provided report server first in the list.
        $MachineNames = @($ReportServer) + $MachineNames | Select-Object -Unique
    }
    else
    {
        $Message = @"
The provided report server [$ReportServer] appears to be an alias!
Excluding it from the list of scale-out report servers.
Please provide the actual machine name of the report server to include it in the list of scale-out report servers.
"@
        Write-Message -Stream 'Warning' -Message $Message
        if ($MachineNames.Count -gt 0)
        {
            Write-Message -Stream 'Verbose' -Message "Found scale-out report server(s): $($MachineNames -join ', ')"
        }
        $MachineNames = $MachineNames | Sort-Object
    }

    return $MachineNames
}