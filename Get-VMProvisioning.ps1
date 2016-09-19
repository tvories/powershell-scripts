# Function to return provisioning information from a VM.
# Tells whether or not the disk is thin provisioned and other basic disk info

function Get-VMProvision {
    
    param ([Object]$VM)

    $view = Get-View $VM
    
    $row = '' | select Name, Provisioned, Total, Used, VMDKs, VMDKsize, DiskUsed, Thin
    $row.Name = $vm.Name
    $row.Provisioned = [math]::round($vm.ProvisionedSpaceGB , 2)
    $row.Total = [math]::round(($view.config.hardware.Device | Measure-Object CapacityInKB -Sum).sum/1048576 , 2)
    $row.Used = [math]::round($vm.UsedSpaceGB , 2)
    $VMDKs = $view.config.hardware.Device.Backing.Filename
    # Some VMDK lists have a blank [] value.  The following removes it
    $row.VMDKs = (($VMDKs -split "`n") | ?{$_ -ne "[]"}) -join "`n" | Out-String
    $row.VMDKsize = $view.config.hardware.Device | where {$_.GetType().name -eq 'VirtualDisk'} | ForEach-Object {($_.capacityinKB)/1048576} | Out-String
    $row.DiskUsed = $vm.Extensiondata.Guest.Disk | ForEach-Object {[math]::round( ($_.Capacity - $_.FreeSpace)/1048576/1024, 2 )} | Out-String
    $row.Thin = $view.config.hardware.Device.Backing.ThinProvisioned | Out-String
    
    $row
}
