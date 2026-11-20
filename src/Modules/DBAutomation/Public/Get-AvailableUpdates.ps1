function Get-AvailableUpdates
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [String]
        $UpdatePath,

        [Parameter()]
        [Switch]
        $SingleUpdate
    )

    Write-Message -Stream 'Verbose' -Message "Connecting to [$ComputerName], looking for local update cache."
    Invoke-Command -ArgumentList $UpdatePath -ScriptBlock {
        param
        (
            [String]
            $UpdatePath,

            [Switch]
            $SingleUpdate
        )

        $ManifestPatchVersions = @()
        $Updates = @(
            Get-ChildItem -Path $UpdatePath -Recurse -Filter 'ChannelManifest.json' | ForEach-Object {
                $LayoutFile = $_
                $LayoutPath = $LayoutFile.Directory.FullName
                $BootstrapperPath = Join-Path -Path $LayoutPath -ChildPath 'vs_setup.exe'
                $manifest = Get-Content $LayoutFile.FullName -Raw | ConvertFrom-Json
                $Installer = Get-ChildItem -Path $LayoutPath -Filter 'vs_SSMS_*.exe' | Select-Object -First 1
                $ManifestPatchVersions += [System.Version]::Parse($manifest.info.productDisplayVersion)

                [PSCustomObject]@{
                    Name = $Installer.Name
                    FullName = $BootstrapperPath
                    Type = 'Manifest'
                    ProductVersion = "$($manifest.info.productName) [$($manifest.info.productDisplayVersion)]"
                    PatchVersion = [System.Version]::Parse($manifest.info.productDisplayVersion)
                }
            }

            Get-ChildItem -Path $UpdatePath -File | Select-Object -Property @(
                'Name',
                'FullName',
                @{ Name = 'Type'; Expression = { 'File' } },
                @{ Name = 'ProductVersion'; Expression = { $_.VersionInfo.ProductName } },
                @{ Name = 'PatchVersion'; Expression = { [System.Version]::Parse($_.VersionInfo.ProductVersion) } }
            )
        )

        if ($using:SingleUpdate.IsPresent)
        {
            $Updates |
                Where-Object { $_.Type -ne 'File' -or $_.PatchVersion -notin $ManifestPatchVersions } |
                Sort-Object -Property PatchVersion -Descending |
                Select-Object -First 1
        }
        else
        {
            $Updates |
                Where-Object { $_.Type -ne 'File' -or $_.PatchVersion -notin $ManifestPatchVersions } |
                Sort-Object -Property PatchVersion
        }
    } -ComputerName $ComputerName -ErrorAction Stop
}