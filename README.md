# Automated CloudVision on KVM Deployment

This deployment script targets the following use cases for CloudVision Portal:
- Baremetal installation
- VM specs outside of provided KVM image (especially HDD)

The installation is fully automated and parameterized. It can either use local available files or download them from the appropriate sources.

## Compatibility

### Host Operating System
| Distribution             | Version |
|--------------------------|---------|
| CentOS                   | 7.9     |
| CentOS                   | 8.3     |
| Red Hat Enterprise Linux | 7.9     |
| Red Hat Enterprise Linux | 8.3     |

### CloudVision Portal
| Product                  | Version  |
|--------------------------|----------|
| CloudVision Portal       | 2020.2.x |
| CloudVision Portal       | 2020.3.x |

## Parameters

### Credentials

| Username       | Password |
|----------------|----------|
| root           | cvpadmin |

<span style="color:red">**IMPORTANT**</span>

Please change root password after first boot!

### Network Configuration
| Option             | Parameter         | Example         | Required | Description                                                                                              |
|--------------------|-------------------|-----------------|----------|----------------------------------------------------------------------------------------------------------|
| `--network`        |                   |                 | Yes      | Enables network configuration mode                                                                       |        
| `--host-nic`       | Device name       | ens192          | Yes      | NIC of the hypervisor (management)                                                                       |
| `--host-ip`        | IPv4 address/CIDR | 192.168.0.10/24 | No       | IP of the hypervisor (management) <br> (only if `--host-nic` and `--libvirt-nic` are identical)          |
| `--host-gw`        | IPv4 address      | 192.168.0.1     | No       | Gateway of the hypervisor (management)<br> (only if `--host-nic` and `--libvirt-nic` are identical)      |
| `--host-dns`       | IPv4 address      | 192.168.0.1     | No       | Name server of the hypervisor (management) <br> (only if `--host-nic` and `--libvirt-nic` are identical) |
| `--host-vlan`      | VLAN ID           | 2000            | No       | Tagged VLAN for `--host-nic` <br>(default: untagged)                                                     |
| `--libvirt-nic`    | Device name       | ens192          | Yes      | NIC used to bridge CVP VM <br>(can be identical to `--host-nic`)                                         |
| `--libvirt-bridge` | Device name       | cvpbr0          | No       | Name of bridge for CVP VM <br> (default: `cvpbr0`)                                                       |
| `--libvirt-vlan`   | VLAN ID           | 1000            | No       | Tagged VLAN for `--host-nic` <br>(default: untagged)                                                     |

<span style="color:red">**IMPORTANT**</span>

The host NIC configuration will only be touched, if `--host-nic` and `--libvirt-nic` are identical! Otherwise only libvirt-related configuration will be taken into account.

**Example**

    ./deploy.sh 
        --network \
        --host-nic ens192 \
        --host-ip 192.168.0.10/24 \
        --host-gw 192.168.0.1 \
        --host-dns 1.1.1.1 \
        --libvirt-nic ens192

    ./deploy.sh 
        --network \
        --host-nic ens32 \
        --libvirt-nic ens160

    ./deploy.sh 
        --network \
        --host-nic ens32 \
        --host-ip 192.168.0.10/24 \
        --host-gw 192.168.0.1 \
        --host-dns 1.1.1.1 \
        --host-vlan 1000 \
        --libvirt-nic ens32 \
        --libvirt-vlan 1000

    ./deploy.sh 
        --network \
        --host-nic ens32 \
        --libvirt-nic ens160
        --libvirt-vlan 1000


