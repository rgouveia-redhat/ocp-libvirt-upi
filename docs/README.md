
# ocp-libvirt-upi

> **In a nutshell, this set of tools automates as much as possible the deployment of OpenShift on Libvirt/KVM using UPI on Bare Metal.**

This project, as many open source projects, started as an itch that I had to scratch.

Due to my $dayjob, I frequently need to quickly access a cluster with a specific version to test something. I have a local Fedora box which serves as my gaming machine, and I don't want to re-install it with another platform, like oVirt/Red Hat Virtualization. In addition, my gaming box does not support nested virtualization, so these options are not possible for me at the moment.

Although, using Libvirt, which is an unsupported platform, an important requirement for me is that the installation is as close as possible to a supported OpenShift installation.

Looking at the available options from the official [openshift-install Github page](https://github.com/openshift/installer) my analysis is as follows:

## Supported Installer-provisioned infrastructure (IPI)

| Provider | Comment |
| --- | --- |
| Clouds: AWS, Azure, GCP | Cost |
| Metal, OpenStack, Power, RHV/oVirt, vSphere, z/VM | Hardware requirements not available |
| Libvirt with KVM | Development only |

With the IPI method, the openshift-install binary connects to the configured provider, and creates the required infrastructure for the installation. The Libvirt option looks really nice, however, I had bad experiences trying to install older versions, and it's, obviously, not supported.

## Supported User-provisioned infrastructure (UPI)

| Provider | Comment |
| --- | --- |
| Clouds: AWS, GCP | Cost |
| OpenStack, RHV/oVirt, vSphere | Hardware requirements not available |
| Metal | Maybe |

With the UPI method, the user is responsible for creating the required infrastructure: hosts, dns, dhcp, etc.

This is doable with Libvirt, but it's a lot of manual work, and it takes a lot of time. So, I created this set of tools to assist with the process.

## What does it do so far?

This first release will prepare the infrastructure for a disconnected installation of OpenShift 4, with your chosen version.

> Disclaimer: Tested only with some 4.9.x versions.

## What is automated?

- The creation in Libvirt of:
  - the storage pool in Libvirt
  - the network for the cluster
  - the virtual machines for all roles:
    - bastion, bootstrap, masters, and workers.
- The configuration in the bastion host of:
  - NTP Server
  - DNS Server
  - DHCP Server
  - PXE Server
  - HTTP Server
  - HA Proxy
- The preparation in the bastion for the installation:
  - Red Hat Core OS PXE boot files
  - OpenShift clients: openshift-install, oc, opm
  - Secure registry mirror
  - Populate the registry mirror
  - Assemble the install-config.yaml
  - Add the ignition files to the HTTP Server

## Requirements

- A Red Hat based system for the hypervisor.
  - Fedora Desktop 35 is tested, but should work with CentOS 8 and Red Hat 8.x variants.
- Libvirt installed and enabled.
- sudo privileges on the hypervisor.
- ISO file for the bastion installation.
  - Fedora Server 35, CentOS 8, and Red Hat 8.5 tested.
- pull secret for the cluster installation.

> Disclaimer: 100% of tests executed with SSD disks.

# How to use?

1. Get the code:

```
$ git clone https://github.com/rgouveia-redhat/ocp-libvirt-upi.git <folder_name>
```

2. Create a configuration file:

```
$ cp Settings-example Settings
```

3. Edit the "Settings" file with the desired options (more help on the file):

4. Execute:

```
$ ./phase1.sh
```

> Note: The script `phase1.sh` creates the infrastructure, and the script `phase2.sh` configures the bastion system. In case of an error, it is safe to rerun any of these two scripts. In case of a successful execution, `phase1.sh` will invoke `phase2.sh`.

> Don't try to run `phase2.sh` without a successful execution of `phase1.sh`.

> Don't try to install OpenShift without a successful execution of `phase2.sh`

## How to install the cluster?

After a successful execution of the script `phase2.sh`, the infrastructure is ready for the cluster installation.

With the UPI, the `openshift-install` binary only monitors the installation, so all you have to do is boot the virtual machines, and on their first boot select the option that matches the role of the system.

The hosts will boot via PXE, and you will see the menus:

![Bootstrap Screenshot](/docs/images/Screenshot_bootstrap.png)

![Bootstrap Screenshot](/docs/images/Screenshot_master.png)

![Bootstrap Screenshot](/docs/images/Screenshot_worker.png)

> You **must** start the installation process for the bootstrap and the `three master nodes`. Regarding the workers, successful deployments were achieved with only two workers.

> Important: the only important step now is to wait to approve certificates from the workers.

## What to do during the installation?

OpenShift has many moving parts, and it is normal to see a lot of warnings and errors. Be patient!

The bastion host was configured with all the necessary tools. This is what you can do:

In a bastion terminal, execute:

```
[root@bastion ~]# openshift-install --dir <cluster_name> wait-for bootstrap-complete                 
```

After this phase is completed, execute:

```
[root@bastion ~]# openshift-install --dir <cluster_name> wait-for install-complete
```

In another terminal, execute:

```
[root@bastion ~]# watch "oc get clusterversion ; oc get co ; oc get nodes ; oc get csr"
```

> Note: This command will provide a lot of information, warnings, and error. Most of them are normal. 

When the above command displays certificates in `Pending` state, then execute the following command to approve them all:

```
[root@bastion ~]# oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve
```

Hopefully, you now have an OpenShift cluster.

# FAQ

## Why didn't you used `tool x` instead?

This was mostly a learning experience for me. However, I did use the inspiration of many other tools to create this one.

## Why a disconnected installation by default? 

There are already many tools, and YouTube videos, that install and show how to install OpenShift in a connected way. The disconnected decision was due to the following:

1. I encounter a lot of deployments using the disconnected option, and I couldn't find a quick lab to run a reproducer.
2. Currently, I don't have a very fast internet, so each installation takes hours. A registry mirror is a way to reduce the installation time.
