function Get-LocalAdministrators {
    # This function returns the local administrators of a remote system.
    
    param ([string]$computername=$env:computername,
    [System.Management.Automation.CredentialAttribute()]$Credential
    )

    $computername = $computername.toupper()
    $ADMINS = get-wmiobject -computername $computername -Credential $Credential -query "select * from win32_groupuser where GroupComponent=""Win32_Group.Domain='$computername',Name='administrators'""" | % {$_.partcomponent}

    foreach ($ADMIN in $ADMINS) {
                $admin = $admin.replace("\\$computername\root\cimv2:Win32_UserAccount.Domain=","") # trims the results for a user
                $admin = $admin.replace("\\$computername\root\cimv2:Win32_Group.Domain=","") # trims the results for a group
                $admin = $admin.replace('Name="',"")
                $admin = $admin.Replace("`"","")
                $admin = $admin.split(",")

                $objOutput = New-Object PSObject -Property @{
                    Machinename = $computername
                    Fullname = ("$($admin[0])\$($admin[1])")
                    DomainName  =$admin[0]
                    UserName = $admin[1]
                }#end object

   $objreport+=@($objoutput)
    }#end for

    return $objreport
}
