<#
    .SYNOPSIS
    This script is used for kicking off multiple threads to patch SQL Server, SSMS, or Report Server.

    .DESCRIPTION
    This script will kick off multiple threads for installing updates for either SQL Server, SSMS, or Report Server.
    The process will sort the files in the 'UpdatePath' by 'ProductVersion' and attempt to install anything
    with a version greater than the version reported by the target 'Product' for the given server(s).

    .PARAMETER Product
    Specifies the product to be updated. Possible values: SqlServer, SSMS, or ReportServer.

    .PARAMETER CSV
    Specifies a path to a text file with a list of servers in the format:
    Server1
    Server2

    .PARAMETER SqlServer
    Specifies a connection to SQL. This can be either a stand-alone server, an Availability Group listener, or a
    Failover Cluster Instance.
    Multiple instances can be passed in and each will be handled in parallel.

    .PARAMETER EnableCertificateFailback
    The connection will be made using the 'TrustServerCertificate' setting if the cert isn't a trusted chain.

    .PARAMETER UseMECM
    Install patches advertised in MECM (SCCM).

    .PARAMETER RemoteSource
    If not using MECM, the file server remote to the target ComputerNames. This directory will be synced to LocalDestination

    .PARAMETER LocalDestination
    If not using MECM, this is the local folder path on the server you are installing the patch on where the patches
    will be staged for this install

    .PARAMETER Credential
    If desired, a PSCredential object can be passed into the script to prevent being prompted for it during the
    process.

    .PARAMETER NoRestart
    This switch is targeted for SSMS installs and will not reboot the target computer(s) before or after the
    install(s).

    .PARAMETER Foreground
    This switch will spawn each install into a new PowerShell window instead of using background jobs.

    .NOTES
    If using Availability Groups, use the listener to patch both nodes (or only include the secondaries).
    Providing both nodes can take down the Availability Group as both nodes will attempt to patch simultaneously.
    Providing a primary server only will cause a failover and will not patch the secondary.

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        CSV = 'D:\ServerList.csv'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        SqlServer = @('StandAloneSqlServer1', 'StandAloneSqlServer2')
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        SqlServer = @('SqlServerAvailabilityGroupListener1', 'SqlServerAvailabilityGroupListener2')
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        SqlServer = @('SqlServerAvailabilityGroupListener1', 'SqlServerAvailabilityGroupListener2')
        UseMECM = $true
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SSMS'
        SqlServer = @('SqlServer1', 'SqlServer2')
        RemoteSource = '\\FileServer\SSMS'
        LocalDestination = 'D:\SSMS'
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -NoRestart -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'ReportServer'
        SqlServer = @('ReportServerFromFarm1', 'ReportServerFromFarm2')
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\ReportServer'
    }
    .\Start-SqlUpdateProcesses.ps1 @InvokeSqlUpdate -Verbose
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
    [String]
    $Product,

    [Parameter(
        Mandatory = $true,
        ParameterSetName = 'CSV')]
    [System.String]
    $CSV,

    [Parameter(
        Mandatory = $true,
        ParameterSetName = 'List')]
    [Alias('ComputerName', 'ListenerList', 'Listeners', 'Listener')]
    [System.String[]]
    $SqlServer,

    [Parameter()]
    [Switch]
    $EnableCertificateFailback,

    [Alias('UseSCCM')]
    [Parameter()]
    [Switch]
    $UseMECM,

    [Parameter()]
    [System.String]
    $RemoteSource,

    [Parameter()]
    [System.String]
    $LocalDestination,

    [Parameter()]
    [PSCredential]
    $Credential,

    [Parameter()]
    [Switch]
    $NoRestart,

    [Parameter()]
    [Switch]
    $Foreground
)

if ($false -eq $UseMECM.IsPresent -and
    ([string]::IsNullOrEmpty($RemoteSource) -or [string]::IsNullOrEmpty($LocalDestination)))
{
    $Message = '[RemoteSource] and [LocalDestination] must be specified if [UseMECM] is not specified!'
    Write-Message -Stream 'Log' -Message $Message
    throw $message
}

Import-Module -Name 'DBAutomation' -Verbose:$false

