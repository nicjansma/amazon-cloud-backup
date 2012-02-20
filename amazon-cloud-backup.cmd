@echo off
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM
REM Amazon Cloud Backup via EC2 and EBS
REM By Nic Jansma
REM http://nicj.net
REM
REM See README.md for instructions
REM

set thisDir=%~dp0
set thisDir=!thisDir:~0,-1!

REM
REM *** Configuration ***
REM

REM The directory you want to backup
REM     NOTE: You will probably need to use cygwin-style paths if you are using cygwin ssh/rsync
REM     For example, D:\Documents would be /cygdrive/d/documents/
set backupDir=/cygdrive/d/documents/

REM Rsync configuration options
set rsyncStandardOptions=--delete --recursive --times --compress --verbose --progress --update --human-readable

REM Rsync include or exclude options
set rsyncInclude=--include-from=!thisDir!\%~n0.include.txt

REM Your EC2 region and zone
set ec2Region=us-west-1
set ec2Zone=us-west-1a
set ec2Url=https://ec2.us-west-1.amazonaws.com

REM Your EC2 Key Pair name
REM    Create a Key Pair by going to your AWS Management Console, EC2, Key Pairs, then Create Key Pair
set ec2KeyPairName=amazon-cloud-backup

REM File name of your Key Pair .pem (put in this directory)
set ec2KeyPairFile=amazon-cloud-backup.pem
set ec2KeyPairPath=!thisDir!\!ec2KeyPairFile!

REM Your X.509 Certificate
REM    Create a X.509 Certificate by going to your Amazon Web Services Security Credentials page
REM    https://aws-portal.amazon.com/gp/aws/securityCredentials

REM Your X.509 Private Key file name (put in this directory)
set ec2PrivateKeyFile=pk-YOURCERTIFICATE.pem
set ec2PrivateKeyPath=!thisDir!\!ec2PrivateKeyFile!

REM Your X.509 Certificate file name (put in this directory)
set ec2CertificateFile=cert-YOURCERTIFICATE.pem
set ec2CertificatePath=!thisDir!\!ec2CertificateFile!

REM The EC2 AMI that you want to use
set ec2Ami=ami-38fe7308

REM The EC2 type of instance you want to use
set ec2InstanceType=t1.micro

REM A tag to help identify the EC2 instance when it's running
set ec2InstanceTag=amazon-cloud-backup

REM The user you want to use to start a rsync on the EC2 instance
REM     If you change this, you should also update amazon-cloud-backup.bootscript.sh to ensure that user can log in
set ec2User=root

REM The security group you want to use with the instance.  It should have port 22 (SSH) open.
set ec2SecurityGroup=ssh

REM The EC2 startup script (user data file), defaults to amazon-cloud-backup.bootscript.sh
set ec2UserDataFile=%~n0.bootscript.sh

REM The EBS volume that you've created
REM     You can create a new volume by going to your AWS Management Console, EC2, Volumes, then Create Volume.
set ec2EbsVolumeID=vol-abcxyz

REM The attach point for the EBS device
set ec2EbsDevice=/dev/sdb

REM The file filesystem type of your volume
REM     You will need to fdisk/format your volume before using it here
set ec2EbsFilesystemType=ext4

REM The mount point you want to use
REM     If you change this, you should also update amazon-cloud-backup.bootscript.sh
set ec2BackupDestPath=/backup

REM EC2 tools dir
REM     Download from http://aws.amazon.com/developertools/
set ec2ToolsDir=!thisDir!\amazon-tools
set ec2ToolsBinDir=!ec2ToolsDir!\bin

REM
REM *** End Configuration ***
REM

REM
REM Parse command-line
REM
set command=%1
set commandLineOptions=%2 %3 %4 %5 %6 %7 %8 %9
if {!command!}=={} (
    goto :Usage
    exit /b 1
)

REM
REM Ensure files exist
REM
if not exist !ec2KeyPairPath! (
    echo !ec2KeyPairPath! does not exist
    echo Please create an EC2 Key Pair and put the *.pem file in this directory
    exit /b 1
)

if not exist !ec2PrivateKeyPath! (
    echo !ec2PrivateKeyPath! does not exist
    echo Please create a X.509 Certificate and put the pk-*.pem and cert-*.pem file in this directory
    exit /b 1
)

if not exist !ec2CertificatePath! (
    echo !ec2CertificatePath! does not exist
    echo Please create a X.509 Certificate and put the pk-*.pem and cert-*.pem file in this directory
    exit /b 1
)

