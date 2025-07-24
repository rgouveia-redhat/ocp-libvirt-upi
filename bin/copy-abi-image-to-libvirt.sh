#!/bin/bash

# TODO: Check if file exists.
network_prefix=$(cat .re-run-with-network)

sudo scp -i ./ssh/id_rsa root@${network_prefix}.3:/root/install-dir/agent.x86_64.iso /var/lib/libvirt/images/
sudo chown qemu:qemu /var/lib/libvirt/images/agent.x86_64.iso
sudo restorecon -F /var/lib/libvirt/images/agent.x86_64.iso
sudo ls -lZ /var/lib/libvirt/images/

