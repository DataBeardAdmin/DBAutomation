function Get-SqlCimNamespaces
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'ReportServer')]
        [String]
        $Product,

        [Parameter()]
        [String]
        $ComputerName = $env:COMPUTERNAME
    )

    $Instances = Find-SqlComponents -ComputerName $ComputerName -Product $Product

    foreach ($Instance in $Instances)
    {
        switch ( $Product )
        {
            'SqlServer'
            {
                "root\Microsoft\SqlServer\ComputerManagement$($Instance.InstanceName)"
            }
    
            'ReportServer'
            {
                "root\Microsoft\SqlServer\ReportServer\RS_$($Instance.InstanceName)\V$($Instance.PatchLevel.Major)\Admin"
            }
        }
    }
}
