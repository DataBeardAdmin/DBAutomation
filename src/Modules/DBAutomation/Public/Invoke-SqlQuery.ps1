function Invoke-SqlQuery
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'Connection', Mandatory = $true, ValueFromPipeline = $true)]
        [System.Data.Common.DbConnection]
        $Connection,

        [Parameter(ParameterSetName = 'Server', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter(ParameterSetName = 'ComputerName', Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [String]
        $InstanceName = 'MSSQLSERVER',

        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [System.String]
        $SqlServer,

        [Parameter()]
        [System.String]
        $DatabaseName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $QueryString,

        [Alias('Parameters')]
        [Parameter()]
        [Hashtable]
        $QueryParameters,

        [Parameter()]
        [System.Data.Common.DbTransaction]
        $Transaction,

        [Parameter()]
        [Int]
        $CommandTimeout = 300,

        [Parameter()]
        [Switch]
        $WithResults,

        [Parameter()]
        [ValidateSet('DataTable', 'PSObject')]
        [String]
        $ResultsType = 'PSObject'
    )

    if ($PSBoundParameters.ContainsKey('ResultsType') -and $WithResults.IsPresent -eq $false)
    {
        $Message = '[WithResults] is mandatory when specifying [ResultsType]'
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }

    if ($PSCmdlet.ParameterSetName -eq 'ComputerName')
    {
        $Server = Connect-SqlServer -ComputerName $ComputerName -InstanceName $InstanceName -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ($PSCmdlet.ParameterSetName -ne 'Connection')
    {
        $Connection = Get-SqlConnectionObject -Server $Server -Verbose:$VerbosePreference
    }

    if ($false -eq [String]::IsNullOrEmpty($DatabaseName))
    {
        Write-Message -Stream 'Debug' -Message "Changing database to [$DatabaseName]"
        $Connection.ChangeDatabase($DatabaseName)
    }

    ## create a command for executing
    $command = $Connection.CreateCommand()

    ## mark this as an ad-hoc query
    $command.CommandType = 'Text'

    ## set the timeout for the command
    $command.CommandTimeout = $CommandTimeout

    ## attach the query string
    $command.CommandText = $QueryString

    if ($Transaction)
    {
        $Command.Transaction = $Transaction
    }

    ## determine whether any parameter attachment is required
    if ($QueryParameters.Keys.Count -gt 0)
    {
        ## loop over the keys
        foreach ($key in $QueryParameters.Keys)
        {
            ## add the parameter to the command's parameters
            $command.Parameters.AddWithValue($key, $QueryParameters[$key]) > $null
        }
    }

    try
    {
        $executeParams = @{
            Command = $Command
            WithResults = $WithResults.IsPresent
        }
        if ($PSBoundParameters.ContainsKey('ResultsType'))
        {
            $executeParams += @{
                ResultsType = $ResultsType
            }
        }

        ## execute the query
        return Invoke-DbCommand @executeParams
    }
    catch
    {
        ## rethrow exception
        $Message = $_.Exception.ToString()
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    finally
    {
        ## dispose of the .net objects created
        $command.Dispose()
    }
}
