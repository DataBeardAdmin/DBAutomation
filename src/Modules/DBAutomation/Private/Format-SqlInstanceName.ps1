<#
    .SYNOPSIS
    This function will return SqlServer in 'connection string' format based on the server and instance name.

    .PARAMETER ComputerName
    Specifies the computer name running SQL.

    .PARAMETER InstanceName
    Specifies the name of the instance running SQL. If no value is provided, the default instance is assumed.
#>

function Format-SqlInstanceName
{
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter()]
        [String]
        $InstanceName = 'MSSQLSERVER'
    )

    if ($InstanceName -eq 'MSSQLSERVER' -or [string]::IsNullOrEmpty($InstanceName))
    {
        return $ComputerName
    }
    else
    {
        return "$ComputerName\$InstanceName"
    }
}