$subscriptionID = '<subscriptionID>'
$imageResourceGroup = 'ImageBuilder'
$location = 'westeurope'
$ImageBuilderManagedIdentityName = 'ImageBuildUserAssignedIdentity'
$imageRoleDefName = 'WVDImageBuilderRoleDefinition'
$galleryName = 'wvdImageGallery'
$galleryImageDefinition = 'Windows10MultiUser'
$imageTemplateName = ''

## Check AZ is installed
try{
    az --version
    az upgrade --all --yes
  }
  catch{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
  }

# Register for Azure Image Builder Feature
If((Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState -ne 'Registered'){
    Register-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages
  }
  while((Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState -eq 'Registering'){
    write-host (Get-AzProviderFeature -FeatureName VirtualMachineTemplatePreview -ProviderNamespace Microsoft.VirtualMachineImages).RegistrationState
    Start-Sleep -Seconds 10
  }
  # wait until RegistrationState is set to 'Registered'
  
  # check you are registered for the providers, ensure RegistrationState is set to 'Registered'.
  Get-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages
  Get-AzResourceProvider -ProviderNamespace Microsoft.Storage 
  Get-AzResourceProvider -ProviderNamespace Microsoft.Compute
  Get-AzResourceProvider -ProviderNamespace Microsoft.KeyVault


## Create Image Builder Resource Group
az group create --location $location --name $imageResourceGroup

# Create Managed Identity for the Image Gallery
$AzUSerAssignedIdentity = az identity create `
                         --resource-group $imageResourceGroup  `
                         --name $ImageBuilderManagedIdentityName `
                         --output tsv


# Get the Mangaged Identity
$idenityNameResourceId = az identity show `
                         --resource-group $imageResourceGroup  `
                         --name $ImageBuilderManagedIdentityName `
                         --query id `
                         --output tsv


$idenityNamePrincipalId = az identity show `
                          --resource-group $imageResourceGroup  `
                          --name $ImageBuilderManagedIdentityName `
                          --query principalId `
                          --output tsv


# Taken from here: "https://raw.githubusercontent.com/danielsollondon/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$aibRoleImageCreationPath = '.\aibRoleImageCreation.json'

$regEx = '/subscriptions/[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/resourceGroups/.*"'
$regExRoleDefintionName = '"Name": ".*"'


$resourceID = az group show --name $imageResourceGroup --query id --output tsv


# Fix up the json role defintion
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace $regEx, $($resourceID + '"' )) | Set-Content -Path $aibRoleImageCreationPath
((Get-Content -path $aibRoleImageCreationPath -Raw) -replace $regExRoleDefintionName, ('"Name": "' + $imageRoleDefName + '"' )) | Set-Content -Path $aibRoleImageCreationPath

 # create role definition
 az role definition create --role-definition @$aibRoleImageCreationPath

 # grant role definition to image builder service principal
 az role assignment create --role $imageRoleDefName --assignee-object-id $idenityNamePrincipalId --scope $resourceID

 # Create Image Gallery
$parameterFile = '.\deployment.Parameters.json' 
az deployment group create `
              --resource-group $imageResourceGroup `
              --name (New-Guid).Guid `
              --template-file .\SharedImageGallery.json `
              --parameters $parameterFile


$galleryImageId = az sig image-definition show `
               --resource-group $imageResourceGroup `
               --gallery-name $galleryName `
               --gallery-image-definition $galleryImageDefinition `
               --query id `
               --output tsv

#Create Image Template
az image builder create `
 -resource-group $imageResourceGroup `
 --name $imageTemplateName `
 --image-template .\armTemplateWinSIG.json

 # Submit Image Template
 az image builder wait `
   --name $imageTemplateName `
   -resource-group $imageResourceGroup `
   --custom "lastRunStatus.runState!='running'"

###
# Get Status of the Image Build and Query
# As there are currently no specific Azure PowerShell cmdlets for image builder, we need to construct API calls, with the authentication, this is just an example, note, you can use existing alternatives you may have.

### Step 1: Update context
$currentAzureContext = Get-AzContext

### Step 2: Get instance profile
$azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
    
Write-Verbose ("Tenant: {0}" -f  $currentAzureContext.Subscription.Name)
 
### Step 4: Get token  
$token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId)
$accessToken=$token.AccessToken

$managementEp = $currentAzureContext.Environment.ResourceManagerUrl

$urlBuildStatus = [System.String]::Format("{0}subscriptions/{1}/resourceGroups/$imageResourceGroup/providers/Microsoft.VirtualMachineImages/imageTemplates/{2}?api-version=2019-05-01-preview", $managementEp, $currentAzureContext.Subscription.Id,$imageTemplateName)

$buildStatusResult = Invoke-WebRequest -Method GET  -Uri $urlBuildStatus -UseBasicParsing -Headers  @{"Authorization"= ("Bearer " + $accessToken)} -ContentType application/json 
$buildJsonStatus =$buildStatusResult.Content
$buildJsonStatus
