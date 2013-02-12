Copyright (c) 2012 [Nic Jansma](http://nicj.net)

This script allows you to use Amazon Web Services to backup your files to your own personal "cloud".

Features
--------
* Uses rsync over ssh to securely backup your Windows machines to Amazon's EC2 (Elastic Compute Cloud) cloud, with persistent storage provided by Amazon EBS (Elastic Block Store)
* Rsync efficiently mirrors your data to the cloud by only transmitting changed deltas, not entire files
* An Amazon EC2 instance is used as a temporary server inside Amazon's data center to backup your files, and it is only running while you are actively performing the rsync
* An Amazon EBS volume holds your backup and is only attached during the rsync, though you could attach it to any other EC2 instance later for data retrieval, or snapshot it to S3 for point-in-time backup

Introduction
------------
There are several online backup services available, from [Mozy](http://mozy.com/) to [Carbonite](http://www.carbonite.com/en/)
to [Dropbox](http://dropbox.com).  They all provide various levels of backup services for little or no cost.  They usually
require you to run one of their apps on your machine, which backs up your files periodically to their "cloud" of storage.

While these services may suffice for the majority of people, you may wish to take a little more control of your backup process. For
example, you are trusting their client app to do the right thing, and for your files to be stored securely in their data centers. They may
also put limits on the rate they upload your backups, change their cost, or even go out of business.

On the other hand, one of the simplest tools to backup files is a program called [rsync](http://en.wikipedia.org/wiki/Rsync), which has been around for a long time. It
efficiently transfers files over a network, and can be used to only transfer the parts of a file that have changed since the last sync.  Rsync
can be run on Linux or Windows machines through [Cygwin](http://www.cygwin.com).  It can be run over SSH, so backups are performed with encryption. The
problem is you need a Linux rsync server somewhere as the remote backup destination.

Instead of relying on one of the commercial backup services, I wanted to create a DIY backup "cloud" that I had complete control of.  This
script uses Amazon Web Services, a service from Amazon that offers on-demand compute instances (EC2) and storage volumes (EBS).  It uses the amazingly
simple, reliable and efficient rsync protocol to back up your documents quickly to Amazon's data centers, only using an EC2 instance
for the duration of the rsync.  Your backups are stored on EBS volumes in Amazon's data center, and you have complete
control over them.  By using this DIY method of backup, you get complete control of your backup experience.  No upload rate-limiting, no
client program constantly running on your computer.  You can even do things like encrypt the volume you're backing up to.

The only service you're paying for is Amazon EC2 and EBS, which is pretty cheap, and not likely to disappear any time soon. For example,
my monthly EC2 costs for performing a weekly backup are less than a dollar, and EBS costs at this time are as cheap as $0.10/GB/mo.

These scripts are provided to give you a simple way to backup your files via rsync to Amazon's infrastructure, and can be easily
adapted to your needs.

How It Works
------------
This script is a simple DOS batch script that can be run to launch an EC2 instance, perform the rsync, stop the instance, and check on the status of your instances.

After you've created your personal backup "cloud" (see *Amazon Cloud Setup*), and have the *Required Tools*, you simply run the `amazon-cloud-backup.cmd -start` to
startup a new EC2 instance.  Internally, this uses the Amazon API Developer Tools to start the instance via `ec2-run-instances`.  There's 
a custom bootscript for the instance, `amazon-cloud-backup.bootscript.sh` that works well with the Amazon Linux AMIs to
enable `root` access to the machine over SSH (they initially only offer the user `ec2-user` SSH access).  We need root access to perform
the mount of the volume.

After the instance is started, the script attaches your personal EBS volume to the device.  Its remote address is queried via
`ec2-describe-instances` and SSH is used to mount the EBS volume to a backup point (eg, `/backup`).  Once this is completed, your remote
EC2 instance and EBS volume are ready for you to rsync.

To start the rsync, you simply need to run `amazon-cloud-backup.cmd -rsync [options]`.  Rsync is started over SSH, and your files are backed up
to the remote volume.

Once the backup is complete, you can stop the EC2 instance at any time by running `amazon-cloud-backup.cmd -stop`, or get the status of the instance
by running `amazon-cloud-backup.cmd -status`.  You can also check on the free space on the volume by running `amazon-cloud-backup.cmd -volumestatus`.

There are a couple things you will need to configure to set this all up.  First you need to sign up for Amazon Web Services and generate the appropriate
keys and certificates. Then you need a few helper programs on your machine, for example `rsync.exe` and `ssh.exe`.  Finally, you need
to set a few settings in `amazon-cloud-backup.cmd` so the backup is tailored to your keys and requirements.

Amazon "Cloud" Setup
--------------------
To use this script, you need to have an Amazon Web Services account.  You can sign up for one at [https://aws.amazon.com/](https://aws.amazon.com/).  Once you have an Amazon Web Services account, you will also need to sign up for Amazon EC2.

Once you have access to EC2, you will need to do the following.

1.  Create a X.509 Certificate so we can enable API access to the Amazon Web Service API.  You can get this in your
    [Security Credentials](https://aws-portal.amazon.com/gp/aws/securityCredentials) page.  Click on the *X.509 Certificates* tab,
    then *Create a new Certificate*.  Download both the X.509 Private Key and Certificate files (pk-xyz.pem and cert-xyz.pem).

2.  Determine which Amazon Region you want to work out of.  See their [Reference](http://docs.amazonwebservices.com/general/latest/gr/rande.html) page for details.
    For example, I'm in the Pacific Northwest so I chose us-west-2 (Oregon) as the Region.

3.  Create an EC2 Key Pair so you can log into your EC2 instance via SSH.  You can do this in the
    [AWS Management Console](https://console.aws.amazon.com/ec2/).  Click on *Create a Key Pair*, name it (for example, "amazon-cloud-backup-rsync") and download the .pem file.

4.  Create an EBS Volume in the [AWS Management Console](https://console.aws.amazon.com/ec2/).  Click on *Volumes* and
    then *Create Volume*.  You can create whatever size volume you want, though you should note that you will pay monthly
    charges for the volume size, not the size of your backed up files.

5.  Determine which EC2 AMI (Amazon Machine Image) you want to use.  I'm using the [Amazon Linux AMI: EBS Backed 32-bit](http://aws.amazon.com/amis/4157)
    image.  This is a Linux image provided and maintained by Amazon.  You'll need to pick the appropriate AMI ID for your region.  If you 
    do not use one of the Amazon-provided AMIs, you may need to modify `amazon-cloud-backup.bootscript.sh` for the backup to work.

6.  Create a new EC2 Security Group that allows SSH access.  In the [AWS Management Console](https://console.aws.amazon.com/ec2/), under
    EC2, open the *Security Groups* pane.  Select *Create Security Group* and name it "ssh" or something similar.  Once added,
    edit its *Inbound* rules to allow port 22 from all sources "0.0.0.0/0".  If you know what your remote IP address is ahead of time,
    you could limit the source to that IP.

7.  Launch an EC2 instance with the "ssh" Security Group.  After you launch the instance, you can use the *Attach Volume* button in the
    *Volumes* pane to attach your new volume as `/dev/sdb`.

8.  Log-in to your EC2 instance using ssh (see *Required Tools* below) and fdisk the volume and create a filesystem.

    For example:

        ssh -i my-rsync-key.pem ec2-user@ec2-1-2-3-4.us-west-1.compute.amazonaws.com
        [ec2-user] sudo fdisk /dev/sdb
        ...
        [ec2-user] sudo mkfs.ext4 /dev/sdb1

9.  Your Amazon personal "Cloud" is now setup.

Many of the choices you've made in this section will need to be set as configuration options in the `amazon-cloud-backup.cmd` script.

Required Tools
--------------
You will need a couple tools on your Windows machine to perform the rsync backup and query the Amazon Web Services API.

1.  First, you'll need a few binaries (`rsync.exe`, `ssh.exe`) on your system to facilitate the ssh/rsync transfer.
    [Cygwin](http://www.cygwin.com/) can be used to accomplish this.  You can easily install Cygwin from [http://www.cygwin.com/](http://www.cygwin.com/).
    After installing, pluck a couple files from the `bin/` folder and put them into this directory.

    The binaries you need are:

        rsync.exe
        ssh.exe
        sleep.exe

    You may also need a couple libraries to ensure those binaries run:

        cygcrypto-0.9.8.dll
        cyggcc_s-1.dll
        cygiconv-2.dll
        cygintl-8.dll
        cygpopt-0.dll
        cygspp-0.dll
        cygwin1.dll
        cygz.dll

2.  You will need the Amazon API Developer Tools, downloaded from [http://aws.amazon.com/developertools/](http://aws.amazon.com/developertools/).

    Place them in a sub-directory called `amazon-tools\`

Script Configuration
--------------------
Now you simply have to configure `amazon-cloud-backup.cmd`.

Most of the settings can be left at their defaults, but you will likely need to change the locations and name of your X.509 Certificate and EC2 Key Pair.

Usage
-----
Once you've done the steps in *Amazon "Cloud" Setup*, *Required Tools* and *Script Configuration*, you just need to run the `amazon-cloud-backup.cmd` script.

These simple steps will launch your EC2 instance, perform the rsync, and then stop the instance.

    amazon-cloud-backup.cmd -launch
    amazon-cloud-backup.cmd -rsync
    amazon-cloud-backup.cmd -stop

After -stop, your EC2 instance will stop and the EBS volume will be un-attached.

Command Line Options
--------------------
`amazon-cloud-backup.cmd -launch`: Launch a new instance if one isn't already running

`amazon-cloud-backup.cmd -status`: Check if any rsync instances are running

`amazon-cloud-backup.cmd -volumestatus`: Checks disk space of your volume

`amazon-cloud-backup.cmd -rsync [opts]`: Performs the rsync

`amazon-cloud-backup.cmd -stop`: Stops the instance

Version History
---------------
v1.0 - 2012-02-20: Initial release