function Start-ParallelCommand
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
        $RequiredFunctions
    )

    Begin
    {
        # Test whether ThreadJob module exists
        if ($null -ne (Get-Module -Name 'ThreadJob' -ListAvailable -Verbose:$false -ErrorAction 'SilentlyContinue'))
        {
            # ThreadJob module is installed, but not loaded; bring it in now.
            $UserVerbosePreference = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            Import-Module -Name 'ThreadJob' -Verbose:$false -ErrorAction 'Stop' > $null
            $VerbosePreference = $UserVerbosePreference
            $UseThreadJob = $true
        }
        else
        {
            # ThreadJob module is not installed, default to native PowerShell jobs.
            $Message = 'ThreadJob is not installed. Using native PowerShell jobs instead. Performance may vary.'
            Write-Message -Stream 'Warning' -Message $Message
            $UseThreadJob = $false
        }
    }

    Process
    {
        if ($RequiredFunctions)
        {
            $FunctionScript = Get-FunctionScript -RequiredFunctions $RequiredFunctions
            if ($InitializationScript)
            {
                $InitializationScript = $InitializationScript.ToString(), $FunctionScript -join "`r`n"
                $InitializationScript = [ScriptBlock]::Create($InitializationScript)
            }
            else
            {
                $InitializationScript = [ScriptBlock]::Create($FunctionScript)
            }
        }

        $Jobs = @()
        for ($x = 0; $x -lt $ArgumentList.Count; $x++)
        {
            if ($ArgumentList[$x] | Get-Member | Where-Object Name -EQ 'ScriptName')
            {
                $JobName = $ArgumentList[$x].ScriptName
            }
            else
            {
                $JobName = "ParallelCommand: #$x"
            }

            # splat parameters to Start-ParallelCommand
            $ParallelCommandParams = @{
                Name = $JobName
                ScriptBlock = $Script
                ArgumentList = $ArgumentList[$x]
            }
            if ($InitializationScript)
            {
                $ParallelCommandParams += @{
                    InitializationScript = $InitializationScript
                }
            }

            Write-Message -Stream 'Verbose' -Message "Starting $JobName"
            if ($UseThreadJob)
            {
                $Jobs += Start-ThreadJob @ParallelCommandParams
            }
            else
            {
                $Jobs += Start-Job @ParallelCommandParams
            }
        }
    }

    End
    {
        return $Jobs
    }
}