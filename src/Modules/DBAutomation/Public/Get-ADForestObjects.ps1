<#
    .SYNOPSIS
    This function will query the Active Directory forest for all available domains and then perform an object search
    based on the parameters specified.

    .PARAMETER IncludedObjects
    This mandatory parameter is a list of object names (wildcard syntax supported) to include in the results.

    .PARAMETER ExcludedObjects
    This optional parameter is a list of object names (wildcard syntax supported) to not include in the results.

    .PARAMETER ObjectType
    Specifies the type of object being queried in the AD forest. Possible values:
        Computer
        ServiceAccount
        User
        Domain

    .PARAMETER IncludePerDCTimestamps
    When specified with ObjectType of User, the results will include information that must be gathered from each
    domain controller in the respective domains. This includes:
        LastLogon
        LockoutTime
        LastBadPassword
        BadPasswordCount
        IsLocked
        LockedDomainController (currently estimated until an authoritative query is found.)

    .PARAMETER SourceDomain
    This optional parameter will filter the list of domains in the forest using NetBIOS or FQDN (wildcard syntax supported)

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'ServiceAccount' -IncludedObjects '[g]MSANamingConvention' -IncludePerDCTimestamps -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'User' -IncludedObjects 'ServiceAccountPrefix*' -IncludePerDCTimestamps -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'User' -IncludedObjects '*ServiceAccountSuffix' -IncludePerDCTimestamps -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'User' -IncludedObjects '*ServiceAccountSuffix' -SourceDomain 'SingleDomain' -IncludePerDCTimestamps -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'Computer' -IncludedObjects 'ComputerNamePrefix*' -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'Computer' -IncludedObjects '*ComputerNameSuffix' -Verbose

    .EXAMPLE
    Get-ADForestObjects -ObjectType 'Domain' -IncludedObjects 'ChildDomain' -Verbose
#>

