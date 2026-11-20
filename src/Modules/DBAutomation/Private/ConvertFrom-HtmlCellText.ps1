function ConvertFrom-HtmlCellText
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Html
    )

    if ([string]::IsNullOrWhiteSpace($Html))
    {
        return $null
    }

    $decoded = [System.Net.WebUtility]::HtmlDecode($Html)
    $text = [regex]::Replace($decoded, '<[^>]+>', '')
    return ($text -replace '\s+', ' ').Trim()
}