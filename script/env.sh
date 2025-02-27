# -*-Shell-script-*-

configure_env () {

    # Bastion must be started
    if [ "$(sudo virsh domstate ${CLUSTER_NAME}-bastion)" != "running" ]; then
        echo "Error: Bastion is not running. Please start the cluster first."
        exit -10
    fi

    # Prefix network must be defined
    if [ "$LIBVIRT_NETWORK_PREFIX" == "" ]; then
        echo "Error: LIBVIRT_NETWORK_PREFIX is not defined."
        exit -11
    fi

    # Get cluster host interface
    INTERFACE=$(ip route | grep "${LIBVIRT_NETWORK_PREFIX}\." | grep -v virbr0 | grep -oP 'dev \K\w+')

    # Configuring host resolvectl
    sudo resolvectl domain ${INTERFACE} ${CLUSTER_NAME}.${CLUSTER_DOMAIN}
    sudo resolvectl dns ${INTERFACE} ${LIBVIRT_NETWORK_PREFIX}.3

    echo
    echo "##### Current DNS configuration #####"
    echo

    resolvectl status ${INTERFACE}

    echo 
    echo "##### DNS validation #####"
    echo

    hosts='bastion api api-int console-openshift-console.apps bootstrap master1 master2 master3'

    if [[ NUMBER_WORKERS -eq 2 ]]; then
        hosts="$hosts worker1 worker2"
    fi
    if [[ NUMBER_WORKERS -eq 3 ]]; then
        hosts="$hosts worker1 worker2 worker3"
    fi
    # more than 3? Who cares.

    output=''
    for host in $hosts; do
        ip=$(dig +short ${host}.${CLUSTER_NAME}.${CLUSTER_DOMAIN})
        name="${host}.${CLUSTER_NAME}.${CLUSTER_DOMAIN}" 
        output="$output\n$name $ip"
    done

    echo -e $output | column -t

    echo
    echo "##### Logging in to Bastion host #####"
    echo 
    ssh -i ssh/id_rsa \
        -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        root@bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}
}
