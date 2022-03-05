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
if ! [ -f Settings ]; then
    echo "Error: Settings file does not exist yet.
Create one from Settings-example and change to your needs."
    exit -2
fi
source Settings

if ! [ -f "$PULL_SECRET" ]; then
  echo "Error: Pull-secret file does not exist yet. Get it from https://console.redhat.com/openshift/downloads"
  exit -1
fi


echo "
  IMPORTANT: This script uses the values defined in the 'Settings' file.
             Feel free to adjust the values to your needs.

These are the current values for your reference:

LIBVIRT_URI=$LIBVIRT_URI
LIBVIRT_NETWORK_PREFIX=$LIBVIRT_NETWORK_PREFIX
LIBVIRT_STORAGE_POOL_BASE=$LIBVIRT_STORAGE_POOL_BASE

BASTION_INSTALL_TYPE=$BASTION_INSTALL_TYPE
BASTION_INSTALL_ISO=$BASTION_INSTALL_ISO
DNS_FORWARDERS=$DNS_FORWARDERS

DISCONNECTED=$DISCONNECTED
CLUSTER_DOMAIN=$CLUSTER_DOMAIN
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_VERSION=$CLUSTER_VERSION
ARCH=$ARCH
OPENSHIFT_MIRROR_BASE=$OPENSHIFT_MIRROR_BASE

PULL_SECRET='$PULL_SECRET'
PULL_SECRET_EMAIL='$PULL_SECRET_EMAIL'
"

echo -e "Bastion $BASTION_DISK_SIZE $BASTION_CPUS $BASTION_MEMORY_SIZE
Bootstrap $BOOTSTRAP_DISK_SIZE $BOOTSTRAP_CPUS $BOOTSTRAP_MEMORY_SIZE
Master $MASTER_DISK_SIZE $MASTER_CPUS $MASTER_MEMORY_SIZE
Worker $WORKER_DISK_SIZE $WORKER_CPUS $WORKER_MEMORY_SIZE
" | column -N 'Role,Disk Size,CPUs, Memory' -t

echo
echo -n "Do you want to continue? Press Enter or CTRL+C to abort."
read tmp
echo


### Check for sudo privileges

sudo id 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: User has sudo privileges."
else
	echo "$(date +%T) WARNING: User DOES NOT have sudo privileges without password."
fi


### Verify libvirt is enabled
if [ $(sudo systemctl is-enabled libvirtd.service) != 'enabled' ] ; then
  echo "$(date +%T) Error: Libvirt is not enabled."
  exit -1
else
  echo "$(date +%T) INFO: Libvirt installed and enabled."
fi

### Check for needed binaries.
packages=""

virsh -v 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: virsh detected."
else
  packages="$packages libvirt-client"
fi

virt-install --version 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: virt-install detected."
else
  packages="$packages virt-install"
fi

virt-viewer --version 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: virt-viewer detected."
else
  packages="$packages virt-viewer"
fi

ansible --version 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: ansible detected."
else
  packages="$packages ansible"
fi

if [ "$packages" != "" ] ; then
  echo "$(date +%T) INFO: Installing missing packages: $packages"
  sudo dnf install -y $packages
fi


### Set permission on images folder.
sudo chown -R qemu:qemu $LIBVIRT_STORAGE_POOL_BASE


### Connect to system instance of libvirt.
sudo virsh connect qemu:///system


### Create network for cluster.
tmp=$(sudo virsh net-list --all --name | egrep "^${CLUSTER_NAME}\s*$")
if [ "$tmp" != "" ] ; then
    echo "$(date +%T) INFO: Network already exists."
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
tmp=$(sudo virsh pool-list --all --name | egrep "^${CLUSTER_NAME}\s*$")
if [ "$tmp" != "" ] ; then
    echo "$(date +%T) INFO: Storage Pool already exists."
else
    sudo mkdir -p $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME
    sudo chown -R qemu:qemu $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME
    sudo virsh pool-create-as --print-xml --name $CLUSTER_NAME --type dir --target $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME > /tmp/pool-tmp.xml
    sudo virsh pool-define --file /tmp/pool-tmp.xml
    sudo virsh pool-autostart $CLUSTER_NAME
    sudo virsh pool-start $CLUSTER_NAME
    rm /tmp/pool-tmp.xml
fi


### Check for installation ISO.
if [ "$BASTION_INSTALL_ISO" != "" ] && [ -f $BASTION_INSTALL_ISO ] ; then
	echo "$(date +%T) INFO: Source: $BASTION_INSTALL_ISO"
else
	echo "$(date +%T) ERROR: Install ISO not found! Please define BASTION_INSTALL_ISO."
	exit 2
fi


### Check/Create SSH Keys. OpenShift compatible.
if [ -f ./ssh/id_rsa ]; then
	echo "$(date +%T) INFO: SSH keys already created."
