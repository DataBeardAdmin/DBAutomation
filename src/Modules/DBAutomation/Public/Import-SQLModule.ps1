# Sourced from SqlServerDsc common modules (originally Import-SQLPSModule, renamed and modified).
function Import-SQLModule
{
    [CmdletBinding()]
    param()
    <#
        Check if either of the modules are already loaded into the session.
        Prefer to use the first one (in order found).
        NOTE: There should actually only be either SqlServer or SQLPS loaded,
        otherwise there can be problems with wrong assemblies being loaded.
    #>
    $loadedModuleName = (Get-Module -Name @('SqlServer', 'SQLPS') | Select-Object -First 1).Name
    if ($loadedModuleName)
    {
        Write-Verbose -Message ('Found PowerShell module {0} already imported in the session.' -f $loadedModuleName)
        return
    }

    $availableModuleName = $null

    # Get the newest SqlServer module if more than one exist
    $availableModule = Get-Module -FullyQualifiedName 'SqlServer' -ListAvailable |
        Sort-Object -Property 'Version' -Descending |
        Select-Object -First 1 -Property Name, Path, Version

    if ($availableModule)
    {
        $availableModuleName = $availableModule.Name
        Write-Verbose -Message 'Preferred module SqlServer found.'
    }
    else
    {
        Write-Verbose -Message 'Information: PowerShell module SqlServer not found, trying to use older SQLPS module.'

        <#
            After installing SQL Server the current PowerShell session doesn't know about the new path
            that was added for the SQLPS module.
            This reloads PowerShell session environment variable PSModulePath to make sure it contains
            all paths.
        #>
        $env:PSModulePath = [System.Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

        <#
            Get the newest SQLPS module if more than one exist.
        #>
        $availableModule = Get-Module -FullyQualifiedName 'SQLPS' -ListAvailable |
            Select-Object -Property Name, Path, @{
                Name = 'Version'
                Expression = {
                    # Parse the build version number '120', '130' from the Path.
                    (Select-String -InputObject $_.Path -Pattern '\\([0-9]{3})\\' -List).Matches.Groups[1].Value
                }
            } |
            Sort-Object -Property 'Version' -Descending |
            Select-Object -First 1

        if ($availableModule)
        {
            # This sets $availableModuleName to the Path of the module to be loaded.
            $availableModuleName = Split-Path -Path $availableModule.Path -Parent
        }
    }

    if ($availableModuleName)
    {
        try
        {
            Write-Debug -Message 'SQLPS module changes CWD to SQLSERVER:\ when loading, pushing location to pop it when module is loaded.'
            Push-Location

            <#
                SQLPS has unapproved verbs, disable checking to ignore Warnings.
                Suppressing verbose so all cmdlet is not listed.
            #>
            $importedModule = Import-Module -Name $availableModuleName -DisableNameChecking -Verbose:$false -PassThru -ErrorAction Stop

            <#
                SQLPS returns two entries, one with module type 'Script' and another with module type 'Manifest'.
                Only return the object with module type 'Manifest'.
                SqlServer only returns one object (of module type 'Script'), so no need to do anything for SqlServer module.
            #>
            if ($availableModuleName -ne 'SqlServer')
            {
                $importedModule = $importedModule | Where-Object -Property 'ModuleType' -EQ -Value 'Manifest'
            }

            Write-Verbose -Message ('Importing PowerShell module [{0}] with version [{1}] from path [{2}].' -f $importedModule.Name, $importedModule.Version, $importedModule.Path)
        }
        catch
        {
            $Message = 'Failed to import {0} module.' -f $availableModuleName
            Write-Message -Stream 'Warning' -Message $Message
        }
        finally
        {
            Write-Debug -Message ('Popping location back to what it was before importing SQLPS module.')
            Pop-Location
        }
    }
    else
    {
        $Message = 'Neither PowerShell module SqlServer or SQLPS was found. Unable to run SQL Server cmdlets.'
        Write-Message -Stream 'Warning' -Message $Message
    }
}
