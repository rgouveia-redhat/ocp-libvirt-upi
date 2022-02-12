#!/usr/bin/env bash

#
# Phase 1 - Prepare the infrastrucutre.
#

# Make sure this script does not kill your laptop.
/usr/bin/renice +19 -p $$ >/dev/null 2>&1
/usr/bin/ionice -c2 -n7 -p $$ >/dev/null 2>&1


# Interval in seconds to check for VMs availability.
DELAY=10


### Validate settings.
source Settings

echo "

IMPORTANT
This script uses the values defined in the 'Settings' file.
Feel free to adjust the values to your needs.

These are the current values for your reference:

LIBVIRT_URI=$LIBVIRT_URI
LIBVIRT_NETWORK_PREFIX=$LIBVIRT_NETWORK_PREFIX
LIBVIRT_STORAGE_POOL_BASE=$LIBVIRT_STORAGE_POOL_BASE

CLUSTER_DOMAIN=$CLUSTER_DOMAIN
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_VERSION=$CLUSTER_VERSION
DISCONNECTED=$DISCONNECTED

BASTION_INSTALL_TYPE=$BASTION_INSTALL_TYPE
BASTION_INSTALL_ISO=$BASTION_INSTALL_ISO

(If redhat)> REDHAT_SUBSCRIPTION_POOL=$REDHAT_SUBSCRIPTION_POOL

BASTION_DISK_SIZE=$BASTION_DISK_SIZE
BASTION_CPUS=$BASTION_CPUS
BASTION_MEMORY_SIZE=$BASTION_MEMORY_SIZE


Do you want to continue? Press Enter or CTRL+C to abort."

#read tmp


### Check for sudo privileges

sudo id 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "INFO: User has sudo privileges."
else
	echo "WARNING: User DOES NOT have sudo privileges without password."
fi


### Verify libvirt is enabled
if [ $(sudo systemctl is-enabled libvirtd.service) != 'enabled' ] ; then
  echo "Error: Libvirt is not enabled."
  exit -1
else
  echo "INFO: Libvirt installed and enabled."
fi

### Check for needed binaries.
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
  echo "INFO: Installing missing virt packages..."
  sudo dnf install -y $packages
fi


### Set permission on images folder.
sudo chown -R qemu:qemu $LIBVIRT_STORAGE_POOL_BASE


### Connect to system instance of libvirt.
sudo virsh connect qemu:///system


### Create network for cluster.
if [ "$(sudo virsh net-list --all --name | grep $CLUSTER_NAME)" != "" ] ; then
    echo "INFO: Network already exists."
else
    if [ $DISCONNECTED ] ; then
        xml=$(eval "echo \"$(cat files.phase1/virt-network-isolated.xml)\"")
    else
        xml=$(eval "echo \"$(cat files.phase1/virt-network-nat.xml)\"")
    fi
    echo $xml > /tmp/network-tmp.xml

    sudo virsh net-define --file /tmp/network-tmp.xml
    sudo virsh net-autostart $CLUSTER_NAME
    sudo virsh net-start $CLUSTER_NAME
    rm /tmp/network-tmp.xml
fi


### Create the storage pool for the cluster.
if [ "$(sudo virsh pool-list --all --name | grep $CLUSTER_NAME)" != "" ] ; then
    echo "INFO: Storage Pool already exists."
else
    mkdir -p $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME
    sudo virsh pool-create-as --print-xml --name $CLUSTER_NAME --type dir --target $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME > /tmp/pool-tmp.xml
    sudo virsh pool-define --file /tmp/pool-tmp.xml
    sudo virsh pool-autostart $CLUSTER_NAME
    sudo virsh pool-start $CLUSTER_NAME
    rm /tmp/pool-tmp.xml
fi


### Check for installation ISO.
if [ "$BASTION_INSTALL_ISO" != "" ] && [ -f $BASTION_INSTALL_ISO ] ; then
	echo "INFO: Source: $BASTION_INSTALL_ISO"
else
	echo "ERROR: Install ISO not found! Please define BASTION_INSTALL_ISO."
	exit 2
fi


### Check/Create SSH Keys. OpenShift compatible.
if [ -f ./ssh/id_rsa ]; then
	echo "INFO: SSH keys already created."
else
    echo "INFO: Generating SSH Keys..."
    mkdir ./ssh
    ssh-keygen -t ed25519 -f ./ssh/id_rsa -N '' -C "kubeadmin@${CLUSTER_NAME}.${CLUSTER_DOMAIN}"
    chmod 400 ./ssh/id_rsa*
fi


# Create bastion vm.
if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-bastion)" != "" ] ; then
    echo "INFO: Bastion VM already exists."
else
    # Variant. Check with 'osinfo-query os'.
    variant='centos8'
    ks='files.phase1/centos.ks.tpl'
    if [ "$BASTION_INSTALL_TYPE" == "redhat" ]; then
        variant='rhel8.5'
        ks='files.phase1/redhat.ks.tpl'
    fi
    if [ "$BASTION_INSTALL_TYPE" == "fedora" ]; then
        variant='fedora35'
        ks='files.phase1/fedora.ks.tpl'
    fi

    # Generate kickstart file.
    ssh_key=$(cat ./ssh/id_rsa.pub)
    sed \
        -e "s#\${CLUSTER_NAME}#$CLUSTER_NAME#" \
        -e "s#\${CLUSTER_DOMAIN}#$CLUSTER_DOMAIN#" \
        -e "s#\${SSH_KEY}#$ssh_key#" \
        $ks > files.phase1/anaconda.ks
    if ! [ $? -eq 0 ]; then
        echo "ERROR: Error generating kickstart file"
        exit 5
    fi

    # Create vm with default NAT network.
	sudo nice -n 19 virt-install --name ${CLUSTER_NAME}-bastion \
        --cpu host \
		--vcpus $BASTION_CPUS \
		--memory $BASTION_MEMORY_SIZE \
		--disk $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME/${CLUSTER_NAME}-bastion.qcow2,size=$BASTION_DISK_SIZE \
		--location $BASTION_INSTALL_ISO \
		--os-variant $variant \
		--network network=default,model=virtio \
		--initrd-inject files.phase1/anaconda.ks \
	    --extra-args 'ks=file:/anaconda.ks console=tty0 console=ttyS0,115200n8' \
		--noautoconsole

    if [ "$BASTION_INSTALL_TYPE" == "redhat" ]; then
        echo "
[ACTION REQUIRED] Open a console to the bastion vm and 
                  complete the Red Hat Network authentication!
                  Close the virt-viewer window when done."
        sudo virt-viewer ${CLUSTER_NAME}-bastion
    fi

    echo "INFO: VMs will power off after installation. Waiting for it..."

    vms_ready=0
    while [[ $vms_ready -eq 0 ]] ; do
        if [ "$(sudo virsh domstate ${CLUSTER_NAME}-bastion)" == "shut off" ]; then
            vms_ready=1
        else
            echo -n "."
            sleep $DELAY
        fi
    done
    echo

    # Add network interface in the isolated network.
    sudo virsh attach-interface ${CLUSTER_NAME}-bastion network $CLUSTER_NAME --model virtio --persistent
fi
