function Get-LocalDomain
{
    [CmdletBinding()]
    param()

    $GetItemPropertyValue = @{
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\'
        PSProperty = 'Domain'
    }
    Get-ItemPropertyValue @GetItemPropertyValue
}