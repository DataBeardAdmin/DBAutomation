<#
.SYNOPSIS
    Gets the pending reboot status on a local or remote computer.

.DESCRIPTION
    This function will query the registry on a local or remote computer and determine if the
    system is pending a reboot, from either Microsoft Patching or a Software Installation.
    For Windows 2008+ the function will query the CBS registry key as another factor in determining
    pending reboot state. "PendingFileRenameOperations" and "Auto Update\RebootRequired" are observed
    as being consistent across Windows Server 2003 & 2008.

    CBServicing = Component Based Servicing (Windows 2008)
    WindowsUpdate = Windows Update / Auto Update (Windows 2003 / 2008)
    CCMClientSDK = SCCM 2012 Clients only (DetermineIfRebootPending method) otherwise $null value
    PendFileRename = PendingFileRenameOperations (Windows 2003 / 2008)

.PARAMETER ComputerName
    Specifies a list of computers to query for pending reboot status. Alternatively, this list can
    be piped in from another command either by name or value. (Default: Local Computer)

.LINK
    Component-Based Servicing:
    http://technet.microsoft.com/en-us/library/cc756291(v=WS.10).aspx

    PendingFileRename/Auto Update:
    http://support.microsoft.com/kb/2723674
    http://technet.microsoft.com/en-us/library/cc960241.aspx
    http://blogs.msdn.com/b/hansr/archive/2006/02/17/patchreboot.aspx

    SCCM 2012/CCM_ClientSDK:
    http://msdn.microsoft.com/en-us/library/jj902723.aspx

.NOTES
    Requires PowerShell remoting to be enabled
