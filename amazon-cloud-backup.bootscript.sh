#!/bin/bash

#
# This is a boot script for the Amazon Linux AMIs:
#  http://aws.amazon.com/amis/4157
#
# It does the following:
#  1. Un-alias cp and mv which may be aliased to `cp -i`, so -f would still prompt for overwrite
#  2. Make the /backup dir
#  3. Ensure 'root' can login by setting PermitRootLogin in sshd_config and copying the authorized-keys
#     from ec2-user to root
#
# root is required to mount the EBS volume non-interactively via a ssh command (sudo doesn't work on
#  the Amazon Linux AMI over ssh).
#
# If you are using a different AMI, you may need to update this script.
#

# unalias things so we don't get prompted
unalias cp
unalias mv

# create backup directory
mkdir /backup

# ensure root can login via ssh
sed 's/^PermitRootLogin.*/PermitRootLogin yes/' < /etc/ssh/sshd_config > /etc/ssh/sshd_config.new
mv -f /etc/ssh/sshd_config.new /etc/ssh/sshd_config
/etc/init.d/sshd reload

# set authorized keys for root
cp -f /home/ec2-user/.ssh/authorized_keys /root/.ssh/authorized_keys