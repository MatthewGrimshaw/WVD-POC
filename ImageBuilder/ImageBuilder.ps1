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
az feature register --namespace Microsoft.VirtualMachineImages --name VirtualMachineTemplatePreview

# Register other proividers
az provider register --namespace Microsoft.VirtualMachineImages
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.KeyVault


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

# Get Infrastructure Dir
$dir = Get-Location | Split-Path
$infraDir = $dir + '\Infrastructure' 

 # Create Image Gallery
$parameterFile = '.\deployment.Parameters.json' 

az deployment group create `
              --resource-group $imageResourceGroup `
              --name (New-Guid).Guid `
              --template-file $infraDir\SharedImageGallery.json `
              --parameters $parameterFile



$galleryImageId = az sig image-definition show `
               --resource-group $imageResourceGroup `
               --gallery-name $galleryName `
               --gallery-image-definition $galleryImageDefinition `
               --query id `
               --output tsv

## Upload AIBWin10MSImageBuild.ps1 to a storage account and get bloburl

az deployment group create `
              --resource-group $imageResourceGroup `
              --name (New-Guid).Guid `
              --template-file $infraDir\SharedImageGallery.json `
              --parameters $parameterFile


# upload script 

$storageAccountName = ''
$containerName = ''
$blobName = = 'AIBWin10MSImageBuild.ps1'

  ## upload artifacts to blob storage
  $artifactsStorageKey = az storage account keys list `
                       --account-name $storageAccountName `
                       --query [0].value `
                       --output tsv

  $SasToken =                    az storage container generate-sas `
                            --account-name $storageAccountName `
                            --name $containerName `
                            --account-key $artifactsStorageKey `
                            --permissions w `
                            --output tsv

    
$connectionString = az storage account show-connection-string `
                    --resource-group $resourceGroupName `
                     --name $storageAccountName `
                     --output tsv
                     
  az storage blob upload `
                        --name $blobName `
                        --container-name $containerName  `
                        --file $blobName `
                        --account-name $storageAccountName `
                        --connection-string $connectionString `
                        --sas-token $SasToken 


$date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".",":")

$artifactsStorageKey = az storage account keys list `
                       --account-name $storageAccountName `
                       --query [0].value `
                       --output tsv

$AIBScriptBlobPath =          az storage blob generate-sas `
                            --account-name $storageAccountName `
                            --container-name $containerName `
                            --name $blobName  `
                            --account-key $artifactsStorageKey `
                            --permissions rw `
                            --expiry $date `
                            --full-uri `
                            --output tsv

write-output "AIBScriptBlobPath : $AIBScriptBlobPath"


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
