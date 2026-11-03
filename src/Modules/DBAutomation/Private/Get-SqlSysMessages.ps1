function Get-SqlSysMessages
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server
    )

    $SysMsgParams = @{
        Server = $Server
        #This is not a stored procedure as it can be called against any server.
        QueryString = "SELECT message_id, language_id, severity, text
        FROM sys.messages
        WHERE language_id = SERVERPROPERTY('LCID')"
        WithResults = $true
        ResultsType = 'DataTable'
    }

    Write-Message -Stream 'Debug' -Message "Getting [sys.messages] from server [$($Server.ConnectionContext.ServerInstance)]."

    # Execute the query
    $Messages = Invoke-SqlQuery @SysMsgParams -Verbose:$VerbosePreference

    foreach ($Message in $Messages)
    {
        $WildCardMessage = $Message.text -replace '(?<!%)(?:%%)*%([\-\+0\ \#])?(\d+|\*)?(\.\*|\.\d+)?([hLIw]|l{1,2}|I32|I64)?([cCdiouxXeEfgGaAnpsSZ])(_BLKIOPTR|_DATE|_LSN|_MSG|_PAGE|_PGID|_RID|_TS|_XID)?', '%'
        $WildCardMessage = $WildCardMessage -replace '\[', '[[]'
        $WildCardMessage = $WildCardMessage -replace '%%', '%'

        if ($WildCardMessage -notin @('%', '% has %.'))
        {
            $Message.text = $WildCardMessage
        }
        else
        {
            Write-Message -Stream 'Debug' -Message "Removing message_id: $($Message.message_id), language_id: $($Message.language_id), severity: $($Message.severity), text: $($Message.text)"
            $Message.Delete()
        }
    }
    $Messages.AcceptChanges()

    return , $Messages
}
