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