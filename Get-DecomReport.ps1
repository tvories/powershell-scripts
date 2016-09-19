# The following program is an example of a custom report I created 
# to gather info on a server before decomissioning it.  This is mostly
# just an example of work, not really usable unless it fits your environment.

function Get-DecomReport{
    param(
        [Parameter(Mandatory=$False,Position=1)]
        [String]$ServerName,

        [System.Management.Automation.CredentialAttribute()]$Credential
        )

        if ($Credential -eq $null) {
        Write-Verbose "Credential not supplied, prompting for credential."
        $UName = Read-Host "What user would you like to run the QA as?  This is probably your admin account."
        $Message = "Please type in your admin credentials"
        $Credential = Get-Credential -UserName "DOMAIN\$UName" -Message $Message
    }

    if ($ServerName.Length -eq 0) {
        $ServerName = Read-Host "What server would you like to run the QA on?"
    }

    # Include Function File - See other github functions
    . 'LOCATION OF ADDITIONAL FUNCTIONS'

    # Define Server object
    $ServerObject = New-Object psobject -Property @{
                        ServerName = $ServerName
                        IsPingable = $null
                        InDNS = $null
                        InAD = $null
                        InvSphere = $null
    }

    # Create CIM Instance Placeholder to reuse in other functions
    $CimSessionOption = $null
    $CimSession = $null

    # Installed programs variable to be used in multiple functions
    $InstalledPrograms = $null

    # List of services variable to be used in multiple functions
    $OSServices = $null

    # Function to grab OS Info
    function Get-OSInfo{
        # Grab OS Version Info
        $OSObj = Get-CimInstance -ClassName Win32_OperatingSystem -cimsession $CimSession `
        | Select Name, Version, ServicePackMajorVersion, OSArchitecture

        # Clean up OS Name and remove install location
        $tempname = $OSObj.Name.split("|")
        $OSObj.Name = $tempname[0].TrimEnd()


        $ServerObject | Add-Member -MemberType NoteProperty -Name OS-Version -Value $OSObj.Name
        $ServerObject | Add-Member -MemberType NoteProperty -Name OS-VersionNumber -Value $OSObj.Version
        $ServerObject | Add-Member -MemberType NoteProperty -Name OS-ServicePackMajor -Value $OSObj.ServicePackMajorVersion
        $ServerObject | Add-Member -MemberType NoteProperty -Name OS-Architecture -Value $OSObj.OSArchitecture
    
        # Populate InstalledPrograms - This won't work if SCCM Client isn't installed
        try{ 
            $InstalledPrograms = Get-CimInstance -ClassName Win32Reg_AddRemovePrograms -CimSession $CimSession  -ErrorAction Stop
            
            # Determine if Diskeeper is installed
            $diskeeper = $InstalledPrograms | where {$_.DisplayName -match "diskeeper"}
            if($diskeeper -ne $null){
                $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasDiskeeper -Value $True
            } else {
                $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasDiskeeper -Value $False
            }
        } catch {
            
        }

        # Populate OSServices
        $OSServices = Get-CimInstance -ClassName Win32_Service -CimSession $CimSession

        # Determine if SCOM is installed
        $SCOM = $OSServices | where {$_.Name -eq "HealthService"}
        if($SCOM -ne $null){
            $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasSCOM -Value $True
        } else{
            $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasSCOM -Value $False
        }

        # Determine if NetIQ is installed
        # TODO: This needs to be tested
        $NetIQ = $OSServices | where {$_.Name -match "NetIQ"}
        if($NetIQ -ne $null){
            $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasNetIQ -Value $True
        } else {
            $ServerObject | Add-Member -MemberType NoteProperty -Name OS-HasNetIQ -Value $False
        }

        # If physical server, add Server Memory/CPU
        if($ServerObject.Type -eq "Physical"){
            
            # Get memory in GB
            $ServerObject | Add-Member -MemberType NoteProperty -Name Physical-MemoryGB -Value `
            (Get-Memory -RemoteComputer $ServerName -Credential $Credential)

            # Get NumCPU
            $CPU = Get-CPU -RemoteComputer $ServerName -Credential $Credential
            $ServerObject | Add-Member -MemberType NoteProperty -Name Physical-NumCPU -Value $CPU.Count

            # Get SerialNumber for Physical Server
            $SerialNumber = Get-CimInstance -CimSession $CimSession -ClassName Win32_BIOS | Select-Object SerialNumber
            $ServerObject | Add-Member -MemberType NoteProperty -Name Physical-SerialNumber -Value $SerialNumber.SerialNumber
        }
    }

    # Function to grab VM Info
    function Get-VMInfo{
        
        # Create VM Object
        $VM = Get-VM -Name $ServerName -Server $ServerObject.VM-vCenter

        # Add Memory and CPU
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-MemoryGB -Value $VM.MemoryGB
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-NumCPU -Value $VM.NumCpu
    }



    # Perform initial status check
    try { 
        $ServerObject.IsPingable = Test-NetConnection -InformationLevel Quiet -ComputerName $ServerName}
    catch {
        $ServerObject.IsPingable = $False}
    
    # Determine DNS Status
    try {
        $DNSIP = [System.Net.DNS]::GetHostAddresses($ServerName)`
        | select IPAddressToString | foreach {$_.IPAddressToString}
        $ServerObject.InDNS = $True
        $ServerObject | Add-Member -MemberType NoteProperty -Name DNS-IP -Value $DNSIP}
    catch{
        $ServerObject.InDNS = $False}
    
    # Determine AD Status
    try {
        $tempAD = Get-ADComputer -Identity $ServerName -Credential $Credential
        $ServerObject.InAD = $True
        $adlastlogon = Get-LastADCheckin -ComputerName $ServerName -Credential $Credential `
        | Select LastLogonDate | foreach {$_.LastLogonDate}
        $ServerObject | Add-Member -MemberType NoteProperty -Name AD-LastLogon -Value $adlastlogon
    } catch {
        $ServerObject.InAD = $False}

    # Determine if exists in vSphere
    $TempFindVM = Find-VM -Name $ServerName
    if ($TempFindVM -eq $null){
        $ServerObject.InvSphere = $False
    } else {
        $ServerObject.InvSphere = $True
        # Add VM Location Properties to ServerObject
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-PowerState -Value $TempFindVM.PowerState
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-Host -Value $TempFindVM.Host
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-vCenter -Value $TempFindVM.VCenter
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-Cluster -Value $TempFindVM.Cluster
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-DataCenter -Value $TempFindVM.DataCenter
        $ServerObject | Add-Member -MemberType NoteProperty -Name VM-Name -Value $TempFindVM.Name
    }



    # If the Server is Pingable and in exists in AD
    if($ServerObject.IsPingable -and $ServerObject.inAD){
        # Load CimInstance in Server2003 Compatability Mode
        $CimSessionOption = New-CimSessionOption -Protocol Dcom
        $CimSession = New-CimSession -SessionOption $CimSessionOption -ComputerName $ServerName -Credential $Credential

        # Determine if server is physical or virtual
        $gwmiCSModel = Get-CimInstance -Class Win32_ComputerSystem -CimSession $CimSession | select Model
        if($gwmiCSModel.Model -eq "VMware Virtual Platform"){
            $ServerObject | Add-Member -MemberType NoteProperty -Name Type -Value "Virtual"
        } else {
            $ServerObject | Add-Member -MemberType NoteProperty -Name Type -Value "Physical"
        }

        Get-OSInfo
    }


    $ServerObject
}
