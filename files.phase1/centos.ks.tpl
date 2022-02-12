# Untested!!!

auth --enableshadow --passalgo=sha512
cdrom
text

rootpw --iscrypted $6$f/dv93KmK1kDGrrA$LMvsl5cdPTdhpqLPBUxzRnxfmHevZuav2kSOVjGWNKkRHwE0nxCeXCR3l/ohakXJxJ96775iDbUUh10b60qy60

timezone Europe/Lisbon --isUtc
firstboot --disable
keyboard --vckeymap=gb --xlayouts='gb'
lang en_GB.UTF-8

network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
network  --hostname=server.example.com

bootloader --location=mbr --boot-drive=vda

ignoredisk --only-use=vda
clearpart --all --initlabel --drives=vda

part /boot --fstype="xfs" --ondisk=vda --size=500
part pv.1 --fstype="lvmpv" --ondisk=vda --size=9500
volgroup server --pesize=4096 pv.1
logvol /home  --fstype="xfs" --size=1000 --name=home --vgname=server
logvol /  --fstype="xfs" --size=5000 --name=root --vgname=server
logvol swap  --fstype="swap" --size=1000 --name=swap --vgname=server

reboot

%packages
@^minimal
@core
chrony
-iwl*

%end

#
# Add custom post scripts after the base post.
#
%post

#---- Install our SSH key ----
mkdir -m0700 /root/.ssh/

cat <<EOF >/root/.ssh/authorized_keys
SSH_KEY_PLACEHOLDER
EOF

### set permissions
chmod 0600 /root/.ssh/authorized_keys

### fix up selinux context
restorecon -R /root/.ssh/

%end
