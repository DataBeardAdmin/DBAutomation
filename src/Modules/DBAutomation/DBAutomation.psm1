#Get public and private function definition files.
$Public = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue )
$Classes = @( Get-ChildItem -Path $PSScriptRoot\Private\Classes\*.ps1 -ErrorAction SilentlyContinue )

#Dot source the files
Foreach ($import in @($Classes + $Public + $Private))
{
    Try
    {
        . $import.FullName
    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

$Script:SessionId = New-Guid

$SetLogPath = @{
    NoLog = $true
}

[bool]$LoggingEnabled = $false
if ([bool]::TryParse($env:DBAutomation_LoggingEnabled, [ref]$LoggingEnabled))
{
    $SetLogPath += @{
        EnableLogging = $LoggingEnabled
    }
}
else
{
    $SetLogPath += @{
        EnableLogging = $true
    }
}

if ($false -eq [string]::IsNullOrEmpty($env:DBAutomation_LogPath))
{
    $LogPath = $env:DBAutomation_LogPath
    $Directory = [System.IO.Path]::GetDirectoryName($LogPath)
    $File = [System.IO.Path]::GetFileName($LogPath)

    if ($false -eq [string]::IsNullOrEmpty($Directory))
    {
        $SetLogPath += @{
            Directory = $Directory
        }
    }

    if ($false -eq [string]::IsNullOrEmpty($File))
    {
        $SetLogPath += @{
            File = $File
        }
    }
}

Set-LogPath @SetLogPath

Import-SQLModule

Export-ModuleMember -Function $Public.Basename