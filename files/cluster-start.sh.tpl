#!/bin/bash
# https://docs.openshift.com/container-platform/4.9/backup_and_restore/graceful-cluster-restart.html

echo
echo "##### Starting Cluster ${CLUSTER_NAME} #####"
echo

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
		sleep 3
	fi
done
echo

echo
echo "Waiting for bastion services to be available..."
waiting_for="all"
while [ "$waiting_for" != "" ]; do
	waiting_for=''
	for service in named haproxy dhcpd podman-registry ; do
		status=$(ssh -i ssh/id_rsa root@${LIBVIRT_NETWORK_PREFIX}.3 "systemctl is-active ${service}.service")
		if [ "$status" != "active" ]; then
			waiting_for="$waiting_for $service"
		fi
	done
	if [ "$waiting_for" != "" ]; then
		echo "Waiting for: $waiting_for"
		sleep 2
	fi
done

echo 
echo "Starting nodes..."
for host in master1 master2 master3 worker1 worker2 worker3; do
  sudo virsh start --domain ${CLUSTER_NAME}-$host
done

echo
echo "All done. You may have to wait a few minutes before the READY status!"

