######################################################################################
# Command out line 440 and command in line 442 to add all devices to AAD Group!       #
######################################################################################
# region variables

$AADGroupID = Get-AutomationVariable 'AADGroupID' # Azure AD Group ID Variable
$AADGroupName = Get-AutomationVariable 'AADGroupName' # Azure AD Group ID Variable
$tenantID = Get-AutomationVariable 'tenantID' # Azure Tenant ID Variable
#endregion variables

#region -[ Graph App Registration Creds ]-
# Uses a Secret Credential named 'GraphApi' in your Automation Account
$clientInfo = Get-AutomationPSCredential 'GraphApi'
# Username of Automation Credential is the Graph App Registration client ID 
$clientID = $clientInfo.UserName
# Password  of Automation Credential is the Graph App Registration secret key (create one if needed)
$secretPass = $clientInfo.GetNetworkCredential().Password

#Required credentials - Get the client_id and client_secret from the app when creating it in Azure AD
$client_id = $clientID #App ID
$client_secret = $secretPass #API Access Key Password
#endregion graph app registration creds

# function AuthToken
function Get-AuthToken {
<#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
#>

param (
    [Parameter(Mandatory=$true)]
    $TenantID,
    [Parameter(Mandatory=$true)]
    $ClientID,
    [Parameter(Mandatory=$true)]
    $ClientSecret
)
       
try {
    # Define parameters for Microsoft Graph access token retrieval
    $resource = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$TenantID"
    $tokenEndpointUri = "$authority/oauth2/token"
        
    # Get the access token using grant type client_credentials for Application Permissions
    $content = "grant_type=client_credentials&client_id=$ClientID&client_secret=$ClientSecret&resource=$resource"
    $response = Invoke-RestMethod -Uri $tokenEndpointUri -Body $content -Method Post -UseBasicParsing -Verbose:$false

    Write-Host "Got new Access Token!" -ForegroundColor Green
    Write-Host

    # If the accesstoken is valid then create the authentication header
    if ($response.access_token){ 
        # Creating header for Authorization token
        $authHeader = @{
            'Content-Type'='application/json'
            'Authorization'="Bearer " + $response.access_token
            'ExpiresOn'=$response.expires_on
        }
        return $authHeader    
    }
    else {    
        Write-Error "Authorization Access Token is null, check that the client_id and client_secret is correct..."
        break    
    }
}
catch {    
    FatalWebError -Exeption $_.Exception -Function "Get-AuthToken"   
}
} #end of function Get-AuthToken

Function Get-ValidToken {
<#
.SYNOPSIS
This function is used to identify a possible existing Auth Token, and renew it using Get-AuthToken, if it's expired
.DESCRIPTION
Retreives any existing Auth Token in the session, and checks for expiration. If Expired, it will run the Get-AuthToken Fucntion to retreive a new valid Auth Token.
.EXAMPLE
Get-ValidToken
Authenticates you with the Graph API interface by reusing a valid token if available - else a new one is requested using Get-AuthToken
.NOTES
NAME: Get-ValidToken
#>

#Fixing client_secret illegal char (+), which do't go well with web requests
$client_secret = $($client_secret).Replace("+","%2B")
       
# Checking if authToken exists before running authentication
if($global:authToken){
       
# Get current time in (UTC) UNIX format (and ditch the milliseconds)
$CurrentTimeUnix = $((get-date ([DateTime]::UtcNow) -UFormat +%s)).split((Get-Culture).NumberFormat.NumberDecimalSeparator)[0]
                      
# If the authToken exists checking when it expires (converted to minutes for readability in output)
$TokenExpires = [MATH]::floor(([int]$authToken.ExpiresOn - [int]$CurrentTimeUnix) / 60)
       
if($TokenExpires -le 0){    
    Write-Host "Authentication Token expired" $TokenExpires "minutes ago! - Requesting new one..." -ForegroundColor Green
    $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret    
}
else{
    Write-Host "Using valid Authentication Token that expires in" $TokenExpires "minutes..." -ForegroundColor Green
    #Write-Host
}
}    
# Authentication doesn't exist, calling Get-AuthToken function    
else {       
# Getting the authorization token
$global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret    
}    
} 

