# -*-Shell-script-*-

. script/ops.sh


show_settings () {

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
REGISTRY_NFS=$REGISTRY_NFS

CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_DOMAIN=$CLUSTER_DOMAIN
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
}

check_sudo () {

    ### Check for sudo privileges
    sudo id 2>&1 1>/dev/null
    if [ $? -eq 0 ]; then
        echo "$(date +%T) INFO: User has sudo privileges."
    else
        echo "$(date +%T) WARNING: User DOES NOT have sudo privileges without password."
    fi
}

check_requisites () {

    ### Verify libvirt is enabled
    if [ $(sudo systemctl is-enabled libvirtd.service) != 'enabled' ] ; then
        echo "$(date +%T) Error: Libvirt is not enabled."
        exit -1
    else
        echo "$(date +%T) INFO: Libvirt installed and enabled."
    fi

    ### Check for installation ISO.
    if [ "$BASTION_INSTALL_ISO" != "" ] && [ -f $BASTION_INSTALL_ISO ] ; then
        echo "$(date +%T) INFO: Source: $BASTION_INSTALL_ISO"
    else
        echo "$(date +%T) ERROR: Install ISO not found! Please define BASTION_INSTALL_ISO."
        exit 2
    fi

    ### Enabling service resolved.
    echo "$(date +%T) INFO: Configuring Host nameserver to recognize cluster fqdn..."
    if [ "$(sudo systemctl is-active systemd-resolved.service)" != "active" ]; then
        sudo systemctl enable --now systemd-resolved.service
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
}

libvirt_prepare () {

    ### Connect to system instance of libvirt.
    sudo virsh connect qemu:///system
}

libvirt_create_network () {

    ### Create network for cluster.
    tmp=$(sudo virsh net-list --all --name | egrep "^${CLUSTER_NAME}\s*$")
    if [ "$tmp" != "" ] ; then
        echo "$(date +%T) INFO: Network already exists."
    else
        if [ "$DISCONNECTED" = true ] ; then
	    echo "$(date +%T) INFO: Creating isolated network..."
            xml=$(eval "echo \"$(cat files/virt-network-isolated.xml)\"")
        else
            echo "$(date +%T) INFO: Creating connected network..."
            xml=$(eval "echo \"$(cat files/virt-network-nat.xml)\"")
        fi
        echo $xml > /tmp/network-tmp.xml

        sudo virsh net-define --file /tmp/network-tmp.xml
        sudo virsh net-autostart $CLUSTER_NAME
        sudo virsh net-start $CLUSTER_NAME
        rm /tmp/network-tmp.xml
    fi
}

libvirt_create_storage () {

    ### Set permission on images folder.
    sudo chown -R qemu:qemu $LIBVIRT_STORAGE_POOL_BASE

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
}

libvirt_create_bastion () {

    ### Create bastion vm.
    if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-bastion)" != "" ] ; then
        echo "$(date +%T) INFO: Bastion VM already exists."
    else
        # Variant. Check with 'osinfo-query os'.
        variant='centos8'
        ks='files/centos.ks.tpl'
        if [ "$BASTION_INSTALL_TYPE" == "redhat" ]; then
            variant='rhel8.5'
            ks='files/redhat.ks.tpl'
        fi
        if [ "$BASTION_INSTALL_TYPE" == "fedora" ]; then
            variant='fedora35'
            ks='files/fedora.ks.tpl'
        fi

        # Generate kickstart file.
        ssh_key=$(cat ./ssh/id_rsa.pub)
        sed \
            -e "s#\${CLUSTER_NAME}#$CLUSTER_NAME#g" \
            -e "s#\${CLUSTER_DOMAIN}#$CLUSTER_DOMAIN#g" \
            -e "s#\${LIBVIRT_NETWORK_PREFIX}#$LIBVIRT_NETWORK_PREFIX#g" \
            -e "s#\${SSH_KEY}#$ssh_key#" \
            $ks > files/anaconda.ks
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
            --initrd-inject files/anaconda.ks \
            --extra-args 'inst.ks=file:/anaconda.ks' \
            --noautoconsole

        rm files/anaconda.ks

        if [ "$BASTION_INSTALL_TYPE" == "redhat" ]; then
            echo "
$(date +%T) [ACTION REQUIRED] Open a console to the bastion vm and 
                              complete the Red Hat Network authentication!
                              Close the virt-viewer window when done."

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
}

libvirt_create_bootstrap () {

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

        # We just need the macs to be generated. For now stop the vm.
        sudo virsh destroy ${CLUSTER_NAME}-bootstrap
    fi
}

libvirt_create_masters () {

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

            # We just need the macs to be generated. For now stop the vm.
            sudo virsh destroy ${CLUSTER_NAME}-master$i
        fi
    done
}

libvirt_create_workers () {

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

            # We just need the macs to be generated. For now stop the vm.
            sudo virsh destroy ${CLUSTER_NAME}-worker$i
        fi
    done
}

create_infra () {

    if ! [ -f "$PULL_SECRET" ]; then
        echo "Error: Pull-secret file does not exist yet. Get it from https://console.redhat.com/openshift/downloads"
        exit -1
    fi

    show_settings
    check_sudo
    check_requisites
    create_ssh_key

    libvirt_prepare
    libvirt_create_network
    libvirt_create_storage

    libvirt_create_bastion
    libvirt_create_bootstrap
    libvirt_create_masters
    libvirt_create_workers

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

    cat <<EOF > ansible/hosts
[bastion]
$bastion_ip hostname=bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}
EOF

    ### Prepare Ansible vars file.
    echo "$(date +%T) INFO: Generating the Ansible vars file..."

    mkdir -p ansible/vars

    reverse=$(echo $LIBVIRT_NETWORK_PREFIX | awk -F. '{print $3 "." $2 "." $1}')

    echo "---
network_prefix: '$LIBVIRT_NETWORK_PREFIX'
network_reverse: '$reverse'
disconnected: $DISCONNECTED
registry_nfs: $REGISTRY_NFS
arch: '$ARCH'
openshift_mirror_base: '$OPENSHIFT_MIRROR_BASE'
cluster_version: '$CLUSTER_VERSION'
cluster_name: '$CLUSTER_NAME'
cluster_domain: '$CLUSTER_DOMAIN'
dns_forwarders: '$DNS_FORWARDERS'
pull_secret: '$PULL_SECRET'
pull_secret_email: '$PULL_SECRET_EMAIL'
" > ansible/vars/common.yaml

    if [ "$(grep mac_bootstrap ansible/vars/common.yaml)" == "" ]; then
        mac=$(sudo virsh domiflist ${CLUSTER_NAME}-bootstrap | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
        echo "mac_bootstrap: '$mac'" >> ansible/vars/common.yaml
    fi

    for i in {1..3}; do
        if [ "$(grep mac_master$i ansible/vars/common.yaml)" == "" ]; then
            mac=$(sudo virsh domiflist ${CLUSTER_NAME}-master$i | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
            echo "mac_master$i: '$mac'" >> ansible/vars/common.yaml
        fi
    done

    for i in {1..3}; do
        if [ "$(grep mac_worker$i ansible/vars/common.yaml)" == "" ]; then
            mac=$(sudo virsh domiflist ${CLUSTER_NAME}-worker$i | grep $CLUSTER_NAME | egrep -o '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
            echo "mac_worker$i: '$mac'" >> ansible/vars/common.yaml
        fi
    done
}
