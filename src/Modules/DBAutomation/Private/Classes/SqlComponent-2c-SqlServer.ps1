class SqlServerComponent : SqlComponent
{
    [string]
    $InstanceName

    [string]
    $InstanceId

    [hashtable]
    $Directories

    [bool]
    $IsHadrEnabled

    [hashtable]
    $Cluster

    [SqlAvailabilityGroup[]]
    $AvailabilityGroups

    SqlServerComponent(
        [string]
        $TargetComputerName,

        [string]
        $ComputerName,

        [string]
        $Product,

        [string]
        $PatchLevel,

        [string]
        $ProductVersion,

        [string]
        $Edition,

        [string]
        $InstanceName,

        [string]
        $InstanceId,

        [hashtable]
        $Directories,

        [bool]
        $IsHadrEnabled,

        [hashtable]
        $Cluster,

        [SqlAvailabilityGroup[]]
        $AvailabilityGroups
    ) : base (
        $TargetComputerName,
        $ComputerName,
        $Product,
        $PatchLevel,
        $ProductVersion,
        $Edition
    ) {
        $this.InstanceName = $InstanceName
        $this.InstanceId = $InstanceId
        $this.Directories = $Directories
        $this.IsHadrEnabled = $IsHadrEnabled
        $this.Cluster = $Cluster
        $this.AvailabilityGroups = $AvailabilityGroups
    }
}
