#!/bin/bash

# Configuring host resolvectl
sudo resolvectl domain ${INTERFACE} ${CLUSTER_NAME}.${CLUSTER_DOMAIN}
sudo resolvectl dns ${INTERFACE} ${LIBVIRT_NETWORK_PREFIX}.3

echo
echo "##### Current configuration #####"
echo

sudo resolvectl status ${INTERFACE}

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
