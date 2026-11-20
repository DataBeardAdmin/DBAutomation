<#
    .SYNOPSIS
    This function is used for patching SQL Server, SSMS, or Report Server.

    .DESCRIPTION
    This function will install updates for either SQL Server, SSMS, or Report Server.
    The process will sort the files in the 'UpdatePath' by 'ProductVersion' and attempt to install anything
    with a version greater than the version reported by the target 'Product' for the given server(s).

    .PARAMETER Product
    Specifies the product to be updated. Possible values: SqlServer, SSMS, or ReportServer.

    .PARAMETER ComputerName
    The computer running an instance of SQL that that you are connecting to.

    .PARAMETER InstanceName
    The name of the instance you are connecting to.

    .PARAMETER SqlServer
    Specifies a connection to SQL. This can be either a stand-alone server, an Availability Group listener, or a
    Failover Cluster Instance.

    .PARAMETER ReportServer
    Specifies a computer name to a Report Server.

    .PARAMETER ExpandReportServer
    When specified, the computer expansion function will take any member server and return all report servers. This is needed because
    scale out report server's cannot be defined by a traditional "listener" (outside of a load balancer which the report servers may or
    may not know about).

    .PARAMETER ComputerName
    Specifies a computer name. This can be a node of a WSFC, and not a SQL endpoint such as a cluster VNN.

    .PARAMETER UpdatePath
    This is the folder path relative to the server you are installing the patch on (typically a local drive/folder)
    where the patches have been staged for this install

    .PARAMETER UseMECM
    Option to use Microsoft Endpoint Configuration Manager instead of patches on the local filesystem.

    .PARAMETER NoRestart
    This switch is targeted for SSMS installs and will not reboot the target computer(s) before or after the install(s).

    .PARAMETER InstallPath
    This switch is targeted for SSMS installs only and allows you to chose the install path.

    .NOTES
    This is often used in combination with 'Sync-Folders' which will assist in copying the patches from a remote
    source to a local directory.

    .EXAMPLE
    Install-SqlUpdate -Product 'SqlServer' -SqlServer 'SqlServer' -UpdatePath 'D:\SqlUpdates' -Verbose

    .EXAMPLE
    Install-SqlUpdate -Product 'SSMS' -SqlServer 'SqlServer' -UpdatePath 'D:\SSMS' -NoRestart -Verbose
#>

