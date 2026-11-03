Function Get-AvailableUpdates
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [String]
        $UpdatePath
    )

    Invoke-Command -ArgumentList $UpdatePath -ScriptBlock {
        param
        (
            [String]
            $UpdatePath
        )

        Get-ChildItem -Path $UpdatePath | Select-Object -Property @(
            'Name',
            'FullName',
            @{ Name = 'ProductVersion'; Expression = { $_.VersionInfo.ProductName } },
            @{ Name = 'PatchVersion'; Expression = { [System.Version]::Parse($_.VersionInfo.ProductVersion) } }
        ) |
            Sort-Object -Property PatchVersion

    } -ComputerName $ComputerName -ErrorAction Stop
}