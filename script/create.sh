# -*-Shell-script-*-

. script/ops.sh


show_settings () {

    echo "
IMPORTANT: This script uses the values defined in the 'Settings' file. Feel free to adjust the values to your needs.


LIBVIRT_URI=$LIBVIRT_URI
LIBVIRT_NETWORK_SUBNET=${LIBVIRT_NETWORK_PREFIX}.0/24
LIBVIRT_STORAGE_POOL=${LIBVIRT_STORAGE_POOL[@]}

BASTION_TYPE=$BASTION_TYPE
BASTION_VARIANT=$BASTION_VARIANT
BASTION_INSTALL_ISO=$BASTION_INSTALL_ISO

DISCONNECTED=$DISCONNECTED
REGISTRY=$REGISTRY
REGISTRY_NFS=$REGISTRY_NFS

CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_DOMAIN=$CLUSTER_DOMAIN
CLUSTER_VERSION=$CLUSTER_VERSION
ARCH=$ARCH
NUMBER_WORKERS=$NUMBER_WORKERS

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
        echo "$(date +%T) Error: Libvirt is not enabled. Fixing!"
        sudo systemctl enable --now libvirtd.service
    else
        echo "$(date +%T) INFO: Libvirt installed and enabled."
    fi

    ### Enabling service resolved.
    echo "$(date +%T) INFO: Configuring Host nameserver to recognize cluster fqdn..."
    if [ "$(sudo systemctl is-active systemd-resolved.service)" != "active" ]; then
        sudo systemctl enable --now systemd-resolved.service
    else
        echo "$(date +%T) INFO: systemd-resolved installed and enabled."
    fi

    ### Check for installation ISO.
    if [ "$BASTION_INSTALL_ISO" != "" ] && [ -f $BASTION_INSTALL_ISO ] ; then
        echo "$(date +%T) INFO: Source: $BASTION_INSTALL_ISO"
    else
        echo "$(date +%T) ERROR: Install ISO not found! Please define BASTION_INSTALL_ISO."
        exit 2
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

    xmlstarlet --version 2>&1 1>/dev/null
    if [ $? -eq 0 ]; then
        echo "$(date +%T) INFO: xmlstarlet detected."
    else
        packages="$packages xmlstarlet"
    fi

    if [ "$packages" != "" ] ; then
        echo "$(date +%T) INFO: Installing missing packages: $packages"
        sudo dnf install -y $packages
    fi
}

libvirt_prepare () {

    ### Connect to system instance of libvirt.
    sudo virsh connect $LIBVIRT_URI
}

libvirt_create_network () {

    ### Create network for cluster.
    tmp=$(sudo virsh net-list --all --name | grep -E "^${CLUSTER_NAME}\s*$")
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

    ### Create the storage pool for the cluster.
    for pool in ${LIBVIRT_STORAGE_POOL[@]}; do

        pool_name=$(echo $pool | sed 's/\//-/g')

        tmp=$(sudo virsh pool-list --all --name | grep -E "^${CLUSTER_NAME}-${pool_name}\s*$")
        if [ "$tmp" != "" ] ; then
            echo "$(date +%T) INFO: Storage Pool ${CLUSTER_NAME}-${pool_name} already exists."
        else
            echo "$(date +%T) INFO: Creating Storage Pool $pool/$CLUSTER_NAME ..."

            ### Set permission on parent folder.
            sudo chown -R qemu:qemu $pool

            ### Create and set permission on cluster folder
            sudo mkdir -p ${pool}/$CLUSTER_NAME
            sudo chown -R qemu:qemu ${pool}/$CLUSTER_NAME 

            ### Create libvirt storage pool
            sudo virsh pool-create-as --print-xml \
                --name ${CLUSTER_NAME}-${pool_name} \
                --type dir \
                --target ${pool}/${CLUSTER_NAME} > /tmp/pool-tmp.xml

            sudo virsh pool-define --file /tmp/pool-tmp.xml
            sudo virsh pool-autostart ${CLUSTER_NAME}-${pool_name}
            sudo virsh pool-start ${CLUSTER_NAME}-${pool_name}
            rm /tmp/pool-tmp.xml
        fi
    done
}

libvirt_create_bastion () {

    ### Create bastion vm.
    if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-bastion)" != "" ] ; then
        echo "$(date +%T) INFO: Bastion VM already exists."
    else

        if [ "$BASTION_TYPE" == "redhat" ]; then
            ks='files/redhat.ks.tpl'
        else
            echo "$(date +%T) ERROR: Bastion VM supports only Red Hat for now."
            exit -2
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

        get_storage_for bastion
        disk="${LIBVIRT_STORAGE_POOL[${STORAGE_POOL_INDEX}]}/$CLUSTER_NAME/${CLUSTER_NAME}-bastion.qcow2"
        echo "$(date +%T) INFO: Using disk: $disk"

        # Create vm with default NAT network.
        sudo nice -n 19 virt-install \
            --name ${CLUSTER_NAME}-bastion \
            --cpu host-model \
            --vcpus $BASTION_CPUS \
            --memory $BASTION_MEMORY_SIZE \
            --disk ${disk},size=$BASTION_DISK_SIZE \
            --location $BASTION_INSTALL_ISO \
            --os-variant $BASTION_VARIANT \
            --network network=default,model=virtio \
            --network network=${CLUSTER_NAME},model=virtio \
            --initrd-inject files/anaconda.ks \
            --extra-args 'inst.ks=file:/anaconda.ks' \
            --noautoconsole

        rm files/anaconda.ks

        echo "
        
                    $(date +%T) [ACTION MAY BE REQUIRED] Open a console to the bastion VM and 
                                check if all steps are successful. For example, the Red Hat Network authentication.