function Get-ADForestObjects
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String[]]
        $IncludedObjects,

        [Parameter()]
        [String[]]
        $ExcludedObjects,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Computer', 'ServiceAccount', 'User', 'DomainController', 'Domain')]
        [String]
        $ObjectType,

        [Parameter()]
        [switch]
        $IncludePerDCTimestamps,

        [Parameter()]
        [String[]]
        $SourceDomain
    )

    $GetAdsiSearchFilter = @{
        ObjectType = $ObjectType
        IncludedObjects = $IncludedObjects
        ExcludedObjects = $ExcludedObjects
    }

    $ResultantFilter = Get-AdsiSearchFilter @GetAdsiSearchFilter

    $ResultType = switch ($ObjectType)
    {
        'DomainController' { 'Computer' }
        'Computer' { 'Computer' }
        'ServiceAccount' { 'User' }
        'User' { 'User' }
    }

    switch ($ResultType)
    {
        'Computer'
        {
            $ResultFields = @(
                'Name'
                'sAMAccountName'
                'dNSHostName'
                'OperatingSystem'
                'OperatingSystemVersion'
            )
        }
        'User'
        {
            $ResultFields = @(
                'Name'
                'sAMAccountName'
                'PwdLastSet'
                'msDS-SupportedEncryptionTypes'
                'ServicePrincipalName'
                'msDS-AllowedToDelegateTo'
                'objectCategory'
            )

            if ($IncludePerDCTimestamps.IsPresent)
            {
                $ResultFields += @(
                    'LastLogon'
                    'lockoutTime'
                    'badPasswordTime'
                    'badPwdCount'
                    'whenChanged'
                )
            }
        }
    }

    $GetAdsiObjects = @{
        SearchRoot = Get-LocalDomain
        SearchScope = 'GlobalCatalog'
        ObjectType = 'Domain'
    }

    if ($ObjectType -eq 'Domain')
    {
        $GetAdsiObjects += @{
            IncludedObjects = $IncludedObjects
            ExcludedObjects = $ExcludedObjects
        }
    }

    $rootDse = [adsi]'LDAP://RootDSE'
    $rootNamingContext = $rootDse.Get('configurationNamingContext')
    $SchemaNamingContext = $rootDse.Get('SchemaNamingContext')

    $SchemaQuery = @{
        SearchRoot = $SchemaNamingContext
        SearchScope = 'LocalDomain'
        ObjectType = 'Schema'
        IncludedObjects = @('Person', 'ms-DS-Managed-Service-Account', 'ms-DS-Group-Managed-Service-Account')
        PropertiesToLoad = @('distinguishedName', 'Name')
    }

    $SchemaMappings = Get-AdsiObjects @SchemaQuery -Verbose:$VerbosePreference |
        ForEach-Object {
            $Name = switch ($_.Properties.Item('Name')[0])
            {
                'Person' { 'Account' }
                'ms-DS-Group-Managed-Service-Account' { 'Group Managed Service Account' }
                'ms-DS-Managed-Service-Account' { 'Managed Service Account' }
            }

            [PSCustomObject]@{
                Name = $Name
                distinguishedName = $_.Properties.Item('distinguishedName')[0]
            }
        }

    # Query the GC for all available domains
    [array]$ForestDomains = Get-AdsiObjects @GetAdsiObjects |
        ForEach-Object {
            $distinguishedName = $_.Properties.Item('distinguishedName')[0]

            $GetAdsiObjects = @{
                SearchScope = 'LocalDomain'
                ManualSearchFilter = "(nCName=$distinguishedName)"
                SearchRoot = "CN=Partitions,$rootNamingContext"
                PropertiesToLoad = @('nETBIOSName', 'dnsRoot')
                FindOne = $true
            }

            $Result = Get-AdsiObjects @GetAdsiObjects
            if ($null -ne $Result)
            {
                $NetBiosName = $Result.Properties.Item('nETBIOSName')[0]
                $FQDN = $Result.Properties.Item('dnsRoot')[0]
            }

            [PSCustomObject]@{
                FQDN = $FQDN
                NetBios = $NetBiosName
                DistinguishedName = $distinguishedName
            }
        }

    if ([String]::IsNullOrEmpty($SourceDomain))
    {
        Write-Message -Stream 'Verbose' -Message 'No domain specified, looking at all domains in the forest.'
        $SearchDomains = $ForestDomains
    }
    else
    {
        # we were given domains to search!
        $SearchDomains = foreach ($MatchDomain in $SourceDomain)
        {
            $ForestDomains | Where-Object { $_.NetBios -like $MatchDomain -or $_.FQDN -like $MatchDomain }
        }

        if ($SearchDomains.Count -eq 0 -and $ObjectType -ne 'Domain')
        {
            $Message = 'No Domains matched the criteria specified: [{0}]' -f ($SourceDomain -join ';')
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }

    if ($ObjectType -eq 'Domain')
    {
        return $SearchDomains
    }

    # log start of operations
    Write-Message -Stream 'Verbose' -Message ('Begin search [{0}]' -f ($SearchDomains.FQDN -join ';'))

    $LogConfiguration = Get-LoggingConfiguration
    $ArgumentList = @()
    foreach ($DomainObject in $SearchDomains)
    {
        $ArgumentList += [PSCustomObject]@{
            ScriptName = "GetADObject(s)[$($DomainObject.FQDN)]"
            DomainObject = $DomainObject
            ResultantFilter = $ResultantFilter
            ResultFields = $ResultFields
            ObjectType = $ObjectType
            ResultType = $ResultType
            SchemaMappings = $SchemaMappings
            IncludePerDCTimestamps = $IncludePerDCTimestamps
            LogConfiguration = $LogConfiguration
            UserVerbosePreference = $VerbosePreference
            UserDebugPreference = $DebugPreference
        }
    }

    # Create an empty array to store the results
    $DiscoveredObjects = @()

    $RequiredFunctions = @(
        'Get-AdsiObjects',
        'Get-AdsiSearchFilter'
    )

    # loop over our domains
    $InvokeParallelCommandParams = @{
        RequiredFunctions = $RequiredFunctions
        ArgumentList = $ArgumentList
        OutputResults = $true
    }

    [array]$DiscoveredObjects = Invoke-ParallelCommand @InvokeParallelCommandParams -Script {
        param
        (
            $ArgumentObject
        )

        [Flags()] enum EncryptionTypes
        {
            Default = 0
            DES_CBC_CRC = 1
            DES_CBC_MD5 = 2
            RC4_HMAC = 4
            AES128_CTS_HMAC_SHA1_96 = 8
            AES256_CTS_HMAC_SHA1_96 = 16
            FAST_Supported = 65536
            Compound_Identity_Supported = 131072
            Claims_Supported = 262144
            Resource_SID_Compression_Disabled = 524288
        }

        #Initialize logging.
        $LogConfiguration = $ArgumentObject.LogConfiguration
        Import-Module 'DBAutomation'
        $LogConfiguration | Set-LoggingConfiguration -NoLog

        $ScriptName = $ArgumentObject.ScriptName
        $DomainObject = $ArgumentObject.DomainObject
        $ObjectType = $ArgumentObject.ObjectType
        $ResultType = $ArgumentObject.ResultType
        $SchemaMappings = $ArgumentObject.SchemaMappings
        $IncludePerDCTimestamps = $ArgumentObject.IncludePerDCTimestamps
        $VerbosePreference = $ArgumentObject.UserVerbosePreference
        $DebugPreference = $ArgumentObject.UserDebugPreference

        # AD Search parameters
        $ResultsPageSize = 9999
        $ResultantFilter = $ArgumentObject.ResultantFilter
        $ResultFields = $ArgumentObject.ResultFields

        Write-Message -Stream 'Verbose' -Message "Begin [$ScriptName]"

        if ($ResultType -eq 'User' -and $IncludePerDCTimestamps.IsPresent)
        {
            try
            {
                Write-Message -Stream 'Debug' -Message "Getting domain controller list from domain [$($DomainObject.NetBios)]"

                $GetAdsiDcObjects = @{
                    SearchRoot = $DomainObject.DistinguishedName
                    SearchScope = 'LocalDomain'
                    ObjectType = 'DomainController'
                    PropertiesToLoad = @('dNSHostName')
                    ResultsPageSize = $ResultsPageSize
                }

                $DomainControllers = Get-AdsiObjects @GetAdsiDcObjects

                $DomainControllerResults = foreach ($DomainController in $DomainControllers)
                {
                    $DomainControllerName = $DomainController.Properties.Item('dNSHostName')[0]
                    Write-Message -Stream 'Debug' -Message "Getting User information from domain controller [$DomainControllerName]"

                    $GetAdsiUserObjects = @{
                        SearchRoot = $DomainControllerName
                        SearchScope = 'LocalDomain'
                        ManualSearchFilter = $ResultantFilter
                        PropertiesToLoad = $ResultFields
                        ResultsPageSize = $ResultsPageSize
                    }

                    try
                    {
                        Get-AdsiObjects @GetAdsiUserObjects | ForEach-Object {
                            $Properties = $_.Properties

                            # translate the SID to an account and get the domain name
                            $sAMAccountName = $Properties.Item('sAMAccountName')[0]

                            if ($Properties.PropertyNames -contains ('name'))
                            {
                                $Name = $Properties.Item('name')[0]
                            }
                            else
                            {
                                $Name = $sAMAccountName
                            }

                            [PSCustomObject] @{
                                DomainName = $DomainObject.FQDN
                                DomainController = $DomainControllerName
                                Name = $Name
                                ObjectCategory = $Properties.Item('objectCategory')
                                AccountName = $Properties.Item('sAMAccountName')[0]
                                LastLogon = [DateTime]::FromFileTime($Properties.Item('LastLogon')[0])
                                LastPasswordReset = [DateTime]::FromFileTime($Properties.Item('PwdLastSet')[0])
                                BadPasswordTime = [DateTime]::FromFileTime($Properties.Item('badPasswordTime')[0])
                                BadPasswordCount = $Properties.Item('badPwdCount')[0]
                                LockoutTime = $Properties.Item('lockoutTime')[0]
                                EncryptionTypes = [EncryptionTypes]($Properties.Item('msDS-SupportedEncryptionTypes')[0] -as [int])
                                ServicePrincipalName = $Properties.Item('ServicePrincipalName')
                                DelegationAllowed = $Properties.Item('msDS-AllowedToDelegateTo')
                                WhenChanged = $Properties.Item('whenChanged')[0]
                            }
                        }
                    }
                    catch
                    {
                        # Put the error on the error stream
                        $Message = "Error querying domain controller [$DomainControllerName]. Results may be incomplete!"
                        Write-Message -Stream 'Warning' -Message $Message
                        continue
                    }
                }

                foreach ($GroupedResults in $DomainControllerResults | Group-Object -Property 'AccountName')
                {
                    $PerUserResults = $GroupedResults.Group

                    $Aggregates = $PerUserResults | Measure-Object -Property LastLogon, BadPasswordTime, BadPasswordCount -Maximum

                    $LastLogon = $Aggregates |
                        Where-Object -Property Property -EQ 'LastLogon' |
                        Select-Object -ExpandProperty Maximum
                    $BadPasswordTime = $Aggregates |
                        Where-Object -Property Property -EQ 'BadPasswordTime' |
                        Select-Object -ExpandProperty Maximum
                    $BadPasswordCount = $Aggregates |
                        Where-Object -Property Property -EQ 'BadPasswordCount' |
                        Select-Object -ExpandProperty Maximum

                    if ($PerUserResults.LockoutTime -gt 0)
                    {
                        $IsLocked = $true
                        $lockout = $PerUserResults |
                            Where-Object { $_.LockoutTime -gt 0 } |
                            Sort-Object -Property LockoutTime, WhenChanged |
                            Select-Object -First 1
                        $LockedDomainController = "$($lockout.DomainController)`?"
                        $LockoutTime = [DateTime]::FromFileTime($lockout.LockoutTime)
                    }
                    else
                    {
                        $IsLocked = $false
                        $LockedDomainController = $null
                        $LockoutTime = $null
                    }

                    $ObjectType = $SchemaMappings |
                        Where-Object distinguishedName -EQ $PerUserResults[0].ObjectCategory |
                        Select-Object -ExpandProperty Name

                    [PSCustomObject] @{
                        DomainName = $DomainObject.FQDN
                        Name = $PerUserResults[0].Name
                        AccountName = $PerUserResults[0].AccountName
                        AccountType = $ObjectType
                        LastLogon = $LastLogon
                        LastPasswordReset = $PerUserResults[0].LastPasswordReset
                        LastBadPassword = $BadPasswordTime
                        BadPasswordCount = $BadPasswordCount
                        IsLocked = $IsLocked
                        LockedDomainController = $LockedDomainController
                        LockoutTime = $LockoutTime
                        EncryptionTypes = $PerUserResults[0].EncryptionTypes
                        ServicePrincipalName = $PerUserResults[0].ServicePrincipalName
                        DelegationAllowed = $PerUserResults[0].DelegationAllowed
                    }
                }
            }
            catch
            {
                # Put the error on the error stream
                $Message = "Error querying domain [$($DomainObject.NetBios)] for a list of domain controllers!"
                Write-Message -Stream 'Warning' -Message $Message
                continue
            }
        }
        else
        {
            try
            {
                Write-Message -Stream 'Debug' -Message "Getting $ObjectType information from domain [$($DomainObject.NetBios)]"

                $GetAdsiObjects = @{
                    SearchRoot = $DomainObject.DistinguishedName
                    SearchScope = 'LocalDomain'
                    ManualSearchFilter = $ResultantFilter
                    PropertiesToLoad = $ResultFields
                    ResultsPageSize = $ResultsPageSize
                }

                $Results = Get-AdsiObjects @GetAdsiObjects

                # determine whether we have any matching objects
                $Results | ForEach-Object {

                    $Properties = $_.Properties

                    # translate the SID to an account and get the domain name
                    $sAMAccountName = $Properties.Item('sAMAccountName')[0]

                    if ($Properties.PropertyNames -contains ('name'))
                    {
                        $Name = $Properties.Item('name')[0]
                    }
                    else
                    {
                        $Name = $sAMAccountName
                    }

                    try
                    {
                        switch ($ResultType)
                        {
                            'Computer'
                            {
                                [PSCustomObject] @{
                                    FQDN = $Properties.Item('dNSHostName')[0]
                                    Name = $Name
                                    DomainName = $DomainObject.FQDN
                                    OperatingSystem = $Properties.Item('OperatingSystem')[0]
                                    OperatingSystemVersion = $Properties.Item('OperatingSystemVersion')[0]
                                }
                            }
                            'User'
                            {
                                $ObjectType = $SchemaMappings |
                                    Where-Object distinguishedName -EQ $Properties.Item('objectCategory') |
                                    Select-Object -ExpandProperty Name

                                [PSCustomObject] @{
                                    DomainName = $DomainObject.FQDN
                                    Name = $Name
                                    AccountName = $Properties.Item('sAMAccountName')[0]
                                    AccountType = $ObjectType
                                    LastPasswordReset = [DateTime]::FromFileTime($Properties.Item('PwdLastSet')[0])
                                    EncryptionTypes = [EncryptionTypes]($Properties.Item('msDS-SupportedEncryptionTypes')[0] -as [int])
                                    ServicePrincipalName = $Properties.Item('ServicePrincipalName')
                                    DelegationAllowed = $Properties.Item('msDS-AllowedToDelegateTo')
                                }
                            }
                        }
                    }
                    catch
                    {
                        # Put the error on the error stream
                        Write-Message -Stream 'Warning' -Message "Error querying object [$Name]"
                        continue
                    }
                }
            }
            catch
            {
                # Put the error on the error stream
                Write-Message -Stream 'Warning' -Message "Error querying domain [$($DomainObject.NetBios)]"
                continue
            }
        }

        Write-Message -Stream 'Verbose' -Message "End [$ScriptName]"
    }

    Write-Message -Stream 'Verbose' -Message ('Search complete. Found {0} object(s).' -f $DiscoveredObjects.Count)

    return $DiscoveredObjects | Sort-Object -Property DomainName, Name
}