function Get-AdsiObjects
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('GlobalCatalog', 'LocalDomain')]
        [string]
        $SearchScope,

        [Parameter(ParameterSetName = 'AutoFilter', Mandatory = $true)]
        [ValidateSet('Computer', 'ServiceAccount', 'User', 'DomainController', 'Domain', 'Schema')]
        [string]
        $ObjectType,

        [Parameter()]
        [String[]]
        $IncludedObjects,

        [Parameter()]
        [String[]]
        $ExcludedObjects,

        [Parameter(ParameterSetName = 'ManualFilter', Mandatory = $true)]
        [String]
        $ManualSearchFilter,

        [Parameter()]
        [string]
        $SearchRoot,

        [Parameter()]
        [string[]]
        $PropertiesToLoad = @('distinguishedName'),

        [Parameter()]
        [int]
        $ResultsPageSize = 9999,

        [Parameter()]
        [switch]
        $FindOne
    )

    $SearchFilter = ''
    if ($PSCmdlet.ParameterSetName -eq 'ManualFilter')
    {
        $SearchFilter = $ManualSearchFilter
    }
    else
    {
        $GetAdsiSearchFilter = @{
            ObjectType = $ObjectType
            IncludedObjects = $IncludedObjects
            ExcludedObjects = $ExcludedObjects
        }

        $SearchFilter = Get-AdsiSearchFilter @GetAdsiSearchFilter
    }

    if ([string]::IsNullOrEmpty($SearchRoot))
    {
        $SearchRoot = Get-LocalDomain
    }

    switch ($SearchScope)
    {
        'GlobalCatalog'
        {
            $SearchRoot = "GC://$SearchRoot"
        }
        'LocalDomain'
        {
            $SearchRoot = "LDAP://$SearchRoot"
        }
    }
    Write-Message -Stream 'Debug' -Message "Querying SearchRoot: [$SearchRoot] and SearchFilter: [$SearchFilter]"

    $adsiSearcher = [adsiSearcher]$SearchFilter
    $adsiSearcher.PropertiesToLoad.AddRange($PropertiesToLoad) > $null
    $adsiSearcher.PageSize = $ResultsPageSize
    $adsiSearcher.SearchRoot = [adsi]$SearchRoot

    if ($FindOne.IsPresent)
    {
        $adsiSearcher.FindOne()
    }
    else
    {
        $adsiSearcher.FindAll()
    }
}