# -*-Shell-script-*-

cluster_destroy () {

    echo
    echo "##### Delete/Remove Cluster ${CLUSTER_NAME} #####"
    echo

    echo -n "

        WARNING:

        ALL resources will be deleted from your system!!!!

        Are you sure you want to proceed ?

        Write the cluster name to confirm: "

    read answer
    echo

    if [ "$answer" != "${CLUSTER_NAME}" ]; then
        echo "Wrong cluster name. Aborting!!!"
        exit 1
    fi

    echo
    echo "WARNING: Proceeding with the cluster removal..."
    echo

    # Before deleting the bastion host, check if BASTION_INSTALL_TYPE == redhat, and: 
    # subscription-manager remove --all
    # subscription-manager unregister

    if [ "$BASTION_TYPE" == "redhat" ]; then
        echo "Start the Red Hat bastion vm to unregister..."
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
                sleep 3
            fi
        done
        echo

        echo "Removing subscriptions and unregistering from Red Hat Customer Portal..."
        ssh -q \
                -o BatchMode=yes \
                -o ConnectTimeout=10 \
                -o UserKnownHostsFile=/dev/null \
                -o StrictHostKeyChecking=no \
                -i ssh/id_rsa root@${LIBVIRT_NETWORK_PREFIX}.3 \
                "subscription-manager remove --all ; subscription-manager unregister"
    fi


    # Stop cluster
    . script/stop.sh
    cluster_stop


    echo "Deleting nodes..."
    for node in bastion bootstrap master1 master2 master3; do
        sudo virsh undefine --domain ${CLUSTER_NAME}-$node --remove-all-storage
    done
    for i in $(seq 1 ${NUMBER_WORKERS}); do
        sudo virsh undefine --domain ${CLUSTER_NAME}-worker${i} --remove-all-storage
    done

    echo "Deleting cluster storage pool..."
    sudo virsh pool-destroy --pool ${CLUSTER_NAME}
    sudo virsh pool-undefine --pool ${CLUSTER_NAME}

    echo "Deleting cluster network..."
    sudo virsh net-destroy --network ${CLUSTER_NAME}
    sudo virsh net-undefine --network ${CLUSTER_NAME}

    echo "Removing related files..."
    rm -rf ssh/ ./.re-run-with-network
    sudo rmdir ${LIBVIRT_STORAGE_POOL_BASE}/${CLUSTER_NAME}

    echo
    echo "Cluster removed!!!"
}