if ($PSCmdlet.ParameterSetName -eq 'CSV')
{
    $SqlServer = Import-Csv -Path $CSV -Header 'Servers' | Select-Object -ExpandProperty 'Servers'
}

if (-not $Credential -and $false -eq $UseMECM.IsPresent)
{
    #This account will be used to connect to the remote server for copying updates to the local server.
    #This is done to avoid a double-hop.
    $GetCredential = @{
        Message = 'SQL Server installation account'
        UserName = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    }
    $Credential = Get-Credential @GetCredential
}

$LogConfiguration = Get-LoggingConfiguration
$ConnectionOptions = Get-SqlConnectionOptions
$ECF = $ConnectionOptions.EnableCertificateFailback -or $EnableCertificateFailback.IsPresent

# Path to PowerShell
$PowerShellPath = Get-Command -Name powershell.exe | Select-Object -ExpandProperty Path

$InstallScript = {
    param
    (
        $Product,
        $SqlServerInstance,
        $UseMECM,
        $ECF,
        $RemoteSource,
        $LocalDestination,
        $TempFile,
        $NoRestart,
        $LogConfigurationDirectory,
        $LogConfigurationFile,
        $LogConfigurationDisable,
        $Foreground,
        $RequestedDebugPreference,
        $RequestedVerbosePreference,
        $RequestedInformationPreference
    )

    $Credential = Import-Clixml -Path $TempFile
    Remove-Item -Path $TempFile -Force

    #Because these values are sent in as strings, we need to cast them back to bool.
    $NoRestart = [bool]::parse($NoRestart)
    $Foreground = [bool]::parse($Foreground)
    $UseMECM = [bool]::parse($UseMECM)
    $ECF = [bool]::parse($ECF)

    Import-Module 'DBAutomation'

    #Setup Logging on the child window to match the parent.
    $SetLoggingConfiguration = @{
        Directory = $LogConfigurationDirectory
        File = $LogConfigurationFile
        Disable = [System.Convert]::ToBoolean($LogConfigurationDisable)
        NoLog = $true
    }
    Set-LoggingConfiguration @SetLoggingConfiguration

    if ($true -eq $ECF)
    {
        Set-SqlConnectionOptions -EnableCertificateFailback -Verbose:$VerbosePreference
    }

    $global:DebugPreference = $RequestedDebugPreference
    $global:VerbosePreference = $RequestedVerbosePreference
    $global:InformationPreference = $RequestedInformationPreference

    if ($Product -eq 'SSMS')
    {
        $ComputerNames = $SqlServerInstance
    }
    elseif ($Product -eq 'ReportServer')
    {
        $ComputerNames = Get-ComputerList -ReportServer $SqlServerInstance -Verbose:$VerbosePreference
    }
    else
    {
        $SqlServerList = Get-ComputerList -SqlServer $SqlServerInstance -Verbose:$VerbosePreference
        $ComputerNames = foreach ($SqlServerInstance in $SqlServerList)
        {
            $ComputerName, $null = $SqlServerInstance.Split('\')

            if (Test-IsClusterVNN -SqlServer $SqlServerInstance -Verbose:$VerbosePreference)
            {
                Get-ComputerList -VirtualNetworkName $ComputerName -Verbose:$VerbosePreference
            }
            else
            {
                $ComputerName
            }
        }
    }

    if ($false -eq $UseMECM)
    {
        $SyncFolders = @{
            ComputerNames = $ComputerNames
            Credential = $Credential
            RemoteSource = $RemoteSource
            LocalDestination = $LocalDestination
        }
        Sync-Folders @SyncFolders -Verbose:$VerbosePreference
    }

    if ($false -eq $Foreground)
    {
        Write-Message -Stream 'Verbose' -Message "Begin 'Update [$SqlServerInstance]': $(Get-Date -Format 'yyyy-MM-dd, HH:mm:ss')"
    }

    $InstallSqlUpdate = @{
        Product = $Product
        ComputerName = $ComputerNames
        InformationAction = [System.Management.Automation.ActionPreference]$InformationPreference
    }
    if ($true -eq $NoRestart)
    {
        $InstallSqlUpdate += @{ NoRestart = $true }
    }
    if ($true -eq $UseMECM)
    {
        $InstallSqlUpdate += @{ UseMECM = $true }
    }
    else
    {
        $InstallSqlUpdate += @{ UpdatePath = $LocalDestination }
    }
    if ($VerbosePreference -eq 'Continue')
    {
        #$VerbosePreference is actually an ActionPreference, but the Verbose syntax works this way.
        $InstallSqlUpdate += @{ Verbose = $true }
    }

    $Output = @('Install-SqlUpdate')
    $Output += foreach ($key in $InstallSqlUpdate.Keys)
    {
        $Value = $InstallSqlUpdate[$Key]
        $ParamType = $Value.GetType().Name
        if ($ParamType -in @('String', 'ActionPreference'))
        {
            Write-Output "-$Key `'$Value`'"
        }
        elseif ($ParamType -eq 'Object[]' -and $Value[0].GetType().Name -eq 'String')
        {
            Write-Output "-$Key `'$($Value -join ''',''')`'"
        }
        elseif ($ParamType -eq 'Boolean')
        {
            Write-Output " -$($key):`$$($Value)"
        }
    }

    if ($Foreground)
    {
        #Change the Window Title to the script being run so we know which script is being run in each.
        $host.ui.RawUI.WindowTitle = $($Output -join ' ')
    }

    #If the user is debugging, this will help with being able to re-run a script in the child window.
    Write-Message -Stream 'Debug' -Message $(@('PS>') + $Output -join ' ')

    Install-SqlUpdate @InstallSqlUpdate

    if ($false -eq $Foreground)
    {
        Write-Message -Stream 'Verbose' -Message "End 'Update [$SqlServerInstance]': $(Get-Date -Format 'yyyy-MM-dd, HH:mm:ss')"
    }
}

# Loop over the target SqlServers
$InstallJobs = @()
foreach ($SqlServerInstance in $SqlServer)
{
    if ($UseMECM.IsPresent)
    {
        $tempPassPhrase = Get-Random -Count 32 -InputObject @(33..33 + 35..38 + 42..46 + 48..57 + 65..90 + 97..122) |
            ForEach-Object -Begin { $aa = $null } -Process { $aa += [char]$_ } -End { $aa } |
            ConvertTo-SecureString -AsPlainText -Force
        $Credential = [PSCredential]::new('EMPTY', $tempPassPhrase)
        $RemoteSource = 'EMPTY'
        $LocalDestination = 'EMPTY'
    }

    $TempFile = [System.IO.Path]::GetTempFileName()
    $Credential | Export-Clixml -Path $TempFile

    if ($Foreground.IsPresent)
    {
        $processParameters = @{
            FilePath = $PowerShellPath
            WorkingDirectory = $PSScriptRoot
            Verb = 'RunAs'
            ArgumentList = @(
                '-NoExit'
                '-WindowStyle Normal'
                "-Command & { $InstallScript }"
                $Product
                $SqlServerInstance
                $UseMECM
                $ECF
                "{$RemoteSource}"
                $LocalDestination
                $TempFile
                $NoRestart.IsPresent
                $LogConfiguration.Directory
                $LogConfiguration.File
                $LogConfiguration.Disable
                $Foreground.IsPresent
                $DebugPreference
                $VerbosePreference
                $InformationPreference
            )
        }

        # Spawn the PowerShell process
        Start-Process @processParameters
    }
    else
    {
        $InstallJobs += Start-Job -Name "Update [$SqlServerInstance]" -ScriptBlock $InstallScript -ArgumentList $Product,
        $SqlServerInstance,
        $UseMECM,
        $ECF,
        $RemoteSource,
        $LocalDestination,
        $TempFile,
        $NoRestart.IsPresent,
        $LogConfiguration.Directory,
        $LogConfiguration.File,
        $LogConfiguration.Disable,
        $Foreground.IsPresent,
        $DebugPreference,
        $VerbosePreference,
        $InformationPreference
    }
}

if ($InstallJobs.Count -gt 0)
{
    Wait-ParallelCommand -Jobs $InstallJobs -OutputResults -Verbose:$VerbosePreference
}
