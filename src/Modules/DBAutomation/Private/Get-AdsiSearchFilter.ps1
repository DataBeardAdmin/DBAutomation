function Get-AdsiSearchFilter
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Computer', 'ServiceAccount', 'User', 'DomainController', 'Domain', 'Schema')]
        [string]
        $ObjectType,

        [Parameter()]
        [String[]]
        $IncludedObjects,

        [Parameter()]
        [String[]]
        $ExcludedObjects
    )

    if ($IncludedObjects.Count -gt 0)
    {
        $List = $IncludedObjects -join ')({0}='
        $SearchFilter += "(|({0}=$List))"
    }

    if ($ExcludedObjects.Count -gt 0)
    {
        $List = $ExcludedObjects -join ')({0}='
        $SearchFilter += "(!(|({0}=$List)))"
    }

    switch ($ObjectType)
    {
        'Computer'
        {
            "(&(objectClass=computer)$SearchFilter)" -f 'Name'
        }
        'ServiceAccount'
        {
            "(&(|(objectCategory=msDS-ManagedServiceAccount)(objectCategory=msDS-GroupManagedServiceAccount))(objectClass=user)$SearchFilter)" -f 'sAMAccountName'
        }
        'User'
        {
            "(&(objectCategory=person)(objectClass=user)$SearchFilter)" -f 'sAMAccountName'
        }
        'DomainController'
        {
            "(&(objectCategory=computer)(userAccountControl:1.2.840.113556.1.4.803:=8192)$SearchFilter)" -f 'Name'
        }
        'Domain'
        {
            "(&(objectCategory=domain)$SearchFilter)" -f 'Name'
        }
        'Schema'
        {
            $SearchFilter -f 'Name'
        }
    }
}