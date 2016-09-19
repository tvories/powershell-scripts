# Grabs Pagefile Info from guest OS and gives info about it.  Used to QA certain server builds

function Get-PageFileInfo{
    param(
    [Parameter(Mandatory=$True,Position=1)]
    [String]$ComputerName,

    [System.Management.Automation.CredentialAttribute()]$Credential

    )

    # Load CimInstance in Server2003 Compatability Mode
    $CimSessionOption = New-CimSessionOption -Protocol Dcom
    $CimSession = New-CimSession -SessionOption $CimSessionOption -ComputerName $ComputerName -Credential $Credential
    
    # Define Pagefile Object
    $PageFileObject = New-Object PSObject -Property @{
                        Name = $null
                        AutomaticManagedProfile = $null
                        MaxSize = $null
                        InitialSize = $null
                        Type = $null
                        PageDrive = $null
    }

    # Check if pagefile is set to automatically managed
    $PageFileObject.AutomaticManagedProfile = Get-CimInstance -CimSession $CimSession `
    -ClassName Win32_ComputerSystem | Select AutomaticManagedPagefile | foreach {$_.AutomaticManagedPagefile}
    
    # Grab pagefile settings
    $pageCIM = Get-CimInstance -CimSession $CimSession -ClassName Win32_PageFileSetting
    $PageFileObject.Name = $pageCIM.Name
    $PageFileObject.MaxSize = $pageCIM.MaximumSize
    $PageFileObject.InitialSize = $pageCIM.InitialSize
    if($PageFileObject.Name -ne $null){$PageFileObject.PageDrive = $pageCIM.Name.Substring(0,2).ToUpper()}

    # Determine what type of settings - Automatic, System managed, or Custom
    # If Automatic
    if($PageFileObject.AutomaticManagedProfile -eq $True){
        $PageFileObject.Type = "Automatically Managed"
    } else {
        # If System Managed
        if($PageFileObject.MaxSize -eq 0 -and $PageFileObject.InitialSize -eq 0){
            $PageFileObject.Type = "System Managed"
        } 
        # If Custom
        elseif($PageFileObject.MaxSize -gt 0 -and $PageFileObject.InitialSize -gt 0) {
            $PageFileObject.Type = "Custom Size"
        } else {
            $PageFileObject.Type = "Unknown"
        }
    }
    $PageFileObject
}
