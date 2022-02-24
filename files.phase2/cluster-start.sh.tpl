#!/bin/bash
# https://docs.openshift.com/container-platform/4.9/backup_and_restore/graceful-cluster-restart.html

CLUSTER_NAME='c4'
CLUSTER_DOMAIN='ocp.com'
LIBVIRT_NETWORK_PREFIX='192.168.99'

echo
echo "##### Starting Cluster ${CLUSTER_NAME} #####"
echo

echo "Starting dependencies..."

sudo virsh start --domain ${CLUSTER_NAME}-bastion

echo -n "Waiting for bastion to be available..."
isup=0
while ! [ $isup ]; do
    echo -n "."
    sleep 3

    nc -z ${LIBVIRT_NETWORK_PREFIX}.3 22 > /dev/null
    if [ $? -eq 0 ]; then
        isup=1
    fi   
done
echo

echo
echo "Waiting for bastion services to be available..."

ssh -i ssh/id_rsa root@${LIBVIRT_NETWORK_PREFIX}.3 "systemctl is-active named.service"



exit

echo 
echo "##### DNS check #####"
echo

output=''
for host in bastion api api-int openshift-console.apps bootstrap master1 master2 master3 worker1 worker2 worker3; do
    ip=$(dig +short ${host}.${CLUSTER_NAME}.${CLUSTER_DOMAIN})
    name="${host}.${CLUSTER_NAME}.${CLUSTER_DOMAIN}" 
    output="$output\n$name $ip"
done

echo -e $output | column -t