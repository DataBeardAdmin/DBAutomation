function Get-ProductInfo
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter()]
        [String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
        [Products]
        $Product
    )

    #Ensure the FQDN is used as this is compared below.
    $ComputerName = (Split-SqlServer -SqlServer $ComputerName -Verbose:$VerbosePreference).SqlServerDNSName

    Write-Message -Stream 'Verbose' -Message "Getting local patch version(s) for computer [$ComputerName]"

    if ($Product -ne 'SqlServer')
    {
        $ProductList = @($Product, 'SqlServer')
    }
    else
    {
        $ProductList = $Product
    }

    $FindSqlComponents = @{
        ComputerName = $ComputerName
        Product = $ProductList
    }
    $InstalledComponents = Find-SqlComponents @FindSqlComponents -Verbose:$VerbosePreference
    $InstalledProducts = $InstalledComponents | Where-Object Product -EQ $Product

    if ($InstalledComponents.Product -contains 'SqlServer')
    {
        $IsSqlServerInstalled = $true
        # Find-SqlComponents populates the PossibleOwners as the local server if it's not a cluster.
        $Instance = ($InstalledComponents | Where-Object {
                $_.Product -eq 'SqlServer' -and
                $_.Cluster.PossibleOwners -contains $ComputerName
            })
        if ($false -eq [string]::IsNullOrEmpty($InstanceName))
        {
            $Instance = $Instance | Where-Object { $_.InstanceName -EQ $InstanceName }
        }
        if ($Instance.Count -lt 1)
        {
            $Message = 'Could not determine the installed version based on the criteria specified!'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
        elseif ($Instance.Count -gt 1)
        {
            # TODO: Support multiple instances. This can return multiple which will not work correctly.
            $Message = 'Found multiple installed versions based on the criteria specified! This is not currently supported.'
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        if ($Instance.Cluster.IsClustered)
        {
            # Because this is a cluster, we need to know where to connect to move any AGs as needed.
            $FormatSqlInstanceName = @{
                ComputerName = $Instance.Cluster.ClusterName
                InstanceName = $Instance.InstanceName
            }
            $SqlServer = Format-SqlInstanceName @FormatSqlInstanceName -Verbose:$VerbosePreference
        }
        else
        {
            $FormatSqlInstanceName = @{
                ComputerName = $ComputerName
                InstanceName = $InstanceName
            }
            $SqlServer = Format-SqlInstanceName @FormatSqlInstanceName -Verbose:$VerbosePreference
        }
    }
    else
    {
        $IsSqlServerInstalled = $false
    }

    if ($Product -eq 'SqlServer')
    {
        [System.Version]$LocalVersion = $Instance.ProductVersion
    }
    else
    {
        # TODO: Handle multiple installed product versions instead of taking the latest version.
        [System.Version]$LocalVersion = $InstalledProducts.ProductVersion |
            Sort-Object -Descending |
            Select-Object -First 1

        if ($Product -eq 'ReportServer')
        {
            [System.Version]$PatchLevel = $InstalledProducts.PatchLevel |
                Sort-Object -Descending |
                Select-Object -First 1
        }
    }

    if ([String]::IsNullOrEmpty($LocalVersion))
    {
        $Message = "Current version of [$Product] on [$ComputerName] not detected!"
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($Product -eq 'ReportServer')
    {
        $RestartSqlServerParams = @{
            ReportServer = $ComputerName
        }
    }
    elseif ($Instance.Cluster.IsClustered)
    {
        $RestartSqlServerParams = @{
            ClusterNode = $ComputerName
        }
    }
    else
    {
        $RestartSqlServerParams = @{
            SqlServer = $SqlServer
        }
    }

    return @{
        IsSqlServerInstalled = $IsSqlServerInstalled
        IsClustered = $Instance.Cluster.IsClustered
        SqlServer = $SqlServer
        LocalVersion = $LocalVersion
        PatchLevel = $PatchLevel
        RestartSqlServerParams = $RestartSqlServerParams
    }
}