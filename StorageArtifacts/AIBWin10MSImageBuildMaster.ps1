if(!(Test-Path 'c:\temp')){
    New-Item -Path 'C:\temp' -ItemType Directory -Force | Out-Null
}

#Script to setup golden image with Azure Image Builder
Start-Transcript -Path c:\temp\aibScript.log

write-host Get-Date
write-host  "Configure Registry"

#Configure Remote Desktop Session Host limits
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v RemoteAppLogoffTimeLimit /t REG_DWORD /d 0 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fResetBroken /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxConnectionTime /t REG_DWORD /d 10800000 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxDisconnectionTime /t REG_DWORD /d 5000 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v MaxIdleTime /t REG_DWORD /d 10800000 /f

#enable time zone redirection
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v fEnableTimeZoneRedirection /t REG_DWORD /d 1 /f

#disable storage sense
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 01 /t REG_DWORD /d 0 /f
#Create temp folder

write-host "Install VS code"
#Install VSCode
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?Linkid=852157' -OutFile 'c:\temp\VScode.exe'
Invoke-Expression -Command 'c:\temp\VScode.exe /verysilent'

#Start sleep
Start-Sleep -Seconds 10

write-host "Install Notepad plus plus"
#InstallNotepadplusplus
Invoke-WebRequest -Uri 'https://notepad-plus-plus.org/repository/7.x/7.7.1/npp.7.7.1.Installer.x64.exe' -OutFile 'c:\temp\notepadplusplus.exe'
Invoke-Expression -Command 'c:\temp\notepadplusplus.exe /S'

#Start sleep
Start-Sleep -Seconds 10

write-host "InstallFSLogix"
#InstallFSLogix
Invoke-WebRequest -Uri 'https://aka.ms/fslogix_download' -OutFile 'c:\temp\fslogix.zip'
Start-Sleep -Seconds 10
Expand-Archive -Path 'C:\temp\fslogix.zip' -DestinationPath 'C:\temp\fslogix\'  -Force
Invoke-Expression -Command 'C:\temp\fslogix\x64\Release\FSLogixAppsSetup.exe /install /quiet /norestart'

#Start sleep
Start-Sleep -Seconds 10

write-host "InstallTeamsMachinemode"
#InstallTeamsMachinemode
New-Item -Path 'HKLM:\SOFTWARE\Citrix\PortICA' -Force | Out-Null
Invoke-WebRequest -Uri 'https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&download=true&managedInstaller=true&arch=x64' -OutFile 'c:\temp\Teams.msi'
Invoke-Expression -Command 'msiexec /i C:\temp\Teams.msi /quiet /l*v C:\temp\teamsinstall.log ALLUSER=1'
Start-Sleep -Seconds 30
New-Item -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved -Name Run32
New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32 -Name Teams -PropertyType Binary -Value ([byte[]](0x01,0x00,0x00,0x00,0x1a,0x19,0xc3,0xb9,0x62,0x69,0xd5,0x01)) -Force

If(Test-Path c:\temp\binaries){write-host "c:\temp\binaries exists"}
If(!(Test-Path c:\temp\binaries)){write-host "c:\temp\binaries does not exist"}

