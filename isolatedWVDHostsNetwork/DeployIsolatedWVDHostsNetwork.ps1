# Check that we are in the right Directory

# Check that we are in the right Directory

If (!(((Get-Location) -split '\\')[-1] -Match 'WVDIsolatedHostsNetwork')) {
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
$netStartInteger = $params.parameters.deploymentParameters.value.netStartInteger
$subnetPrefix = $params.parameters.deploymentParameters.value.subnetPrefix
$subnetSuffix = $params.parameters.deploymentParameters.value.subnetSuffix
$AzfwName = $params.parameters.deploymentParameters.value.AzfwName
$AzfwCollectionName = $params.parameters.deploymentParameters.value.AzfwCollectionName
$secvnetname = $params.parameters.deploymentParameters.value.vnetName
$vnetAddress = $params.parameters.deploymentParameters.value.vnetAddress
$ADSubnet = $params.parameters.deploymentParameters.value.ADSubnet
$count = $params.parameters.deploymentParameters.value.count


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
az login 
az account set --subscription $subscriptionID 

## Create WVD Hosts Resource Group
az group create --location $location --name $wvdHostsResourceGroup

#Deploy Vnets
az deployment group create `
  --resource-group $wvdHostsResourceGroup `
  --name (New-Guid).Guid `
  --template-file .\isolatedHosts.network.json `
  --parameters $parameterFile

# Get the Firewall vnet
$fwVnetID = az network vnet show `
  --resource-group $AzfwResourceGroup `
  --name $AzfwVnetName `
  --query id `
  --out tsv

$i = 0
do {
  ## Make sure we are in the correct subscription
  #az account set --subscription $params.parameters.deploymentParameters.value.subscriptionid

  $vnetname = $secvnetName + $i
  $peeringName = "Peering_$($vnetname)_toHub"
  $peeringNameToHub = "Peering_toHub_$vnetname"

  ## create vnet peering to Hub
  az network vnet peering create `
    --resource-group $wvdHostsResourceGroup `
    --name  $peeringName  `
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
    --name  $peeringNameToHub `
    --vnet-name $AzfwVnetName `
    --remote-vnet $spokeVnetID `
    --allow-vnet-access `
    --allow-gateway-transit

  #Create Firewall Routes
  $startInteger = $netStartInteger + $i
  $subnetToAdd = $subnetPrefix `
    + $startInteger `
    + $subnetSuffix

  #WVD Subnet to AD
  az network firewall network-rule create `
    --destination-ports * `
    --firewall-name $AzfwName `
    --resource-group $AzfwResourceGroup `
    --collection-name $AzfwCollectionName `
    --source-addresses $subnetToAdd `
    --destination-addresses $ADSubnet `
    --name "$($vnetname)_to_ActiveDirectory" `
    --protocols Any

  #AD Subnet to WVD
  az network firewall network-rule create `
    --destination-ports * `
    --firewall-name $AzfwName `
    --resource-group $AzfwResourceGroup `
    --collection-name $AzfwCollectionName `
    --source-addresses $ADSubnet `
    --destination-addresses $subnetToAdd  `
    --name "ActiveDirectory_to_$($vnetname)" `
    --protocols Any


  $i++

} while ($i -lt $count)