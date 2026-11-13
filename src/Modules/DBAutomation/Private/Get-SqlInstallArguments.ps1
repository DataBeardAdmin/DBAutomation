function Get-SqlInstallArguments
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
        [Products]
        $Product,

        [Parameter()]
        [int]
        $MajorVersion,

        [Parameter()]
        [string]
        $Mode = 'Update',

        [Parameter()]
        [string]
        $InstallPath
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
    elseif ($Product -eq 'SSMS' -and $MajorVersion -ge 21)
    {
        $InstallArguments = @()
        if ($Mode -eq 'Update')
        {
            $InstallArguments += @('update')
        }
        $InstallArguments += @(
            '--noWeb',
            '--quiet',
            '--wait',
            '--norestart'
        )

        if ($false -eq [string]::IsNullOrWhiteSpace($InstallPath))
        {
            $InstallArguments += @('--installPath')
            $InstallArguments += @($InstallPath)
        }
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