# Windows Virtual Desktop and Azure Image Builder template

These templates will create:

* An Azure Image Gallery
* A Managed Identity
* A role definition
* An Azure Image Builder Template
* A template submission to create the Windows Virtual Desktop in the Azure Image Gallery
* A Storage Account for the customisation scripts used during the Image Build Process

More details can be found here: https://github.com/danielsollondon/azvmimagebuilder

![Screenshot](AzureImageBuilder.PNG)

# To Deploy this solution:

* Correct the values in the deployment.Parameters.clean.json file
* Make sure you are in the 'ImageBuilder' Directory
* Run the ImageBuilder.ps1 script