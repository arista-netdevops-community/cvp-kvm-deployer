# ===========================================================================================
# Copyright (c) 2021 Arista Networks, Inc.
# Use of this source code is governed by the Apache License 2.0
# that can be found in the LICENSE file.
# ===========================================================================================
# Automated CloudVision on KVM Deployment
# == Florian Hibler <florian@arista.com>
# ===========================================================================================
# == Supported host operating systems
# * Red Hat Enterprise Linux/CentOS 7.9
# * Red Hat Enterprise Linux/CentOS 8.3
# ===========================================================================================
# == Usage (Hypervisor network config)
# ./deploy.sh \
#   --network
#   --host-nic <Host NIC> \
#   --host-ip <Host IP plus CIDR - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-gw <Host gateway - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-dns <Host DNS server - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-vlan <optional - Host VLAN (tagged) on Host NIC>
#   --libvirt-nic <NIC for libvirt use> \
#   --libvirt-bridge <optional - (default: 'cvpbr0') - Bridge for libvirt use (do not use 'virbr0')> \
#   --libvirt-vlan <optional - libvirt VLAN (tagged) on Host NIC>
# ===========================================================================================
# == Usage (CVP VM)
# ./deploy.sh \
#   --vm
#   --centos <'download' or local file> \
#   --cloudvision <'download' or local file> \
#   --version <CloudVision - only required if '--cloudvision download'> \
#   --apikey <API key from arista.com - only required if '--cloudvision download'> \
#   --libvirt-bridge <optional - (default: 'cvpbr0') - Bridge VM will be connected to> \
#   --cpu <Amount of vCPUs - minimum 8> \
#   --memory <Amount of memory in GB - minimum 16> \
#   --rootsize <Amount of root filesystem in GB - minimum 35> \
#   --datasize <Amount of data filesystem in GB - minimum 110> \
#   --vm-fqdn <CVP hostname plus full qualified domain name> \
#   --vm-ip <CVP IP + CIDR> \
#   --vm-gw <CVP gateway> \
#   --vm-dns <CVP DNS> \
#   --vm-ntp <CVP NTP>
# ===========================================================================================
# == Usage (CVP VM - Cleanup for reinstall)
# ./deploy.sh \
#   --vm-cleanup
# ===========================================================================================

# ===========================================================================================
# == Default settings
# ===========================================================================================
LIBVIRT_BRIDGE=cvpbr0
LIBVIRT_BOOT=/var/lib/libvirt/boot
LIBVIRT_IMAGES=/var/lib/libvirt/images
LIBVIRT_VMNAME=cvp

# ===========================================================================================
# == General functions 
# ===========================================================================================

function cidr_to_netmask {
    M=$(( 0xffffffff ^ ((1 << (32-$1)) -1) ))
    echo "$(( (M>>24) & 0xff )).$(( (M>>16) & 0xff )).$(( (M>>8) & 0xff )).$(( M & 0xff ))"
    unset M
}

