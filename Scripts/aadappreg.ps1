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
    $Path = "Scripts/manifestdemo.json"
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
   Write-Host "👉 App Registration created: $($app.AppId)"
}
else
{
   $app = az ad app update --id $appId --required-resource-accesses $manifestfilepath| ConvertFrom-Json     
   Write-Host "👉 App Registration already exists: $($app.AppId)"  
}

# $app = az ad app create --display-name $($obj.name) --required-resource-accesses 'Scripts/manifestdemo.json' | ConvertFrom-Json

Write-Host "👉 Creating service principle.."
$sp = az ad sp list --display-name $($obj.name)
# if (!$sp) {
if ($sp -eq "[]") {      
   Write-Information "Creating service principle.. $($app.AppId)" 
   $sp = az ad sp create --id $app.AppId | ConvertFrom-Json
   Write-Host "👉 App Service Principle created: $($sp.AppId)"
} 
else {
   Write-Host "👉 SP  exists already: $($app.AppId)"    
}
Write-Host "👉 Grant admin consent for all Apis... $appId"
#az ad app permission grant --id $app.AppId --api 00000003-0000-0000-c000-000000000000 --scope Application.ReadWrite.All
# az ad app permission admin-consent --id $appId
Write-Host "👉 admin consent for all Apis: $appId"   

Write-Host "👉 Creating app Credential.."
# $credential = az ad app credential reset --id $app.AppId --append | ConvertFrom-Json
# $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $credential.password

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