else
    echo "$(date +%T) INFO: Generating SSH Keys..."
    mkdir ./ssh
    ssh-keygen -t ed25519 -f ./ssh/id_rsa -N '' -C "kubeadmin@${CLUSTER_NAME}.${CLUSTER_DOMAIN}"
    chmod 400 ./ssh/id_rsa*
fi


### Create bastion vm.
if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-bastion)" != "" ] ; then
    echo "$(date +%T) INFO: Bastion VM already exists."
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
        -e "s#\${CLUSTER_NAME}#$CLUSTER_NAME#g" \
        -e "s#\${CLUSTER_DOMAIN}#$CLUSTER_DOMAIN#g" \
        -e "s#\${LIBVIRT_NETWORK_PREFIX}#$LIBVIRT_NETWORK_PREFIX#g" \
        -e "s#\${SSH_KEY}#$ssh_key#" \
        $ks > files.phase1/anaconda.ks
    if ! [ $? -eq 0 ]; then
        echo "$(date +%T) ERROR: Error generating kickstart file"
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
		--network network=${CLUSTER_NAME},model=virtio \
		--initrd-inject files.phase1/anaconda.ks \
		--extra-args 'inst.ks=file:/anaconda.ks' \
		--noautoconsole

    if [ "$BASTION_INSTALL_TYPE" == "redhat" ]; then
        echo "

$(date +%T) [ACTION REQUIRED] Open a console to the bastion vm and 
                  complete the Red Hat Network authentication!
                  Close the virt-viewer window when done.
                  
                  "
        sudo virt-viewer ${CLUSTER_NAME}-bastion
    fi

    echo "$(date +%T) INFO: VMs will power off after installation. Waiting for it..."

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
fi


### Start bastion and wait for ip address.
if [ "$(sudo virsh domstate ${CLUSTER_NAME}-bastion)" != "running" ]; then
    sudo virsh start ${CLUSTER_NAME}-bastion
fi

bastion_ip=""
echo -n "Waiting for bastion IP..."
while [ "$bastion_ip" == "" ]; do
    echo -n "."
    sleep $DELAY
	bastion_ip=$(sudo virsh domifaddr ${CLUSTER_NAME}-bastion | egrep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
done
echo
echo "$(date +%T) INFO: Bastion IP: $bastion_ip"


### Create hosts file for Ansible.
echo "$(date +%T) INFO: Generating the Ansible hosts file..."

mkdir -p ansible/vars

cat <<EOF > ansible/hosts
[bastion]
$bastion_ip hostname=bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}
EOF


### Prepare Ansible vars file.
echo "$(date +%T) INFO: Generating the Ansible vars file..."

reverse=$(echo $LIBVIRT_NETWORK_PREFIX | awk -F. '{print $3 "." $2 "." $1}')
echo "---
network_prefix: '$LIBVIRT_NETWORK_PREFIX'
network_reverse: '$reverse'
disconnected: '$DISCONNECTED'
arch: '$ARCH'
openshift_mirror_base: '$OPENSHIFT_MIRROR_BASE'
cluster_version: '$CLUSTER_VERSION'
cluster_name: '$CLUSTER_NAME'
cluster_domain: '$CLUSTER_DOMAIN'
dns_forwarders: '$DNS_FORWARDERS'
pull_secret: '$PULL_SECRET'
pull_secret_email: '$PULL_SECRET_EMAIL'
" > ansible/vars/common.yaml


# Create bootstrap vm.
if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-bootstrap)" != "" ]; then
    echo "$(date +%T) INFO: Bootstrap VM already exists."
else
    # Variant. Check with 'osinfo-query os'.
    variant='rhel8.5'

    # Create vm in cluster network.
	sudo nice -n 19 virt-install --name ${CLUSTER_NAME}-bootstrap \
        --cpu host \
		--vcpus $BOOTSTRAP_CPUS \
		--memory $BOOTSTRAP_MEMORY_SIZE \
		--disk $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME/${CLUSTER_NAME}-bootstrap.qcow2,size=$BOOTSTRAP_DISK_SIZE \
		--pxe \
        --boot network,hd,menu=off \
		--os-variant $variant \
		--network network=${CLUSTER_NAME},model=virtio \
		--noautoconsole

    sudo virsh destroy ${CLUSTER_NAME}-bootstrap
fi

if [ "$(grep mac_bootstrap ansible/vars/common.yaml)" == "" ]; then
    mac=$(sudo virsh domiflist ${CLUSTER_NAME}-bootstrap | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
    echo "mac_bootstrap: '$mac'" >> ansible/vars/common.yaml
fi

# Create masters vm.
for i in {1..3}; do
    if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-master$i)" != "" ]; then
        echo "$(date +%T) INFO: Master$i VM already exists."
    else
        # Variant. Check with 'osinfo-query os'.
        variant='rhel8.5'

        # Create vm in cluster network.
        sudo nice -n 19 virt-install --name ${CLUSTER_NAME}-master$i \
            --cpu host \
            --vcpus $MASTER_CPUS \
            --memory $MASTER_MEMORY_SIZE \
            --disk $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME/${CLUSTER_NAME}-master$i.qcow2,size=$MASTER_DISK_SIZE \
            --pxe \
            --boot network,hd,menu=off \
            --os-variant $variant \
            --network network=${CLUSTER_NAME},model=virtio \
            --noautoconsole

        sudo virsh destroy ${CLUSTER_NAME}-master$i
    fi