# ===========================================================================================
# == Argument parser
# ===========================================================================================
PWD=$(pwd)
PARAMS=""
while (( "$#" )); do
    case "$1" in
        --network)
                NETWORK=1
                shift
                ;;
        --host-nic)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                HOST_NIC=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --host-ip)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                HOST_IP=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;; 
        --host-gw)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                HOST_GW=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;; 
        --host-dns)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                HOST_DNS=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --host-vlan)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                HOST_VLAN=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --libvirt-nic)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                LIBVIRT_NIC=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --libvirt-bridge)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                LIBVIRT_BRIDGE=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --libvirt-vlan)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                LIBVIRT_VLAN=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm)
                VM=1
                shift
                ;;
        --centos)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                CENTOS=$2
                shift 2
            else
                echo "Error: '$1' requires either the parameter 'download' or a local path to the CentOS image" >&2
                exit 1
            fi
            ;;
        --cloudvision)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                CLOUDVISION=$2
                shift 2
            else
                echo "Error: '$1' requires either the parameter 'download' or a local path to the CloudVision installer" >&2
                exit 1
            fi
            ;;
        --apikey)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                APIKEY=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --version)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                CLOUDVISION_VERSION=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
         --cpu)
            if [ -n "$2" ] && [ "${2}" -lt 8  ]; then
                echo "Error: Minimum of 8 VM CPUs required" >&2
                exit 1
            elif [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_CPU=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --memory)
            if [ -n "$2" ] && [ "${2}" -lt 16  ]; then
                echo "Error: Minimum of 16 GB memory required" >&2
                exit 1        
            elif [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_MEMORY=$(expr $2 \* 1024)
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --rootsize)
            if [ -n "$2" ] && [ "${2}" -lt 35  ]; then
                echo "Error: Minimum of 35 GB HDD for root filesystem required" >&2
                exit 1       
            elif [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_DISK_ROOT=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --datasize)
            if [ -n "$2" ] && [ "${2}" -lt 110  ]; then
                echo "Error: Minimum of 110 GB HDD for root filesystem required" >&2
                exit 1       
            elif [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_DISK_DATA=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-fqdn)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_FQDN=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-ip)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_IP=$(echo $2 | cut -f1 -d'/')
                VM_CIDR=$(echo $2 | cut -f2 -d'/')
                if [ ${#VM_CIDR} != "2" ]; then
                    echo "Error: No CIDR for $1 is specified." >&2
                    exit 1
                fi
                VM_NETMASK=$(cidr_to_netmask ${VM_CIDR})
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-gw)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_GW=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-dns)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_DNS=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-ntp)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                VM_NTP=$2
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --vm-cleanup)
                VM_CLEANUP=1
                shift
                ;;        
        --assume-yes)
                ASSUME_YES=1
                shift
                ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
        ;;
        *) # preserve positional arguments
            PARAMS="$PARAMS $1"
            shift
        ;;
    esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

# ===========================================================================================
# == Host OS related functions 
# ===========================================================================================

