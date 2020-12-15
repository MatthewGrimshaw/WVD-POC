Connect-AzAccount

$location = "West Europe"

Get-AzVMImagePublisher -Location $location | Select PublisherName

Get-AzVMImagePublisher -Location $location | Select PublisherName | Where-Object { $_.PublisherName -like '*Windows*' }

$publisher = "MicrosoftWindowsDesktop"

Get-AzVMImageOffer -Location $location -PublisherName $publisher | Select Offer

#windows 10 multi session
#$offer =  "windows-10"

# windows 10 with m365
$offer = "office-365"

Get-AzVMImageSku -Location $location -PublisherName $publisher -Offer $offer | Select Skus


<# 
Windows 10 multi-session + M365

                        "publisher": "microsoftwindowsdesktop",
                        "offer": "windows-10",
                        "sku": "20h1-evd",
                        "version": "latest"

Windows 10 multi-session + M365

                        "publisher": "microsoftwindowsdesktop",
                        "offer": "office-365",
                        "sku": "20h1-evd-o365pp",
                        "version": "latest"

#>