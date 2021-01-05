# Check that we are in the right Directory

# Check that we are in the right Directory

If (!(((Get-Location) -split '\\')[-1] -Match 'WVDHostsNetwork')) {
  write-output "Please execute this script from the 'WVDHosts' directory"
  exit
}
  
#Create Paramters File
$parameterFile = '.\deployment.Parameters.json'
Copy-Item .\deployment.Parameters.clean.json $parameterFile

#Read in Variables
$params = Get-Content -Path $parameterFile -Raw | ConvertFrom-Json 

$subscriptionID = $params.parameters.deploymentParameters.value.subscriptionid
$wvdHostsResourceGroup = $params.parameters.deploymentParameters.value.wvdHostResourceGroupName
$location = $params.parameters.deploymentParameters.value.location
$AzfwVnetName = $params.parameters.deploymentParameters.value.AzfwVnetName
$AzfwResourceGroup = $params.parameters.deploymentParameters.value.AzfwResourceGroup
$AzfwName = $params.parameters.deploymentParameters.value.AzfwName
$AzfwCollectionName = $params.parameters.deploymentParameters.value.AzfwCollectionName
$vnetname = $params.parameters.deploymentParameters.value.vnetName
$vnetAddress = $params.parameters.deploymentParameters.value.vnetAddress
$ADSubnet = $params.parameters.deploymentParameters.value.ADSubnet


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

## Create WVD Hosts Resource Group
az group create --location $location --name $wvdHostsResourceGroup

#Create Vnet, Route Table and NSG
az deployment group create `
  --resource-group $wvdHostsResourceGroup `
  --name (New-Guid).Guid `
  --template-file .\WVDHosts.network.json `
  --parameters $parameterFile

# Get the Firewall vnet
$fwVnetID = az network vnet show `
  --resource-group $AzfwResourceGroup `
  --name $AzfwVnetName `
  --query id `
  --out tsv

## Make sure we are in the correct subscription
#az account set --subscription $params.parameters.deploymentParameters.value.subscriptionid  


## create vnet peering to Hub
az network vnet peering create `
  --resource-group $wvdHostsResourceGroup `
  --name  "$($vnetname)_toHub"  `
  --vnet-name $vnetname `
  --remote-vnet $fwVnetID `
  --allow-vnet-access `
  --use-remote-gateways

## Create vnet peering to spoke
#az account set --subscription $params.parameters.deploymentParameters.value.fwSubscriptionid
$spokeVnetID = az network vnet show `
  --resource-group $wvdHostsResourceGroup `
  --name $vnetname `
  --query id `
  --out tsv

az network vnet peering create `
  --resource-group $AzfwResourceGroup `
  --name  "hubTo_$($vnetname)" `
  --vnet-name $AzfwVnetName `
  --remote-vnet $spokeVnetID `
  --allow-vnet-access `
  --allow-gateway-transit

#Create Firewall Routes

#WVD Subnet to AD
az network firewall network-rule create `
  --destination-ports * `
  --firewall-name $AzfwName `
  --resource-group $AzfwResourceGroup `
  --collection-name $AzfwCollectionName `
  --source-addresses $vnetAddress `
  --destination-addresses $ADSubnet `
  --name "$($vnetname)_to_ActiveDirectory" `
  --protocols Any

#AD Subnet to WVD
az network firewall network-rule create `
  --destination-ports * `
  --firewall-name $AzfwName `
  --resource-group $AzfwResourceGroup `
  --collection-name $AzfwCollectionName `
  --source-addresses  $ADSubnet `
  --destination-addresses $vnetAddress  `
  --name "ActiveDirectory_to_$($vnetname)" `
  --protocols Any