done

for i in {1..3}; do
    if [ "$(grep mac_master$i ansible/vars/common.yaml)" == "" ]; then
        mac=$(sudo virsh domiflist ${CLUSTER_NAME}-master$i | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
        echo "mac_master$i: '$mac'" >> ansible/vars/common.yaml
    fi
done

# Create workers vms.
for i in {1..3}; do
    if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-worker$i)" != "" ]; then
        echo "$(date +%T) INFO: Worker$i VM already exists."
    else
        # Variant. Check with 'osinfo-query os'.
        variant='rhel8.5'

        # Create vm in cluster network.
        sudo nice -n 19 virt-install --name ${CLUSTER_NAME}-worker$i \
            --cpu host \
            --vcpus $WORKER_CPUS \
            --memory $WORKER_MEMORY_SIZE \
            --disk $LIBVIRT_STORAGE_POOL_BASE/$CLUSTER_NAME/${CLUSTER_NAME}-worker$i.qcow2,size=$WORKER_DISK_SIZE \
            --pxe \
            --boot network,hd,menu=off \
            --os-variant $variant \
            --network network=${CLUSTER_NAME},model=virtio \
            --noautoconsole

        sudo virsh destroy ${CLUSTER_NAME}-worker$i
    fi
done

for i in {1..3}; do
    if [ "$(grep mac_worker$i ansible/vars/common.yaml)" == "" ]; then
        mac=$(sudo virsh domiflist ${CLUSTER_NAME}-worker$i | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
        echo "mac_worker$i: '$mac'" >> ansible/vars/common.yaml
    fi
done


# Go to Ansible folder.
cd ansible


### Use Ansible to configure bastion vm.
echo "$(date +%T) INFO: Waiting for SSH to be ready on bastion vm..."

ready=0
while [ $ready -eq 0 ]; do
	ssh -q \
		-o BatchMode=yes \
		-o ConnectTimeout=10 \
		-o UserKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no \
		-i ../ssh/id_rsa root@${bastion_ip} exit
	if [ $? -eq 0 ]; then
		ready=1
	else
	    echo -n "."
		sleep 5
	fi
done
echo

echo "$(date +%T) INFO: Installing Ansible dependencies..."
if ! [ -d ~/.ansible/collections/ansible_collections/community/general/ ]; then
    ansible-galaxy collection install community.general
fi
if ! [ -d ~/.ansible/collections/ansible_collections/ansible/posix/ ]; then
    ansible-galaxy collection install ansible.posix
fi


echo "$(date +%T) INFO: Check to make sure Ansible can proceed."
ansible \
	--private-key=../ssh/id_rsa \
	--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
	-u root -i hosts all -m ping

if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: Running Ansible Playbook to configure Systems..."

	ansible-playbook \
		--private-key=../ssh/id_rsa \
		--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
		-u root -i hosts bastion.yaml

    if ! [ $? -eq 0 ]; then
        echo "$(date +%T) ERROR: Ansible exited with errors. Fix the errors and rerun ./phase1.sh !"
        exit 10
    fi
else
	echo "$(date +%T) ERROR: Ansible test failed. Fix the issue and run this command again."
	exit 100
fi

# Back to script folder.
cd ..

echo
echo "$(date +%T) INFO: Configuring Host nameserver to recognize cluster fqdn..."
if [ "$(sudo systemctl is-active systemd-resolved.service)" != "active" ]; then
    sudo systemctl enable --now systemd-resolved.service
fi

# Generate script.
interface=$(ip route | grep ${LIBVIRT_NETWORK_PREFIX} | grep -oP 'dev \K\w+')
sed \
    -e "s#\${LIBVIRT_NETWORK_PREFIX}#$LIBVIRT_NETWORK_PREFIX#g" \
    -e "s#\${CLUSTER_NAME}#$CLUSTER_NAME#g" \
    -e "s#\${CLUSTER_DOMAIN}#$CLUSTER_DOMAIN#g" \
    -e "s#\${INTERFACE}#$interface#g" \
    files.phase1/start-env.sh.tpl > ./start-env.sh
    chmod +x ./start-env.sh
if ! [ $? -eq 0 ]; then
    echo "$(date +%T) ERROR: Error generating start-env.sh script."
    exit 5
fi


echo "$(date +%T) INFO: Phase 1 (Infra) sucessfully created.

Moving to Phase 2 - Preparing Bastion VM for the OpenShift Install."

./phase2.sh
