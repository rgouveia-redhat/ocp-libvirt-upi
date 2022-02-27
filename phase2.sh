#!/usr/bin/env bash

#
# Phase 1 - Prepare the infrastrucutre.
#

# Make sure this script does not kill your laptop.
/usr/bin/renice +19 -p $$ >/dev/null 2>&1
/usr/bin/ionice -c2 -n7 -p $$ >/dev/null 2>&1

### Validate settings.
source Settings

echo
echo "$(date +%T) INFO: Phase 2 - Preparing Bastion VM for the OpenShift Install."

# Go to Ansible folder.
cd ansible

echo "$(date +%T) INFO: Check to make sure Ansible can proceed."
ansible \
	--private-key=../ssh/id_rsa \
	--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
	-u root -i hosts all -m ping

if [ $? -eq 0 ]; then
	echo "$(date +%T) INFO: Running Ansible Playbook to configure Bastion..."

	ansible-playbook \
		--private-key=../ssh/id_rsa \
		--ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
		-u root -i hosts bastion-phase2.yaml
    if ! [ $? -eq 0 ]; then
        echo "$(date +%T) ERROR: Ansible exited with errors. Fix the errors and rerun ./phase2.sh !"
        exit 10
    fi
else
	echo "$(date +%T) ERROR: Ansible test failed. Fix the issue and run this command again."
	exit 100
fi

# Back to script folder.
cd ..


echo "Generating cluster scripts..."
for script in cluster-start cluster-stop cluster-delete; do
    sed \
        -e "s#\${CLUSTER_NAME}#$CLUSTER_NAME#g" \
        -e "s#\${CLUSTER_DOMAIN}#$CLUSTER_DOMAIN#g" \
        -e "s#\${LIBVIRT_NETWORK_PREFIX}#$LIBVIRT_NETWORK_PREFIX#g" \
        files.phase2/${script}.sh.tpl > ./${script}.sh
        chmod +x ./${script}.sh
    if ! [ $? -eq 0 ]; then
        echo "$(date +%T) ERROR: Error generating ${script}.sh script."
        exit 5
    fi
done


echo "

$(date +%T) INFO: Phase 2 (Pre-install steps) sucessfully created.


- To define host variables to open the web console, execute:

  ./start-env.sh

- To SSH in to the bastion host, execute:

  ssh -i ssh/id_rsa root@bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}


### In the bastion host: ###

- To keep track of the installation, execute:

    openshift-install --dir ${CLUSTER_NAME} --log-level debug wait-for bootstrap-complete

  And after that:

    openshift-install --dir ocp4/ wait-for install-complete

  Note: In metal UPI, the openshift-install only monitors the installation.


- To keep track of Pending certificates, execute:

    oc get csr -o name | xargs oc adm certificate approve

  or:

    oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve


- To see the evolution of the installation, execute:

    watch \"oc get clusterversion ; oc get co ; oc get nodes ; oc get csr\"


Note: To start the installation, simply boot all the nodes and select the role assigned in the PXE menu. After the first boot it's automated.

"
