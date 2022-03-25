
# ocp-libvirt-upi

> **In a nutshell, this project automates as much as possible the deployment of Red Hat OpenShift Container Platform using the method UPI for Bare Metal on top of Libvirt/KVM.**

Just to put the simplicity in perspective:

1. You set some desired settings in a file,
2. You execute a command, and 
3. Press Enter once per each node of the cluster to be installed.

**See how easy it is in 10 minutes:**

[![Watch the demo](https://i.ytimg.com/an_webp/FJrSF-eL0sY/mqdefault_6s.webp?du=3000&sqp=CIaA9JEG&rs=AOn4CLDi6K4Jdk6s1dzILZPigi7ikm_4Mw)](https://youtu.be/FJrSF-eL0sY)

# Prior-art

I am just going to say it! This is not an original idea! There are other implementations out there. Just here on GitHub I found the following projects that I liked:

| Project | Comments |
| --- | --- |
| [Automated OpenShift 4 Cluster Installation on KVM](https://github.com/kxr/ocp4_setup_upi_kvm) | Really cool project, made entirely in Bash. It has a command that accepts parameters, and fully automates the deployment from zero to 100%. |
| [Automate your cluster provisioning from 0 to OCP!](https://github.com/kubealex/libvirt-ocp4-provisioner) | Does the job, but has a lot of playbooks, and you have to touch a lot of configuration files. |
| [ocp4-upi-baremetal-lab](https://github.com/samuelvl/ocp4-upi-baremetal-lab) | "Deploy an OpenShift 4 cluster using UPI method (User Provisioned Infrastructure) in a disconnected scenario without a cloud provider to simulate a real baremetal environment. The cluster is deployed on top of libvirt/kvm using Terraform and every step of the installation and configuration is automated to be able to destroy and deploy a new cluster in less than 30 minutes." |

**But, if you want a tool that:**

- Allows you to install several versions in the same host without overlapping (depending on disk).
- Uses the same services that you would find in a production environment.
- Follows the same installation method a production environment would use (no hacks).
- Hides the complexity, and provides tools to make your life easier (create, stop, start, destroy cluster).
- Follows Red Hat best practices, and links the sources.

**Then, this project is for you.**

# Motivation

This project, as many open source projects, started as an itch that I had to scratch. IPI installations were not feasible, and UPI installation are just too much work.

Due to my $dayjob, I frequently need to quickly access a cluster with a specific version to test something for a customer. I have a local Fedora box which main purpose is to be my gaming machine, and I don't want to re-install it with another platform, like oVirt/Red Hat Virtualization. In addition, my gaming box does not support nested virtualization, so these options are not possible for me at the moment. However, I have a 2 TB SSD disk, 16 vCPU cores, and 64 GB of memory that I want to put to good use.

Although, using Libvirt, which is an unsupported platform, an important requirement for me is that the installation is as close as possible to a supported OpenShift installation done in real metal.

> Disclaimer: This tool is not endorsed nor supported by Red Hat, and it's also not created for production use.

Looking at the available options from the official [openshift-install GitHub page](https://github.com/openshift/installer) my analysis is as follows:

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

With the UPI method, the user is responsible for creating the required infrastructure: hosts, DNS, DHCP, etc. This is doable with Libvirt, but it's a lot of manual work, and it takes a lot of time for each single deployment. So, I created this project to assist me with the process.

## What does it do so far?

This first release will prepare the infrastructure (bastion vm) for an installation of OpenShift 4, with your chosen version. It deploys 3 masters and 3 workers. You can choose a disconnected installation, but the mirror still lacks the operators. It's planned.

**Note:** The single master cluster is a work in progress.

### Tested versions

- Some 4.9.x
- 4.10.3

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
  - HTTP Server (to host the PXE boot files and the ignition files)
  - HA Proxy (for all purposes: api.*, api-int.*, apps.*)
- The preparation in the bastion for the installation:
  - Red Hat Core OS PXE boot files
  - OpenShift clients: openshift-install, oc, opm
  - Secure registry mirror
  - Populate the mirror registry with the chosen OCP release
  - Assemble the install-config.yaml
  - Add the ignition files to the HTTP Server

## Requirements

- A Red Hat based system for the hypervisor.
  - Fedora Desktop 35 is tested, but should work with CentOS 8 and Red Hat 8.x variants.
- Libvirt installed and enabled.
- 'sudo' privileges on the hypervisor host for your convenience.
- ISO file for the bastion installation.
  - Tested with Fedora Server 34, CentOS 8, and Red Hat 8.5.
- Pull secret for the cluster installation.

> Disclaimer: 100% of tests executed with SSD disks.

# How to use?

1. Get the code:

```
$ git clone https://github.com/rgouveia-redhat/ocp-libvirt-upi.git <folder_name>
```

2. Create the configuration file, and Edit the "Settings" file with the desired options (more help on the file):

```
$ cp Settings-example Settings
$ vim Settings
```

3. Execute:

```
$ ./engage create
```

> Note: The script `engage` creates the infrastructure, and configures the bastion system. In case of an error, it is safe to fix the problem and rerun the script.

> Don't try to install OpenShift without a successful execution of `engage`.

## How to install the cluster?

After a successful execution of the script `engage`, the infrastructure is ready for the cluster installation.

With the UPI, the `openshift-install` binary only monitors the installation, so all you have to do is boot the virtual machines, and on their first boot select the option that matches the role of the system.

The hosts will boot via PXE, and you will see the menus:

![Bootstrap Screenshot](/docs/images/Screenshot_bootstrap.png)

![Bootstrap Screenshot](/docs/images/Screenshot_master.png)

![Bootstrap Screenshot](/docs/images/Screenshot_worker.png)

> You **must** start the installation process for the bootstrap and the `three master nodes`. Regarding the workers, successful deployments were achieved with only two workers.

> Important: the only critical step now is to wait to approve certificates from the workers.

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

In another terminal, you may execute to monitor the progress of the installation:

```
[root@bastion ~]# watch "oc get clusterversion ; oc get co ; oc get nodes ; oc get csr"
```

> Note: This command will provide a lot of information, warnings, and error. Most of them are normal. Again, be patient!

When the above command displays certificates in `Pending` state, then execute the following command to approve them all:

```
[root@bastion ~]# oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve
```

Hopefully, in a few minutes after that you will have a functional OpenShift cluster.

# FAQ

## Why didn't you use `tool x` instead ?

This was mostly a learning experience for me. However, I did use the inspiration of many other tools to create this one.

## Why a disconnected installation ? 

There are already many tools, and YouTube videos, that install and show how to install OpenShift in a connected way. The disconnected decision was due to the following:

1. I encounter a lot of deployments using the disconnected option, and I couldn't find a quick lab to run a reproducer.
2. Currently, I don't have a very fast internet, so each installation takes hours. A registry mirror is a way to reduce the installation time.
