function Get-LoggingConfiguration
{
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Directory = $script:LogDirectory
        File = $script:LogFile
        Disable = -not $script:LoggingEnabled
    }
}