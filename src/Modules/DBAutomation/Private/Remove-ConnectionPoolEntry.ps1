<#
    .SYNOPSIS
    Clears the connection pool associated with the specified SqlConnection

    .PARAMETER ConnectionObject
    SqlConnection object to be cleared from the pool.
#>
function Remove-ConnectionPoolEntry
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Data.Common.DbConnection]
        $SqlConnection
    )

    $ConnectionType = $SqlConnection.GetType().FullName
    Write-Message -Stream 'Debug' -Message "Type provided to Remove-ConnectionPoolEntry: [$ConnectionType]"

    if ($ConnectionType -eq 'Microsoft.Data.SqlClient.SqlConnection')
    {
        [Microsoft.Data.SqlClient.SqlConnection]::ClearPool($SqlConnection)
    }
    elseif ($ConnectionType -eq 'System.Data.SqlClient.SqlConnection')
    {
        [System.Data.SqlClient.SqlConnection]::ClearPool($SqlConnection)
    }
    else
    {
        $Message = 'Invalid type passed to [Remove-ConnectionPoolEntry]!'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
}