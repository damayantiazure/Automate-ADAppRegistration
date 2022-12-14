# AAD App Registration Automation
1. Automating AAD App Registration using DevOps pipeline

2. The pipeline will use the input file (JSON) with App details and create the AAD App on Azure AD with the inputs provided in the file. Ex: API Permissions, granting admin consent etc.

3. Using Azure CLI and DevOps YML pipeline

# What does it do
a)	  The script checks if the App exists or not, if it doesn’t exist, it creates the app else it modifies the App

b)	  Checks if Service Principal exists, otherwise it creates the Service Principal

c)	  Creates secret, if there is no secret

d)	  Creates the secret to store the app secret in Azure Key Vault securely

e)	  Adds API Permissions and grants Admin consent (In progress)

## Pre- Requisites:
1.	  A repository, pipeline
2.    Service Connection (type: Azure Resource Manager)  with authentication method Service Principal
3.	  Master App Service Principal with required permissions
         - Reader access ole in Subscription level
         - Microsoft graph API Permission Application.ReadWrite.All

![image](https://user-images.githubusercontent.com/92169356/207417402-242c78ee-6e09-4adc-9ba9-33a688e2e335.png)


4. 	Master App should have app secret will be added under Access Policy for Azure key vault, and should have get set secret permission
5.	Manifest file with app details



## Master App – For granting admin consent
For Granting admin consents: below API Permissions are required
![image](https://user-images.githubusercontent.com/92169356/207417703-30a0403b-0e8e-484c-8b33-cb8611aaa1a7.png)

Note: AADAppRegistration.ps1 is having the rest api calls for providing admin consent. BUt its not automated using the pipeline yet. 
For now, running using local powershel, will be automated using pipeline (In progress)

- If you are using global admin account, the consent can be granted easily
az ad app permission grant --id $app.AppId --api 00000003-0000-0000-c000-000000000000 --scope Application.ReadWrite.All

- But If you are using Service principal, It’s a bit complex .



1. Get MS Graph API Object ID for 00000003-0000-0000-c000-000000000000

![image](https://user-images.githubusercontent.com/92169356/207418398-9340e694-4c93-44e7-af2d-b7336151baa3.png)

2. Get the Access tokenfrom https://graph.microsoft.com

![image](https://user-images.githubusercontent.com/92169356/207418825-b2a53965-98b9-41ff-93c8-69fdda59b97a.png)

3. Get all api permissions from the manifest file

![image](https://user-images.githubusercontent.com/92169356/207419057-9c8f8785-cec3-43ec-b95d-9112f5dd265f.png)

4. Iterating through the API Permissions with type "Role" and granting admin consent
- Grant an appRoleAssignment to a service principal

- App roles that are assigned to service principals are also known as application permissions.

 Reference: https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments?view=graph-rest-1.0&tabs=http

![image](https://user-images.githubusercontent.com/92169356/207419279-29bcc601-9928-405c-98a1-bd33a53af425.png)


6. Iterating through the API Permissions with type "Scope" and granting admin consent
- Create oAuth2PermissionGrant (a delegated permission grant)

- Delegated permission grant authorizes a client service principal (representing a client application) to access a resource service principal (representing an API), on behalf of a signed-in user, for the level of access limited by the delegated permissions which were granted.

Reference: https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-post?view=graph-rest-1.0&tabs=http

![image](https://user-images.githubusercontent.com/92169356/207419440-56ef47d5-d3c1-45d2-b5d5-0d2eb54b51cb.png)


