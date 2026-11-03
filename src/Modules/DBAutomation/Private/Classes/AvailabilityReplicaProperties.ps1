enum AvailabilityReplicaWritableProperties
{
    AvailabilityMode
    FailoverMode
    ConnectionModeInPrimaryRole
    ConnectionModeInSecondaryRole
    SeedingMode
    SessionTimeout
    EndpointUrl
    BackupPriority
}

# We're creating these both in the same script to ensure visibility if changes are required.
enum AvailabilityReplicaAllProperties
{
    # Writable - Ensure these match the properties in AvailabilityReplicaWritableProperties
    AvailabilityMode
    FailoverMode
    ConnectionModeInPrimaryRole
    ConnectionModeInSecondaryRole
    SeedingMode
    SessionTimeout
    EndpointUrl
    BackupPriority

    # Read-only
    ConnectionState
    JoinState
    MemberState
    OperationalState
    QuorumVoteCount
    Role
    RollupRecoveryState
    RollupSynchronizationState
    Name
    AvailabilityReplicaServerName
}
