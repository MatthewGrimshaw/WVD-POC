# Check that we are in the right Directory

If(!(((Get-Location) -split '\\')[-1] -Match 'ImageBuilder')){
  write-output "Please execute this script from the 'ImageBuilder' directory"
  exit
}

#Create Paramters File
$parameterFile = '.\deployment.Parameters.json'
Copy-Item .\deployment.Parameters.clean.json $parameterFile

#Read in Variables
$params = Get-Content -Path $parameterFile -Raw | ConvertFrom-Json 

$subscriptionID = $params.parameters.deploymentParameters.value.subscriptionid
$imageResourceGroup = $params.parameters.deploymentParameters.value.ImageBuilderResourceGroup
$location = $params.parameters.deploymentParameters.value.location
$ImageBuilderManagedIdentityName = $params.parameters.deploymentParameters.value.ImageBuilderManagedIdentityName
$imageRoleDefName = $params.parameters.deploymentParameters.value.ImageBuilderRoleDefintionName
$galleryName = $params.parameters.deploymentParameters.value.galleryName
$galleryImageDefinition = $params.parameters.deploymentParameters.value.galleryImageDefinitionName
$imageTemplateName = $params.parameters.deploymentParameters.value.imageTemplateName
$storageAccountName = $params.parameters.deploymentParameters.value.artifactsStorageAccountName
$containerName = $params.parameters.deploymentParameters.value.artifactsContainerName
$blobName = $params.parameters.deploymentParameters.value.AIBScriptBlobName

## Check AZ is installed
try{
    az --version
    az upgrade --all --yes
  }
  catch{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi'
  }

## Connect to Azure
az login
az account set --subscription $subscriptionID

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
                         
# Fix up the json parameters
((Get-Content -path $parameterFile -Raw) -replace '"userAssignedIdentities":""', $('"userAssignedIdentities":"' + $idenityNameResourceId + '"')) | Set-Content -Path $parameterFile

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

#Create Shared Image Gallery 
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

 # Fix up the json parameters
((Get-Content -path $parameterFile -Raw) -replace '"galleryImageId":""', $('"galleryImageId":"' + $galleryImageId + '"')) | Set-Content -Path $parameterFile

# Create Storage Account
az deployment group create `
              --resource-group $imageResourceGroup `
              --name (New-Guid).Guid `
              --template-file $infraDir\StorageAccount.Artifacts.json `
              --parameters $parameterFile

$storageAccountName = az storage account list `
                      --resource-group $imageResourceGroup `
                      --query [0].'name' `
                      --output tsv    

  ## upload artifacts to blob storage
  $artifactsStorageKey = az storage account keys list `
                       --account-name $storageAccountName `
                       --query [0].value `
                       --output tsv

  $SasToken =               az storage container generate-sas `
                            --account-name $storageAccountName `
                            --name $containerName `
                            --account-key $artifactsStorageKey `
                            --permissions w `
                            --output tsv

    
$connectionString = az storage account show-connection-string `
                    --resource-group $imageResourceGroup `
                     --name $storageAccountName `
                     --output tsv
      
# Get StorageArtifacts
$dir = Get-Location | Split-Path
$StorageArtifactsDir = $dir + '\StorageArtifacts' 

foreach($artifactToUpload in $(Get-ChildItem -Path $StorageArtifactsDir -Recurse -File)){ 

  ## upload artifacts to blob storage
  az storage blob upload `
                        --name $artifactToUpload.name `
                        --container-name $containerName.ToLower() `
                        --file $artifactToUpload.Fullname `
                        --account-name $storageAccountName `
                        --connection-string $connectionString `
                        --sas-token $SasToken 
                        
}


$date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".",":")
$AIBScriptBlobPath =          az storage blob generate-sas `
                            --account-name $storageAccountName `
                            --container-name $containerName.ToLower() `
                            --name $blobName  `
                            --account-key $artifactsStorageKey `
                            --permissions rw `
                            --expiry $date `
                            --full-uri `
                            --output tsv

# Set Parameter
((Get-Content -path $parameterFile -Raw) -replace '"AIBScriptBlobPath":""', $('"AIBScriptBlobPath":"' + $AIBScriptBlobPath + '"')) | Set-Content -Path $parameterFile



#Submit Image Template
az deployment group create `
              --resource-group $imageResourceGroup `
              --name (New-Guid).Guid `
              --template-file .\armTemplateWinSIG.json `
              --parameters $parameterFile

# Build and Distribute Image
az image builder run `
--name $imageTemplateName `
--resource-group $imageResourceGroup `
--no-wait

# This can take a bit of time
 az image builder wait `
   --name $imageTemplateName `
   --resource-group $imageResourceGroup `
   --custom "lastRunStatus.runState!='Running'"

az image builder show `
 --name $imageTemplateName `
 --resource-group $imageResourceGroup

# az image builder delete --name $imageTemplateName --resource-group $imageResourceGroup