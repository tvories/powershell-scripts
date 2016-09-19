# This script returns VMware network adaptor info for QAing servers.

function Get-NetAdapterInfo{
    param(
    [Parameter(Mandatory=$True,Position=1)]
    [String]$ComputerName,

    [System.Management.Automation.CredentialAttribute()]$Credential

    )
    # Load CimInstance in Server2003 Compatability Mode
    $CimSessionOption = New-CimSessionOption -Protocol Dcom
    $CimSession = New-CimSession -SessionOption $CimSessionOption -ComputerName $ComputerName -Credential $Credential

    # Array of results
    $resultArr = @()
    # Create custom network object to grab all the info we need
    $NetAdapterObject = New-Object psobject -Property @{
                    AdapterName = $null
                    ConnectionName = $null
                    IPv4Address = $null
                    IPv6Address = $null
                    DNSServers = $null
                    MACAddress = $null
                    DNSDomain = $null
                    Index = $null
    }

    # Function to parse IPv4 and IPv6 from IPAddress field
    function Parse-IP{
        param(
            [Object]$IPAddressStr
        )

        # Object to return
        $IPObject = New-Object psobject -Property @{
                        IPv4Address = $null
                        IPv6Address = $null
        }

        if($IPAddressStr.Count -gt 1){
            $IPObject.IPv4Address = $IPAddressStr[0]
            $IPObject.IPv6Address = $IPAddressStr[1]
        } else {
            $IPObject.IPv4Address = $IPAddressStr[0]
        }

        return $IPObject
    }
    
    # Load Network adapter and network adapter config
    $netAdapterConfig = Get-CimInstance -CimSession $CimSession -ClassName Win32_Networkadapterconfiguration `
    -filter "ipenabled = 'True'"
    $netAdapter = Get-CimInstance -CimSession $CimSession -ClassName win32_Networkadapter

    # Match config with adapter and add to result array
    foreach($adapt in $netAdapterConfig){
        
        # Match NetAdapter with Config
        $matchAdapter = $netAdapter | where {$_.Index -eq $adapt.Index}
        
        # Clear NetAdapterObject before re-creating it
        $netobj = $NetAdapterObject.psobject.copy()

        # Parse IPv4 and 6 addresses
        $ips = Parse-IP -IPAddressStr $adapt.IPAddress

        $netobj.AdapterName = $matchAdapter.Name
        $netobj.ConnectionName = $matchAdapter.NetConnectionID
        $netobj.IPv4Address = $ips.IPv4Address
        $netobj.IPv6Address = $ips.IPv6Address
        $netobj.DNSServers = $adapt.DNSServerSearchOrder
        $netobj.MACAddress = $matchAdapter.MACAddress
        $netobj.DNSDomain = $adapt.DNSDomain
        $netobj.Index = $adapt.Index

        # Add to result array
        $resultArr += $netobj
    }

    return $resultArr
}
