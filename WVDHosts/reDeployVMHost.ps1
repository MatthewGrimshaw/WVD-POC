
# Check that we are in the right Directory

If (!(((Get-Location) -split '\\')[-1] -Match 'WVDHosts')) {
    write-output "Please execute this script from the 'WVDHosts' directory"
    exit
  }

  Install-Module -Name Microsoft.RDInfra.RDPowerShell -Force
  Import-Module -Name Microsoft.RDInfra.RDPowerShell
  Update-Module -Name Microsoft.RDInfra.RDPowerShell

  #Create Paramters File
  $parameterFile = '.\deployment.Parameters.json'
  Copy-Item .\deployment.Parameters.clean.json $parameterFile
  
  #Read in Variables
  $params = Get-Content -Path $parameterFile -Raw | ConvertFrom-Json 
  
  $subscriptionID = $params.parameters.deploymentParameters.value.subscriptionid
  $keyVaultName = $params.parameters.deploymentParameters.value.keyVaultName
  $dscArtifactsName = $params.parameters.deploymentParameters.value.dscArtifactsName
  $location = $params.parameters.deploymentParameters.value.location
  $containerName = $params.parameters.deploymentParameters.value.artifactsContainerName
  $subnetName = $params.parameters.deploymentParameters.value.subnetName
  $vnetName = $params.parameters.deploymentParameters.value.vnetName
  $wvdHostsResourceGroup = $params.parameters.deploymentParameters.value.wvdHostResourceGroupName
  $ImageBuilderResourceGroup = $params.parameters.deploymentParameters.value.ImageBuilderResourceGroup
  $galleryName = $params.parameters.deploymentParameters.value.galleryName
  $galleryImageDefinitionName = $params.parameters.deploymentParameters.value.galleryImageDefinitionName
  $hostPoolName = $params.parameters.deploymentParameters.value.hostPoolName
  $wvdResourceGroupName = $params.parameters.deploymentParameters.value.wvdResourceGroupName
  $dscArtifactsResourceGroupName = $params.parameters.deploymentParameters.value.dscArtifactsResourceGroupName
  $tenantID = $params.parameters.deploymentParameters.value.tenantID
  

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

  
#No Cli commands for this, revert to Powershell - authenticate first

#$tenantID = '7c4357a6-cad4-4f49-bca2-153d47af5ae7'
Disconnect-AzAccount
Connect-AzAccount -Tenant $tenantID
get-azcontext



-UseDeviceAuthentication
Select-AzSubscription $subscriptionID | Set-AzContext

#Get WVD Hosts and set them in drain mode
$wvdSessionHosts = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $wvdResourceGroupName
foreach($sessionHost in $wvdSessionHosts){
    $SessionHostName =  ($sessionHost.Name).Replace('ManagedDesktop/','')

    #Put into drain mode tp prevent new logins
    if($sessionHost.AllowNewSession){
            Update-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $wvdResourceGroupName  -Name $SessionHostName -AllowNewSession:$false 
        }
    
    #    Log Users off
    If($sessionHost.Session -gt 0){
        # Get User sessions
        
        $Sessions = Get-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $wvdResourceGroupName  -SessionHostName $SessionHostName
        foreach($session in $Sessions){
            Send-AzWvdUserSessionMessage -HostPoolName $HostPoolName `
                                         -ResourceGroupName $wvdResourceGroupName `
                                         -SessionHostName $SessionHostName `
                                         -UserSessionId $Session.SessionId `
                                         -MessageTitle 'Computer Shutdown warning' `
                                         -MessageBody "You will be logged off in two minutes. Please save your work"
        }

        start-sleep -Seconds 120

        foreach($session in $Sessions){
            Remove-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $wvdResourceGroupName  -Name $SessionHostName           
        }

    }

    #Remove VM from Session Host Pool
    Remove-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $wvdResourceGroupName  -SessionHostName $SessionHostName

    #Stop VM's
    $vmName = ($SessionHostName.Split('.'))[0]
    Stop-AzVM -name $vmName -Force -ResourceGroupName $wvdHostsResourceGroup

    #Remove VM
    Remove-AzVm -name $vmName -Force -ResourceGroupName $wvdHostsResourceGroup -NoWait
    # need to delete disk, nic and nsg
}

# get Storage Account Name and Key
$storageAccountName = az storage account list `
  --resource-group $dscArtifactsResourceGroupName `
  --query [0].'name' `
  --output tsv

$artifactsStorageKey = az storage account keys list `
  --account-name $storageAccountName `
  --query [0].value `
  --output tsv  


# Get SAS for dscArtifactsName
$date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".", ":")

$dscArtifactsLocation = az storage blob generate-sas `
  --account-name $storageAccountName `
  --container-name $containerName.ToLower() `
  --name $dscArtifactsName `
  --account-key $artifactsStorageKey `
  --permissions rw `
  --expiry $date `
  --full-uri `
  --output tsv

((Get-Content -path $parameterFile -Raw) -replace '"dscArtifactsLocation":""', $('"dscArtifactsLocation":"' + $dscArtifactsLocation + '"')) | Set-Content -Path $parameterFile

## Get WVD Host Pool Registration Key
$registrationInfoToken = az desktopvirtualization hostpool show `
  --name $hostPoolName `
  --resource-group $wvdResourceGroupName `
  --query registrationInfo.token `
  --output tsv

if(!$registrationInfoToken){
  $date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-ddTH:mm:ss:fffffffZ")
  $date = $date.Replace(".", ":")
  $registrationInfo = az desktopvirtualization hostpool update `
  --registration-info expiration-time=$date registration-token-operation="Update" `
  --name $hostPoolName `
  --resource-group $wvdResourceGroupName

  $registrationInfoToken =  ($registrationInfo | ConvertFrom-Json).registrationInfo.token
}

((Get-Content -path $parameterFile -Raw) -replace '"registrationInfoToken":""', $('"registrationInfoToken":"' + $registrationInfoToken + '"')) | Set-Content -Path $parameterFile



# Create wvdHosts
az deployment group create `
  --resource-group $wvdHostsResourceGroup `
  --name (New-Guid).Guid `
  --template-file .\wvdVMHosts.json `
  --parameters $parameterFile
