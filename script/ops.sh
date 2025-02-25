# -*-Shell-script-*-

create_ssh_key () {

    ### Check/Create SSH Keys. OpenShift compatible.
    if [ -f ./ssh/id_rsa ]; then
        echo "$(date +%T) INFO: SSH keys already created."
    else
        echo "$(date +%T) INFO: Generating SSH Keys..."
        mkdir ./ssh
        ssh-keygen -t ed25519 -f ./ssh/id_rsa -N '' -C "kubeadmin@${CLUSTER_NAME}.${CLUSTER_DOMAIN}"
        chmod 400 ./ssh/id_rsa*
    fi
}

show_help() {

    echo "
Usage: $0 option

options:

    help       - Displays this help.

    create     - Creates a new cluster based on settings from the file 'Settings'.

    env        - Configures the host local DNS resolver and SSH into the bastion vm.
                 This is required to access the OpenShift Web Console via browser.

    start      - Start the cluster.

    stop       - Stop the cluster.

    destroy    - Destroys/Deletes the cluster. Removes ALL Libvirt used resources.
                 Use with care!!!
    
    "    
}

show_help_install () {

    echo "
- To define host variables to open the web console, execute:
  ./engage env

- To SSH in to the bastion host, execute one of:
  ssh -i ssh/id_rsa root@bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}

### In the bastion host: ###

- To start the installation, boot all the nodes and select the role assigned in the PXE menu.
  You must select the role option to load the ignition file. After that, by default, the 
  nodes boot from the local disk.

- To keep track of the installation, execute:
  openshift-install --dir ${CLUSTER_NAME} wait-for bootstrap-complete

  And after that:
  openshift-install --dir ${CLUSTER_NAME} wait-for install-complete

- To keep track of Pending certificates, execute:
  oc get csr -o name | xargs oc adm certificate approve
  oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{\"\\n\"}}{{end}}{{end}}' | xargs oc adm certificate approve

- To see the evolution of the installation, execute:
  watch \"oc get clusterversion ; oc get co ; oc get nodes ; oc get csr\"
    "

# TODO
#$ oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim": ""}}}}'
#$ oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
}