# Install Custom Software
write-host "Install Custom Software"
write-host "Install Mediator"
try {
    Start-Process "msiexec.exe" -ArgumentList "/i `"Mediator 9.msi`" TRANSFORMS=`"Mediator 9 ENNI.mst`" /qn /l*v c:\temp\binaries\Mediator9.log" -WorkingDirectory "c:\temp\binaries\1164_08_M-Mediator9\" -Wait
    write-host "install NewWaveConceptsPCBWizard"
    Start-Process "msiexec.exe" -ArgumentList "/i `"1808_01_M-NewWaveConceptsPCBWizardV3.7.msi`" /qn /l*v c:\temp\binaries\NewWaveConcepts.log" -WorkingDirectory "c:\temp\binaries\1808_01_M-NewWaveConceptsPCBWizardV3.7\" -Wait
    write-host "Install audioscore"
    Start-Process "msiexec.exe" -ArgumentList "/i `"audioscore lite.msi`" /qn /l*v c:\temp\binaries\audioscorelite.log" -WorkingDirectory "c:\temp\binaries\1826_02_M-NueratronAudioScoreLite6.5\" -Wait 
    write-host "Install Sibelius"
    Start-Process "msiexec.exe" -ArgumentList "/i `"Sibelius 6.msi`" TRANSFORMS=`"Sibelius 6.mst`" /qn /l*v c:\temp\binaries\Sibelius6.msi" -WorkingDirectory "c:\temp\binaries\1827_03_M-AvidSibelius6\" -Wait
    write-host "Install Create A Story"
    Start-Process "msiexec.exe" -ArgumentList "/i `"2Simple 2Create A Story 1.0.0.922.msi`" /qn /l*v c:\temp\binaries\2Simple2CreateAStory.log " -WorkingDirectory "c:\temp\binaries\1837_01_M-2Simple2CreateAStory1.0.0.922\" -Wait
    write-host "Install All About Number"
    Start-Process "msiexec.exe" -ArgumentList "/i `"All About Number At Level 1 1.0.MSI`" /qn /l*v c:\temp\binaries\AllAboutNumberAtLevel1.log" -WorkingDirectory "c:\temp\binaries\1863_01_M-GranadaAllAboutNumberAtLevel1.0\" -Wait
    write-host "Install Spider in the Kitchen"
    Start-Process "msiexec.exe" -ArgumentList "/i `"Spider in the Kitchen 2.0.msi`" /qn /l*v c:\temp\binaries\SpiderintheKitchen.log" -WorkingDirectory "c:\temp\binaries\1986_01_M-InclusiveTechnologiesSpiderInTheKitchen2.0\" -Wait
    write-host "Install Tizzys Toybox"
    Start-Process "msiexec.exe" -ArgumentList "/i `"Tizzys Toybox SE 1.0.msi`" /qn /l*v c:\temp\binaries\TizzysToybox.log" -WorkingDirectory "c:\temp\binaries\2033_01_M-SherstonSoftwareTizzysToyboxSE1.0\" -Wait
    write-host "Install AdobePhotoshop"
    Start-Process "setup.exe" -ArgumentList "--silent" -WorkingDirectory "c:\temp\binaries\2190_01_M-AdobePhotoshopCCV2020\build\" -Wait
    write/host "Install Adopbe Premier Pro"
    Start-Process "setup.exe" -ArgumentList "--silent" -WorkingDirectory "c:\temp\binaries\2194_01_M-AdobePremiere ProCC2020\build\" -Wait
    }
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    write-host "Failed to install packages"
    write-host $ErrorMessage
    write-host $FailedItem
}


#Install Dev Software
try{    

        write-host "Install Choclatey"
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

        write-host "Install AZ CLI"
        choco install azure-cli --version 2.15.1 -y

        write-host "Install Chrome"
        choco install googlechrome -y

        write-host "Install 7-ZIP"
        choco install 7zip -y

        write-host "Install GIT"
        choco install git -y --params="'/GitAndUnixToolsOnPath /NoAutoCrlf'"

        write-host "Install NODE.JS"
        choco install nodejs.install -y

        write-host "Install RUBY DEVKIT"
        choco Install ruby.devkit -y

        write-host "Install RUBY"
        choco install ruby --version 2.1.5 -my

        write-host "Install SysInternals"
        choco install sysinternals -y

        write-host "Install VStudio"
        choco install visualstudio2019community -y

        write-host "Install DOTNETCORE SDK"
        choco install dotnetcore-sdk -y

        write-host "Install DOTNETCORE"
        choco install dotnetcore-windowshosting -y

        write-host "Install REDIS"
        choco install redis-64 -y

        write-host "Install SQL MangementStudio"
        choco install SQLManagementStudio -source webpi -y

        write-host "Install SQLExpress Tools"
        choco install SQLExpressTools -source webpi -y

        write-host "Install Postman"
        choco install postman -y
}
catch{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    write-host "Failed to install choclatey packages"
    write-host $ErrorMessage
    write-host $FailedItem
}


write-host Get-Date
write-host "Done - Stop Transaction Logging"
Stop-Transcript


$env:AZCOPY_CRED_TYPE = "Anonymous";
azcopy.exe copy "C:\Users\matgri\Repos\WVD-POC\StorageArtifacts\Binaries\Binaries.zip" "https://storslrsuksapppkg.blob.core.windows.net/binaries/Binaries.zip?sv=2019-12-12&se=2021-02-23T11%3A14%3A04Z&sr=c&sp=rwl&sig=sELgj9LfxMEaquZsiwgKZR28paUvfOePs3QiEd6myPA%3D" --overwrite=prompt --from-to=LocalBlob --blob-type Detect --follow-symlinks --put-md5 --follow-symlinks --recursive;
$env:AZCOPY_CRED_TYPE = "";
