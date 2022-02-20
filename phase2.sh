#!/usr/bin/env bash

#
# Phase 1 - Prepare the infrastrucutre.
#

# Make sure this script does not kill your laptop.
/usr/bin/renice +19 -p $$ >/dev/null 2>&1
/usr/bin/ionice -c2 -n7 -p $$ >/dev/null 2>&1

### Validate settings.
source Settings

echo
echo "$(date +%T) INFO: Phase 2 - Preparing Bastion VM for the OpenShift Install."

# Go to Ansible folder.
cd ansible

echo "$(date +%T) INFO: Check to make sure Ansible can proceed."
ansible \
	--private-key=../ssh/id_rsa \
	--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
	-u root -i hosts all -m ping

if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: Running Ansible Playbook to configure Bastion..."

	ansible-playbook \
		--private-key=../ssh/id_rsa \
		--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
		-u root -i hosts bastion-phase2.yaml
else
	echo "$(date +%T) ERROR: Ansible test failed. Fix the issue and run this command again."
	exit 100
fi

# Back to script folder.
cd ..
