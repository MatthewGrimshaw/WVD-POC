Connect-AzAccount

$location = "West Europe"

Get-AzVMImagePublisher -Location $location | Select PublisherName

Get-AzVMImagePublisher -Location $location | Select PublisherName | Where-Object { $_.PublisherName -like '*Windows*' }

$publisher = "MicrosoftWindowsDesktop"

Get-AzVMImageOffer -Location $location -PublisherName $publisher | Select Offer

$offer = "office-365"

Get-AzVMImageSku -Location $location -PublisherName $publisher -Offer $offer | Select Skus


<# Windows 10 + M365

                        "publisher": "microsoftwindowsdesktop",
                        "offer": "office-365",
                        "sku": "20h1-evd-o365pp",
                        "version": "latest"

#>