# end of function Get-ValidToken
####################################
Function Get-AADGroup(){

<#
.SYNOPSIS
This function is used to get AAD Groups from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Groups registered with AAD
.EXAMPLE
Get-AADGroup
Returns all users registered with Azure AD
.NOTES
NAME: Get-AADGroup
#>

[cmdletbinding()]

param
(
$GroupName,
$id,
[switch]$Members
)

# Defining Variables
$graphApiVersion = "v1.0"
$Group_resource = "groups"

try {

    if($id){

    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

    }
    
    elseif($GroupName -eq "" -or $GroupName -eq '$null'){
    
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)"
    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
    
    }

    else {
        
        if(!$Members){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
        (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
        
        }
        
        elseif($Members){
        
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
        $Group = (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value
        
            if($Group){

            $GID = $Group.id

            $Group.displayName
            write-host

            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)/$GID/Members"
            (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

            }

        }
    
    }

}

catch {

$ex = $_.Exception
$errorResponse = $ex.Response.GetResponseStream()
$reader = New-Object System.IO.StreamReader($errorResponse)
$reader.BaseStream.Position = 0
$reader.DiscardBufferedData()
$responseBody = $reader.ReadToEnd();
Write-Output "Response content:`n$responseBody" -f Red
Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
write-Output ""
break

}

}

####################################################

Function Get-AADDevice(){

<#
.SYNOPSIS
This function is used to get an AAD Device from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets an AAD Device registered with AAD
.EXAMPLE
Get-AADDevice -DeviceID $DeviceID
Returns an AAD Device from Azure AD
.NOTES
NAME: Get-AADDevice
#>

[cmdletbinding()]

param
(
$DeviceID
)

# Defining Variables
$graphApiVersion = "v1.0"
$Resource = "devices"

try {

$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$filter=deviceId eq '$DeviceID'"

(Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).value 

}

catch {

$ex = $_.Exception
$errorResponse = $ex.Response.GetResponseStream()
$reader = New-Object System.IO.StreamReader($errorResponse)
$reader.BaseStream.Position = 0
$reader.DiscardBufferedData()
$responseBody = $reader.ReadToEnd();
Write-Output "Response content:`n$responseBody" -f Red
Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
write-Output ""
break

}

}

####################################################

Function Add-AADGroupMember(){

<#
.SYNOPSIS
This function is used to add an member to an AAD Group from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a member to an AAD Group registered with AAD
.EXAMPLE
Add-AADGroupMember -GroupId $GroupId -AADMemberID $AADMemberID
Returns all users registered with Azure AD
.NOTES
NAME: Add-AADGroupMember
#>

[cmdletbinding()]

param
(
$AADGroupId,
$AADMemberId
)

# Defining Variables
$graphApiVersion = "v1.0"
$Resource = "groups"
    
    try {

    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$AADGroupId/members/`$ref"

$JSON = @"

{
    "@odata.id": "https://graph.microsoft.com/v1.0/directoryObjects/$AADMemberId"
}

"@

    Invoke-RestMethod -Uri $uri -Headers $authToken -Method Post -Body $Json -ContentType "application/json"

    }

catch {

$ex = $_.Exception
$errorResponse = $ex.Response.GetResponseStream()
$reader = New-Object System.IO.StreamReader($errorResponse)
$reader.BaseStream.Position = 0
$reader.DiscardBufferedData()
$responseBody = $reader.ReadToEnd();
Write-Output "Response content:`n$responseBody" -f Red
Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
write-Output ""
break

}

}

####################################################

Function Get-ManagedDevices(){

<#
.SYNOPSIS
This function is used to get Intune Managed Devices from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Intune Managed Device
.EXAMPLE
Get-ManagedDevices
Returns all managed devices but excludes EAS devices registered within the Intune Service
.EXAMPLE
Get-ManagedDevices -IncludeEAS
Returns all managed devices including EAS devices registered within the Intune Service
.NOTES
NAME: Get-ManagedDevices
#>

[cmdletbinding()]

# Defining Variables
$graphApiVersion = "beta"
$Resource = "deviceManagement/managedDevices"

try {

    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource`?`$filter=managedDeviceOwnerType eq 'company' and skuFamily eq 'Enterprise' and operatingSystem eq 'Windows'"

    (Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get).Value

}

catch {

$ex = $_.Exception
$errorResponse = $ex.Response.GetResponseStream()
$reader = New-Object System.IO.StreamReader($errorResponse)
$reader.BaseStream.Position = 0
$reader.DiscardBufferedData()
$responseBody = $reader.ReadToEnd();
Write-Output "Response content:`n$responseBody"
Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
Write-Output ""
break

}

}

####################################################

#region Authentication user/password

# Checking if authToken exists before running authentication
if ($global:authToken) {
$DateTime = (Get-Date).ToUniversalTime() # Setting DateTime to Universal time to work in all timezones
$TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes # If the authToken exists checking when it expires
if ($TokenExpires -le 0) {
    Write-Output ("Authentication Token expired" + $TokenExpires + "minutes ago")
    #Calling Microsoft to see if they will give us access with the parameters defined in the config section of this script.
    Get-ValidToken
    $global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret
}
}
else { # Authentication doesn't exist, calling Get-AuthToken function
Get-ValidToken #Calling Microsoft to see if they will give us access with the parameters defined in the config section of this script.
$global:authToken = Get-AuthToken -TenantID $tenantID -ClientID $client_id -ClientSecret $client_secret  # Getting the authorization token
}
#endregion

####################################################

#region AAD Group

# Setting application AAD Group to assign application

if($AADGroupId -eq '$null' -or $AADGroupId -eq ""){

Write-Output "----------------------------------------------------"
Write-Output "AAD Group - '$AADGroupName' doesn't exist, please specify a valid AAD Group..."
Write-Output ""
exit

}

else {

$GroupMembers = Get-AADGroup -GroupName "$AADGroupName" -Members

}

#endregion

####################################################

# Count used to calculate how many devices were added to the Group

$count = 0

# Count to check if any devices have already been added to the Group

$countAdded = 0

#endregion

####################################################

Write-Output "----------------------------------------------------"
Write-Output "Checking if any Managed Devices are registered with Intune..."
Write-Output ""

$Devices = Get-ManagedDevices | Where-Object {$_.wiFiMacAddress -ne '' -and $_.deviceName -ne 'SURFACEHUB01' -and $_.deviceName -notlike 'Kiosk*' -and $_.deviceName -eq "WAP-ABCDEFGH12"}  
# All Devices
# $Devices = Get-ManagedDevices | Where-Object {$_.wiFiMacAddress -ne ''} 


if($Devices){

Write-Output "----------------------------------------------------"
Write-Output "Intune Managed Devices found..."
Write-Output ""

foreach($Device in $Devices){

$DeviceID = $Device.id
$AAD_DeviceID = $Device.azureActiveDirectoryDeviceId

    # Filtering on the wifiMacAddress to add only Notebooks to a specific group

    if($Device.wiFiMacAddress -ne ''){

    Write-Output "----------------------------------------------------"
    Write-Output "Device Name: $($Device.deviceName)"
    Write-Output "Management State: $($Device.managementState)"
    write-Output "Operating System: $($Device.operatingSystem)"
    write-Output "Device Type: $($Device.deviceType)"
    write-Output "Last Sync Date Time: $($Device.lastSyncDateTime)"
    write-Output "Jail Broken: $($Device.jailBroken)"
    write-Output "Compliance State: $($Device.complianceState)"
    write-Output "Enrollment Type: $($Device.enrollmentType)"
    write-Output "AAD Registered: $($Device.aadRegistered)"
    Write-Output "UPN: $($Device.userPrincipalName)"

    Write-Output "----------------------------------------------------"
    Write-Output "Adding device '$($Device.deviceName)' to AAD Group '$AADGroupName'"
    Write-Output ""

    # Getting Device information from Azure AD Devices

    $AAD_Device = Get-AADDevice -DeviceID $AAD_DeviceID       

    $AAD_Id = $AAD_Device.id

        if($GroupMembers.id -contains $AAD_Id){
        
        Write-Output "----------------------------------------------------"
        Write-Output "Device already exists in AAD Group!"
        Write-Output ""

        $countAdded++

        }

        else {
        
        Write-Output "----------------------------------------------------"
        Write-Output "Adding Device to AAD Group!"
        Write-Output ""

        Add-AADGroupMember -GroupId $AADGroupId -AADMemberId $AAD_Id

        $count++

        }

    }

}

Write-Output "----------------------------------------------------"
Write-Output "$count devices added to AAD Group '$AADGroupName'"
Write-Output "$countAdded devices already in AAD Group '$AADGroupName'"
Write-Output ""

}

else {
Write-Output "----------------------------------------------------"
Write-Output "No Intune Managed Devices found..."
Write-Output ""

}