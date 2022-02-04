#!/usr/bin/env bash
#
# Phase 1 - Prepare the infrastrucutre.
#

# Verify libvirt is enabled
if [ $(sudo systemctl is-enabled libvirtd.service) != 'enabled' ] ; then
  echo "Error: Libvirt is not enabled."
  exit -1
else
  echo "INFO: Libvirt installed and enabled."
fi

# Check for binaries.
packages=""

virsh -v 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "INFO: virsh detected."
else
  packages="$packages libvirt-client"
fi

virt-install --version 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "INFO: virt-install detected."
else
  packages="$packages virt-install"
fi

virt-viewer --version 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "INFO: virt-viewer detected."
else
  packages="$packages virt-viewer"
fi

if [ "$packages" != "" ] ; then
  echo "Installing missing virt packages..."
  sudo dnf install -y $packages
fi

# Validate settings.
source Settings

echo "

This setup uses the values defined in the Settings file.
Feel free to adjust to your liking.


Current values:

LIBVIRT_URI=$LIBVIRT_URI
LIBVIRT_STORAGE=$LIBVIRT_STORAGE
LIBVIRT_NETWORK_PREFIX=$LIBVIRT_NETWORK_PREFIX

DOMAIN=$DOMAIN
CLUSTER_NAME=$CLUSTER_NAME

Do you want to continue? Press Enter or CTRL+C to abort."

read tmp


# Connect to system instance of libvirt.
virsh connect qemu:///system


# Create network for cluster.
