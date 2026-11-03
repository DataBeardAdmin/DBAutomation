<#
    .SYNOPSIS
    This script is used for pulling down updates from a file share and patching SQL Server, SSMS, or Report Server.

    .DESCRIPTION
    This script will sync updates from a remote file share 'RemoteSource' to a folder on the local server
    'LocalDestination' and then install updates for either SQL Server, SSMS, or Report Server. The process will
    sort the files in the 'LocalDestination' by 'ProductVersion' and attempt to install anything with a version
    greater than the version reported by the target 'Product' for the given server(s)

    .PARAMETER Product
    Specifies the product to be updated. Possible values: SqlServer, SSMS, or ReportServer.

    .PARAMETER SqlServer
    Specifies a connection to SQL. This can be either a stand-alone server, an Availability Group listener, or a
    Failover Cluster Instance.

    .PARAMETER RemoteSource
    The file server remote to the target ComputerNames. This directory will be synced to LocalDestination

    .PARAMETER LocalDestination
    This is the local folder path on the server you are installing the patch on where the patches will be staged
    for this install

    .PARAMETER Credential
    If desired, a PSCredential object can be passed into the script to prevent being prompted for it during the
    process.

    .PARAMETER NoRestart
    This switch is targeted for SSMS installs and will not reboot the target computer(s) before or after the
    install(s).

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        SqlServer = 'SqlServer'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SqlServer'
        SqlServer = 'SqlServerAvailabilityGroupListener'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'SSMS'
        SqlServer = 'SqlServer'
        RemoteSource = '\\FileServer\SSMS'
        LocalDestination = 'D:\SqlUpdates'
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate -NoRestart -Verbose

    .EXAMPLE
    $InvokeSqlUpdate = @{
        Product = 'ReportServer'
        SqlServer = 'ReportServer1'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\ReportServer'
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate -Verbose

    .EXAMPLE
    $GetCredential = @{
        Message = 'SQL Server installation account'
        UserName = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    }
    $Credential = Get-Credential @GetCredential

    $InvokeSqlUpdate1 = @{
        Product = 'SqlServer'
        SqlServer = 'SqlServer1'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
        Credential = $Credential
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate1 -Verbose

    $InvokeSqlUpdate2 = @{
        Product = 'SqlServer'
        SqlServer = 'SqlServer2'
        RemoteSource = '\\FileServer\Share'
        LocalDestination = 'D:\SqlUpdates'
        Credential = $Credential
    }
    .\Invoke-SqlUpdate @InvokeSqlUpdate2 -Verbose
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
    [String]
    $Product,

    [Alias('ComputerName', 'Listener')]
    [Parameter(Mandatory = $true)]
    [System.String]
    $SqlServer,

    [Parameter(Mandatory = $true)]
    [System.String]
    $RemoteSource,

    [Parameter(Mandatory = $true)]
    [System.String]
    $LocalDestination,

    [Parameter()]
    [PSCredential]
    $Credential,

    [Parameter()]
    [Switch]
    $NoRestart
)

Import-Module -Name 'DBAutomation' -Verbose:$false

if (-not $Credential)
{
    #This account will be used to connect to the remote server for copying updates to the local server.
    #This is done to avoid a double-hop.
    $GetCredential = @{
        Message = 'SQL Server installation account'
        UserName = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    }
    $Credential = Get-Credential @GetCredential
}

if ($Product -eq 'SSMS')
{
    $ComputerNames = $SqlServer
}
elseif ($Product -eq 'ReportServer')
{
    $ComputerNames = Get-ComputerList -ReportServer $SqlServer -Verbose:$VerbosePreference
}
else
{
    $SqlServerList = Get-ComputerList -SqlServer $SqlServer -Verbose:$VerbosePreference
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

$SyncFolders = @{
    ComputerNames = $ComputerNames
    Credential = $Credential
    RemoteSource = $RemoteSource
    LocalDestination = $LocalDestination
}
Sync-Folders @SyncFolders -Verbose:$VerbosePreference

# Install-SqlUpdate does not currently utilize instance names, so we can just pass in the base server (clustered or not)
$InstallSqlUpdate = @{
    Product = $Product
    ComputerName = $ComputerNames
    UpdatePath = $LocalDestination
    NoRestart = $NoRestart.IsPresent
    InformationAction = $InformationPreference
}
Install-SqlUpdate @InstallSqlUpdate -Verbose:$VerbosePreference