function distro_check {
    if [ -f "/etc/redhat-release" ]; then
        DISTRO=$(gawk 'match($0, /.*^ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        VERSION=$(gawk 'match($0, /.*^VERSION_ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        if [ "${DISTRO}" = "centos" ]; then
            if [ "${VERSION}" = "7" ]; then
                echo "[DEPLOYER] Detected $DISTRO $VERSION"
                DETECTED_DISTRO=rhel79
                 if [ -n "${NETWORK}" ]; then
                    if [ -f "/usr/bin/nmcli" ]; then
                        DETECTED_METHOD=nmcli
                    else
                        echo "[DEPLOYER] Unsupported network configuration method for $DISTRO $VERSION)"
                        exit 1 
                    fi
                fi
            elif [ "${VERSION}" = "8" ] | [ "${VERSION}" = "8.3" ]; then
                echo "[DEPLOYER] Detected $DISTRO $VERSION"
                DETECTED_DISTRO=rhel83
                 if [ -n "${NETWORK}" ]; then
                    if [ -f "/usr/bin/nmcli" ]; then
                        DETECTED_METHOD=nmcli
                    else
                        echo "[DEPLOYER] Unsupported network configuration method for $DISTRO $VERSION)"
                        exit 1 
                    fi
                fi
            else
                echo "[DEPLOYER] Unsupported distro version (Detected $DISTRO $VERSION)"
                exit 1
            fi
        elif [ "${DISTRO}" = "rhel" ]; then
            if [ "${VERSION}" = "7.9" ]; then
                echo "[DEPLOYER] Detected $DISTRO $VERSION"
                DETECTED_DISTRO=rhel79
                 if [ -n "${NETWORK}" ]; then
                    if [ -f "/usr/bin/nmcli" ]; then
                        DETECTED_METHOD=nmcli
                    else
                        echo "[DEPLOYER] Unsupported network configuration method for $DISTRO $VERSION)"
                        exit 1 
                    fi
                fi
            elif [ "${VERSION}" = "8.3" ]; then
                echo "[DEPLOYER] Detected $DISTRO $VERSION"
                DETECTED_DISTRO=rhel83
                 if [ -n "${NETWORK}" ]; then
                    if [ -f "/usr/bin/nmcli" ]; then
                        DETECTED_METHOD=nmcli
                    else
                        echo "[DEPLOYER] Unsupported network configuration method for $DISTRO $VERSION)"
                        exit 1 
                    fi
                fi    
            else
                echo "[DEPLOYER] Unsupported distro version (Detected $DISTRO $VERSION)"
                exit 1
            fi        
        else
            echo "[DEPLOYER] Unsupported distro (Detected $DISTRO)"
            exit 1
        fi
    fi    
}

function init {
    deps_$DETECTED_DISTRO
    if [ "$CLOUDVISION" = "download" ]; then
        'deps_'$DETECTED_DISTRO'_cloudvision_download'
    fi
    mkdir -p /tmp/cvp/centos
    mkdir -p /tmp/cvp/cloudvision
}

function deps_rhel79 {
    yum install -y libvirt virt-install libvirt-daemon-kvm rsync
    systemctl enable libvirtd
    systemctl start libvirtd
}

function deps_rhel83 {
    dnf install -y libvirt virt-install libvirt-daemon-kvm rsync
    systemctl enable libvirtd
    systemctl start libvirtd
}

function deps_rhel79_cloudvision_download {
    yum install -y python3
    python3 -m pip install --upgrade pip
    python3 -m pip install scp paramiko tqdm requests
}

function deps_rhel83_cloudvision_download {
    dnf install -y python3
    python3 -m pip install --upgrade pip
    python3 -m pip install scp paramiko tqdm requests
}

# ===========================================================================================
# == Network configuration 
# ===========================================================================================

function network_rhel79_network_nmcli {
    if [ $(nmcli -t con show | grep $LIBVIRT_BRIDGE | wc -l) -ge 1 ]; then
        nmcli con delete $LIBVIRT_BRIDGE
    fi
    if [ "${HOST_NIC}" != "${LIBVIRT_NIC}" ]; then
        for UUID in $(nmcli -t -f NAME,UUID,DEVICE con show | grep $LIBVIRT_NIC | cut -d ":" -f 2 ); do
            nmcli con delete $UUID
        done
    fi
    for CONNECTIONS in $(nmcli -t -f UUID,DEVICE con show); do
        UUID=$(echo $CONNECTIONS | cut -d ":" -f 1)
        INTERFACE=$(echo $CONNECTIONS | cut -d ":" -f 2)
        for BRIDGE in $(nmcli -t -f connection.master con show $UUID | cut -d ":" -f 2 ); do
            if [ "${BRIDGE}" == "${LIBVIRT_BRIDGE}" ]; then
                if [ "${INTERFACE}" == "${HOST_NIC}" ]; then
                    nmcli con modify $UUID -connection.master "" -connection.slave-type ""
                else
                    nmcli con delete $UUID
                fi
            fi
        done
    done

    echo "[DEPLOYER] Create libvirt bridge $LIBVIRT_BRIDGE"
    nmcli con add ifname $LIBVIRT_BRIDGE type bridge con-name $LIBVIRT_BRIDGE
    nmcli con modify $LIBVIRT_BRIDGE bridge.stp no
    nmcli con modify $LIBVIRT_BRIDGE connection.autoconnect yes

    if [ "${HOST_NIC}" == "${LIBVIRT_NIC}" ]; then
        echo "[DEPLOYER] Applying hypervisor IPv4 configuration to $LIBVIRT_BRIDGE"
        nmcli con modify $LIBVIRT_BRIDGE ipv4.addresses $HOST_IP
        nmcli con modify $LIBVIRT_BRIDGE ipv4.gateway $HOST_GW
        nmcli con modify $LIBVIRT_BRIDGE ipv4.dns $HOST_DNS
        nmcli con modify $LIBVIRT_BRIDGE ipv4.method manual
        nmcli con modify $LIBVIRT_BRIDGE ipv6.method ignore
        if [ -n "${HOST_VLAN}" ] && [ "${HOST_VLAN}" == "${LIBVIRT_VLAN}" ]; then
            echo "[DEPLOYER] Adding host VLAN $HOST_VLAN to $LIBVIRT_BRIDGE"
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-filtering yes
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-default-pvid $HOST_VLAN
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlans $HOST_VLAN            
            nmcli con add type vlan con-name $HOST_NIC.$HOST_VLAN dev $HOST_NIC id $HOST_VLAN master $LIBVIRT_BRIDGE
            nmcli con mod ens32 -ipv4.addresses "" -ipv4.gateway "" -ipv4.dns "" ipv4.method disabled
        else
            echo "[DEPLOYER] Adding host NIC $HOST_NIC to $LIBVIRT_BRIDGE"
            nmcli con mod $HOST_NIC connection.master $LIBVIRT_BRIDGE connection.slave-type bridge
        fi
    else
        nmcli con modify $LIBVIRT_BRIDGE ipv4.method disabled
        nmcli con modify $LIBVIRT_BRIDGE ipv6.method ignore
        if [ -n "${LIBVIRT_VLAN}" ]; then
            echo "[DEPLOYER] Adding libvirt VLAN $LIBVIRT_VLAN to $LIBVIRT_BRIDGE"       
            nmcli con add type vlan con-name $LIBVIRT_NIC.$LIBVIRT_VLAN dev $LIBVIRT_NIC id $LIBVIRT_VLAN master $LIBVIRT_BRIDGE
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-filtering yes
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-default-pvid $LIBVIRT_VLAN
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlans $LIBVIRT_VLAN  
        else
            echo "[DEPLOYER] Adding libvirt NIC $LIBVIRT_NIC to $LIBVIRT_BRIDGE"
            if [ $(nmcli -t con show | grep $LIBVIRT_NIC | wc -l) == 0 ]; then
                nmcli con add ifname $LIBVIRT_NIC type ethernet con-name $LIBVIRT_NIC
                nmcli con modify $LIBVIRT_NIC ipv4.method disabled
                nmcli con modify $LIBVIRT_NIC ipv6.method ignore
            fi
            nmcli con modify $LIBVIRT_NIC connection.master $LIBVIRT_BRIDGE connection.slave-type bridge
        fi
    fi
    nmcli con up $LIBVIRT_BRIDGE
    if [ -f "${LIBVIRT_VLAN}" ]; then
        nmcli con up $LIBVIRT_NIC.$LIBVIRT_VLAN
    fi
    if [ -f "${HOST_VLAN}" ]; then
        nmcli con up $HOST_NIC.$HOST_VLAN
    fi
    if [ "${HOST_NIC}" == "${LIBVIRT_NIC}" ]; then
        nmcli con up $HOST_NIC
    else
        nmcli con up $HOST_NIC
        if [ -f "${LIBVIRT_VLAN}" ]; then     
            nmcli con up $LIBVIRT_NIC
        fi
    fi
}

function network_rhel83_network_nmcli {
    if [ $(nmcli -t con show | grep $LIBVIRT_BRIDGE | wc -l) -ge 1 ]; then
        nmcli con delete $LIBVIRT_BRIDGE
    fi
    if [ "${HOST_NIC}" != "${LIBVIRT_NIC}" ]; then
        for UUID in $(nmcli -t -f NAME,UUID,DEVICE con show | grep $LIBVIRT_NIC | cut -d ":" -f 2 ); do
            nmcli con delete $UUID
        done
    fi
    for CONNECTIONS in $(nmcli -t -f UUID,DEVICE con show); do
        UUID=$(echo $CONNECTIONS | cut -d ":" -f 1)
        INTERFACE=$(echo $CONNECTIONS | cut -d ":" -f 2)
        for BRIDGE in $(nmcli -t -f connection.master con show $UUID | cut -d ":" -f 2 ); do
            if [ "${BRIDGE}" == "${LIBVIRT_BRIDGE}" ]; then
                if [ "${INTERFACE}" == "${HOST_NIC}" ]; then
                    nmcli con modify $UUID -connection.master "" -connection.slave-type ""
                else
                    nmcli con delete $UUID
                fi
            fi
        done
    done

    echo "[DEPLOYER] Create libvirt bridge $LIBVIRT_BRIDGE"
    nmcli con add ifname $LIBVIRT_BRIDGE type bridge con-name $LIBVIRT_BRIDGE
    nmcli con modify $LIBVIRT_BRIDGE bridge.stp no
    nmcli con modify $LIBVIRT_BRIDGE connection.autoconnect yes

    if [ "${HOST_NIC}" == "${LIBVIRT_NIC}" ]; then
        echo "[DEPLOYER] Applying hypervisor IPv4 configuration to $LIBVIRT_BRIDGE"
        nmcli con modify $LIBVIRT_BRIDGE ipv4.addresses $HOST_IP
        nmcli con modify $LIBVIRT_BRIDGE ipv4.gateway $HOST_GW
        nmcli con modify $LIBVIRT_BRIDGE ipv4.dns $HOST_DNS
        nmcli con modify $LIBVIRT_BRIDGE ipv4.method manual
        nmcli con modify $LIBVIRT_BRIDGE ipv6.method disabled
        if [ -n "${HOST_VLAN}" ] && [ "${HOST_VLAN}" == "${LIBVIRT_VLAN}" ]; then
            echo "[DEPLOYER] Adding host VLAN $HOST_VLAN to $LIBVIRT_BRIDGE"
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-filtering yes
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-default-pvid $HOST_VLAN
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlans $HOST_VLAN            
            nmcli con add type vlan con-name $HOST_NIC.$HOST_VLAN dev $HOST_NIC id $HOST_VLAN master $LIBVIRT_BRIDGE
            nmcli con mod ens32 -ipv4.addresses "" -ipv4.gateway "" -ipv4.dns "" ipv4.method disabled
        else
            echo "[DEPLOYER] Adding host NIC $HOST_NIC to $LIBVIRT_BRIDGE"
            nmcli con mod $HOST_NIC connection.master $LIBVIRT_BRIDGE connection.slave-type bridge
        fi
    else
        nmcli con modify $LIBVIRT_BRIDGE ipv4.method disabled
        nmcli con modify $LIBVIRT_BRIDGE ipv6.method disabled
        if [ -n "${LIBVIRT_VLAN}" ]; then
            echo "[DEPLOYER] Adding libvirt VLAN $LIBVIRT_VLAN to $LIBVIRT_BRIDGE"       
            nmcli con add type vlan con-name $LIBVIRT_NIC.$LIBVIRT_VLAN dev $LIBVIRT_NIC id $LIBVIRT_VLAN master $LIBVIRT_BRIDGE
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-filtering yes
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlan-default-pvid $LIBVIRT_VLAN
            nmcli con mod $LIBVIRT_BRIDGE bridge.vlans $LIBVIRT_VLAN  
        else
            echo "[DEPLOYER] Adding libvirt NIC $LIBVIRT_NIC to $LIBVIRT_BRIDGE"
            if [ $(nmcli -t con show | grep $LIBVIRT_NIC | wc -l) == 0 ]; then
                nmcli con add ifname $LIBVIRT_NIC type ethernet con-name $LIBVIRT_NIC
                nmcli con modify $LIBVIRT_NIC ipv4.method disabled
                nmcli con modify $LIBVIRT_NIC ipv6.method disabled
            fi
            nmcli con modify $LIBVIRT_NIC connection.master $LIBVIRT_BRIDGE connection.slave-type bridge
        fi
    fi
    nmcli con up $LIBVIRT_BRIDGE
    if [ -f "${LIBVIRT_VLAN}" ]; then
        nmcli con up $LIBVIRT_NIC.$LIBVIRT_VLAN
    fi
    if [ -f "${HOST_VLAN}" ]; then
        nmcli con up $HOST_NIC.$HOST_VLAN
    fi
    if [ "${HOST_NIC}" == "${LIBVIRT_NIC}" ]; then
        nmcli con up $HOST_NIC
    else
        nmcli con up $HOST_NIC
        if [ -f "${LIBVIRT_VLAN}" ]; then     
            nmcli con up $LIBVIRT_NIC
        fi
    fi
}

# ===========================================================================================
# == CentOS Image variables
# ===========================================================================================
function centos_download {
    CENTOS_URL=http://mirror.nsc.liu.se/centos-store/7.7.1908/isos/x86_64/CentOS-7-x86_64-Minimal-1908.iso
    CENTOS=/tmp/cvp/centos/centos.iso
    CENTOS_DOWNLOAD=1
    mkdir -p /tmp/cvp/centos
    if [ -f "/tmp/cvp/centos/centos.iso" ] && [ -z "${ASSUME_YES}" ]; then
        while true; do
            read -p "[DEPLOYER] CentOS image already found. Do you want to re-download? (yes/no) " yn
            case $yn in
                [Yy]* )
                    rm -Rf /tmp/cvp/centos/centos.iso
                    break
                    ;;
                [Nn]* )
                    CENTOS_DOWNLOAD=0
                    break
                    ;;
                * ) 
                    echo "Please answer yes or no."
                    ;;
            esac
        done
        unset yn
    fi
    if [ "${CENTOS_DOWNLOAD}" == '1' ]; then
        echo "[DEPLOYER] Downloading CentOS image from $CENTOS_URL to $CENTOS"
        curl $CENTOS_URL --output $CENTOS
    fi
}

