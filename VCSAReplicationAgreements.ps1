<#
.SYNOPSIS
    Map VCSA Linked Mode Replication Partners
.DESCRIPTION
    Map Linked Mode Replication Partners. Will connect to entry point vCenter and discover all the replication partners.   

.NOTES
    Version:          1.0.0
    Author:           Chris Hildebrandt
    Twitter:          @childebrandt42
#>

if(!(Get-Module -Name "Posh-SSH")){
    
    # Check to see if running as admin.
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $AdminState = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    # If not running as admin close session
    if(!($AdminState)){
        Write-Host "Your PowerShell Session is not running as admin, Please close and run as admin."
        Start-Sleep 30
        exit
    }

    # Install Posh SSH Module
    Write-Host "Installing Posh-SSH PowerShell Module."
    Install-Module 'posh-ssh' -Confirm:$false -Force
}

#---------------------------------------------------------------------------------------------#
#                                  Script Varribles                                           #
#---------------------------------------------------------------------------------------------#
$DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)

# Prompt for Input
$vCenterServers = Read-Host -Prompt "Enter Seed vCenter FQDN:"
$vCenterCredentials = Get-Credential -Message "Enter Root User password" -UserName 'root'
$Credentials = Get-Credential -Message "Enter administrator@vsphere.local password" -UserName 'administrator@vsphere.local'

if (($ReportLocation = Read-Host "Press enter to accept default value $DesktopPath or enter the correct location" ) -eq '') {$ReportLocation = $DesktopPath}



$Date = Get-date -Format MM-dd-yyyy

$ReplicationReport = "$ReportLocation\vCenterReplicationReport-$Date.csv"


#---------------------------------------------------------------------------------------------#
#                                      Functions                                              #
#---------------------------------------------------------------------------------------------#

function Get-ReplicationPartner {

    [CmdletBinding()]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [string[]]$vCenterServer,
        [PSCredential]$vCenterCreds,
        [PSCredential]$SSOAdministratorCreds

    )

    # Run SSH session for each vCenter
    $Password = $SSOAdministratorCreds.GetNetworkCredential().password

    $SessionID = New-SSHSession -ComputerName $vCenterServer -Credential $vCenterCreds -AcceptKey -KeepAliveInterval 5
    $SSHShellStream = New-SSHShellStream -Index $SSHSession.SessionID
    $SSHShellStream.WriteLine("shell")
    $SSHShellStream.WriteLine("chsh -s /bin/bash root")
    $SSHShellStream.WriteLine("logout")
    $Trash = Remove-SSHSession -SessionId $SessionID.SessionId
    $SessionID = New-SSHSession -ComputerName $vCenterServer -Credential $vCenterCreds -AcceptKey -KeepAliveInterval 5


    $ShowReplicationParts = Invoke-SSHCommand "/usr/lib/vmware-vmdir/bin/vdcrepadmin -f showpartners -h localhost -u administrator -w $Password" -SessionID $($sessionID.SessionId) | Select-Object -ExpandProperty Output
    $count = $ShowReplicationParts.Count

    $RepPartners = @()
    $RepData = @()

    foreach($ShowReplicationPart in $ShowReplicationParts){

        $SPPartner = $ShowReplicationPart | Select-String  -Pattern "ldap://" 
        $SPPartner = $SPPartner | Out-String
        $SPPartner = $SPPartner -replace "`t|`n|`r",""
        $SPPartner = $SPPartner.Split(':')[$($SPPartner.Split(':').Count-1)]
        $SPPartner = $SPPartner.Trim('//')
        #$RepPartners += [pscustomobject]@{Partners = $SPPartner}
        $RepPartners += $SPPartner
    }
    
    $Trash = Remove-SSHSession -SessionId $($sessionID.SessionId)

    Return $RepPartners
}


