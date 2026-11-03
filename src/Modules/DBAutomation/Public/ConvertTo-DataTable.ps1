function ConvertTo-DataTable
{
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.Object[]]
        $InputObject,

        [Parameter()]
        [System.String]
        $TableName = 'ConvertedDataTable',

        [Parameter()]
        [PSCustomObject]
        $MappingOverride
    )

    Begin
    {
        Write-Message -Stream 'Verbose' -Message 'Begin conversion to DataTable'

        # Initialize the DataTable
        $dataTable = New-Object System.Data.DataTable $TableName
        $dataTable.TableName = $TableName

        # Determines whether columns are to be added to the DataTable
        $createColumns = $true
    }

    Process
    {
        # Iterate over all objects in the collection
        foreach ($object in $InputObject)
        {
            # Create a new DataRow for storing our values
            $newRow = $dataTable.NewRow()

            # Iterate over the properties of the current Object
            foreach ($property in $object.PSObject.Properties)
            {
                # Need to create rows on the first pass
                if ($createColumns)
                {
                    Write-Message -Stream 'Verbose' -Message ('Creating column for property {0}' -f $property.Name)

                    # Create the DataColumn object
                    $newColumn = New-Object System.Data.DataColumn
                    $newColumn.ColumnName = $property.Name

                    if ([String]::IsNullOrEmpty($MappingOverride.$($property.Name)))
                    {
                        # Default all columns to string
                        $newColumn.DataType = [System.String]

                        # If we have a value, update the type to match
                        if ($property.value)
                        {
                            $DataType = [System.Type]::GetType($property.TypeNameOfValue)
                            Write-Message -Stream 'Debug' -Message "Setting column to type [$DataType]"

                            # Update the column's data type
                            $newColumn.DataType = [System.Type]::GetType($property.TypeNameOfValue)
                        }
                    }
                    else
                    {
                        $DataType = $MappingOverride.$($property.Name)
                        Write-Message -Stream 'Debug' -Message "Using override, setting column to type [$DataType]"
                        $newColumn.DataType = $DataType
                    }

                    # Add the column to the collection
                    $null = $dataTable.Columns.Add($newColumn)
                }

                # Assign the cell value from our property
                $newRow.Item($property.Name) = $property.Value
            }

            # Add the row to the DataTable
            $null = $dataTable.Rows.Add($newRow)

            # No longer on the first row
            $createColumns = $false
        }
    }

    End
    {
        Write-Message -Stream 'Verbose' -Message 'End conversion to DataTable'
        return , $dataTable
    }
}