function centos_copy {
    echo "[DEPLOYER] Copying CentOS image from $CENTOS to $LIBVIRT_BOOT/centos.iso"
    if [ -f "/usr/bin/rsync" ]; then
        rsync -av --info=progress2 $CENTOS $LIBVIRT_BOOT/centos.iso
    else
        cp $CENTOS $LIBVIRT_BOOT/centos.iso
    fi
}

function centos_check {
    echo "[DEPLOYER] Checking $CENTOS"
    if [ ! -f "${CENTOS}" ]; then
        echo "Error: Something went wrong. $CENTOS is not available." >&2
        exit 1
    fi
}

# ===========================================================================================
# == CloudVision related functions
# ===========================================================================================
function cloudvision_download {
    CLOUDVISION=/tmp/cvp/cloudvision/cvp-rpm-installer-$CLOUDVISION_VERSION
    CLOUDVISION_DOWNLOAD=1
    if [ -f "${CLOUDVISION}" ] && [ -n "${ASSUME_YES}" ]; then
        rm -Rf /tmp/cvp/cloudvision/cvp-rpm-installer-$CLOUDVISION_VERSION
    elif [ -f "${CLOUDVISION}" ]; then
        while true; do
            read -p "[DEPLOYER] CloudVision Installer already found. Do you want to re-download? (yes/no) " yn
            case $yn in
                [Yy]* )
                    rm -Rf /tmp/cvp/cloudvision/cvp-rpm-installer-$CLOUDVISION_VERSION
                    break
                    ;;
                [Nn]* )
                    CLOUDVISION_DOWNLOAD=0
                    break
                    ;;
                * ) 
                    echo "Please answer yes or no."
                    ;;
            esac
        done
        unset yn
    fi
    if [ "${CLOUDVISION_DOWNLOAD}" == '1' ]; then   
        echo "[DEPLOYER] Downloading Arista CloudVision $CLOUDVISION_VERSION to /tmp/cvp/cloudvision/cvp-rpm-installer-$CLOUDVISION_VERSION" 
        mkdir -p /tmp/cvp/cloudvision  
        curl https://raw.githubusercontent.com/arista-netdevops-community/eos-scripts/main/eos_download.py --output /tmp/cvp/cloudvision/eos_download.py
        cd /tmp/cvp/cloudvision/
        python3 ./eos_download.py --api $APIKEY --ver cvp-$CLOUDVISION_VERSION --img rpm
        cd $PWD
    fi
}

