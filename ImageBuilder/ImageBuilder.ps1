# Check that we are in the right Directory

If (!(((Get-Location) -split '\\')[-1] -Match 'ImageBuilder')) {
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
$galleryName = $params.parameters.deploymentParameters.value.galleryName
$galleryImageDefinition = $params.parameters.deploymentParameters.value.galleryImageDefinitionName
$imageTemplateName = $params.parameters.deploymentParameters.value.imageTemplateName
$storageAccountName = $params.parameters.deploymentParameters.value.artifactsStorageAccountName
$containerName = $params.parameters.deploymentParameters.value.artifactsContainerName
$binariesContainerName = $params.parameters.deploymentParameters.value.binariesContainerName
$blobName = $params.parameters.deploymentParameters.value.AIBScriptBlobName

## Check AZ is installed
try {
  az --version
  az upgrade --all --yes
}
catch {
  Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi'
}

## Connect to Azure
az login
az account set --subscription $subscriptionID

## Create Image Builder Resource Group
az group create --location $location --name $imageResourceGroup

# Get the Mangaged Identity
$idenityNameResourceId = az identity show `
  --resource-group $imageResourceGroup  `
  --name $ImageBuilderManagedIdentityName `
  --query id `
  --output tsv
                         
# Fix up the json parameters
((Get-Content -path $parameterFile -Raw) -replace '"userAssignedIdentities":""', $('"userAssignedIdentities":"' + $idenityNameResourceId + '"')) | Set-Content -Path $parameterFile


# Get Infrastructure Dir
$dir = Get-Location | Split-Path
$infraDir = $dir + '\Infrastructure' 

$galleryImageId = az sig image-definition show `
  --resource-group $imageResourceGroup `
  --gallery-name $galleryName `
  --gallery-image-definition $galleryImageDefinition `
  --query id `
  --output tsv

# Fix up the json parameters
((Get-Content -path $parameterFile -Raw) -replace '"galleryImageId":""', $('"galleryImageId":"' + $galleryImageId + '"')) | Set-Content -Path $parameterFile


$storageAccountName = az storage account list `
  --resource-group $imageResourceGroup `
  --query [0].'name' `
  --output tsv    

## upload artifacts to blob storage
$artifactsStorageKey = az storage account keys list `
  --account-name $storageAccountName `
  --query [0].value `
  --output tsv

$SasToken = az storage container generate-sas `
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

foreach ($artifactToUpload in $(Get-ChildItem -Path $StorageArtifactsDir -Recurse -File)) { 

  ## upload artifacts to blob storage
  az storage blob upload `
    --name $artifactToUpload.name `
    --container-name $containerName.ToLower() `
    --file $artifactToUpload.Fullname `
    --account-name $storageAccountName `
    --connection-string $connectionString `
    --sas-token $SasToken 
                        
}


$date = (Get-Date).AddMinutes(180).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".", ":")
$AIBScriptBlobPath = az storage blob generate-sas `
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


# Zip binaries to be installed as part of Image build
$dir = Get-Location | Split-Path
$StorageArtifactsDir = $dir + '\StorageArtifacts'
Compress-Archive -Path .\Binaries\* -DestinationPath $StorageArtifactsDir\Binaries\binaries.zip -Force

$binariesSasToken = az storage container generate-sas `
--account-name $storageAccountName `
--name $binariesContainerName `
--account-key $artifactsStorageKey `
--permissions w `
--output tsv
    
## upload artifacts to blob storage
az storage blob upload `
  --name binaries.zip `
  --container-name $binariesContainerName.ToLower() `
  --file $StorageArtifactsDir\Binaries\binaries.zip `
  --account-name $storageAccountName `
  --connection-string $connectionString `
  --sas-token $binariesSasToken 
                      

# Get SAS for blobArtifacts
$date = (Get-Date).AddMinutes(180).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".", ":")

$blobURI = az storage blob generate-sas `
  --account-name $storageAccountName `
  --container-name $binariesContainerName.ToLower() `
  --name binaries.zip `
  --account-key $artifactsStorageKey `
  --permissions rw `
  --expiry $date `
  --full-uri `
  --output tsv

((Get-Content -path $parameterFile -Raw) -replace '"binariesUri":""', $('"binariesUri":"' + $blobUri + '"')) | Set-Content -Path $parameterFile


# az image builder cancel --name $imageTemplateName --resource-group $imageResourceGroup
# az image builder delete --name $imageTemplateName --resource-group $imageResourceGroup

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

# This can take a bit of time (1hr?)
az image builder wait `
  --name $imageTemplateName `
  --resource-group $imageResourceGroup `
  --custom "lastRunStatus.runState!='Running'"

az image builder show `
  --name $imageTemplateName `
  --resource-group $imageResourceGroup


  



