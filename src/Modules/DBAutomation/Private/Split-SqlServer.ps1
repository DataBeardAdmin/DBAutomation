$script:SqlServerInfoCache = @{}

<#
    .SYNOPSIS
    This function will take a SqlServer in 'connection string' format and split out the following components:
        SqlServer (Connection string format using FQDN server name, resolved from possible CNAME/IP)
        SqlServerDNSName (Base FQDN server name, resolved from possible CNAME/IP, no instance name)
        SqlServerName (Base server name with no domain, resolved from possible CNAME/IP, no instance name)
        Domain (Domain name resolved from DNS if not provided)
        InstanceName (Name of the instance)
        SqlServiceName (The name of the service running SQL Server)
        AgtServiceName (The name of the service running SQL Agent)

    .PARAMETER SqlServer
    Specifies a connection to SQL.
#>

function Split-SqlServer
{
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $SqlServer
    )

    if ($script:SqlServerInfoCache.Keys -contains $SqlServer)
    {
        Write-Message -Stream 'Debug' -Message "Existing SqlServer entry [$SqlServer] found in [Split-SqlServer] cache."
        return $script:SqlServerInfoCache[$SqlServer]
    }

    $SqlServerDNSName, $InstanceName = $SqlServer.Split('\')
    if ($SqlServerDNSName -eq '.')
    {
        $SqlServerDNSName = 'localhost'
    }

    try
    {
        $IsIPAddress = [System.Net.IPAddress]::TryParse($SqlServerDNSName, [ref]$Null)

        if ($false -eq $IsIPAddress)
        {
            # This both updates $SqlServerDNSName to be FQDN and resolves CNAMEs and IPs to their underlying A record.
            $HostEntry = [System.Net.Dns]::GetHostEntry($SqlServerDNSName)
            $SqlServerDNSName = $HostEntry.HostName
            $SqlServerName, $Domain = $SqlServerDNSName.Split('.', 2)
        }
        else
        {
            $Message = "IP Address [$SqlServerDNSName] was supplied to [Split-SqlServer]"
            try
            {
                $HostEntry = [System.Net.Dns]::GetHostEntry($SqlServerDNSName)
                Write-Message -Stream 'Debug' -Message "$Message and *does* resolve in DNS."
                # We are not updating SqlServer as we assume this was intentional.'
                $SqlServerName, $Domain = $HostEntry.HostName.Split('.', 2)
            }
            catch
            {
                Write-Message -Stream 'Debug' -Message "$Message but *does not* resolve in DNS."
                $SqlServerName = $SqlServerDNSName
                $Domain = $null
            }
        }
    }
    catch
    {
        $Message = "Cannot resolve SQL Server name from DNS using input! [$SqlServerDNSName]"
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($false -eq [string]::IsNullOrEmpty($InstanceName) -and $InstanceName -ne 'MSSQLSERVER')
    {
        $SqlServiceName = "MSSQL`$$InstanceName"
        $AgtServiceName = "SQLAgent`$$InstanceName"
    }
    else
    {
        $InstanceName = 'MSSQLSERVER'
        $SqlServiceName = 'MSSQLSERVER'
        $AgtServiceName = 'SQLSERVERAGENT'
    }
    $Listener = Format-SqlInstanceName -ComputerName $SqlServerDNSName -InstanceName $InstanceName

    $SqlServerInfo = [PSCustomObject]@{
        SqlServer = $Listener
        SqlServerDNSName = $SqlServerDNSName
        SqlServerName = $SqlServerName
        Domain = $Domain
        InstanceName = $InstanceName
        SqlServiceName = $SqlServiceName
        AgtServiceName = $AgtServiceName
    }
    
    Write-Message -Stream 'Debug' -Message "Storing SqlServer entry [$SqlServer] in [Split-SqlServer] cache."
    $script:SqlServerInfoCache += @{ "$SqlServer" = $SqlServerInfo }

    return $SqlServerInfo
}