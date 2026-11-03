$script:ConnectionOptions = @{}
$script:sessionCache = @{}

<#
    .SYNOPSIS
    This function will return an smo server object for the specified SQL Server.
    If a connection already exists in the cache, the cached session will be returned.

    .PARAMETER ComputerName
    The computer running an instance of SQL that that you are connecting to.

    .PARAMETER InstanceName
    The name of the instance you are connecting to.

    .PARAMETER SqlServer
    The server that that you are connecting to.

    .PARAMETER EnableCertificateFailback
    The connection will be made using the 'TrustServerCertificate' setting only if the cert isn't a trusted chain.

    .PARAMETER TrustServerCertificate
    The connection will be made using the 'TrustServerCertificate' setting without validating the certificate chain.

    .PARAMETER Force
    When specified, a new connection to the server will be made even if an existing connection already exists.
    Any existing connections in the session will be removed.

    .NOTES
    The main use case for force is in a scenario where a refresh method is either not present or does not work
    properly. For example, in some cases of failover, Availability Group information may not refresh even if
    refresh is called on the Availability Group.
#>

function Connect-SqlServer
{
    param
    (
        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter()]
        [switch]
        $EnableCertificateFailback,

        [Parameter()]
        [Switch]
        $TrustServerCertificate,

        [Parameter()]
        [Switch]
        $Force
    )

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $SqlServer = Format-SqlInstanceName -ComputerName $ComputerName -InstanceName $InstanceName
    }
    $SqlServer = (Split-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference).SqlServer

    if ($script:sessionCache.Keys -contains $SqlServer)
    {
        Write-Message -Stream 'Debug' -Message 'Existing session found in cache.'

        if ($Force.IsPresent)
        {
            Write-Message -Stream 'Verbose' -Message 'Force specified, closing existing sessions.'
            $TSC = $script:sessionCache[$SqlServer].ConnectionContext.TrustServerCertificate
            Disconnect-SqlServer -SqlServer $SqlServer -ClearConnectionPool
        }
        else
        {
            Write-Message -Stream 'Verbose' -Message 'Returning existing session.'
            return $script:sessionCache[$SqlServer]
        }
    }

    Write-Message -Stream 'Verbose' -Message "Creating connection to SQL Server '$SqlServer'"
    $session = New-Object -TypeName 'Microsoft.SqlServer.Management.Smo.Server' $SqlServer
    $session.ConnectionContext.EncryptConnection = $true
    if ($TrustServerCertificate.IsPresent -or $true -eq $TSC)
    {
        $Message = "Applying [TrustServerCertificate] to skip certificate trust checks on [$SqlServer]."
        Write-Message -Stream 'Debug' -Message $Message
        $session.ConnectionContext.TrustServerCertificate = $true
    }
    if ($session.Status -ne 'Online')
    {
        if ($true -eq $script:ConnectionOptions.EnableCertificateFailback -or $EnableCertificateFailback.IsPresent -or $true -eq $TSC)
        {
            try
            {
                $session.ConnectionContext.Connect()
            }
            catch
            {
                if ($_.Exception.InnerException -is [Microsoft.SqlServer.Management.Common.ConnectionException])
                {
                    if ($_.Exception.InnerException.InnerException.Message -match 'certificate chain was issued by an authority that is not trusted.')
                    {
                        $Message = "Using [TrustServerCertificate] as the certificate on [$SqlServer] is not trusted!"
                        Write-Message -Stream 'Warning' -Message $Message
                        $session.ConnectionContext.TrustServerCertificate = $true
                    }
                }
            }
        }
    }

    $Retries = 5
    while ($session.Status -ne 'Online' -and $Retries -gt 0)
    {
        $Retries--
        try
        {
            $session.ConnectionContext.Connect()
        }
        catch
        {
            if ($Retries -gt 0)
            {
                if ($_.Exception.InnerException.InnerException.Message -match 'certificate chain was issued by an authority that is not trusted.')
                {
                    $Message = "Failed to connect to '$SqlServer'. The certificate is not trusted!"
                    Write-Message -Stream 'Log' -Message $Message
                    throw $Message
                }
                Write-Message -Stream 'Verbose' -Message "Failed to connect to '$SqlServer'. Retrying in 5 seconds..."
                Start-Sleep -Seconds 5
            }
            else
            {
                $Message = $_.Exception.InnerException.InnerException
                Write-Message -Stream 'Debug' -Message $Message
                throw $_
            }
        }
    }

    Write-Message -Stream 'Debug' -Message 'Storing session in cache.'
    $script:sessionCache += @{ "$SqlServer" = $session }

    return $session
}
