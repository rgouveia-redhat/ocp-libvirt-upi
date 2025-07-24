# -*-Shell-script-*-

# This is a very idiotic way of spreading the vms per disks.
# But, I am in a hurry, and... I don't care!

get_storage_for () {

  echo -n "$(date +%T) INFO: Get storage index for $1 == "

  if [[ ${#LIBVIRT_STORAGE_POOL[@]} -eq 0 ]]; then
    echo -n "$(date +%T) ERROR: No Storage pools defined."
    exit -3
  fi

  if [[ ${#LIBVIRT_STORAGE_POOL[@]} -eq 1 ]]; then
    STORAGE_POOL_INDEX=0
    echo $STORAGE_POOL_INDEX
    return
  fi

  if [[ ${#LIBVIRT_STORAGE_POOL[@]} -eq 2 ]]; then
    STORAGE_POOL_INDEX=$((0 + $RANDOM % 1))
    echo $STORAGE_POOL_INDEX
    return
  fi

  # Else, assume 3 pools or more.
  case "$1" in
  
    bastion|master1)
      STORAGE_POOL_INDEX=0
      ;;

    bootstrap|master2|worker1)
      STORAGE_POOL_INDEX=1
      ;;

    master3|worker2)
      STORAGE_POOL_INDEX=2
      ;;

    *|'')
      max=${#LIBVIRT_STORAGE_POOL[@]}
      ((max--))
      STORAGE_POOL_INDEX=$((0 + $RANDOM % $max))
      ;;

  esac

  echo $STORAGE_POOL_INDEX
}

get_available_subnet () {

  # TODO: What if a host has networks not in the 192.168.0.0/16 range ???

  # Get Libvirt existing subnets
  libvirt_networks=$(sudo virsh net-list --name --all)
  #echo $libvirt_networks

  subnets=''
  for net in $libvirt_networks; do
    gw=$(sudo virsh net-dumpxml $net | xmlstarlet select --text -t -v '/network/ip/@address')
    subnets="$subnets $gw"
  done
  #echo $subnets

  # Get existing networks configured in the host
  host_networks=$(ip route list | cut -d' ' -f1 | grep -v default)
  #echo $host_networks

  # Get the octets
  octets=''
  for sub in $subnets $host_networks; do
    #echo "debug: $sub"
    oct=$(echo $sub | cut -d'.' -f3)
    octets="$octets $oct"
  done
  octets=$(echo $octets | sed 's/ /\n/g' | sort -n | uniq)
  #echo $octets

  # Select an available octet
  n=1
  found=0
  # TODO: What if n>254 ???
  while [ $found -eq 0 ]; do

    exists=0
    for oct in $octets; do
      #echo "debug: $oct"
      if [ "$oct" == "$n" ]; then
        #echo "$n exists"
        exists=1
        break
      fi
    done

    if [ $exists -eq 1 ]; then
      ((n++))
    else
      found=1
    fi
  done
  #echo "debug: available=$n"

  LIBVIRT_NETWORK_PREFIX="192.168.${n}"

  # Saving the prefix for script idempotent re-runs.
  echo $LIBVIRT_NETWORK_PREFIX > ./.re-run-with-network
}

validate_defaults () {

  if [ "$LIBVIRT_URI" == "" ]; then
    LIBVIRT_URI='qemu:///system'
  fi

  if [ "$LIBVIRT_NETWORK_PREFIX" == "" ]; then
    # Check if network file exists and re-use it.
    if [ -f ./.re-run-with-network ]; then
      echo -n "$(date +%T) INFO: Previously selected network file exists. Re-using it: "
      LIBVIRT_NETWORK_PREFIX=$(cat ./.re-run-with-network)
      echo $LIBVIRT_NETWORK_PREFIX
    else
      echo "$(date +%T) INFO: Get available subnet..."
      get_available_subnet
    fi
  fi

  if [ "$DISCONNECTED" == "true" ]; then
    if [ "$REGISTRY" == "false" ] && [ "$PROXY" == "false" ]; then
      echo "ERROR: Disconnected requested! Either enable Registry or Proxy to continue."
      exit -5
    fi
    # TODO: Can they both be installed?
  fi
  # When Connected, I guess the registry may be installed for cache, and proxy can be used although not needed.

  # If not defined
  if [ "$NUMBER_WORKERS" == "" ]; then
    NUMBER_WORKERS=2
  fi

  if ! ( [[ $NUMBER_WORKERS -eq 0 ]] || [[ $NUMBER_WORKERS -ge 2 ]] ); then
    echo "$(date +%T) ERROR: Allowed number of workers is: 0, 2 or more. (not tested with more than 3)"
    exit
  fi
}

create_ssh_key () {

    ### Check/Create SSH Keys. OpenShift compatible.
    if [ -f ./ssh/id_rsa ]; then
        echo "$(date +%T) INFO: SSH keys already created."
    else
        echo "$(date +%T) INFO: Generating SSH Keys..."
        mkdir ./ssh
        ssh-keygen -t ed25519 -f ./ssh/id_rsa -N '' -C "kubeadmin@${CLUSTER_NAME}.${CLUSTER_DOMAIN}"
        chmod 400 ./ssh/id_rsa*
    fi
}

stop_abi_nodes () {

    echo
    echo "Stopping nodes..."

    for i in $(seq 1 3) ; do
        sudo virsh shutdown --domain ${CLUSTER_NAME}-master${i}
    done

    for i in $(seq 1 ${NUMBER_WORKERS}); do
        sudo virsh shutdown --domain ${CLUSTER_NAME}-worker${i}
    done

    echo -n "Waiting for nodes to shutdown..."
    while [ "$(sudo virsh list --name | grep ${CLUSTER_NAME}- | grep -v ${CLUSTER_NAME}-bastion)" != "" ]; do
        echo -n "."
        sleep 2
    done
    echo
}

start_abi_nodes () {

    echo "Starting dependencies..."
    sudo virsh start --domain ${CLUSTER_NAME}-bastion

    echo -n "Waiting for bastion to be available..."
    ready=0
    while [ $ready -eq 0 ]; do

        ssh -q \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            -o UserKnownHostsFile=/dev/null \
            -o StrictHostKeyChecking=no \
            -i ssh/id_rsa root@${LIBVIRT_NETWORK_PREFIX}.3 exit

        if [ $? -eq 0 ]; then
            ready=1
        else
            echo -n "."
            sleep 2
        fi
    done
    echo

    # Start master vms.
    for i in {1..3}; do

      echo "Starting master${i}..."

      sudo nice -n 19 virt-install \
          --reinstall ${CLUSTER_NAME}-master${i} \
          --boot cdrom,hd,menu=on \
          --os-variant $BASTION_VARIANT \
          --cdrom /var/lib/libvirt/images/agent.x86_64.iso \
          --noautoconsole --wait=-1
    done

    # Start worker vms.
    for i in $(seq 1 ${NUMBER_WORKERS}); do

      echo "Starting worker${i}..."

      sudo nice -n 19 virt-install \
          --reinstall ${CLUSTER_NAME}-worker${i} \
          --boot cdrom,hd,menu=on \
          --os-variant $BASTION_VARIANT \
          --cdrom /var/lib/libvirt/images/agent.x86_64.iso \
          --noautoconsole --wait=-1
    done
}


show_help() {

    echo "
Usage: $0 option

options:

    help       - Displays this help.

    create     - Creates a new cluster based on settings from the file 'Settings'.

    env        - Configures the host local DNS resolver and SSH into the bastion vm.
                 This is required to access the OpenShift Web Console via browser.

    start      - Start the cluster.

    stop       - Stop the cluster.

    destroy    - Destroys/Deletes the cluster. Removes ALL Libvirt used resources.
                 Use with care!!!
    
    "    
}

show_help_install () {

    echo "
- To define host variables to open the web console, execute:
  ./engage env

- To SSH in to the bastion host, execute one of:
  ssh -i ssh/id_rsa root@bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}
  ssh -i ssh/id_rsa root@${LIBVIRT_NETWORK_PREFIX}.3

### In the bastion host: ###

## UPI

- To start the installation, boot all the nodes and select the role assigned in the PXE menu.
  You must select the role option to load the ignition file. After that, by default, the 
  nodes boot from the local disk.

- To keep track of the installation, execute:
  openshift-install --dir install-dir wait-for bootstrap-complete

  And after that:
  openshift-install --dir install-dir wait-for install-complete

- To keep track of Pending certificates, execute:
  oc get csr -o name | xargs oc adm certificate approve
  oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{\"\\n\"}}{{end}}{{end}}' | xargs oc adm certificate approve


## ABI

- To keep track of the installation, execute:
  openshift-install --dir install-dir agent wait-for bootstrap-complete

  And after that:
  openshift-install --dir install-dir agent wait-for install-complete


## All

- To see the evolution of the installation, execute:
  watch \"oc get clusterversion ; oc get co ; oc get nodes ; oc get csr\"
    "
}
