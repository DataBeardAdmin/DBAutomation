function Get-TimeZoneOffset
{
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true)]
        [String[]]
        [Alias('CN', 'Computer')]
        $ComputerName = $env:COMPUTERNAME
    )

    $CurrentTimeZone = Get-CimInstance -ComputerName $ComputerName -ClassName Win32_OperatingSystem -Verbose:$false | Select-Object -ExpandProperty CurrentTimeZone
    [int]$Hours = [Math]::Floor($CurrentTimeZone / 60)
    $Minutes = $CurrentTimeZone % 60
    return [PSCustomObject]@{
        UtcOffsetMins = $CurrentTimeZone
        OffsetString = "{0:D2}`:{1:D2}" -f $Hours, $Minutes
    }
}