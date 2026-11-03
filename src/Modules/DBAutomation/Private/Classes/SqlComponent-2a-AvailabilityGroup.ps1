class SqlAvailabilityGroup
{
    [string]
    $Name

    [string]
    $Listener

    [string]
    $DnsName

    [string]
    $DnsSuffix

    SqlAvailabilityGroup(
        [string]
        $Name,

        [string]
        $Listener,

        [string]
        $DnsName,

        [string]
        $DnsSuffix
    ){
        $this.Name = $Name
        $this.Listener = $Listener
        $this.DnsName = $DnsName
        $this.DnsSuffix = $DnsSuffix
    }
}
