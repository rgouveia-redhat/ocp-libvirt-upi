#version=RHEL8
# Use graphical install
graphical


%packages
@^minimal-environment
@container-management
@guest-agents
@headless-management
@standard
kexec-tools

%end

# Keyboard layouts
keyboard --xlayouts='gb'
# System language
lang en_GB.UTF-8

# Network information
network  --bootproto=dhcp --device=enp1s0 --noipv6 --activate
network  --bootproto=static --device=enp2s0 --gateway=${LIBVIRT_NETWORK_PREFIX}.1 --ip=${LIBVIRT_NETWORK_PREFIX}.3 --nameserver=${LIBVIRT_NETWORK_PREFIX}.3,${LIBVIRT_NETWORK_PREFIX}.1 --netmask=255.255.255.0 --noipv6 --activate
network  --hostname=bastion.${CLUSTER_NAME}.${CLUSTER_DOMAIN}

# Run the Setup Agent on first boot
firstboot --enable

ignoredisk --only-use=vda
autopart
# Partition clearing information
clearpart --none --initlabel

reboot

# System timezone
timezone Europe/London --isUtc

# Root password
rootpw --iscrypted $6$duAHa0uyW/T9n75W$3yTl/YuBpzN7rRKG/WUH1pB8A0pYyvh07KcHUY2IRxiKPO8OGL9zJKgFshHUQYjeUYq2zEO20tu/iStus8Rw8/

%addon com_redhat_kdump --disable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

# Add custom post scripts after the base post.
%post

#---- Install our SSH key ----
mkdir -m0700 /root/.ssh/

cat <<EOF >/root/.ssh/authorized_keys
${SSH_KEY}
EOF

### set permissions
chmod 0600 /root/.ssh/authorized_keys

### fix up selinux context
restorecon -R /root/.ssh/

%end
