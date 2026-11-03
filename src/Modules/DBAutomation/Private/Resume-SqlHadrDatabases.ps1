<#
    .SYNOPSIS
    This function is used for resuming databases in an Availability Group that are suspended.

    .DESCRIPTION
    Resume the database replicas in an Availability Group that are suspended.
    This is typically used after an update or maintenance operation that may have caused the databases to be suspended.

    .PARAMETER SqlServer
    The server that that you are connecting to.

    .PARAMETER Server
    In place of SqlServer, this is an SMO server object that can be passed in.

    .PARAMETER AvailabilityGroupName
    This parameter specifies the Availability Group(s) that have databases to potentially resume.

    .NOTES
    Per https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.databasereplicasuspendreason:
    SuspendFromUser		0	User initiated suspend command.
    SuspendFromPartner	1	Partner initiated suspend command.
    SuspendFromRedo		2	The database replica is currently in redo mode.
    SuspendFromApply	3	The database replica is currently in apply mode.
    SuspendFromCapture	4	The database replica is currently in capture mode.
    SuspendFromRestart	5	The database replica is restarting.
    SuspendFromUndo		6	The database replica is currently in undo mode.
    NotApplicable		7	The database is not suspended.

    We are not resuming databases suspended from a user, but rather those that are suspended due to being in
    redo/apply/capture/undo mode or restarting as these are typically the result of an update or maintenance operation.

    .EXAMPLE
    Resume-SqlHadrDatabases -SqlServer 'SqlServer' -Verbose
#>

function Resume-SqlHadrDatabases
{
    [CmdletBinding()]
    param
    (
        [Parameter(ParameterSetName = 'SqlServer', Mandatory = $true)]
        [String]
        $SqlServer,

        [Parameter(ParameterSetName = 'ServerObject', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Server]
        $Server,

        [Parameter()]
        [String]
        $AvailabilityGroupName,

        [Parameter()]
        [ValidateSet('SuspendFromUser', 'SuspendFromRedo', 'SuspendFromApply', 'SuspendFromCapture', 'SuspendFromRestart', 'SuspendFromUndo')]
        [String[]]
        $SuspendReasons = @('SuspendFromRedo', 'SuspendFromApply', 'SuspendFromCapture', 'SuspendFromRestart', 'SuspendFromUndo')
    )

    if ($PSCmdlet.ParameterSetName -eq 'SqlServer')
    {
        $Server = Connect-SqlServer -SqlServer $SqlServer -Verbose:$VerbosePreference
    }

    if ([String]::IsNullOrEmpty($AvailabilityGroupName))
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -ExcludeDistributed
    }
    else
    {
        $AvailabilityGroups = $Server | Get-AvailabilityGroup -Name $AvailabilityGroupName -ExcludeDistributed
    }

    foreach ($AvailabilityGroup in $AvailabilityGroups)
    {
        $Databases = $AvailabilityGroup.AvailabilityDatabases | Where-Object { $true -eq $_.IsSuspended }
        foreach ($Database in $Databases)
        {
            $SuspendReason = ($AvailabilityGroup.DatabaseReplicaStates |
                    Where-Object { $_.AvailabilityDatabaseName -eq $Database.Name -and $true -eq $_.IsLocal }).SuspendReason
            $Message = "Database [$($Database.Name)] in Availability Group [$($AvailabilityGroup.Name)] is suspended with reason [$SuspendReason]."
            Write-Message -Stream 'Debug' -Message $Message

            if ($SuspendReason -in $SuspendReasons)
            {
                try
                {
                    $Message = "Resuming Availability Database [$($Database.Name)]."
                    Write-Message -Stream 'Verbose' -Message $Message
                    $Database.ResumeDataMovement()
                }
                catch
                {
                    $ErrMessage = $_.Exception.ToString()
                    $Message = "Error resuming database [$($Database.Name)]. Error: $ErrMessage"
                    Write-Message -Stream 'Error' -Message $Message
                }
            }
            else
            {
                $Message = "Database [$($Database.Name)] not resumed because [$SuspendReason] is not in the list of reasons to resume."
                Write-Message -Stream 'Warning' -Message $Message
            }
        }
    }
}
