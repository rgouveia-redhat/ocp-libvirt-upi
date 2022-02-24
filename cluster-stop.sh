#!/bin/bash
# Ref: https://docs.openshift.com/container-platform/4.9/backup_and_restore/graceful-cluster-shutdown.html

echo
echo "##### Stopping Cluster c4 #####"
echo

expire=$(ssh -i ssh/id_rsa root@bastion.c4.ocp.com "./bin/oc --kubeconfig ./c4/auth/kubeconfig -n openshift-kube-apiserver-operator get secret kube-apiserver-to-kubelet-signer -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'")

echo "WARNING: Cluster certificates will expire by: $expire"

echo "Stopping nodes..."

for node in master1 master2 master3 worker1 worker2 worker3; do
    sudo virsh shutdown --domain c4-$node
done

echo -n "Waiting for nodes to shutdown..."
while [ "$(sudo virsh list --name | grep c4- | grep -v c4-bastion)" != "" ]; do
    echo -n "."
done
echo

echo "Stopping dependencies..."

sudo virsh shutdown --domain c4-bastion

echo "Cluster stopped!"