function Install-SqlUpdate
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
        [Products]
        $Product,

        [Alias('Listener', 'VirtualNetworkName')]
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String[]]
        $SqlServer,

        [Parameter(ParameterSetName = 'ReportServer', Mandatory = $true)]
        [String[]]
        $ReportServer,

        [Parameter(ParameterSetName = 'ReportServer')]
        [Switch]
        $ExpandReportServer,

        [Alias('ClusterNode')]
        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String[]]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName,

        [Parameter()]
        [String]
        $UpdatePath,

        [Alias('UseSCCM')]
        [Parameter()]
        [Switch]
        $UseMECM,

        [Parameter()]
        [Switch]
        $NoRestart,

        [Parameter()]
        [string]
        $InstallPath
    )

    if ($false -eq $UseMECM.IsPresent -and [string]::IsNullOrEmpty($UpdatePath))
    {
        $Message = '[UpdatePath] must be specified if [UseMECM] is not specified!'
        Write-Message -Stream 'Log' -Message $Message
        throw $message
    }

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $SqlServerList = foreach ($member in $SqlServer)
        {
            Get-ComputerList -SqlServer $member -Verbose:$VerbosePreference
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ReportServer')
    {
        if ($ExpandReportServer.IsPresent)
        {
            $SqlServerList = foreach ($member in $ReportServer)
            {
                Get-ComputerList -ReportServer $member -Verbose:$VerbosePreference
            }
        }
        else
        {
            $SqlServerList = $ReportServer
        }
    }
    else
    {
        $SqlServerList = $ComputerName
    }

    foreach ($SqlServerInstance in $SqlServerList)
    {
        $availableUpdates = @()

        $SqlServerInfo = Split-SqlServer -SqlServer $SqlServerInstance -Verbose:$VerbosePreference
        $SqlServerDNSName = $SqlServerInfo.SqlServerDNSName
        if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
        {
            $InstanceName = $SqlServerInfo.InstanceName
        }

        $SqlServerComponent = Find-SqlComponents -ComputerName $SqlServerDNSName -Product 'SqlServer' -Verbose:$VerbosePreference
        if ($SqlServerComponent)
        {
            if (Test-IsAlias -SqlServerComponent $SqlServerComponent)
            {
                $Message = "A connection to [$SqlServerInstance] resulted in a different computer name. Please use the actual computer name."
                Write-Message -Stream 'Log' -Message $Message
                throw $Message
            }
            if (Test-IsClusterName -SqlServerComponent $SqlServerComponent)
            {
                $Message = "[$SqlServerInstance] is a cluster. Please specify either the SQL instance or cluster node(s) instead."
                Write-Message -Stream 'Log' -Message $Message
                throw $Message
            }

            if (Test-IsClusterVNN -SqlServerComponent $SqlServerComponent)
            {
                $ComputerNames = Get-ComputerList -VirtualNetworkName $SqlServerDNSName -Verbose:$VerbosePreference
                $IsClusterMember = $true
            }
            else
            {
                $ComputerNames = @($SqlServerDNSName)
                # Because of how this is used, we care if this node is a member of *any* cluster.
                $IsClusterMember = @(($SqlServerComponent.Cluster |
                            Where-Object { $_.PossibleOwners -contains $SqlServerDNSName }).IsClustered).Contains($true)
            }
        }
        else
        {
            $ComputerNames = @($SqlServerDNSName)
        }

        foreach ($Computer in $ComputerNames)
        {
            if ($UseMECM.IsPresent)
            {
                $GetAvailableUpdates = @{
                    ComputerName = $Computer
                    Product = $Product
                    UseWMI = $true
                    ErrorAction = [System.Management.Automation.ActionPreference]'Stop'
                }
                [System.Array]$availableUpdates = Get-MecmPatchStatus @GetAvailableUpdates -Verbose:$VerbosePreference
            }
            else
            {
                # Gather a listing of updates that are available to be applied, sorted by version
                $GetAvailableUpdates = @{
                    ComputerName = $Computer
                    UpdatePath = $UpdatePath
                }
                if ($Product -eq 'SSMS')
                {
                    $GetAvailableUpdates += @{
                        SingleUpdate = $true
                    }
                }
                [System.Array]$availableUpdates = Get-AvailableUpdates @GetAvailableUpdates -Verbose:$VerbosePreference
            }

            if ($NoRestart.IsPresent)
            {
                $RestartCheck = $false
            }
            else
            {
                $RestartCheck = $true
            }

            $UpdateCount = $availableUpdates.Count
            if ($UpdateCount -lt 1)
            {
                Write-Message -Stream 'Verbose' -Message "No [$Product] patches found on [$Computer]!"
            }

            # Try installing the update(s)
            if ($UseMECM.IsPresent -and $UpdateCount -ge 1)
            {
                #Region Patch preparation
                $ProductInfo = Get-ProductInfo -ComputerName $Computer -Product $Product -Verbose:$VerbosePreference

                if ($false -eq [string]::IsNullOrEmpty($ProductInfo.SqlServer))
                {
                    $SqlServerInstance = $ProductInfo.SqlServer
                }
                $RestartSqlServerParams = $ProductInfo.RestartSqlServerParams

                #Verify the computer is ready for install.
                if ($RestartCheck)
                {
                    Restart-SqlServer @RestartSqlServerParams -Verbose:$VerbosePreference
                }

                <#
                    Installing a SQL Server patch will restart the affected instance,
                    so a planned failover should be performed even if NoRestart is specified.
                #>
                if (-not $NoRestart.IsPresent -or $Product -eq 'SqlServer')
                {
                    if ($NoRestart.IsPresent)
                    {
                        $Message = 'Availability Groups with automatic failover will be moved to the first available secondary.'
                        Write-Message -Stream 'Warning' -Message $Message
                    }
                    if ($ProductInfo.IsSqlServerInstalled)
                    {
                        Set-AvailabilityReplica -SqlServer $SqlServerInstance -Role 'Secondary' -Verbose:$VerbosePreference
                    }
                }
                $ClusterNodeIsPaused = $false
                if ($IsClusterMember)
                {
                    Suspend-SqlClusterNode -ComputerName $Computer -DrainType 'Drain' -Verbose:$VerbosePreference
                    $ClusterNodeIsPaused = $true
                    if ($ProductInfo.IsClustered)
                    {
                        # TODO: Create Move-SqlClusterNode. Leaving the node paused for patching fails validation.
                        Resume-SqlClusterNode -ComputerName $Computer -Verbose:$VerbosePreference
                        $ClusterNodeIsPaused = $false
                    }
                }
                #endregion

                #Region MECM Patch
                Wait-CcmExec -ComputerName $Computer -Verbose:$VerbosePreference

                $Message = "Applying [$($availableUpdates.PatchName -join '], [')] from MECM on [$Computer]."
                Write-Message -Stream 'Information' -Message $Message

                $i = 1
                foreach ($Update in $availableUpdates)
                {
                    $Retries = 50
                    $RetrySeconds = 30
                    do
                    {
                        try
                        {
                            $CCM_SoftwareUpdatesManager = @{
                                ComputerName = $Computer
                                Class = 'CCM_SoftwareUpdatesManager'
                                Name = 'InstallUpdates'
                                ArgumentList = $Update.CCM_SoftwareUpdate
                                Namespace = 'root\ccm\ClientSDK'
                                Verbose = $false
                            }
                            $null = Invoke-WmiMethod @CCM_SoftwareUpdatesManager
                            Write-Message -Stream 'Verbose' -Message "Started update [$($Update.PatchName)] On [$Computer]"
                            if ($i -lt $UpdateCount)
                            {
                                $Message = 'Waiting 5 seconds before starting next update.'
                                Write-Message -Stream 'Debug' -Message $Message
                                Start-Sleep -Seconds 5
                            }
                            $Retries = 0
                        }
                        catch
                        {
                            $Message = $_.Exception.ToString()
                            if ($Retries -gt 0)
                            {
                                # re-throw the exception
                                Write-Message -Stream 'Debug' -Message $Message
                                Write-Message -Stream 'Warning' -Message "Error starting. Retrying in [$RetrySeconds] seconds."
                                Start-Sleep -Seconds $RetrySeconds
                                $Retries--
                            }
                            else
                            {
                                if ($ClusterNodeIsPaused)
                                {
                                    Resume-SqlClusterNode -ComputerName $Computer -Verbose:$VerbosePreference
                                    $ClusterNodeIsPaused = $false
                                }
                                # re-throw the exception
                                Write-Message -Stream 'Log' -Message $Message
                                throw $Message
                            }
                        }
                    }
                    while ($Retries -gt 0)
                    $i++
                }

                do
                {
                    $PatchStatus = Get-MecmPatchStatus @GetAvailableUpdates -Verbose:$VerbosePreference
                    #We're including state 0 in case no install has started.
                    $InProcess = @($PatchStatus.CCM_SoftwareUpdate.EvaluationState | Where-Object { $_ -in @(0, 4, 5, 6, 7, 11) })
                    if ($InProcess.Count -ge 1)
                    {
                        # If any single update is still running:
                        $InstallRunning = $true
                        Start-Sleep -Seconds 10
                    }
                    else
                    {
                        # If no update is running and there's at least 1 failure:
                        $InstallRunning = $false
                        if ($PatchStatus.CCM_SoftwareUpdate.EvaluationState -contains 13)
                        {
                            $FailedUpdate = $PatchStatus.CCM_SoftwareUpdate | Where-Object { $_.EvaluationState -eq 13 }
                            $Message = 'Install result on [{0}]: Error Code: [{1}]' -f $Computer, $FailedUpdate.ErrorCode
                            Write-Message -Stream 'Warning' -Message $Message
                        }
                    }
                }
                while ($true -eq $InstallRunning)

                Write-Message -Stream 'Verbose' -Message "Install finished on [$Computer]"
                #endregion

                #Region Patch Complete
                if ($ClusterNodeIsPaused)
                {
                    Resume-SqlClusterNode -ComputerName $Computer -Verbose:$VerbosePreference
                }

                # Restart the server after applying the patch but only if the user has not opted out.
                if (-not $NoRestart.IsPresent)
                {
                    Restart-SqlServer @RestartSqlServerParams -Verbose:$VerbosePreference
                }
                #endregion
            }
            else
            {
                $CheckVersion = $true

                foreach ($update in $availableUpdates)
                {
                    $FilePath = $update.FullName
                    $updateVersion = $update.PatchVersion
                    $updateVersionString = $updateVersion.ToString()

                    #Region Patch preparation
                    if ($CheckVersion)
                    {
                        $GetProductInfo = @{
                            ComputerName = $Computer
                            Product = $Product
                        }
                        if ($Product -eq 'SSMS')
                        {
                            #Get-ProductInfo throws an error if the product is not installed, so we need to ignore that error for this scenario.
                            $GetProductInfo += @{
                                ErrorAction = [System.Management.Automation.ActionPreference]'SilentlyContinue'
                            }
                        }
                        $ProductInfo = Get-ProductInfo @GetProductInfo -Verbose:$VerbosePreference
                        $LocalVersion = $ProductInfo.LocalVersion
                        if ($false -eq [string]::IsNullOrEmpty($LocalVersion))
                        {
                            $LocalVersionString = $LocalVersion.ToString()
                        }

                        if ($Product -eq 'SSMS' -and
                            ($LocalVersion.Major -ne $update.PatchVersion.Major -or $true -eq [string]::IsNullOrEmpty($LocalVersion)))
                        {
                            $Mode = 'Install'
                            $LocalVersion = [System.Version]"$($update.PatchVersion.Major).0"
                            $DebugMessage = 'Installer Version {0}'
                        }
                        else
                        {
                            # If SSMS is already installed, we will treat this as an update.
                            $Mode = 'Update'
                            $DebugMessage = "Server Version: $LocalVersionString, Patch Version {0}"
                        }

                        if ($false -eq [string]::IsNullOrEmpty($ProductInfo.SqlServer))
                        {
                            $SqlServerInstance = $ProductInfo.SqlServer
                        }
                        $RestartSqlServerParams = $ProductInfo.RestartSqlServerParams
                        Write-Message -Stream 'Debug' -Message "Mode: [$Mode]"
                    }
                    #endregion

                    if ($Product -eq 'ReportServer' -and $ProductInfo.PatchLevel.Major -le 13)
                    {
                        $Message = 'Product [ReportServer] is only supported for stand-alone Report Server (2017 and higher).'
                        Write-Message -Stream 'Log' -Message $Message
                        throw $Message
                    }

                    if ($LocalVersion.Major -ne $updateVersion.Major)
                    {
                        Write-Message -Stream 'Verbose' -Message "The server's major version is not the same as the patch file [$FilePath]."
                        Write-Message -Stream 'Debug' -Message "Server Version: $LocalVersionString, Patch Version $updateVersionString"
                        $CheckVersion = $false
                    }
                    elseif (
                        ($LocalVersion.Build -ge $updateVersion.Build -and $Product -ne 'SSMS') -or
                        ($LocalVersion -ge $updateVersion -and $Product -eq 'SSMS'))
                    {
                        Write-Message -Stream 'Verbose' -Message "The server's version is greater than or equal to the version of the patch file [$FilePath]."
                        Write-Message -Stream 'Debug' -Message "Server Version: $LocalVersionString, Patch Version $updateVersionString"
                        $CheckVersion = $false
                    }
                    else
                    {
                        Write-Message -Stream 'Verbose' -Message "Getting ready to apply [$FilePath]."
                        Write-Message -Stream 'Debug' -Message ($DebugMessage -f $updateVersionString)

                        #Verify the computer is ready for install.
                        if ($RestartCheck)
                        {
                            Restart-SqlServer @RestartSqlServerParams -Verbose:$VerbosePreference
                        }

                        <#
                            Installing a SQL Server patch will restart the affected instance,
                            so a planned failover should be performed even if NoRestart is specified.
                        #>
                        if (-not $NoRestart.IsPresent -or $Product -eq 'SqlServer')
                        {
                            if ($NoRestart.IsPresent)
                            {
                                $Message = 'Availability Groups with automatic failover will be moved to the first available secondary.'
                                Write-Message -Stream 'Warning' -Message $Message
                            }
                            if ($ProductInfo.IsSqlServerInstalled)
                            {
                                Set-AvailabilityReplica -SqlServer $SqlServerInstance -Role 'Secondary' -Verbose:$VerbosePreference
                            }
                        }
                        $ClusterNodeIsPaused = $false
                        if ($IsClusterMember)
                        {
                            Suspend-SqlClusterNode -ComputerName $Computer -DrainType 'Drain' -Verbose:$VerbosePreference
                            $ClusterNodeIsPaused = $true
                            if ($ProductInfo.IsClustered)
                            {
                                # TODO: Create Move-SqlClusterNode. Leaving the node paused for patching fails validation.
                                Resume-SqlClusterNode -ComputerName $Computer -Verbose:$VerbosePreference
                                $ClusterNodeIsPaused = $false
                            }
                        }

                        $GetSqlInstallArguments = @{
                            Product = $Product
                            MajorVersion = $LocalVersion.Major
                            Mode = $Mode
                            InstallPath = $InstallPath
                        }
                        $InstallArguments = Get-SqlInstallArguments @GetSqlInstallArguments
                        $ExitCodes = Get-SqlExitCodes -Product $Product

                        #Region FileSystem Patch
                        # splat parameters to Start-Process
                        $startProcessParams = @{
                            FilePath = $FilePath
                            ArgumentList = $InstallArguments
                            Verb = 'RunAs'
                            WindowStyle = 'Hidden'
                            Wait = $true
                            PassThru = $true
                        }

                        $resultString = ''
                        Write-Message -Stream 'Information' -Message "Applying [$FilePath] on [$Computer]."
                        Write-Message -Stream 'Verbose' -Message "Install started on [$Computer]"

                        #Perform the install.
                        $ExitCode = Invoke-Command -ScriptBlock {
                            $InstallFolder = Split-Path -Path $using:FilePath -Parent
                            $certPath = Join-Path $InstallFolder 'certificates'
                            if ($using:update.Type -eq 'Manifest' -and $true -eq (Test-Path $certPath -PathType Container))
                            {
                                $certs = @(
                                    'manifestRootCertificate.cer',
                                    'manifestCounterSignRootCertificate.cer',
                                    'vs_installer_opc.RootCertificate.cer',
                                    'Microsoft Windows Code Signing PCA 2024.crt'
                                )

                                foreach ($cert in $certs)
                                {
                                    $fullPath = Join-Path $certPath $cert

                                    if ($true -eq (Test-Path $fullPath) -and $fullPath -match '\.cer$')
                                    {
                                        certutil.exe -addstore -f 'Root' $fullPath | Out-Null
                                    }
                                    elseif ($true -eq (Test-Path $fullPath) -and $fullPath -match '\.crt$')
                                    {
                                        certutil.exe -addstore -f CA $fullPath | Out-Null
                                    }
                                    else
                                    {
                                        Write-Warning "Certificate not found: $fullPath"
                                    }
                                }
                            }

                            $process = Start-Process @using:startProcessParams
                            return $process.ExitCode
                        } -ComputerName $Computer -ErrorAction Stop

                        Write-Message -Stream 'Verbose' -Message "Install finished on [$Computer]"

                        $resultString = $($ExitCodes | Where-Object Code -EQ $ExitCode).resultString
                        if ([String]::IsNullOrEmpty($resultString))
                        {
                            $resultString = 'Unknown'
                        }

                        Write-Message -Stream 'Verbose' -Message "Install result on [$Computer]: $resultString [$ExitCode]"
                        #endregion

                        #Region Patch Complete
                        if ($ClusterNodeIsPaused)
                        {
                            Resume-SqlClusterNode -ComputerName $Computer -Verbose:$VerbosePreference
                        }

                        # Restart the server after applying the patch but only if the user has not opted out.
                        if (-not $NoRestart.IsPresent)
                        {
                            Restart-SqlServer @RestartSqlServerParams -Verbose:$VerbosePreference
                        }
                        #endregion

                        #We just performed an install. Re-evaluate that the next patch is required.
                        $CheckVersion = $true

                        #We're in a foreach loop and we check for pending updates before install.
                        #We are setting this variable to bypass that check to save time since we just handled the reboot above.
                        $RestartCheck = $false
                    }
                }
            }
        }
    }
}