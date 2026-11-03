class SqlReportServerComponent : SqlComponent
{
    [string]
    $InstanceName

    [string]
    $InstanceId

    [string]
    $RSVirtualRootWebApp

    [string]
    $RSVirtualRootServer

    SqlReportServerComponent(
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

        [string]
        $RSVirtualRootWebApp,

        [string]
        $RSVirtualRootServer
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
        $this.RSVirtualRootWebApp = $RSVirtualRootWebApp
        $this.RSVirtualRootServer = $RSVirtualRootServer
    }
}
