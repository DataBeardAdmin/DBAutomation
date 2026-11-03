function Wait-ParallelCommand
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job[]]
        $Jobs,

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

    # Get the total number of jobs
    $totalJobs = ($Jobs | Measure-Object).Count

    $results = @()
    if ($totalJobs -gt 1)
    {
        do
        {
            # Cancel any long-running jobs
            if ($TimeoutMinutes -gt 0)
            {
                $Jobs | Where-Object -FilterScript {
                    if (-not [String]::IsNullOrEmpty($_.PSBeginTime))
                    {
                        [DateTime]::Parse($_.PSBeginTime).AddMinutes($TimeoutMinutes) -lt [DateTime]::Now
                    }
                } | Stop-Job
            }

            # Build a listing of jobs and states
            $jobStates = ($Jobs |
                    Group-Object -Property State |
                    Sort-Object -Property Name |
                    ForEach-Object -Process { "$($_.Name) ($($_.Count))" }) -join '; '

            $Completed = $Jobs | Where-Object State -NotIn @('Running', 'NotStarted')

            foreach ($CompletedJob in $Completed | Where-Object Name -NotIn $results.Member)
            {
                $results += @{
                    Member = $CompletedJob.Name
                    Results = Receive-Job -Job $CompletedJob
                }
            }

            # Build a listing of active jobs
            # Using PSThreadJob, a job can also be 'NotStarted' when throttling threads. We will count these the same as running.
            $activeJobNames = ($Jobs | Where-Object -Property State -In @('Running', 'NotStarted')).Name

            # Calculate the number of jobs that are not running
            $notRunning = ($Completed | Measure-Object).Count

            # Determine how far along in the process we are
            $percentComplete = ($notRunning / $totalJobs) * 100

            # Write the current progress out
            Write-Progress -Activity 'Parallel Command' -Status $jobStates -CurrentOperation "Active: $($activeJobNames -join '; ')" -PercentComplete $percentComplete

            # Sleep for a second
            Start-Sleep -Seconds 1
        } while ($notRunning -lt $totalJobs)
        Write-Progress -Activity 'Parallel Command' -Completed
    }
    else
    {
        if ($TimeoutMinutes -gt 0)
        {
            $TimeoutSeconds = $TimeoutMinutes * 60
        }
        else
        {
            $TimeoutSeconds = $TimeoutMinutes
        }

        $Output = $Jobs | Wait-Job -Timeout $TimeoutSeconds | Receive-Job

        if ($Jobs.State -eq 'Running')
        {
            $Jobs | Stop-Job
        }

        $results = @{
            Member = $Jobs[0].Name
            Results = $Output
        }
    }

    if ($OutputJobStatus.IsPresent)
    {
        # Report the final job status
        $Jobs | Format-Table -Property Name, State, PSBeginTime, PSEndTime -AutoSize
    }

    # Remove all the jobs
    $Jobs | Remove-Job

    if ($OutputResults.IsPresent)
    {
        $results.Results | Sort-Object { $_.Member }
    }
}