#>
function Get-PendingReboot
{
    [CmdletBinding()]
    param
    (
        [Alias('CN', 'Computer')]
        [Parameter(ValueFromPipeline = $true)]
        [String[]]
        $ComputerName = $env:COMPUTERNAME
    )

    Begin
    {
        $ComputerNames = @()
    }

    Process
    {
        $ComputerNames += $ComputerName
    }

    End
    {
        $ChecksCompleted = @()
        $Retries = 5

        $CheckScript = {
            $VerbosePreference = $using:VerbosePreference
            $DebugPreference = $using:DebugPreference
            $LocalHost = $env:COMPUTERNAME

            # Default values
            $pendingCBS = $pendingWUAU = $pendingSCCM = $pendingFileRename = $false

            $Time = Get-Date -Format 'HH:mm:ss.ffff'
            Write-Debug "[$Time]Get Operating System information [$LocalHost]"
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -Property Version, LastBootUpTime, CSName -Verbose:$false
            $OSVersion = $operatingSystem.Version -as [System.Version]

            if ($OSVersion.Major -gt 6)
            {
                $Time = Get-Date -Format 'HH:mm:ss.ffff'
                Write-Debug "[$Time]Check CBS registry key [$LocalHost]"
                $pendingCBS = Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -PathType 'Container'
            }

            $Time = Get-Date -Format 'HH:mm:ss.ffff'
            Write-Debug "[$Time]Check Windows Update Automatic Updates [$LocalHost]"
            $pendingWUAU = Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -PathType 'Container'

            $Time = Get-Date -Format 'HH:mm:ss.ffff'
            Write-Debug "[$Time]Getting pending file renames [$LocalHost]"
            # Get information from the Session Manager registry key
            $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'

            if ($sessionManager.PendingFileRenameOperations)
            {
                Write-Debug 'Initialize an ArrayList to store the file rename operations'
                $fileRenameOperations = New-Object 'System.Collections.ArrayList'

                $fileRenameOperations += for ($i = 0; $i -lt $sessionManager.PendingFileRenameOperations.Count; $i += 2)
                {
                    $escapeSequence = '^(!?\\\?\?\\)'
                    $source = $sessionManager.PendingFileRenameOperations[$i] -replace $escapeSequence, ''
                    $target = $sessionManager.PendingFileRenameOperations[$i + 1] -replace $escapeSequence, ''

                    if ([String]::IsNullOrEmpty($target))
                    {
                        $target = 'Delete'
                    }

                    [PSCustomObject]@{
                        Source = $source
                        Target = $target
                        SourceExists = (Test-Path -Path $source -ErrorAction SilentlyContinue)
                    }
                }

                # Set a reboot flag if there are pending reboot operations
                $pendingFileRename = ($fileRenameOperations.Count -gt 0)
            }

            $Time = Get-Date -Format 'HH:mm:ss.ffff'
            $CcmPatches = New-Object 'System.Collections.ArrayList'

            Write-Debug "[$Time]Querying SCCM ClientSDK [$LocalHost]"
            $CCM_SoftwareUpdate = @{
                ClassName = 'CCM_SoftwareUpdate'
                Namespace = 'root\ccm\ClientSDK'
                ErrorAction = [System.Management.Automation.ActionPreference]'SilentlyContinue'
                Verbose = $false
            }
            $Patches = Get-CimInstance @CCM_SoftwareUpdate | Sort-Object EvaluationState
            if ($Patches)
            {
                $Time = Get-Date -Format 'HH:mm:ss.ffff'
                Write-Debug "[$Time]SCCM Client found [$LocalHost]"

                foreach ($Patch in $Patches | Where-Object { $_.EvaluationState -In @(8, 9) })
                {
                    # Creates custom object for output.
                    $computerPSObject = [PSCustomObject]@{
                        PatchName = $Patch.Name
                        EvaluationState = $Patch.EvaluationState
                        Status = switch ($Patch.EvaluationState)
                        {
                            8 { 'Reboot Required (Soft)' }
                            9 { 'Reboot Required (Hard)' }
                        }
                    }
                    $CcmPatches += $computerPSObject
                }
            }

            # Set a reboot flag if there are pending reboot operations
            $pendingSCCM = ($CcmPatches.Count -gt 0)

            $RebootPending = ($pendingCBS -or $pendingWUAU -or $pendingSCCM -or $pendingFileRename)

            $Time = Get-Date -Format 'HH:mm:ss.ffff'
            Write-Verbose "[$Time]Reboot Pending for computer [$LocalHost]: $RebootPending"

            return [PSCustomObject]@{
                Computer = $operatingSystem.CSName
                LastBootUpTime = $operatingSystem.LastBootUpTime
                CBS = $pendingCBS
                WindowsUpdate = $pendingWUAU
                SCCM = $pendingSCCM
                SCCM_Pending = $CcmPatches
                PendingFileRename = $pendingFileRename
                FileRenameOperations = $fileRenameOperations
                RebootPending = $RebootPending
            }
        }
        $ReturnProperties = @(
            'Computer',
            'LastBootUpTime',
            'CBS',
            'WindowsUpdate',
            'SCCM',
            'SCCM_Pending',
            'PendingFileRename',
            'FileRenameOperations',
            'RebootPending'
        )

        do
        {
            try
            {
                Write-Message -Stream 'Verbose' -Message "Testing reboot status for computer(s): $($ComputerNames -join  ', ')"

                if ($Retries -eq 1)
                {
                    $EA = [System.Management.Automation.ActionPreference]'Stop'
                }
                else
                {
                    $EA = [System.Management.Automation.ActionPreference]'SilentlyContinue'
                }

                $InvokeCommand = @{
                    ComputerName = $ComputerNames
                    ScriptBlock = $CheckScript
                    ErrorAction = $EA
                }

                $ChecksCompleted += Invoke-Command @InvokeCommand |
                    ForEach-Object {
                        $ComputerName = $_.Computer
                        $Message = "Reboot Pending for computer [$ComputerName]: $($_.RebootPending)"
                        Write-Message -Stream 'Log' -Message $Message

                        $ComputerNames = $ComputerNames | Where-Object { $_ -NotMatch $ComputerName }

                        $_ | Select-Object -Property $ReturnProperties
                    }

                if ($ComputerNames.Count -gt 0)
                {
                    $Retries--
                    $Message = "Failed to get reboot status for computer(s): $($ComputerNames -join  ', ')"
                    Write-Message -Stream 'Warning' -Message "$Message. Retrying in 10 seconds."
                    Start-Sleep -Seconds 10
                }
            }
            catch
            {
                $Retries = 0
                Write-Message -Stream 'Debug' -Message $_
                $Message = "Failed to get reboot status for computer(s): $($ComputerNames -join  ', ')"
                Write-Message -Stream 'Error' -Message $Message
            }
        }
        while ($Retries -gt 0 -and $ComputerNames.Count -gt 0)

        return $ChecksCompleted
    }
}
