# Tells whether or not a disk is RDM in VMware.  Returns true if disk is RDM, otherwise false.

function Get-RDM {
    param(
    [Object]$VM
    )

    $result = $VM | Get-HardDisk -DiskType "RawPhysical", "RawVirtual" | Select `
    Parent,Name,DiskType,ScsiCanonicalName,DeviceName

    return $result
}
