function Invoke-DbCommand
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Data.Common.DbCommand]
        $Command,

        [Parameter(ParameterSetName = 'WithResults', Mandatory = $true)]
        [Switch]
        $WithResults,

        [Parameter(ParameterSetName = 'WithResults')]
        [ValidateSet('DataTable', 'PSObject')]
        [String]
        $ResultsType = 'PSObject'
    )

    try
    {
        # determines whether a result set is required
        if ($WithResults)
        {
            Write-Message -Stream 'Verbose' -Message 'Processing results.'

            Write-Message -Stream 'Debug' -Message 'Executing query...'
            # execute the query and return the results
            $reader = $Command.ExecuteReader()

            if ($ResultsType -eq 'PSObject')
            {
                # parse the output into a custom object
                try
                {
                    Write-Message -Stream 'Debug' -Message 'Parsing results'
                    while ($reader.Read())
                    {
                        # create a new hashtable to represent this row
                        $rowHashTable = @{}

                        # loop through the columns
                        for ( $i = 0; $i -lt $reader.VisibleFieldCount; $i++ )
                        {
                            # get the field name
                            $key = $reader.GetName($i)

                            # get the value
                            $value = $reader[$i]

                            Write-Message -Stream 'Debug' -Message "Field: $key; Value: $value"

                            # add the column to our row
                            $rowHashTable += @{ $key = $value }
                        }

                        <#
                            The PSCustomObject type accelerator is noticeably faster
                            Build a custom object and add it to the pipeline
                        #>
                        [PSCustomObject]$rowHashTable
                    }

                    # close the reader
                    $reader.Close()
                }
                catch
                {
                    # re-throw the exception
                    $Message = $_.Exception.ToString()
                    Write-Message -Stream 'Log' -Message $Message
                    throw $Message
                }
            }

            if ($ResultsType -eq 'DataTable')
            {
                $dataTable = [System.Data.DataTable]::new()

                Write-Message -Stream 'Debug' -Message 'Loading data table...'
                $dataTable.Load($reader)

                return , $dataTable

            }
        }
        else
        {
            # just execute, returning nothing
            $null = $Command.ExecuteNonQuery()
        }
    }
    catch
    {
        # re-throw the exception
        $Message = $_.Exception.ToString()
        Write-Message -Stream 'Log' -Message $Message
        throw $Message
    }
    finally
    {
        # dispose of the .net objects created
        $Command.Dispose()
    }
}
