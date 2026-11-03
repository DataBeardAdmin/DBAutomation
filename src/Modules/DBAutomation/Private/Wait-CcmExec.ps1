function Wait-CcmExec
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName
    )

    $Service = Get-Service -ComputerName $ComputerName -Name 'CcmExec' -ErrorAction 'SilentlyContinue'

    if ($Service)
    {
        $ServiceState = $Service.Status

        While ($ServiceState -ne 'Running')
        {
            $ServiceState = (Get-Service -ComputerName $ComputerName -Name 'CcmExec' -ErrorAction 'SilentlyContinue').Status
            if ($ServiceState -and $ServiceState -ne 'Running')
            {
                Write-Message -Stream 'Verbose' -Message "CcmExec Service State: [$ServiceState]. Waiting 30 seconds."
                Start-Sleep -Seconds 30
            }
        }
    }
}