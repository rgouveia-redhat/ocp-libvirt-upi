# -*-Shell-script-*-

# Following 'stop cluster' best practices:
# https://docs.openshift.com/container-platform/4.9/backup_and_restore/graceful-cluster-shutdown.html

cluster_stop () {
    
    echo
    echo "##### Stopping Cluster ${CLUSTER_NAME} #####"
    echo

    # TODO: Test the readiness of the cluster API. If unavailable, fail fast.
    expire=$(ssh -i ssh/id_rsa -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN} "/root/bin/oc --kubeconfig /root/${CLUSTER_NAME}/auth/kubeconfig -n openshift-kube-apiserver-operator get secret kube-apiserver-to-kubelet-signer -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'")
    if ! [ $? -eq 0 ]; then
        echo "Error getting cluster certificates expiration date. Skipping..."
    fi
    echo "
        WARNING:

        Cluster certificates will expire by: $expire
        Restart your cluster before that date for automatic renewal."

    echo
    echo "Stopping nodes..."
    for node in master1 master2 master3 worker1 worker2 worker3; do
        sudo virsh shutdown --domain ${CLUSTER_NAME}-$node
    done

    echo -n "Waiting for nodes to shutdown..."
    while [ "$(sudo virsh list --name | grep ${CLUSTER_NAME}- | grep -v ${CLUSTER_NAME}-bastion)" != "" ]; do
        echo -n "."
        sleep 3
    done
    echo

    echo
    echo "Stopping dependencies..."

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
