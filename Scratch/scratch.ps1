#scratch this
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
$binariesContainerName = 'binaries'
$blobName = $params.parameters.deploymentParameters.value.AIBScriptBlobName
#scratch this


# Zip binaries to be installed as part of Image build
$dir = Get-Location | Split-Path
$StorageArtifactsDir = $dir + '\StorageArtifacts'

Push-Location
Set-Location .\Binaries
$dirsToArchive = Get-ChildItem -Directory
Pop-Location

foreach($Archive in $dirsToArchive.Name){
    Compress-Archive -Path .\Binaries\$Archive\* -DestinationPath $StorageArtifactsDir\Binaries\$Archive.zip -Force
}



# Upload Archives to Artifacts storage account

$storageAccountName = az storage account list `
  --resource-group $imageResourceGroup `
  --query [0].'name' `
  --output tsv    

## upload artifacts to blob storage
$artifactsStorageKey = az storage account keys list `
  --account-name $storageAccountName `
  --query [0].value `
  --output tsv

  
$connectionString = az storage account show-connection-string `
  --resource-group $imageResourceGroup `
  --name $storageAccountName `
  --output tsv

#create binaries container
 az storage container create `
 --name $binariesContainerName `
 --account-key $artifactsStorageKey `
 --connection-string $connectionString 


  $SasToken = az storage container generate-sas `
  --account-name $storageAccountName `
  --name $binariesContainerName `
  --account-key $artifactsStorageKey `
  --permissions w `
  --output tsv
      
# Get StorageArtifacts


foreach ($artifactToUpload in $(Get-ChildItem -Path $StorageArtifactsDir\Binaries -Recurse -File)) { 

  ## upload artifacts to blob storage
  az storage blob upload `
    --name $artifactToUpload.name `
    --container-name $binariesContainerName.ToLower() `
    --file $artifactToUpload.Fullname `
    --account-name $storageAccountName `
    --connection-string $connectionString `
    --sas-token $SasToken 
                        
}


# Get binaries urls

$blobsToDownload = az storage blob list `
--container-name $binariesContainerName.ToLower() `
--account-key $artifactsStorageKey `
--account-name $storageAccountName `
--connection-string $connectionString `
--query [].name `
--output tsv

# Get SAS for dscArtifactsName
$date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".", ":")

$blobUris = @()

foreach($blobToDownload in $blobsToDownload){
    $blobUris += az storage blob generate-sas `
  --account-name $storageAccountName `
  --container-name $binariesContainerName.ToLower() `
  --name $blobToDownload `
  --account-key $artifactsStorageKey `
  --permissions rw `
  --expiry $date `
  --full-uri `
  --output tsv
}