function cloudvision_geniso {
    echo "[DEPLOYER] Generate Arista CloudVision image to $LIBVIRT_IMAGES/cvp.iso"
    if [ -f "/usr/bin/genisoimage" ]; then
        genisoimage -input-charset utf-8 -udf -allow-limited-size -l -J -r -iso-level 3 -o $LIBVIRT_IMAGES/cvp.iso $CLOUDVISION
    else
        echo "[DEPLOYER] Error: Something went wrong. 'genisoimage' is not available. Please install it to /usr/bin/genisoimage" >&2
        exit 1
    fi
}

function cloudvision_check {
    echo "[DEPLOYER] Checking $CLOUDVISION"
    if [ ! -f "${LIBVIRT_IMAGES}/cvp.iso" ]; then
        echo "[DEPLOYER] Error: Something went wrong. ${LIBVIRT_IMAGES}/cvp.iso is not available." >&2
        exit 1
    fi
}

# ===========================================================================================
# == VM related functions
# ===========================================================================================

function vm_generate_ks {
    touch /tmp/cvp/ks.cfg
    cat <<EOF > /tmp/cvp/ks.cfg
# =========================================================================================== > 
# == Kickstart file for CloudVision VM based on RPM installer and custom specs
# == Fully automated install
# == Florian Hibler <florian@arista.com>
# ===========================================================================================
# == Root password is 'cvpadmin'
# ===========================================================================================

# Language settings
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts=''
timezone Etc/UTC --isUtc --ntpservers=$VM_NTP

# Root password is 'cvpadmin'
rootpw --iscrypted \$6\$7z9CSB6nxDedcRMy\$WglVJ6UcIlGlIfxjRo/FlyubNA.rewsUKwwqqcjjThK.oahaDGqWRQXS2TARVhmZt95T3Nvig3zvTkiOMdrNr0
sshpw --username=root --iscrypted \$6\$7z9CSB6nxDedcRMy\$WglVJ6UcIlGlIfxjRo/FlyubNA.rewsUKwwqqcjjThK.oahaDGqWRQXS2TARVhmZt95T3Nvig3zvTkiOMdrNr0 

# Network settings
network --bootproto=static --device eth0 --ip=$VM_IP --netmask=$VM_NETMASK --gateway=$VM_GW --nameserver=$VM_DNS --noipv6 --activate
network  --hostname=$VM_FQDN

# Installer settings
reboot
cdrom
text

# Storage and boot configuration
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=vda
zerombr
clearpart --all --initlabel --drives=vda,vdb
part /boot --size=512 --ondisk=vda --asprimary --fstype=ext4 --label=boot --fsoptions=acl,user_xattr,errors=remount-ro,nodev,noexec,nosuid
part pv.00 --size=1 --grow --asprimary --ondisk=vda
part pv.01 --size=1 --grow --asprimary --ondisk=vdb
volgroup vg_root pv.00
volgroup vg_data pv.01
logvol / --fstype=ext4 --fsoptions=acl,user_xattr,errors=remount-ro --size=1 --grow --name=root --vgname=vg_root
logvol /data --fstype=ext4 --fsoptions=acl,user_xattr,errors=remount-ro --size=1 --grow --vgname=vg_data
firstboot --disable

# System settings
auth --enableshadow --passalgo=sha512
selinux --disabled
firewall --enabled --ssh
services --enabled="chronyd"
skipx

# Minimal installation
%packages
@core
chrony
kexec-tools
-alsa-firmware
-alsa-tools-firmware
-aic94xx-firmware
-iwl100-firmware
-iwl7265-firmware
-iwl7260-firmware
-iwl5150-firmware
-iwl105-firmware
-iwl135-firmware
-iwl4965-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-ivtv-firmware
-iwl6000-firmware
-iwl5000-firmware
-iwl3945-firmware
-iwl2030-firmware
-iwl2000-firmware
-iwl1000-firmware
-iwl3160-firmware
-iwl6000g2a-firmware
%end

# Disable kdump
%addon com_redhat_kdump --disable
%end

# Install CloudVision
%post --log=/tmp/ks-cvp-rpm-install.log
mkdir /tmp/cvprpm
mount /dev/sr1 /tmp/cvprpm
cd /tmp/cvprpm
bash ./cvp-rpm-installer* --type demo
cd / 
umount /tmp/cvprpm
%end

# Disable CentOS online repositories
%post --log=/tmp/ks-disable-repos.log
yum-config-manager --disable base,updates,extras
yum repolist
%end

# Enforce password policies
%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
EOF
}

