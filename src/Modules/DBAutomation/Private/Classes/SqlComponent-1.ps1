class SqlComponent
{
    [string]
    $TargetComputerName

    [string]
    $ComputerName

    [Products]
    $Product

    [System.Version]
    $PatchLevel

    [System.Version]
    $ProductVersion

    [string]
    $Edition

    SqlComponent(
        [string]
        $TargetComputerName,

        [string]
        $ComputerName,

        [Products]
        $Product,

        [string]
        $PatchLevel,

        [string]
        $ProductVersion,

        [string]
        $Edition
    ){
        $this.TargetComputerName = $TargetComputerName
        $this.ComputerName = $ComputerName
        $this.Product = $Product
        $this.PatchLevel = $PatchLevel
        $this.ProductVersion = $ProductVersion
        $this.Edition = $Edition
    }
}
