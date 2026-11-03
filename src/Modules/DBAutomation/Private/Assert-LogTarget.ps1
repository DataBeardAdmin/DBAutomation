function Assert-LogTarget
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Console', 'Disk', 'SQL')]
        [String[]]
        $SendTo,

        [Parameter()]
        [String]
        $TargetFilePath,

        [Parameter()]
        [String]
        $TargetSqlServer,

        [Parameter()]
        [String]
        $TargetSqlDatabase
    )

    if ($SendTo -contains 'SQL' -and ([string]::IsNullOrEmpty($TargetSqlServer) -or [string]::IsNullOrEmpty($TargetSqlDatabase)))
    {
        $Message = 'The TargetSqlServer and TargetSqlDatabase must be specified when storing the results to SQL!'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($SendTo -contains 'Disk' -and [string]::IsNullOrEmpty($TargetFilePath))
    {
        $Message = 'The LogFile must be specified when storing the results to Disk!'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
}