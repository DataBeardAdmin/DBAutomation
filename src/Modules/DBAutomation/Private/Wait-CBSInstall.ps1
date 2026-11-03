function Wait-CBSInstall
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName
    )

    $WriteProgressTemplate = @{
        Id = 1
        Activity = 'Validating/Waiting for CBS Install status...'
    }

    do
    {
        try
        {
            $Session = New-PSSession -Name 'CBS Check' -ComputerName $ComputerName -ErrorAction Stop
            $StartTime = Get-Date
            $ExecuteStateProceedLogged = $false
            $PercentComplete = 0

            while ($PercentComplete -lt 100)
            {
                $PercentComplete = (((Get-Date) - $StartTime).TotalSeconds / 30 * 100)
                $TiRunning = Invoke-Command -Session $Session -ScriptBlock {
                    $CBSRootPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
                    Test-Path -Path "$CBSRootPath\TiRunning" -PathType 'Container'
                } -ErrorAction Stop

                if ($true -eq $TiRunning)
                {
                    $ExecuteState = Invoke-Command -Session $Session -ScriptBlock {
                        ($(Get-ItemProperty -Path $CBSRootPath).ExecuteState -eq [uint32]::MaxValue -and
                        $(Get-ItemProperty -Path "$CBSRootPath\Interface").ServicingInProgress -eq 0)
                    } -ErrorAction Stop

                    if ($true -eq $ExecuteState)
                    {
                        #Trusted Installer is running but has progressed to a point that *should* not affect us.
                        if ($false -eq $ExecuteStateProceedLogged)
                        {
                            Write-Message -Stream 'Debug' -Message 'Trusted Installer is running but has progressed to a point that *should* not affect us.'
                            $ExecuteStateProceedLogged = $True
                        }
                        $TiRunning = $false
                    }
                    else
                    {
                        # We have no way of measuring the current activity, let's turn off the progress bar at this time.
                        Write-Progress @WriteProgressTemplate -Completed

                        Write-Message -Stream 'Debug' -Message 'CBS Install in progress. Waiting for install to complete.'

                        $ExecuteStateProceedLogged = $false
                        Start-Sleep -Seconds 30
                        $StartTime = Get-Date
                    }
                }

                if ($TiRunning -eq $false)
                {
                    Write-Message -Stream 'Log' -Message "$($WriteProgressTemplate.Activity) ($PercentComplete%)"
                    if ($PercentComplete -gt 100)
                    {
                        $PercentComplete = 100
                    }
                    Write-Progress @WriteProgressTemplate -PercentComplete $PercentComplete
                    Start-Sleep -Seconds 1
                }
            }

            Write-Progress @WriteProgressTemplate -Completed

            $Completed = $true
        }
        catch
        {
            Write-Progress @WriteProgressTemplate -Completed

            Write-Message -Stream 'Warning' -Message 'Failed to check CBS Running status. The system may be rebooting. Waiting 30 seconds...'
            Write-Message -Stream 'Debug' -Message $_

            $Completed = $false
            Start-Sleep -Seconds 30
        }
    }
    While ($Completed -ne $true)

    Remove-PSSession -Session $Session
}