function vm_install {
    virt-install \
        --virt-type=kvm \
        --name $LIBVIRT_VMNAME \
        --memory=$VM_MEMORY,maxmemory=$VM_MEMORY \
        --cpu host-passthrough \
        --vcpus=$VM_CPU --os-variant=rhel7.7 \
        --location=$LIBVIRT_BOOT/centos.iso \
        --network=bridge=$LIBVIRT_BRIDGE,model=virtio \
        --disk path=$LIBVIRT_IMAGES/$LIBVIRT_VMNAME.root.img,size=$VM_DISK_ROOT,bus=virtio,format=raw \
        --disk path=$LIBVIRT_IMAGES/$LIBVIRT_VMNAME.data.img,size=$VM_DISK_DATA,bus=virtio,format=raw \
        --disk path=$LIBVIRT_IMAGES/cvp.iso,device=cdrom,bus=sata,readonly=yes \
        --initrd-inject=/tmp/cvp/ks.cfg \
        --extra-args "console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH ks=file:/ks.cfg inst.sshd" \
        --graphics none \
        --autostart \
        --noreboot

    virt-xml $LIBVIRT_VMNAME --remove-device --disk 3
    virt-xml $LIBVIRT_VMNAME --remove-device --disk 3
    virsh define /etc/libvirt/qemu/$LIBVIRT_VMNAME.xml

    virsh start $LIBVIRT_VMNAME
}

