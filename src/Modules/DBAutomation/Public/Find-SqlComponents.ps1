Function Find-SqlComponents
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true)]
        [String[]]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [Products[]]
        $Product = @('SqlServer', 'ADS', 'SSMS', 'ReportServer')
    )

    Begin
    {
        $InstalledProducts = @()
    }

    Process
    {
        $ScriptBlock = {
            param
            (
                [Parameter()]
                [String[]]
                $Product,

                [Parameter()]
                [System.Management.Automation.ActionPreference]
                $VerbosePreference
            )
            $LocalHost = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName

            # Properties to exclude from registry object
            $excludeProperties = @('PSChildName', 'PSDrive', 'PSParentPath', 'PSPath', 'PSProvider')
            # Base SQL Registry key
            $sqlServerBaseRegistry = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'

            $uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
            $uninstallKeyWow64 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'

            $InstalledPrograms = Get-ChildItem -Path @($uninstallKey, $uninstallKeyWow64) -ErrorAction Continue |
                ForEach-Object -Process {
                    New-Object PSObject -Property @{
                        DisplayName = $_.GetValue('DisplayName')
                        Version = ($_.GetValue('DisplayVersion') -as [System.Version])
                    }
                }

            $RSInstances = @()
            foreach ($InstalledProgram in $InstalledPrograms)
            {
                if ($Product -contains 'ADS' -and $InstalledProgram.DisplayName -match 'Azure Data Studio')
                {
                    [PSCustomObject]@{
                        ComputerName = $LocalHost
                        Product = 'ADS'
                        PatchLevel = $InstalledProgram.Version
                        ProductVersion = $InstalledProgram.Version
                        Edition = $InstalledProgram.DisplayName
                    }
                }

                if ($Product -contains 'SSMS' -and
                    $InstalledProgram.DisplayName -match 'Microsoft SQL Server Management Studio')
                {
                    [PSCustomObject]@{
                        ComputerName = $LocalHost
                        Product = 'SSMS'
                        PatchLevel = $InstalledProgram.Version
                        ProductVersion = $InstalledProgram.Version
                        Edition = $InstalledProgram.DisplayName
                    }
                }

                $RSAppNames = @(
                    'Microsoft SQL Server Reporting Services',
                    'Microsoft Power BI Report Server'
                )
                if ($InstalledProgram.DisplayName -in $RSAppNames)
                {
                    $RSInstances += [PSCustomObject]@{
                        DisplayName = $InstalledProgram.DisplayName
                        Version = [System.Version]$InstalledProgram.Version
                    }
                }
            }

            if (Test-Path -Path "$sqlServerBaseRegistry\Instance Names")
            {
                if ($Product -contains 'ReportServer')
                {
                    if (Test-Path -Path "$sqlServerBaseRegistry\Instance Names\RS")
                    {
                        # Registry key that stores RS instance information
                        $RSDiscoveryRegPath = "$sqlServerBaseRegistry\Instance Names\RS"

                        # Get the instances from the registry
                        Get-ItemProperty -Path $RSDiscoveryRegPath -ErrorAction:Stop |
                            Get-Member -MemberType NoteProperty |
                            Where-Object -Property Name -NotIn $excludeProperties |
                            ForEach-Object -Process {
                                $Time = Get-Date -Format 'HH:mm:ss.ffff'
                                Write-Verbose "[$Time]On $LocalHost, found Report Server instance [$($_.Name)]"
                                $instanceId = ((Get-ItemProperty -Path $RSDiscoveryRegPath -Name $_.Name).$($_.Name))

                                # Get the Setup information about this instance
                                $instanceSetupPath = "$sqlServerBaseRegistry\$instanceId\Setup"
                                $instanceSetup = Get-ItemProperty -Path $instanceSetupPath

                                # Open the instance settings key
                                $InstanceVersionPath = "$sqlServerBaseRegistry\$instanceId\MSSQLServer\CurrentVersion"
                                $instanceVersions = Get-ItemProperty -Path $InstanceVersionPath

                                $CurrentVersion = [System.Version]$instanceVersions.CurrentVersion
                                $ProductVersion = [System.Version]$instanceVersions.ProductVersion

                                if ($CurrentVersion.Major -ge 14)
                                {
                                    foreach ($RSInstance in $RSInstances)
                                    {
                                        if ((
                                                $RSInstance.Version.Major -eq $ProductVersion.Major -and
                                                $instanceSetup.ServiceName -eq 'PowerBIReportServer' -and
                                                $RSInstance.DisplayName -eq 'Microsoft Power BI Report Server'
                                            ) -or
                                            (
                                                $RSInstance.Version.Major -eq $CurrentVersion.Major -and
                                                $instanceSetup.ServiceName -eq 'SQLServerReportingServices' -and
                                                $RSInstance.DisplayName -eq 'Microsoft SQL Server Reporting Services'
                                            ))
                                        {
                                            $ProductVersion = $RSInstance.Version
                                            $Edition = $RSInstance.DisplayName
                                        }
                                    }
                                }
                                else
                                {
                                    $ProductVersion = $instanceSetup.PatchLevel
                                    $Edition = $instanceSetup.Edition
                                }

                                [PSCustomObject]@{
                                    ComputerName = $LocalHost
                                    Product = 'ReportServer'
                                    PatchLevel = $CurrentVersion
                                    ProductVersion = $ProductVersion
                                    Edition = $Edition
                                    InstanceName = $_.Name
                                    InstanceId = $instanceId
                                    RSVirtualRootWebApp = $instanceSetup.RSVirtualRootWebApp
                                    RSVirtualRootServer = $instanceSetup.RSVirtualRootServer
                                }
                            }
                    }
                }

                if ($Product -contains 'SqlServer')
                {
                    if (Test-Path -Path "$sqlServerBaseRegistry\Instance Names\SQL")
                    {
                        $CimInstanceClusterName = @{
                            Namespace = 'root/MSCluster'
                            ClassName = 'MSCluster_Resource'
                            Filter = 'Name = "Cluster Name"'
                            Verbose = $false
                        }
                        $ClusterProperties = (Get-CimInstance @CimInstanceClusterName -ErrorAction:'SilentlyContinue').PrivateProperties

                        # Registry key that stores SQL instance information
                        $SSDiscoveryRegPath = "$sqlServerBaseRegistry\Instance Names\SQL"

                        # Get the instances from the registry
                        Get-ItemProperty -Path $SSDiscoveryRegPath -ErrorAction:Stop |
                            Get-Member -MemberType NoteProperty |
                            Where-Object -Property Name -NotIn $excludeProperties |
                            ForEach-Object -Process {
                                $Time = Get-Date -Format 'HH:mm:ss.ffff'
                                Write-Verbose "[$Time]On $LocalHost, found SQL Server instance [$($_.Name)]"
                                $instanceId = ((Get-ItemProperty -Path $SSDiscoveryRegPath -Name $_.Name).$($_.Name))

                                # Get the Setup information about this instance
                                $instanceSetupPath = "$sqlServerBaseRegistry\$instanceId\Setup"
                                $instanceSetup = Get-ItemProperty -Path $instanceSetupPath
                                $PatchLevel = [System.Version]$instanceSetup.PatchLevel

                                # Open the instance settings key
                                $InstanceSettingsPath = "$sqlServerBaseRegistry\$instanceId\MSSQLServer"
                                $instanceSettings = Get-ItemProperty -Path $InstanceSettingsPath

                                #Validate if Hadr is enabled
                                $AvailabilityGroups = @()
                                if ($PatchLevel.Major -ge 11)
                                {
                                    $Hadr = Get-ItemProperty -Path "$sqlServerBaseRegistry\$instanceId\MSSQLServer\HADR"
                                    $HadrEnabled = $Hadr.HADR_Enabled -as [bool]
                                    if ($HadrEnabled)
                                    {
                                        $CimInstance = @{
                                            Namespace = 'root/MSCluster'
                                            ClassName = 'MSCluster_Resource'
                                            Filter = 'Type = "SQL Server Availability Group"'
                                            Verbose = $false
                                        }
                                        $AvailabilityGroups = Get-CimInstance @CimInstance | ForEach-Object {
                                            $CimInstanceNetworkName = @{
                                                Namespace = 'root/MSCluster'
                                                ClassName = 'MSCluster_Resource'
                                                Filter = "Type = 'Network Name' and OwnerGroup = '$($_.OwnerGroup)'"
                                                Verbose = $false
                                            }
                                            $PrivateProperties = (Get-CimInstance @CimInstanceNetworkName).PrivateProperties

                                            <#
                                                TODO: The possibility exists that 2 instances exist on a computer and
                                                both are AG members. This code does not currently validate association.
                                            #>
                                            [PSCustomObject]@{
                                                Name = $_.Name
                                                Listener = '{0}.{1}' -f $PrivateProperties.DnsName, $PrivateProperties.DnsSuffix
                                                DnsName = $PrivateProperties.DnsName
                                                DnsSuffix = $PrivateProperties.DnsSuffix
                                            }
                                        }
                                    }
                                }
                                else
                                {
                                    $HadrEnabled = $false
                                }

                                # Determine whether it is clustered
                                $Time = Get-Date -Format 'HH:mm:ss.ffff'
                                if ($instanceSetup.SQLCluster -eq 1)
                                {
                                    Write-Verbose "[$Time] (Clustered instance detected)"
                                    $isClustered = $true
                                    $ClusterRegPath = "$sqlServerBaseRegistry\$instanceId\Cluster\"
                                    $clusterName = (Get-ItemProperty -Path $ClusterRegPath).ClusterName
                                    $Time = Get-Date -Format 'HH:mm:ss.ffff'
                                    Write-Debug "[$Time]Querying cluster for instance information"
                                    # Get the information about the cluster nodes
                                    $CimInstance = @{
                                        Namespace = 'root/MSCluster'
                                        ClassName = 'MSCluster_Resource'
                                        Filter = 'Type = "SQL Server"'
                                        Verbose = $false
                                    }
                                    $clusteredInstance = Get-CimInstance @CimInstance | Where-Object -FilterScript {
                                        $_.PrivateProperties.VirtualServerName -eq $clusterName
                                    }
                                    $Time = Get-Date -Format 'HH:mm:ss.ffff'
                                    Write-Debug "[$Time]Getting possible owners"
                                    # Get a listing of possible owners from the cluster
                                    $CimAssociatedInstance = @{
                                        Association = 'MSCluster_ResourceToPossibleOwner'
                                        KeyOnly = $true
                                        Verbose = $false
                                    }
                                    $possibleOwners = $clusteredInstance |
                                        Get-CimAssociatedInstance @CimAssociatedInstance |
                                        ForEach-Object { [System.Net.Dns]::GetHostEntry($_.Name).Hostname }
                                    # We're done using the short name. Return the FQDN for the final output.
                                    $clusterName = [System.Net.Dns]::GetHostEntry($clusterName).Hostname
                                }
                                else
                                {
                                    Write-Verbose "[$Time] (Standalone instance detected)"
                                    $isClustered = $false
                                    $clusterName = ''
                                    $possibleOwners = @($LocalHost)
                                }

                                if ($ClusterProperties)
                                {
                                    $BaseCluster = [System.Net.Dns]::GetHostEntry($ClusterProperties.DnsName).Hostname
                                }

                                [PSCustomObject]@{
                                    ComputerName = $LocalHost
                                    Product = 'SqlServer'
                                    PatchLevel = $PatchLevel
                                    ProductVersion = $PatchLevel
                                    Edition = $instanceSetup.Edition
                                    InstanceName = $_.Name
                                    InstanceId = $instanceId
                                    Directories = @{
                                        BackupDirectory = $instanceSettings.BackupDirectory
                                        DefaultDataDirectory = $instanceSettings.DefaultData
                                        DefaultLogDirectory = $instanceSettings.DefaultLog
                                    }
                                    IsHadrEnabled = $HadrEnabled
                                    Cluster = @{
                                        IsClustered = $isClustered
                                        ClusterName = $clusterName
                                        PossibleOwners = $possibleOwners
                                        BaseCluster = $BaseCluster
                                    }
                                    AvailabilityGroups = $AvailabilityGroups
                                }
                            }
                    }
                }
            }
        }
        $LocalHostTest = $ComputerName | Where-Object { $_ -match "^$($env:ComputerName)(\.[a-zA-Z0-9-]+)*$" }
        if ($false -eq [string]::IsNullOrEmpty($LocalHostTest))
        {
            $Localhost = $LocalHostTest
        }
        $ComputerList = $ComputerName | Where-Object { $_ -ne $Localhost }
        if ($false -eq [string]::IsNullOrEmpty($ComputerList))
        {
            $InvokeCommand = @{
                ComputerName = $ComputerList
                ScriptBlock = $ScriptBlock
                ArgumentList = @($Product, $VerbosePreference)
            }
            $InstalledProducts += Invoke-Command @InvokeCommand
        }
        if ($false -eq [string]::IsNullOrEmpty($Localhost))
        {
            $InvokeCommand = @{
                ScriptBlock = $ScriptBlock
                ArgumentList = @($Product, $VerbosePreference)
            }
            $InstalledProducts += Invoke-Command @InvokeCommand
        }
    }

    End
    {
        foreach ($InstalledProduct in $InstalledProducts)
        {
            $TargetComputer = $InstalledProduct.PSComputerName
            if ([string]::IsNullOrEmpty($TargetComputer))
            {
                $TargetComputer = $Localhost
            }
            $TargetComputer = (Split-SqlServer -SqlServer $TargetComputer).SqlServerDNSName
            switch ( $InstalledProduct.Product )
            {
                'SqlServer'
                {
                    $InstanceName = $InstalledProduct.InstanceName
                    $Message = "On $($InstalledProduct.ComputerName), found SQL Server instance [$InstanceName]"
                    if ($InstalledProduct.Cluster.IsClustered)
                    {
                        $Message = $Message + ' (Clustered)'
                    }
                    else
                    {
                        $Message = $Message + ' (Standalone)'
                    }
                    Write-Message -Stream 'Log' -Message $Message

                    $AvailabilityGroups = foreach ($AvailabilityGroup in $InstalledProduct.AvailabilityGroups)
                    {
                        [SqlAvailabilityGroup]::new(
                            $AvailabilityGroup.Name,
                            $AvailabilityGroup.Listener,
                            $AvailabilityGroup.DnsName,
                            $AvailabilityGroup.DnsSuffix
                        )
                    }

                    [SqlServerComponent]::New(
                        $TargetComputer,
                        $InstalledProduct.ComputerName,
                        $InstalledProduct.Product,
                        $InstalledProduct.PatchLevel,
                        $InstalledProduct.ProductVersion,
                        $InstalledProduct.Edition,
                        $InstalledProduct.InstanceName,
                        $InstalledProduct.InstanceId,
                        @{
                            BackupDirectory = $InstalledProduct.Directories.BackupDirectory
                            DefaultDataDirectory = $InstalledProduct.Directories.DefaultDataDirectory
                            DefaultLogDirectory = $InstalledProduct.Directories.DefaultLogDirectory
                        },
                        $InstalledProduct.IsHadrEnabled,
                        @{
                            IsClustered = $InstalledProduct.Cluster.IsClustered
                            ClusterName = $InstalledProduct.Cluster.ClusterName
                            PossibleOwners = $InstalledProduct.Cluster.PossibleOwners
                            BaseCluster = $InstalledProduct.Cluster.BaseCluster
                        },
                        $AvailabilityGroups
                    )
                }

                'ReportServer'
                {
                    $InstanceName = $InstalledProduct.InstanceName
                    $Message = "On $($InstalledProduct.ComputerName), found Report Server instance [$InstanceName]"
                    Write-Message -Stream 'Log' -Message $Message

                    [SqlReportServerComponent]::New(
                        $TargetComputer,
                        $InstalledProduct.ComputerName,
                        $InstalledProduct.Product,
                        $InstalledProduct.PatchLevel,
                        $InstalledProduct.ProductVersion,
                        $InstalledProduct.Edition,
                        $InstalledProduct.InstanceName,
                        $InstalledProduct.InstanceId,
                        $InstalledProduct.RSVirtualRootWebApp,
                        $InstalledProduct.RSVirtualRootServer
                    )
                }

                Default
                {
                    [SqlComponent]::New(
                        $TargetComputer,
                        $InstalledProduct.ComputerName,
                        $InstalledProduct.Product,
                        $InstalledProduct.PatchLevel,
                        $InstalledProduct.ProductVersion,
                        $InstalledProduct.Edition
                    )
                }
            }
        }
    }
}