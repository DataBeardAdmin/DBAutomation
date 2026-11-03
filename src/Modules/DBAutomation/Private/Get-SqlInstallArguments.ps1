function Get-SqlInstallArguments
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
        [Products]
        $Product
    )

    if ($Product -eq 'SqlServer')
    {
        $InstallArguments = @(
            '/IAcceptSQLServerLicenseTerms',
            '/AllInstances',
            '/Action=Patch',
            '/Q'
        )
    }
    elseif ($Product -eq 'SSMS')
    {
        $InstallArguments = @(
            '/install',
            '/quiet',
            '/norestart'
        )
    }
    elseif ($Product -eq 'ReportServer')
    {
        $InstallArguments = @(
            '/IAcceptLicenseTerms',
            '/quiet',
            '/norestart'
        )
    }
    
    return $InstallArguments
}