function vm_cleanup {
    virsh destroy $LIBVIRT_VMNAME
    virsh undefine $LIBVIRT_VMNAME
    rm -Rf $LIBVIRT_IMAGES/$LIBVIRT_VMNAME.root.img $LIBVIRT_IMAGES/$LIBVIRT_VMNAME.data.img
}

function cleanup {
    rm -Rf /tmp/cvp
}

# ===========================================================================================
# == Running the script
# ===========================================================================================

distro_check

if [ -n "${VM_CLEANUP}" ]; then
    vm_cleanup
    exit 0
fi

if [ "${NETWORK}" == 1 ] && [ "${VM}" == 1 ]; then
    echo "[DEPLOYER] Error: Network configuration and VM setup cannot be conducted at the same time."
    exit 1
elif [ -n "${NETWORK}" ]; then
    if [ -n "${HOST_NIC}" ] && [ -n "${LIBVIRT_NIC}" ]; then
        if [ "${HOST_NIC}" == "${LIBVIRT_NIC}" ]; then
            if [ -n "${HOST_IP}" ] && [ -n "${HOST_GW}" ] && [ -n "${HOST_DNS}" ]; then
                'network_'$DETECTED_DISTRO'_network_'$DETECTED_METHOD
            else
                echo "[DEPLOYER] Error: Not all necessary parameters set for host network configuration."
                exit 1
            fi
        else
            echo "[DEPLOYER] Error: Not all necessary parameters set for host network configuration."
            exit 1
        fi
    else
        echo "[DEPLOYER] Error: Not all necessary parameters set for host network configuration."
        exit 1
    fi
