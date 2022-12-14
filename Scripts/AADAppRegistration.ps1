#===================================================================
# DISCLAIMER:
#
# This sample is provided as-is and is not meant for use on a
# production environment. It is provided only for illustrative
# purposes. The end user must test and modify the sample to suit
# their target environment.
#
# Microsoft can make no representation concerning the content of
# this sample. Microsoft is providing this information only as a
# convenience to you. This is to inform you that Microsoft has not
# tested the sample and therefore cannot make any representations
# regarding the quality, safety, or suitability of any code or
# information found here.
#
#===================================================================

param(
    # The Azure DevOps organisation to create the service connection in, available from System.TeamFoundationCollectionUri if running from pipeline.
    
    [Parameter( HelpMessage = "The subscription id")]
    [string]
    $SubsciptionId = "",  

    [Parameter( HelpMessage = "Provide the path of manifest file")]
    [string]
    $Path = ""
)
$manifestfilepath = $Path
#$obj = Get-Content -Path 'Scripts/manifestdemo.json' | ConvertFrom-Json
$obj = Get-Content -Path $manifestfilepath | ConvertFrom-Json
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$env:SuppressAzurePowerShellBreakingChangeWarnings = $true

Write-Host "👉 STARTING SCRIPT"

#Connect to subscription
Write-Host "👉 Connecting to subscription $SubsciptionId.."
# $login = az login --service-principal -u $env:servicePrincipalId -p $env:servicePrincipalKey --tenant $env:tenantId
az login --service-principal -u $env:servicePrincipalId -p $env:servicePrincipalKey --tenant $env:tenantId
az account set --subscription "$SubsciptionId"
$account = az account show --subscription "$SubsciptionId" | ConvertFrom-Json

# Create App Registration
Write-Host "👉 Creating app registration.."
Write-Host "👉 Check if app exists app registration.."
$app = az ad sp list --display-name $($obj.name) | ConvertFrom-Json
$appId = $app.AppID

if (!$app) {
   Write-Information "Create App Registration '$app'"  
   $app = az ad app create --display-name $($obj.name) --required-resource-accesses $manifestfilepath| ConvertFrom-Json 
   $appId = $app.AppID    
   Write-Host "👉 App Registration created: $appId"
}
else
{
   $app = az ad app update --id $appId --required-resource-accesses $manifestfilepath| ConvertFrom-Json     
   Write-Host "👉 App Registration already exists: $appId"  
}

# $app = az ad app create --display-name $($obj.name) --required-resource-accesses 'Scripts/manifestdemo.json' | ConvertFrom-Json

Write-Host "👉 Creating service principle.."
$sp = az ad sp list --display-name $($obj.name) | ConvertFrom-Json
if (!$sp) {
#if ($sp -eq "[]") {      
   Write-Information "Creating service principle.. $($app.AppId)" 
   $sp = az ad sp create --id $app.AppId | ConvertFrom-Json
   Write-Host "👉 App Service Principle created: $($sp.AppId)"
} 
else {
   Write-Host "👉 SP  exists already: $($app.AppId)"    
}
$spobjectid = $sp.objectId

Write-Host "👉 Creating app Credential.."

$credential = az ad app credential list --id $appid | ConvertFrom-Json

if (!$credential) 
{
   $credential = az ad app credential reset --id $appid --append | ConvertFrom-Json
   $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $credential.password
}
else {
   Write-Host "👉 App Credential already exists... $appid"   
}

Write-Host "👉 Adding the app secret to the Azure key vault... "
$appsecret = "Secret-"+ $obj.name
az keyvault secret set --vault-name "azappregkeyvault" --name $appsecret --value $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY

#Write-Host "👉 Adding the app Certificate to the Azure key vault... "
#az keyvault key import --vault-name "ContosoKeyVault" --name "ContosoFirstKey" --pem-file "./softkey.pem" --pem-password "hVFkk965BuUv" --protection software

# Provide admin consent with global admin account
#Write-Host "👉 Grant admin consent for all Apis... $appId"
# #az ad app permission grant --id $app.AppId --api 00000003-0000-0000-c000-000000000000 --scope Application.ReadWrite.All
# az ad app permission admin-consent --id $appId
# Write-Host "👉 admin consent for all Apis: $appId"  

Write-Host "👉 Get MS Graph API Object ID for 00000003-0000-0000-c000-000000000000"
$msgraphclientid = "00000003-0000-0000-c000-000000000000"
$msgraph = az ad sp show --id $msgraphclientid --only-show-errors | ConvertFrom-Json 
$msgraphobjectid = $msgraph.objectId 

Write-Host "👉 Grant admin consent for all Apis... $appId"

$token = az account get-access-token --resource https://graph.microsoft.com | ConvertFrom-Json
$accessToken = $token.accessToken
$targetAPIPermission = (Get-Content $manifestfilepath | ConvertFrom-Json).requiredResourceAccess.resourceAccess

#Iterating through the API Permissions with type "Role" and granting admin consent
#Grant an appRoleAssignment to a service principal
#App roles that are assigned to service principals are also known as application permissions.
#Reference: https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments?view=graph-rest-1.0&tabs=http

foreach($apipermission in $targetAPIPermission){
    if($apipermission.type -eq "Role"){
        Write-Host "👉 Grant admin consent for Application Roles..."
        Write-Host $apipermission.id -BackgroundColor Red
        $id = $apipermission.id
        az ad app permission add --id $appid --api $msgraphclientid --api-permissions $id=Role

        $body = @{
            principalId = $spobjectid #target app reg's spn object id
            resourceId =  $msgraphobjectid #Microsoft Graph's object id
            appRoleId = $id #app role id - reference https://learn.microsoft.com/en-us/graph/permissions-reference
            
        } 
        $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/servicePrincipals/$($spobjectid)/appRoleAssignments"
        Invoke-RestMethod -Uri $appRoleAssignmentUrl -Headers @{Authorization = "Bearer $accessToken" }  -Method POST -Body $($body | ConvertTo-Json) -ContentType "application/json" | ConvertTo-Json

    }
}

#Iterating through the API Permissions with type "Scope" and granting admin consent
#Create oAuth2PermissionGrant (a delegated permission grant)
#A delegated permission grant authorizes a client service principal (representing a client application) to access a resource service principal (representing an API), on behalf of a signed-in user, for the level of access limited by the delegated permissions which were granted.
# Reference: https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-post?view=graph-rest-1.0&tabs=http

foreach($apipermission in $targetAPIPermission){
    if($apipermission.type -eq "Scope"){
        Write-Host "👉 Grant admin consent for Deligated Scopes..."
        Write-Host $apipermission.id -BackgroundColor Green
        $id = $apipermission.id        
        az ad app permission add --id $appid --api $msgraphclientid --api-permissions $id=Scope
        
        $body = @{
            clientId = $spobjectid #theObjectId_for_the_service_principal_for_test
            consentType= "AllPrincipals"
            expiryTime= "2023-05-12T19:34:28.9831598Z" #Microsoft Graph's object id
            resourceId = $msgraphobjectid
            scope = "User.Read.All Application.Read.All"
        }

        $token = az account get-access-token --resource https://graph.microsoft.com | ConvertFrom-Json
        $accessToken = $token.accessToken
        $appRoleAssignmentUrl = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants"
        Invoke-RestMethod -Uri $appRoleAssignmentUrl -Headers @{Authorization = "Bearer $accessToken" }  -Method POST -Body $($body | ConvertTo-Json) -ContentType "application/json" | ConvertTo-Json

    }
}