REM
REM Ensure tools exist
REM
if not exist !ec2ToolsBinDir!\ec2-run-instances.cmd (
    echo !ec2ToolsBinDir!\ec2-run-instances.cmd does not exist
    echo Please download the Amazon EC2 API Tools from http://aws.amazon.com/developertools/
)

call ssh -V 2> NUL
if !ErrorLevel! NEQ 0 (
    echo Could not find ssh
    echo Please download ssh via the Cygwin tools or a standalone package
    exit /b 1
)

call rsync --version 1> NUL
if !ErrorLevel! NEQ 0 (
    echo Could not find rsync
    echo Please download rsync via the Cygwin tools or a standalone package
    exit /b 1
)

call sleep 0 1> NUL
if !ErrorLevel! NEQ 0 (
    echo Could not find sleep
    echo Please download sleep via the Cygwin tools or a standalone package
    exit /b 1
)

REM
REM EC2 environment constants
REM
set EC2_HOME=!ec2ToolsDir!
set EC2_PRIVATE_KEY=!ec2PrivateKeyPath!
set EC2_CERT=!ec2CertificatePath!
set EC2_URL=!ec2Url!

REM Turn off cygwin DOS file path warning
set CYGWIN=nodosfilewarning

REM
REM Run command
REM
if /i {!command!}=={-launch} (
    call :Launch
    exit /b 0
)
if /i {!command!}=={-start} (
    call :Launch
    exit /b 0
)

if /i {!command!}=={-status} (
    call :Status
    exit /b 0
)

if /i {!command!}=={-volumestatus} (
    call :VolumeStatus
    exit /b 0
)

if /i {!command!}=={-rsync} (
    call :Rsync
    exit /b 0
)

if /i {!command!}=={-stop} (
    call :Stop
    exit /b 0
)

REM no command matched
goto :Usage
exit /b 1

REM
REM Functions
REM

REM
REM Determines if any EC2 rsync instances are running
REM
:Status
    echo Status:
    echo -------
    echo Checking if any instances tagged '!ec2InstanceTag!' are running...
    set cmd=!ec2ToolsBinDir!\ec2-describe-instances.cmd --filter "tag:!ec2InstanceTag!="
    echo ^>!cmd!

    set ec2Instance=
    for /f "tokens=2" %%f in ('!cmd! ^| findstr INSTANCE') do (
        set ec2Instance=%%f
        echo Instance is running: !ec2Instance!
    )

    if {!ec2Instance!}=={} (
        echo Instance is NOT running
    )

    goto :eof

REM
REM Checks the free space on the volume
REM
:VolumeStatus
    echo Drive Status:
    echo -------------

    call :GetFQDN

    if {!ec2FQDN!}=={} (
        echo Instance not found, use -start to start one
        exit /b 1
    )

    echo.
    echo Checking drive space of !ec2BackupDestPath! on !ec2FQDN!
    set cmd=ssh -i !ec2KeyPairPath! -o StrictHostKeychecking=no !ec2User!@!ec2FQDN! "df -h"
    echo ^>!cmd!
    call !cmd! | findstr "Filesystem !ec2BackupDestPath!"
    goto :eof

REM
REM Launches a new EC2 instance and attaches the EBS volume
REM
:Launch
    echo Launch:
    echo -------

    REM Ensure no EC2 instances are running fist
    echo Ensuring no instances are running...
    call :GetFQDN

    if NOT {!ec2FQDN!}=={} (
        echo An instance is already running at !ec2FQDN!
        exit /b 1
    )

    REM Start a new instance
    echo.
    echo No instances found, starting a new one...
    set cmd=!ec2ToolsBinDir!\ec2-run-instances.cmd !ec2Ami! --availability-zone !ec2Zone! --instance-type !ec2InstanceType! --user-data-file !ec2UserDataFile! --group !ec2SecurityGroup! --key !ec2KeyPairName!
    echo ^>!cmd!
    for /f "tokens=2" %%f in ('!cmd! ^| findstr INSTANCE') do (
        set ec2Instance=%%f
        echo    Launched instance: !ec2Instance!
    )

    REM Tag it for later
    echo.
    echo Tagging !ec2Instance! as !ec2InstanceTag!...
    set cmd=!ec2ToolsBinDir!\ec2-create-tags.cmd !ec2Instance! --tag !ec2InstanceTag!
    echo ^>!cmd!
    call !cmd!

    REM Wait for it to startup and get its FQDN
    call :WaitForInstance
    call :GetFQDN

    if {!ec2FQDN!}=={} (
        echo Could not find the instances' FQDN
        exit /b 1
    )

    REM Attach the EBS volume
    echo.
    echo Attaching !ec2EbsVolumeID! on !ec2Instance!...
    set cmd=!ec2ToolsBinDir!\ec2-attach-volume.cmd !ec2EbsVolumeID! -i !ec2Instance! -d !ec2EbsDevice!
    echo ^>!cmd!
    call !cmd!

    echo.
    echo Waiting 60 seconds for startup scripts and volume to attach...
    call sleep 60

    REM Mount the EBS volume
    echo.
    echo Mounting !ec2EbsDevice! to !ec2BackupDestPath!...
    set cmd=ssh -i !ec2KeyPairPath! -o StrictHostKeychecking=no !ec2User!@!ec2FQDN! "mount -t !ec2EbsFilesystemType! !ec2EbsDevice! !ec2BackupDestPath!"
    echo ^>!cmd!
    call !cmd!
    goto :eof