### VM Configuration
| Option             | Parameter                | Example                         | Required | Description                                                                       |
|--------------------|--------------------------|---------------------------------|----------|-----------------------------------------------------------------------------------|
| `--vm`             |                          |                                 | Yes      | Enables VM configuration mode                                                     | 
| `--centos`         | `download` or local file | /tmp/CentOS.iso                 | Yes      | Downloads CentOS image or uses locally specified file                             | 
| `--cloudvision`    | `download` or local file | /tmp/cvp-rpm-installer-2020.3.0 | Yes      | Downloads CVP installer or uses locally specified file                            | 
| `--version`        |  CVP version             | 2020.3.0                        | No       | Specifies CVP version <br> (only if `--cloudvision download`)                     | 
| `--apikey`         |  API key from arista.com | xxxxxxxxxxxxxxxxxxxxxxxxx       | No       | API key for CVP download from arista.com  <br> (only if `--cloudvision download`) | 
| `--libvirt-bridge` |  Device name             | cvpbr0                          | No       | Name of bridge for CVP VM <br> (default: `cvpbr0`)                                | 
| `--cpu`            |  VM CPUs                 | 8                               | Yes      | Amount of CPUs in VM <br> (Minimum: 8)                                            | 
| `--memory`         |  VM memory in GB         | 32                              | Yes      | Amount of memory in VM <br> (Minimum: 16)                                         | 
| `--rootsize`       |  VM disk size in GB      | 50                              | Yes      | Disk size for root file system <br> (Minimum: 35)                                 | 
| `--datasize`       |  VM disk size in GB      | 700                             | Yes      | Disk size for data file system <br> (Minimum: 110)                                | 
| `--vm-fqdn`        |  Hostname + domain name  | cvp.test.local                  | Yes      | Hostname + domain name for CVP VM                                                 | 
| `--vm-ip`          |  IP address/CIDR         | 192.168.0.11/24                 | Yes      | IP address of CVP VM                                                              | 
| `--vm-gw`          |  IP address              | 192.168.0.1                     | Yes      | Gateway of CVP VM                                                                 | 
| `--vm-dns`         |  IP address              | 192.168.0.1                     | Yes      | Name server of CVP VM                                                             | 
| `--vm-ntp`         |  IP address/FQDN         | pool.ntp.org                    | Yes      | NTP server of CVP VM                                                              | 

**Example**

    ./deploy.sh 
        --vm \
        --centos download \
        --cloudvision download \
        --version 2020.3.0 \
        --apikey xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
        --cpu 14 \
        --memory 28 \
        --rootsize 35 \
        --datasize 110 \
        --vm-fqdn cvp.test.local \
        --vm-ip 192.168.0.11/24 \
        --vm-gw 192.168.0.1 \
        --vm-dns 192.168.0.11 \
        --vm-ntp pool.ntp.org

    ./deploy.sh 
        --vm \
        --centos /tmp/CentOS-7-x86_64-Minimal-1908.iso \
        --cloudvision download \
        --version 2020.3.0 \
        --apikey xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
        --cpu 8 \
        --memory 16 \
        --rootsize 50 \
        --datasize 110 \
        --vm-fqdn cvp.test.local \
        --vm-ip 192.168.0.11/24 \
        --vm-gw 192.168.0.1 \
        --vm-dns 192.168.0.11 \
        --vm-ntp pool.ntp.org

    ./deploy.sh 
        --vm \
        --centos /tmp/CentOS-7-x86_64-Minimal-1908.iso \
        --cloudvision /tmp/cvp-rpm-installer-2020.3.0 \
        --cpu 8 \
        --memory 16 \
        --rootsize 50 \
        --datasize 110 \
        --vm-fqdn cvp.test.local \
        --vm-ip 192.168.0.11/24 \
        --vm-gw 192.168.0.1 \
        --vm-dns 192.168.0.11 \
        --vm-ntp pool.ntp.org

| Option             | Parameter                | Example                         | Required | Description                                                                       |
|--------------------|--------------------------|---------------------------------|----------|-----------------------------------------------------------------------------------|
| `--vm-cleanup`     |                          |                                 | Yes      | Deletes disk files and removes VM                                                 | 

**Example**

    ./deploy.sh
        --vm-cleanup