# This is actually two functions that grab disk information and matches guest OS disk info to VMware vmdk files

function Match-DiskToLetter {

    # Finds a VM and matches the vmdk to the scsi ID and disk letters of the guest OS.

    param(
    [Parameter(Mandatory=$True)]
    [Int]$DiskNumber,

    [Parameter(Mandatory=$True)]
    [Object]$CimSession
    )

    $WMI_DiskMountProps   = @('Name','Label','Caption','Capacity','FreeSpace','Compressed','PageFilePresent','SerialNumber')

    # Gather CIM/WMI Data
    $wmi_diskdrives = $WinDisks
    $wmi_mountpoints = Get-CimInstance -Class Win32_Volume -CimSession $CimSession -Filter "DriveType=3 AND DriveLetter IS NULL" | Select $WMI_DiskMountProps

    # Array to hold objects to return
    $AllDisks = @()
    $DiskElements = @('Partition','VolumeName','Drive')
    foreach ($diskdrive in $wmi_diskdrives) 
    {
        $partitionquery = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID=`"$($diskdrive.DeviceID.replace('\','\\'))`"} WHERE AssocClass = Win32_DiskDriveToDiskPartition"
        $partitions = @(Get-CimInstance -Query $partitionquery -CimSession $CimSession)
        foreach ($partition in $partitions)
        {
            $logicaldiskquery = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=`"$($partition.DeviceID)`"} WHERE AssocClass = Win32_LogicalDiskToPartition"
            $logicaldisks = @(Get-CimInstance -Query $logicaldiskquery -CimSession $CimSession)
            foreach ($logicaldisk in $logicaldisks)
            {
                $diskprops = @{
                                Partition = $partition.Name
                                VolumeName = $logicaldisk.VolumeName
                                Drive = $logicaldisk.Name
                                }
                # Add object to array
                $AllDisks += New-Object psobject -Property $diskprops  | Select $DiskElements
            }
        }
    }
    $drives = $AllDisks | Where {$_.Partition -match "Disk #$DiskNumber"} | Select Drive
    $letters = @()
    foreach ($letter in $drives){ $letters += $letter.Drive }
    #$letter_string = $letters -join " "
    #$letter_string
    $letters
}

function Get-DiskInfo {
    
    param(
    [Parameter(Mandatory=$True,Position=1)]
    [String]$VMName,

    [System.Management.Automation.CredentialAttribute()]$Credential
    )
    if ($Credential -eq $null) {$Credential = Get-Credential}

    $DiskInfo= @()
    $VMObject = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    # Checks RDM
    $DiskType = $VMObject | Get-HardDisk | Select Filename,DiskType

    # If VM is not found by using Get-VM, return "Not found"
    if ($VMObject -ne $null) {
    $VmView = $VMObject | Get-View

    # Load CimInstance in Server2003 Compatability Mode
    $CimSessionOption = New-CimSessionOption -Protocol Dcom
    $CimSession = New-CimSession -SessionOption $CimSessionOption -ComputerName $VMName -Credential $Credential
  
    $WinDisks = Get-CimInstance -Class Win32_DiskDrive -CimSession $CimSession

    # Function to find GPT or MBR - eventually move this to its own function
    function Get-PartitionTable{
        param(
            [String]$DiskNumber
        )
        # Grab just the disk number, ignores letters
        $regex = '\D+'
        
        # Convert disk type to GPT or MBR
        function GPTorMBR{
            param(
            [String]$disktype
            )

            if($disktype -eq "Installable File System"){
                return "MBR"
            } elseif($disktype -eq "GPT: Basic Data"){
                return "GPT"
            } else{
                return "Unknown"
            }
        }

        # Convert string to int ignoring letters
        function StringToIntParse {
            param(
                [String]$str
            )

            $intFromString = [int]($str -replace $regex, "")
            $intFromString
        }

        $parsedDiskNum = StringToIntParse -str $DiskNumber
        $disk = Get-CimInstance -CimSession $CimSession -ClassName Win32_DiskPartition | `
        Where {$_.index -eq 0 -and $_.diskindex -eq $parsedDiskNum}
        $disktype = GPTorMBR -disktype $disk.Type
        $disktype
    }

    foreach ($VirtualSCSIController in ($VMView.Config.Hardware.Device | where {$_.DeviceInfo.Label -match "SCSI Controller"})) {
        foreach ($VirtualDiskDevice in ($VMView.Config.Hardware.Device | where {$_.ControllerKey -eq $VirtualSCSIController.Key})) {
            $VirtualDisk = "" | Select SCSIController, DiskName, SCSI_Id, DiskFile,  DiskSize, WindowsDisk, DiskLabel, IsRDM, DiskMode, IsThinProv, DiskPartitionType
            $VirtualDisk.SCSIController = $VirtualSCSIController.DeviceInfo.Label
            $VirtualDisk.DiskName = $VirtualDiskDevice.DeviceInfo.Label
            $VirtualDisk.SCSI_Id = "$($VirtualSCSIController.BusNumber) : $($VirtualDiskDevice.UnitNumber)"
            $VirtualDisk.DiskFile = $VirtualDiskDevice.Backing.FileName
            $VirtualDisk.DiskSize = $VirtualDiskDevice.CapacityInKB * 1KB / 1GB
            # Checks if disk is RDM
            $match = $DiskType | Where {$_.Filename -eq $VirtualDisk.DiskFile}
            $VirtualDisk.IsRDM = $match.DiskType -eq "RawPhysical" -or $match.DiskType -eq "RawVirtual"
            $VirtualDisk.DiskMode = $VirtualDiskDevice.Backing.DiskMode
            $VirtualDisk.IsThinProv = $VirtualDiskDevice.Backing.ThinProvisioned

            # Match disks based on SCSI ID
            $DiskMatch = $WinDisks | ?{($_.SCSIPort – 2) -eq $VirtualSCSIController.BusNumber -and $_.SCSITargetID -eq $VirtualDiskDevice.UnitNumber}
            if ($DiskMatch){
                $VirtualDisk.WindowsDisk = "Disk $($DiskMatch.Index)"
                $VirtualDisk.DiskLabel = Match-DiskToLetter -DiskNumber $DiskMatch.Index -CimSession $CimSession
                $VirtualDisk.DiskLabel = $VirtualDisk.DiskLabel -join " "
                $VirtualDisk.DiskPartitionType = Get-PartitionTable -DiskNumber $VirtualDisk.WindowsDisk
            }
            else {Write-Host "No matching Windows disk found for SCSI id $($VirtualDisk.SCSI_Id)"}
            $DiskInfo += $VirtualDisk
        }
    }

    $DiskInfo

    } else {
        Write-Host "VM $VMName Not Found"
    }
}
