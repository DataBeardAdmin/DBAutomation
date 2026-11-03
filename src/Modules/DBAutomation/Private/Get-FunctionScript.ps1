function Get-FunctionScript
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String[]]
        $RequiredFunctions,

        [Parameter()]
        [switch]
        $NoLog
    )

    $FunctionScript = foreach ($RequiredFunction in $RequiredFunctions)
    {
        Write-Message -Stream 'Debug' -Message "Exporting function [$RequiredFunction]" -NoLog:$NoLog.IsPresent
        $(Get-ChildItem function: | Where-Object Name -EQ $RequiredFunction).ScriptBlock.Ast.Extent.Text
    }

    return  $FunctionScript -join "`r`n"
}