<#
    .SYNOPSIS
    This function validates the TCP port is accessible on the specified computer.

    .PARAMETER ComputerName
    The name of the computer to validate the port on.

    .PARAMETER Port
    The TCP port to test on the specified computer.

    .PARAMETER Timeout
    This timeout in milliseconds for the given test.
#>

function Test-TcpPort
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [Int]
        $Port,

        [Parameter()]
        [Int]
        $Timeout = 1000
    )

    #milliseconds to wait between checks.
    $LoopTime = 250

    $Connection = New-Object System.Net.Sockets.TcpClient

    try
    {
        $null = $Connection.BeginConnect($ComputerName, $Port, $null, $null)

        do
        {
            Start-Sleep -Milliseconds $LoopTime

            $Timeout -= $LoopTime
        }
        while ($Timeout -ge 0 -and $false -eq $Connection.Connected)

        return $Connection.Connected
    }
    finally
    {
        $Connection.Close()
    }
}