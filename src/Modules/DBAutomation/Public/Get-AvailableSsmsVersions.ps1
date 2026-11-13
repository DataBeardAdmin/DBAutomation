function Get-AvailableSsmsVersions
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]
        $ReleaseHistoryUrl = 'https://learn.microsoft.com/en-us/ssms/release-history',

        [Parameter()]
        [int]
        $MaxResults = 5
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Message -Stream 'Verbose' -Message "Fetching SSMS versions from: $ReleaseHistoryUrl"
    $response = Invoke-WebRequest -Uri $ReleaseHistoryUrl -UseBasicParsing -Verbose:$false

    $html = $response.Content

    # Parse table rows that contain a version and a bootstrapper link.
    # This intentionally avoids depending on a specific table ID because Microsoft Learn
    # can change generated HTML around markdown tables.
    $rowPattern = '(?is)<tr[^>]*>(?<row>.*?)</tr>'
    $cellPattern = '(?is)<t[dh][^>]*>(?<cell>.*?)</t[dh]>'

    $results = foreach ($rowMatch in [regex]::Matches($html, $rowPattern))
    {
        $rowHtml = $rowMatch.Groups['row'].Value
        $cells = @([regex]::Matches($rowHtml, $cellPattern) | ForEach-Object {
                $_.Groups['cell'].Value
            })

        if ($cells.Count -lt 2)
        {
            continue
        }

        $rowText = ConvertFrom-HtmlCellText $rowHtml

        # Find the first SSMS-like version in the row.
        $versionMatch = [regex]::Match($rowText, '\b(?<version>\d{2}\.\d+(?:\.\d+)*)\b')
        if (-not $versionMatch.Success)
        {
            continue
        }

        # Find an href in the row.
        $hrefMatch = [regex]::Match($rowHtml, '(?is)<a[^>]+href="(?<href>[^"]+)"[^>]*>(?<text>.*?)</a>')
        if (-not $hrefMatch.Success)
        {
            continue
        }

        $href = [System.Net.WebUtility]::HtmlDecode($hrefMatch.Groups['href'].Value)
        $linkText = ConvertFrom-HtmlCellText $hrefMatch.Groups['text'].Value

        # Keep likely SSMS bootstrapper links.
        if ($rowText -notmatch 'SQL Server Management Studio|SSMS|vs_SSMS')
        {
            continue
        }

        $absoluteUri = try
        {
            [uri]::new([uri]$ReleaseHistoryUrl, $href).AbsoluteUri
        }
        catch
        {
            $href
        }

        $Version = $versionMatch.Groups['version'].Value
        Write-Message -Stream 'Debug' -Message "Found SSMS version: $Version [$absoluteUri]"
        [PSCustomObject]@{
            Version = $Version
            Bootstrapper = $linkText
            BootstrapperUrl = $absoluteUri
            Source = $ReleaseHistoryUrl
            RowText = $rowText
        }
    }

    $results |
        Sort-Object @{ Expression = { [version]$_.Version }; Descending = $true }, BootstrapperUrl -Unique |
        Select-Object -First $MaxResults
}