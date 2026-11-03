<#
    .SYNOPSIS
        Retrieves available MECM installs from the target servers.
    .PARAMETER ComputerName
        The target Windows computer.
    .PARAMETER PatchName
        A filter used to match against the patch name(s). This manual filter can be used instead of 'Product'
    .PARAMETER PatchDescription
        A filter used to match against the patch description(s). This manual filter can be used instead of 'Product'
    .PARAMETER Product
        A pre-defined filter setup to match SQL Server or SSMS installs. Possible values: SqlServer or SSMS
    .NOTES
        The output will show all installs that are being advertised by the MECM (SCCM) software.
        # CCM_SoftwareUpdate Client WMI Class Documentation
        # https://learn.microsoft.com/en-us/mem/configmgr/develop/reference/core/clients/sdk/ccm_softwareupdate-client-wmi-class
#>
function Get-MecmPatchStatus
{
    [CmdletBinding(DefaultParameterSetName = 'Manual')]
    param
    (
        [Alias('CN', 'Computer')]
        [Parameter(ValueFromPipeline = $true)]
        [String[]]
        $ComputerName = $env:COMPUTERNAME,

        [Parameter(ParameterSetName = 'Manual')]
        [String]
        $PatchName,

        [Parameter(ParameterSetName = 'Manual')]
        [String]
        $PatchDescription,

        [Parameter(ParameterSetName = 'Product')]
        [ValidateSet('SqlServer', 'SSMS')]
        [String]
        $Product,

        [Parameter()]
        [switch]
        $UseWMI
    )

    Begin
    {
        if ($PSCmdlet.ParameterSetName -eq 'Manual')
        {
            $GetPatchByFilter = @{
                PatchName = $PatchName
                PatchDescription = $PatchDescription
            }
        }
        else
        {
            $GetPatchByFilter = @{
                Product = $Product
            }
        }

        $Updates = New-Object -TypeName System.Collections.ArrayList
        $ComputerNames = New-Object -TypeName System.Collections.ArrayList
    }

    Process
    {
        # This solves a loopback issue in the code below.
        $LocalHostTest = $ComputerName | Where-Object { $_ -match "^$($env:ComputerName)(\.[a-zA-Z0-9-]+)*$" }
        if ($false -eq [string]::IsNullOrEmpty($LocalHostTest))
        {
            $Localhost = $LocalHostTest
        }
        $ComputerNames += $ComputerName -replace "^$($env:ComputerName)(\.[a-zA-Z0-9-]+)*$", 'localhost'
    }

    End
    {
        # We're doing this to improve the output.
        $ComputerList = $ComputerNames -join ', ' -replace 'localhost', $Localhost
        $Message = "Querying [$ComputerList] for any installs that are advertised by MECM (SCCM)."
        Write-Message -Stream 'Debug' -Message $Message

        $FQDNs = $ComputerNames | ForEach-Object {
            (Split-SqlServer -SqlServer ($_ -replace 'localhost', $Localhost) ).SqlServerDNSName
        }

        if ($UseWMI.IsPresent)
        {
            $CCM_SoftwareUpdate = @{
                Class = 'CCM_SoftwareUpdate'
                Namespace = 'root\ccm\ClientSDK'
                Verbose = $false
            }

            try
            {
                $Patches = Get-WmiObject -ComputerName $ComputerNames @CCM_SoftwareUpdate -ErrorAction 'Stop'
            }
            catch
            {
                $Patches = $ComputerNames | ForEach-Object {
                    try
                    {
                        $Computer = $_
                        Get-WmiObject -ComputerName $Computer @CCM_SoftwareUpdate -ErrorAction 'Stop'
                    }
                    catch
                    {
                        $Message = "Failed to retrieve patch info from  [$Computer]. No results will be returned!"
                        Write-Message -Stream 'Error' -Message $Message
                    }
                }
            }
        }
        else
        {
            $CCM_SoftwareUpdate = @{
                ClassName = 'CCM_SoftwareUpdate'
                Namespace = 'root\ccm\ClientSDK'
                Verbose = $false
            }

            try
            {
                $Patches = Get-CimInstance -ComputerName $ComputerNames @CCM_SoftwareUpdate -ErrorAction 'Stop'
            }
            catch
            {
                $Patches = $ComputerNames | ForEach-Object {
                    try
                    {
                        $Computer = $_
                        Get-CimInstance -ComputerName $Computer @CCM_SoftwareUpdate -ErrorAction 'Stop'
                    }
                    catch
                    {
                        $Message = "Failed to retrieve patch info from  [$Computer]. No results will be returned!"
                        Write-Message -Stream 'Error' -Message $Message
                    }
                }
            }
        }

        foreach ($Patch in $Patches)
        {
            $Computer = ($FQDNs | Where-Object { $_ -Match ($Patch.PSComputerName -replace 'localhost', "^$($env:ComputerName)(\.[a-zA-Z0-9-]+)*$") })
            if ([string]::IsNullOrEmpty($Computer))
            {
                $Computer = $Patch.PSComputerName
            }

            # Creates custom object for output.
            $computerPSObject = [PSCustomObject]@{
                ComputerName = $Computer
                PatchName = $Patch.Name
                PatchDescription = $Patch.Description
                Status = switch ($Patch.EvaluationState)
                {
                    0 { 'Available' }
                    1 { 'Available' }
                    2 { 'Submitted' }
                    3 { 'Detecting' }
                    4 { 'PreDownload' }
                    5 { "Downloading ($($Patch.PercentComplete)%)" }
                    6 { 'Waiting' }
                    7 { "Installing ($($Patch.PercentComplete)%)" }
                    8 { 'Reboot Required (Soft)' }
                    9 { 'Reboot Required (Hard)' }
                    10 { 'Wait Reboot' }
                    11 { 'Verifying' }
                    12 { 'Install Complete' }
                    13 { 'Error' }
                    14 { 'Wait Service Window' }
                    15 { 'Wait User Logon' }
                    16 { 'Wait User Logoff' }
                    17 { 'Wait Job User Logon' }
                    18 { 'Wait User Reconnect' }
                    19 { 'Pending User Logoff' }
                    20 { 'Pending Update' }
                    21 { 'Waiting Retry' }
                    22 { 'Waiting Presentation Mode Off' }
                    23 { 'Waiting For Orchestration' }
                    Default { 'Undefined' }
                }
                CCM_SoftwareUpdate = $Patch
            }
            $Updates += $computerPSObject
        }

        $Updates | ForEach-Object {
            $Message = 'MECM: [{0}], PatchName: [{1}], ArticleID: [{2}], EvaluationState: [{3}], PercentComplete: [{4}]'
            $Update = $_.CCM_SoftwareUpdate
            $Message = $Message -f $_.ComputerName, $_.PatchName, $Update.ArticleID, $Update.EvaluationState, $Update.PercentComplete
            Write-Message -Stream 'Debug' -Message $Message
            return $_
        } | Get-MecmPatchByFilter @GetPatchByFilter
    }
}