function Get-ReplicationPartnerStatus {

    [CmdletBinding()]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [string[]]$vCenterServer,
        [PSCredential]$vCenterCreds,
        [PSCredential]$SSOAdministratorCreds

    )

    $RepData = @()

    # Run SSH session for each vCenter
    $Password = $SSOAdministratorCreds.GetNetworkCredential().password

    $SessionID = New-SSHSession -ComputerName $vCenterServer -Credential $vCenterCreds -AcceptKey -KeepAliveInterval 5

    $ShowReplicationParts = Invoke-SSHCommand "/usr/lib/vmware-vmdir/bin/vdcrepadmin -f showpartners -h localhost -u administrator -w $Password" -SessionID $($sessionID.SessionId) | Select-Object -ExpandProperty Output
    $count = $ShowReplicationParts.Count


    $showpartnerstatus = Invoke-SSHCommand "/usr/lib/vmware-vmdir/bin/vdcrepadmin -f showpartnerstatus -h localhost -u administrator -w $Password" -SessionID $($sessionID.SessionId) | Select-Object -ExpandProperty Output

    $i = -1
    Do{
    
    $i++
    $SPStatPartner = $showpartnerstatus | Select-String  -Pattern "Partner:" | Select-Object -First 1 -Skip $i
    $SPStatPartner = $SPStatPartner | Out-String
    $SPStatPartner = $SPStatPartner.Split(':')[$($SPStatPartner.Split(':').Count-1)]
    $SPStatPartner = $SPStatPartner.Trim(' ')
    $SPStatPartner = $SPStatPartner -replace "`t|`n|`r",""

    $SPStatHostAval = $showpartnerstatus | Select-String  -Pattern "Host available:" | Select-Object -First 1 -Skip $i
    $SPStatHostAval = $SPStatHostAval | Out-String
    $SPStatHostAval = $SPStatHostAval.Split(':')[$($SPStatHostAval.Split(':').Count-1)]
    $SPStatHostAval = $SPStatHostAval.Trim(' ')
    $SPStatHostAval = $SPStatHostAval -replace "`t|`n|`r",""

    $SPStatStatusAval = $showpartnerstatus | Select-String  -Pattern "Status Available:" | Select-Object -First 1 -Skip $i
    $SPStatStatusAval = $SPStatStatusAval | Out-String
    $SPStatStatusAval = $SPStatStatusAval.Split(':')[$($SPStatStatusAval.Split(':').Count-1)]
    $SPStatStatusAval = $SPStatStatusAval.Trim(' ')
    $SPStatStatusAval = $SPStatStatusAval -replace "`t|`n|`r",""

    $SPStatLastChangeNum = $showpartnerstatus | Select-String  -Pattern "My last change number:" | Select-Object -First 1 -Skip $i
    $SPStatLastChangeNum = $SPStatLastChangeNum | Out-String
    $SPStatLastChangeNum = $SPStatLastChangeNum.Split(':')[$($SPStatLastChangeNum.Split(':').Count-1)]
    $SPStatLastChangeNum = $SPStatLastChangeNum.Trim(' ')
    $SPStatLastChangeNum = $SPStatLastChangeNum -replace "`t|`n|`r",""

    $SPStatPartnerLastChangeNum = $showpartnerstatus | Select-String  -Pattern "Partner has seen my change number:" | Select-Object -First 1 -Skip $i
    $SPStatPartnerLastChangeNum = $SPStatPartnerLastChangeNum | Out-String
    $SPStatPartnerLastChangeNum = $SPStatPartnerLastChangeNum.Split(':')[$($SPStatPartnerLastChangeNum.Split(':').Count-1)]
    $SPStatPartnerLastChangeNum = $SPStatPartnerLastChangeNum.Trim(' ')
    $SPStatPartnerLastChangeNum = $SPStatPartnerLastChangeNum -replace "`t|`n|`r",""

    if(!($SPStatPartnerLastChangeNum -eq $SPStatLastChangeNum)){
        $ReplicationStatus = 'Fail'
    }else{$ReplicationStatus = 'Good'
    $Diff = 0
    $ReplicationStatusNote = ""
    }
    [string]$vCenterServerString = $vCenterServer

    # Create Table
    $RepData += [pscustomobject]@{
        Source = $vCenterServerString
        Partner = $SPStatPartner
        Host_Available = $SPStatHostAval
        Status_Available = $SPStatStatusAval
        Last_Change_Number = $SPStatLastChangeNum
        Partner_Change_Number = $SPStatPartnerLastChangeNum
        Replication_Satus = $ReplicationStatus

    }
    
    }While($i -lt $count - 1)

    $SSHShellStream = New-SSHShellStream -Index $SSHSession.SessionID
    $SSHShellStream.WriteLine("chsh -s /bin/appliancesh root")
    $SSHShellStream.WriteLine("logout")
    $Trash = Remove-SSHSession -SessionId $($sessionID.SessionId)

    Return $RepData
}


#---------------------------------------------------------------------------------------------#
#                                  Script Body                                                #
#---------------------------------------------------------------------------------------------#

# Clear and Define Varibles
[string[]]$AlreadyConnectedTo = @()
$RPList = @()
$vCS = ''
[string[]]$ReplicationPartnerList =@()
$ReplicationPartnerList = $vCenterServers

# Get Replication Partners
While ($ReplicationPartnerList) {
    
    $RepPartner = $ReplicationPartnerList[0]
    if(!($RepPartner)){ break}

    $AlreadyConnectedTo = $AlreadyConnectedTo + $RepPartner

    $RPList = Get-ReplicationPartner -vCenterServer $RepPartner -SSOAdministratorCreds $Credentials -vCenterCreds $vCenterCredentials
    foreach($RPL in $RPList){
        $ReplicationPartnerList += $RPL -join "`n"
        $ReplicationPartnerList = $ReplicationPartnerList | Select-Object -Unique
    }
    $AlreadyConnectedTo = $AlreadyConnectedTo | Select-Object -Unique
    $ReplicationPartnerList = $ReplicationPartnerList | Where-Object { $AlreadyConnectedTo -notcontains $_}

}

# Build out Replication Report
foreach ($VCS in $AlreadyConnectedTo) {
    $ReplicationData = Get-ReplicationPartnerStatus -vCenterServer $VCS -SSOAdministratorCreds $Credentials -vCenterCreds $vCenterCredentials
    $ReplicationData | Select-Object ('Source','Partner','Host_Available','Status_Available','Last_Change_Number','Partner_Change_Number','Replication_Satus') | Export-Csv $ReplicationReport -notypeinformation -Append
}