# Check that we are in the right Directory

If (!(((Get-Location) -split '\\')[-1] -Match 'Infrastructure')) {
  write-output "Please execute this script from the 'WVDHosts' directory"
  exit
}
  
#Create Paramters File
$parameterFile = '.\deployment.Parameters.json'
Copy-Item .\deployment.Parameters.clean.json $parameterFile

#Read in Variables
$params = Get-Content -Path $parameterFile -Raw | ConvertFrom-Json 

$subscriptionID = $params.parameters.deploymentParameters.value.subscriptionid
$keyVaultResourceGroupName = $params.parameters.deploymentParameters.value.keyVaultResourceGroupName
$keyVaultName = $params.parameters.deploymentParameters.value.keyVaultName
$keyVaultUser = $params.parameters.deploymentParameters.value.keyVaultUser
$wvdHostsResourceGroup = $params.parameters.deploymentParameters.value.wvdHostResourceGroupName
$containerName = $params.parameters.deploymentParameters.value.artifactsContainerName
$location = $params.parameters.deploymentParameters.value.location

$domainJoinAccount = 'dummyValue'
$domainJoinPassword = 'dummyValue'
$localAdminAccountName = 'dummyValue'
$localAdminAccountPassword = 'dummyValue'

## Check AZ is installed
try {
  az --version
  #az upgrade --all --yes
}
catch {
  #Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi'
  choco uninstall azure-cli
  choco install azure-cli --version 2.15.1
  az version
}
  
## Connect to Azure
az login #--tenant "72f988bf-86f1-41af-91ab-2d7cd011db47"
az account set --subscription $subscriptionID 

# Create Key Vault

## Get Variables for Key Vault deployment
$tennantID = az account show --query tenantId --output tsv
$objectId = az ad user show --id $keyVaultUser --query objectId --out tsv 

# Fix up the json parameters
((Get-Content -path $parameterFile -Raw) -replace '"tennantID":""', $('"tennantID":"' + $tennantID + '"')) | Set-Content -Path $parameterFile
((Get-Content -path $parameterFile -Raw) -replace '"objectId":""', $('"objectId":"' + $objectId + '"')) | Set-Content -Path $parameterFile


az group create --location $location --name $keyVaultResourceGroupName

az keyvault create `
  --location $location `
  --name $keyVaultName `
  --resource-group $keyVaultResourceGroupName `
  --bypass 'AzureServices' `
  --default-action 'Allow' `
  --sku 'Standard' `
  --enabled-for-template-deployment $true `
  --enabled-for-deployment $true `
  --enabled-for-disk-encryption $false


# set key vault secrets
az keyvault secret set `
  --name 'domainJoinAccount' `
  --vault-name $keyVaultName `
  --value $domainJoinAccount

az keyvault secret set `
  --name 'domainJoinPassword' `
  --vault-name $keyVaultName `
  --value $domainJoinPassword

az keyvault secret set `
  --name 'localAdminAccountName' `
  --vault-name $keyVaultName `
  --value $localAdminAccountName

az keyvault secret set `
  --name 'localAdminAccountPassword' `
  --vault-name $keyVaultName `
  --value $localAdminAccountPassword

## Please login into the Key Vault and manully update the secrets values with the correct information


# Create Storage Account and Upload Artifacts

#Create zip archive for DSC artifacts
$dir = Get-Location | Split-Path
$StorageArtifactsDir = $dir + '\StorageArtifacts' 
Compress-Archive -Path $dir\Configuration\* -DestinationPath $StorageArtifactsDir\Configuration.zip -Force 

# Get Infrastructure Dir
$dir = Get-Location | Split-Path
$infraDir = $dir + '\Infrastructure' 

#Create WVDHosts Resource Groupo
az group create --location $location --name $wvdHostsResourceGroup

#Create storage Account
az deployment group create `
  --resource-group $wvdHostsResourceGroup `
  --name (New-Guid).Guid `
  --template-file $infraDir\StorageAccount.Artifacts.json `
  --parameters $parameterFile

$storageAccountName = az storage account list `
  --resource-group $wvdHostsResourceGroup `
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
  --resource-group $wvdHostsResourceGroup `
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