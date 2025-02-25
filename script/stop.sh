# -*-Shell-script-*-

# Following 'stop cluster' best practices:
# https://docs.openshift.com/container-platform/4.9/backup_and_restore/graceful-cluster-shutdown.html

cluster_stop () {
    
    echo
    echo "##### Stopping Cluster ${CLUSTER_NAME} #####"
    echo

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
        sleep 3
    done
    echo

    echo
    echo "Stopping bastion..."

    sudo virsh shutdown --domain ${CLUSTER_NAME}-bastion
    echo -n "Waiting for bastion to shutdown..."
    while [ "$(sudo virsh list --name | grep ${CLUSTER_NAME}-bastion)" != "" ]; do
        echo -n "."
        sleep 3
    done
    echo

    echo
    echo "Cluster stopped!"
}
