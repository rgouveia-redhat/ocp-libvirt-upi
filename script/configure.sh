# -*-Shell-script-*-

configure_bastion () {

    ### Start bastion and wait for ip address.
    if [ "$(sudo virsh domstate ${CLUSTER_NAME}-bastion)" != "running" ]; then
        sudo virsh start ${CLUSTER_NAME}-bastion
    fi

    ### Use Ansible to configure bastion vm.
    echo "$(date +%T) INFO: Waiting for SSH to be ready on bastion vm..."

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
            sleep 5
        fi
    done
    echo

    echo "$(date +%T) INFO: Installing Ansible dependencies..."
    if ! [ -d ~/.ansible/collections/ansible_collections/community/general/ ]; then
        ansible-galaxy collection install community.general
    fi
    if ! [ -d ~/.ansible/collections/ansible_collections/ansible/posix/ ]; then
        ansible-galaxy collection install ansible.posix
    fi

    # Go to Ansible folder.
    cd ansible

    echo "$(date +%T) INFO: Check to make sure Ansible can proceed."
    ansible \
        --private-key=../ssh/id_rsa \
        --ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
        -u root -i hosts all -m ping

    if [ $? -eq 0 ]; then
        echo "$(date +%T) INFO: Running Ansible Playbook to configure Systems..."

        ansible-playbook \
            --private-key=../ssh/id_rsa \
            --ssh-extra-args="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
            -u root -i hosts bastion.yaml

        if ! [ $? -eq 0 ]; then
            echo "$(date +%T) ERROR: Ansible exited with errors. Fix the errors and rerun!"
            exit 10
        fi
    else
        echo "$(date +%T) ERROR: Ansible test failed. Fix the issue and run this command again."
        exit 100
    fi

    # Back to script folder.
    cd ..
}