"

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
        get_storage_for bootstrap
        disk="${LIBVIRT_STORAGE_POOL[${STORAGE_POOL_INDEX}]}/$CLUSTER_NAME/${CLUSTER_NAME}-bootstrap.qcow2"
        echo "$(date +%T) INFO: Using disk: $disk"

        # Create vm in cluster network.
        sudo nice -n 19 virt-install \
            --name ${CLUSTER_NAME}-bootstrap \
            --cpu host-model \
            --vcpus $BOOTSTRAP_CPUS \
            --memory $BOOTSTRAP_MEMORY_SIZE \
            --disk ${disk},size=$BOOTSTRAP_DISK_SIZE \
            --pxe \
            --boot network,hd,menu=off \
            --os-variant $BASTION_VARIANT \
            --network network=${CLUSTER_NAME},model=virtio \
            --noautoconsole

        # We just need the macs to be generated. For now stop the vm.
        sudo virsh destroy ${CLUSTER_NAME}-bootstrap
    fi
}

libvirt_create_masters () {

    # Create masters vm.
    for i in {1..3}; do
        if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-master${i})" != "" ]; then
            echo "$(date +%T) INFO: Master${i} VM already exists."
        else

            get_storage_for master${i}
            disk="${LIBVIRT_STORAGE_POOL[${STORAGE_POOL_INDEX}]}/$CLUSTER_NAME/${CLUSTER_NAME}-master${i}.qcow2"
            echo "$(date +%T) INFO: Using disk: $disk"

            # Create vm in cluster network.
            sudo nice -n 19 virt-install \
                --name ${CLUSTER_NAME}-master${i} \
                --cpu host-model \
                --vcpus $MASTER_CPUS \
                --memory $MASTER_MEMORY_SIZE \
                --disk ${disk},size=$MASTER_DISK_SIZE \
                --pxe \
                --boot network,hd,menu=off \
                --os-variant $BASTION_VARIANT \
                --network network=${CLUSTER_NAME},model=virtio \
                --noautoconsole

            # We just need the macs to be generated. For now stop the vm.
            sudo virsh destroy ${CLUSTER_NAME}-master${i}
        fi
    done
}

libvirt_create_workers () {

    # Create workers vms.
    for i in $(seq 1 ${NUMBER_WORKERS}); do

        if [ "$(sudo virsh list --all | grep ${CLUSTER_NAME}-worker${i})" != "" ]; then
            echo "$(date +%T) INFO: Worker${i} VM already exists."
        else
            get_storage_for worker${i}
            disk="${LIBVIRT_STORAGE_POOL[${STORAGE_POOL_INDEX}]}/$CLUSTER_NAME/${CLUSTER_NAME}-worker${i}.qcow2"
            echo "$(date +%T) INFO: Using disk: $disk"

            # Create vm in cluster network.
            sudo nice -n 19 virt-install \
                --name ${CLUSTER_NAME}-worker${i} \
                --cpu host-model \
                --vcpus $WORKER_CPUS \
                --memory $WORKER_MEMORY_SIZE \
                --disk ${disk},size=$WORKER_DISK_SIZE \
                --pxe \
                --boot network,hd,menu=off \
                --os-variant $BASTION_VARIANT \
                --network network=${CLUSTER_NAME},model=virtio \
                --noautoconsole

            # We just need the macs to be generated. For now stop the vm.
            sudo virsh destroy ${CLUSTER_NAME}-worker${i}
        fi
    done
}

create_infra () {

    if ! [ -f "$PULL_SECRET" ]; then
        echo "Error: Pull-secret file does not exist yet. Get it from https://console.redhat.com/openshift/downloads"
        exit -1
    fi

    check_sudo
    check_requisites
    validate_defaults
    show_settings

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
        bastion_ip=$(sudo virsh domifaddr ${CLUSTER_NAME}-bastion | grep -Eo "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
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
registry: $REGISTRY
registry_nfs: $REGISTRY_NFS
arch: '$ARCH'
openshift_mirror_base: '$OPENSHIFT_MIRROR_BASE'
cluster_version: '$CLUSTER_VERSION'
cluster_name: '$CLUSTER_NAME'
cluster_domain: '$CLUSTER_DOMAIN'
number_workers: '$NUMBER_WORKERS'
pull_secret: '$PULL_SECRET'
pull_secret_email: '$PULL_SECRET_EMAIL'
" > ansible/vars/common.yaml

    if [ "$(grep mac_bootstrap ansible/vars/common.yaml)" == "" ]; then
        mac=$(sudo virsh domiflist ${CLUSTER_NAME}-bootstrap | grep $CLUSTER_NAME | grep -Eo '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
        echo "mac_bootstrap: '$mac'" >> ansible/vars/common.yaml
    fi

    for i in {1..3}; do
        if [ "$(grep mac_master${i} ansible/vars/common.yaml)" == "" ]; then
            mac=$(sudo virsh domiflist ${CLUSTER_NAME}-master${i} | grep $CLUSTER_NAME | grep -Eo '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
            echo "mac_master${i}: '$mac'" >> ansible/vars/common.yaml
        fi
    done

    for i in $(seq 1 ${NUMBER_WORKERS}); do
        if [ "$(grep mac_worker${i} ansible/vars/common.yaml)" == "" ]; then
            mac=$(sudo virsh domiflist ${CLUSTER_NAME}-worker${i} | grep $CLUSTER_NAME | grep -Eo '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')
            echo "mac_worker${i}: '$mac'" >> ansible/vars/common.yaml
        fi
    done
}
