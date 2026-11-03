function Get-SqlConnectionObject
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server
    )

    $SqlConnection = $Server.ConnectionContext.SqlConnectionObject
    if ($SqlConnection.State -eq 'closed')
    {
        Write-Message -Stream 'Debug' -Message "Connection to server [$($Server.ConnectionContext.ServerInstance)] was [closed]. Opening..."
        $SqlConnection.Open()
    }
    
    return $SqlConnection
}