function Invoke-ParallelCommand
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]
        $ArgumentList,

        [Parameter(Mandatory = $true)]
        [scriptblock]
        $Script,

        [Parameter()]
        [scriptblock]
        $InitializationScript,

        [Parameter()]
        [string[]]
        $RequiredFunctions,

        [Parameter()]
        [Switch]
        $OutputJobStatus,

        [Parameter()]
        [Switch]
        $OutputResults,

        [Alias('ProcessTimeout', 'Timeout')]
        [Parameter(HelpMessage = 'The number of minutes to allow a job to run before cancelling it.')]
        [ValidateRange(1, 1440)]
        $TimeoutMinutes = -1
    )

    # splat parameters to Start-ParallelCommand
    $ParallelCommandParams = @{
        ArgumentList = $ArgumentList
        Script = $Script
        InitializationScript = $InitializationScript
    }
    if ($RequiredFunctions)
    {
        $ParallelCommandParams += @{
            RequiredFunctions = $RequiredFunctions
        }
    }

    $Jobs = Start-ParallelCommand @ParallelCommandParams

    # splat parameters to Wait-ParallelCommand
    $ParallelCommandParams = @{
        Jobs = $Jobs
        OutputJobStatus = $OutputJobStatus.IsPresent
        OutputResults = $OutputResults.IsPresent
    }

    if ($TimeoutMinutes -gt 0)
    {
        $ParallelCommandParams += @{
            TimeoutMinutes = $TimeoutMinutes
        }
    }

    Wait-ParallelCommand @ParallelCommandParams
}