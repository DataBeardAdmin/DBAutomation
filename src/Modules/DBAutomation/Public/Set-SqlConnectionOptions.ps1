<#
    .SYNOPSIS
    This function will configure connection options for new connections to SQL server using Connect-SqlServer.

    .PARAMETER EnableCertificateFailback
    When new connections are made, the connection will be made using the 'TrustServerCertificate' setting
    if the certificate isn't trusted (including self-signed)

    .PARAMETER Force
    All existing sessions will be dropped.
#>

Function Set-SqlConnectionOptions
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [switch]
        $EnableCertificateFailback,

        [Parameter()]
        [switch]
        $Force
    )

    if ($EnableCertificateFailback.IsPresent)
    {
        $Message = 'New connections to SQL Server will use the setting [EnableCertificateFailback].'
        Write-Message -Stream 'Verbose' -Message $Message
        if ($true -ne $script:ConnectionOptions.EnableCertificateFailback)
        {
            $script:ConnectionOptions += @{ 'EnableCertificateFailback' = $true }
        }
    }
    else
    {
        $Message = 'New connections to SQL Server will not use the setting [EnableCertificateFailback].'
        Write-Message -Stream 'Verbose' -Message $Message
        $script:ConnectionOptions.Remove('EnableCertificateFailback')
    }

    if ($Force.IsPresent)
    {
        Write-Message -Stream 'Verbose' -Message 'Clearing the session cache.'
        $script:sessionCache = @{}
    }
}