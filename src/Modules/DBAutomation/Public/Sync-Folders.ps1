<#
    .SYNOPSIS
    This function will sync the contents of the 'LocalDestination' using 'RemoteSource' as a reference.
    The sync will be executed on each of the members of 'ComputerNames' and will use 'Credential' to connect to 'RemoteSource'.

    .PARAMETER ComputerNames
    This is a list of computer names (resolvable in DNS) where the sync will be executed from.

    .PARAMETER Credential
    The 'Credential' is used to connect to 'RemoteSource' because the sync will be executed on each member of 'ComputerNames' and this eliminates the 'double-hop' issue.

    .PARAMETER RemoteSource
    The file server remote to the target ComputerNames. This directory will be used as a reference for syncing to LocalDestination

    .PARAMETER LocalDestination
    This is the local path relative to the ComputerNames that will be synced using the RemoteSource as a reference.

    .PARAMETER CopyTimeout
    This is the number of minutes to allow the sync to run before cancelling it.

    .NOTES
    This process uses robocopy to sync 'RemoteSource' to 'LocalDestination' on the 'ComputerNames' supplied. This will copy files only, not permissions or extended attributes.

    .EXAMPLE
    Sync-Folders -ComputerNames @(Computer1, Computer2) -Credential [PassCredential] -RemoteSource '\\FileServer\Share' -LocalDestination 'D:\TargetFolder'
#>

Function Sync-Folders
{
    [CmdletBinding()]
    param
    (
        [Alias('ComputerNames')]
        [Parameter(Mandatory = $true)]
        [String[]]
        $ComputerName,

        [Parameter(Mandatory = $true)]
        [PSCredential]
        $Credential,

        [Parameter(Mandatory = $true)]
        [String]
        $RemoteSource,

        [Parameter(Mandatory = $true)]
        [String]
        $LocalDestination
    )

    $RobocopyArgumentList = ('"{0}" "{1}" /NJH /NJS /NDL /nc /ns /nfl /MIR /J' -f $RemoteSource, $LocalDestination)

    $RobocopyMessage = "Running: robocopy $RobocopyArgumentList"
    Write-Message -Stream 'Verbose' -Message $RobocopyMessage

    # Robocopy the patches from the file share to the local destination
    $Messages = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference

        # Ensure the destination path exists
        if ($false -eq (Test-Path -Path $using:LocalDestination))
        {
            New-Item -Path $using:LocalDestination -ItemType Directory > $null
        }

        # Map a drive to the remote server using the specified credential
        $null = New-PSDrive -Name 'Sync' -PSProvider FileSystem -Root $using:RemoteSource -Credential $using:Credential

        # Create a splat for robocopy
        $robocopyParameters = @{
            FilePath = (Get-Command -Name 'robocopy.exe' -ErrorAction Stop).Name
            ArgumentList = $using:RobocopyArgumentList
        }

        # Run robocopy and wait for it to finish
        $robocopyProcess = Start-Process @robocopyParameters -Wait -NoNewWindow -PassThru

        $Time = Get-Date -Format 'HH:mm:ss.ffff'
        $FinishMessage = "Robocopy finished on [$env:COMPUTERNAME], Exit code[$($robocopyProcess.ExitCode)]"
        Write-Verbose -Message "[$Time]$FinishMessage"

        # Copy process is done, un-map the drive
        Remove-PSDrive -Name 'Sync' -Force

        if ($robocopyProcess.ExitCode -in @(8, 16))
        {
            <#
                https://docs.microsoft.com/en-us/troubleshoot/windows-server/backup-and-storage/return-codes-used-robocopy-utility
                Improved clarity: https://ss64.com/nt/robocopy-exit.html

                0       No errors occurred, and no copying was done.
                        The source and destination directory trees are completely synchronized.

                1       One or more files were copied successfully (that is, new files have arrived).

                2       Some Extra files or directories were detected. No files were copied
                        Examine the output log for details.

                3       (2+1) Some files were copied. Additional files were present. No failure was encountered.

                4       Some Mismatched files or directories were detected.
                        Examine the output log. Housekeeping might be required.

                5       (4+1) Some files were copied. Some files were mismatched. No failure was encountered.

                6       (4+2) Additional files and mismatched files exist. No files were copied and no failures were encountered.
                            This means that the files already exist in the destination directory

                7       (4+1+2) Files were copied, a file mismatch was present, and additional files were present.

                8       Some files or directories could not be copied
                        (copy errors occurred and the retry limit was exceeded).
                        Check these errors further.

                16      Serious error. Robocopy did not copy any files.
                        Either a usage error or an error due to insufficient access privileges
                        on the source or destination directories.
            #>

            $resultString = switch ($robocopyProcess.ExitCode)
            {
                8 { 'Some files or directories could not be copied.' }
                16 { 'Serious error. Robocopy did not copy any files.' }
            }

            $FailedCopy = "Robocopy failed with error: $resultString"
        }
        else
        {
            $FailedCopy = $null
        }

        Unblock-File -Path "$using:LocalDestination\*.*"

        [PSCustomObject]@{
            FinishMessage = $FinishMessage
            FailedCopy = $FailedCopy
        }
    }

    foreach ($Message in $Messages)
    {
        Write-Message -Stream 'Log' -Message $Message.FinishMessage

        if ($null -ne $Message.FailedCopy)
        {
            $Message = $Message.FailedCopy
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }
}