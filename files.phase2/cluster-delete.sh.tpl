#!/bin/bash

echo
echo "##### Delete/Remove Cluster ${CLUSTER_NAME} #####"
echo

echo -n "

    WARNING:

    ALL resources will be deleted from your system!!!!

    Are you sure you want to proceed ?

    Write the cluster name if you are sure: "

read answer
echo

if [ "$answer" != "${CLUSTER_NAME}" ]; then
	echo "Wrong cluster name. Aborting!!!"
	exit 1
fi

echo
echo "WARNING: Proceeding with the cluster removal..."
echo

./cluster-stop.sh


echo "Deleting nodes..."

for node in bootstrap master1 master2 master3 worker1 worker2 worker3 bastion; do
    sudo virsh undefine --domain ${CLUSTER_NAME}-$node --remove-all-storage 
done

echo "Deleting cluster storage pool..."
sudo virsh pool-destroy --pool ${CLUSTER_NAME}
sudo virsh pool-undefine --pool ${CLUSTER_NAME}

echo "Deleting cluster network..."
sudo virsh net-destroy --network ${CLUSTER_NAME}
sudo virsh net-undefine --network ${CLUSTER_NAME}

echo "Removing related files..."
rm -rf ssh/ start-env.sh cluster-*.sh

echo
echo "Cluster removed!!!"