elif [ -n "${VM}" ]; then
    if [ -n "${CENTOS}" ] && [ -n "${CLOUDVISION}" ]; then
        if [ -n "${VM_CPU}" ] && [ -n "${VM_MEMORY}" ] && [ -n "${VM_DISK_ROOT}" ] && [ -n "${VM_DISK_DATA}" ] && [ -n "${VM_FQDN}" ] && [ -n "${VM_IP}" ] && [ -n "${VM_NETMASK}" ] && [ -n "${VM_GW}" ] && [ -n "${VM_DNS}" ] && [ -n "${VM_NTP}" ]; then
            init
            if [ "${CENTOS}" == 'download' ]; then
                centos_download
            fi
            if [ -f "${CENTOS}" ]; then
                centos_copy
                centos_check
            else
                echo "[DEPLOYER] Error: '--centos' specified local file cannot be found" >&2
                exit 1
            fi
            if [ "${CLOUDVISION}" == 'download' ]; then
                if [ ! -n "${APIKEY}" ]; then
                    echo "[DEPLOYER] Error: '--apikey' for arista.com has to be specified in order to download CloudVision" >&2
                    exit 1
                fi
                if [ ! -n "${CLOUDVISION_VERSION}" ]; then
                    echo "[DEPLOYER] Error: '--version' has to be specified in order to download CloudVision" >&2
                    exit 1
                fi
                cloudvision_download
            fi
            if [ -f "${CLOUDVISION}" ]; then
                cloudvision_geniso
                cloudvision_check
            else
                echo "[DEPLOYER] Error: '--cloudvision' specified local file cannot be found" >&2
                exit 1
            fi
            vm_generate_ks
            vm_install
        else
            echo "[DEPLOYER] Error: VM specification parameters are missing." >&2
        fi
    else
        echo "[DEPLOYER] Error: Required parameter '--centos' or '--cloudvision' is missing" >&2
        exit 1
    fi
else
        echo "[DEPLOYER] Error: Neither network configuration nor VM configuration mode specified."
        exit 1
fi