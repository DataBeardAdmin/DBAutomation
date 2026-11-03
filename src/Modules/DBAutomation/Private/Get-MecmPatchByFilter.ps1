filter Get-MecmPatchByFilter
{
    [CmdletBinding(DefaultParameterSetName = 'Manual')]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [PSCustomObject]
        $Patch,

        [Parameter(ParameterSetName = 'Manual')]
        [String]
        $PatchName,

        [Parameter(ParameterSetName = 'Manual')]
        [String]
        $PatchDescription,

        [Parameter(ParameterSetName = 'Product')]
        [ValidateSet('SqlServer', 'SSMS')]
        [String]
        $Product
    )

    if ($PSCmdlet.ParameterSetName -eq 'Manual')
    {
        if ($Patch.PatchName -notmatch $PatchName)
        {
            return
        }

        if ($Patch.PatchDescription -notmatch $PatchDescription)
        {
            return
        }

        return $Patch
    }
    else
    {
        switch ( $Product )
        {
            'SqlServer'
            {
                if ($Patch.PatchName -Match 'SQL Server' -and
                    $Patch.PatchName -NotMatch 'ODBC Driver' -and
                    $Patch.PatchName -NotMatch 'OLE DB Driver' -and
                    $Patch.PatchName -NotMatch 'SQL Server Management Studio')
                {
                    return $Patch
                }
            }
            'SSMS'
            {
                if ($Patch.PatchName -Match 'SQL Server Management Studio')
                {
                    return $Patch
                }
            }
            Default
            {
                return
            }
        }
    }
}