REM
REM Performs the rsync
REM
:Rsync
    echo Rsync:
    echo ------

    call :GetFQDN

    if {!ec2FQDN!}=={} (
        echo Instance not found, use -start to start one
        exit /b 1
    )

    echo.
    echo Rsyncing...
    set rsyncRshCmd=--rsh="ssh -i !ec2KeyPairPath!"
    set cmd=rsync !rsyncStandardOptions! !rsyncRshCmd! !commandLineOptions! !rsyncInclude! !backupDir! !ec2User!@!ec2FQDN!:!ec2BackupDestPath!
    echo ^>!cmd!
    call !cmd!
    goto :eof

REM
REM Stops the EC2 instance
REM
:Stop
    echo Stop:
    echo -----
    echo Checking if any instances are running...
    set cmd=!ec2ToolsBinDir!\ec2-describe-instances.cmd --filter "tag:!ec2InstanceTag!="
    echo ^>!cmd!

    set ec2State=unknown
    for /f "tokens=2,6" %%f in ('!cmd! ^| findstr INSTANCE') do (
        set ec2Instance=%%f
        set ec2State=%%g
        echo     State: !ec2State!
    )

    if {!ec2State!}=={running} (
        echo.
        echo Stopping !ec2Instance!...
        set cmd=!ec2ToolsBinDir!\ec2-terminate-instances.cmd !ec2Instance!
        echo ^>!cmd!
        call !cmd!
    ) else (
        echo No instances found
    )

    goto :eof

REM
REM Gets the FQDN of the instance
REM
:GetFQDN
    echo.
    echo Getting FQDN of the instance...
    set cmd=!ec2ToolsBinDir!\ec2-describe-instances.cmd !ec2Instance! --filter "tag:!ec2InstanceTag!="
    echo ^>!cmd!
    for /f "tokens=4" %%f in ('!cmd! ^| findstr INSTANCE') do (
        set ec2FQDN=%%f
        echo     FQDN: !ec2FQDN!
    )
    goto :eof

REM
REM Waits for an instance to startup
REM
:WaitForInstance
    echo.
    echo Sleeping 10 seconds before checking on !ec2Instance!...
    call sleep 10

    REM fall-through

    REM
    REM Loops, waiting for the instance to startup
    REM
    echo.
    echo Checking if !ec2Instance! is running...
    set cmd=!ec2ToolsBinDir!\ec2-describe-instances.cmd --filter "tag:!ec2InstanceTag!="
    echo ^>!cmd!

    set ec2State=unknown
    for /f "tokens=2,6" %%f in ('!cmd! ^| findstr INSTANCE') do (
        set ec2Instance=%%f
        set ec2State=%%g
    )

    if {!ec2State!}=={running} (
        echo    !ec2Instance! is !ec2State!
        goto :eof
    )

    echo     State: !ec2State!
    REM not found or not running
    goto :WaitForInstance

REM
REM Command line usage
REM
:Usage
    echo amazon-cloud-backup.cmd [-command]
    echo.
    echo Usage: -launch         Launch a new instance
    echo        -status         Check if any rsync instances are running
    echo        -volumestatus   Checks disk space of your volumne
    echo        -rsync [opts]   Perform a rsync
    echo        -stop           Stops the instance
    exit /b 1
