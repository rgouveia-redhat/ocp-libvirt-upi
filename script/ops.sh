# -*-Shell-script-*-

show_help() {

    echo "help"
    
}

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