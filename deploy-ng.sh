# ===========================================================================================
# == Usage (Hypervisor network config)
# ./deploy.sh \
#   --network
#   --host-nic <Host NIC of the hypervisor> \
#   --host-ip <Host IP of the hypervisor - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-gw <Gateway of the hypervisor - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-dns <DNS server of the hypervisor - only required if '--host_nic' and '--libvirt_nic are the same'> \
#   --host-vlan <Host VLAN (tagged) on Host NIC - optional>
#   --libvirt-nic <NIC for libvirt use> \
#   --libvirt-bridge <Bridge for libvirt use (do not use 'virbr0')> \
#   --libvirt-vlan <libvirt VLAN (tagged) on Host NIC - optional>
# ===========================================================================================
# == Usage (CVP VM)
# ./deploy.sh \
#   --vm
#   --centos <'download' or local file> \
#   --cloudvision <'download' or local file> \
#   --apikey <API key from arista.com - only required if '--cloudvision download'> \
#   --version <CloudVision - only required if '--cloudvision download'> \
# ===========================================================================================
# == Supported host operating systems
# * CentOS/RHEL 8.3
# ===========================================================================================
# == Florian Hibler <florian@arista.com>
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
# == Path variables
# ===========================================================================================
LIBVIRT_BOOT=/var/lib/libvirt/boot
LIBVIRT_IMAGES=/var/lib/libvirt/images

function distro_check {
    if [ -f "/etc/redhat-release" ]; then
        DISTRO=$(gawk 'match($0, /.*^ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        VERSION=$(gawk 'match($0, /.*^VERSION_ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        if [ "$DISTRO" = "centos" ]; then
            if [ "$VERSION" = "8" ]; then
                echo "[DEPLOYER] Detected $DISTRO $VERSION"
                DETECTED_DISTRO=rhel8
                if [ -f "/usr/bin/nmcli" ]; then
                    DETECTED_METHOD=nmcli
                else
                    echo "[DEPLOYER] Unsupported network configuration method for  $DISTRO $VERSION)" 
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

function deps_rhel8 {
    dnf install -y libvirt virt-install
    systemctl enable libvirtd
    systemctl start libvirtd
}

function deps_rhel8_cloudvision_download {
    dnf install -y python3
    python3 -m pip install --upgrade pip
    python3 -m pip install scp paramiko tqdm requests
}

# ===========================================================================================
# == Network configuration 
# ===========================================================================================

function network_rhel8_network_nmcli {
    if [ $(nmcli -t con show | grep $LIBVIRT_BRIDGE | wc -l) -ge 1 ]; then
        nmcli con delete $LIBVIRT_BRIDGE
    fi
    if [ "${HOST_NIC}" != "${LIBVIRT_NIC}" ]; then
        for interface in $(nmcli -t -f NAME,UUID,DEVICE con show | grep $LIBVIRT_NIC | cut -d ":" -f 2 ); do
            nmcli con delete $interface
        done
    fi
    for interface in $(nmcli -t -f UUID con show); do
        for bridge in $(nmcli -t -f connection.master con show $interface | cut -d ":" -f 2 ); do
            if [ "${bridge}" == "${LIBVIRT_BRIDGE}" ]; then
                if [ "${interface}" == "${HOST_NIC}" ]; then
                    nmcli con modify $interface -connection.master "" -connection.slave-type ""
                else
                    nmcli con delete $interface
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
    if [ -f "/tmp/cvp/centos/centos.iso" ]; then
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
    if [ -f "${CLOUDVISION}" ]; then
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
# == Running the script
# ===========================================================================================

distro_check

if [ "${NETWORK}" == 1 ] && [ "${VM}" == 1 ]; then
    echo "[DEPLOYER] Error: Network configuration and VM setup cannot be conducted at the same time."
    exit 1
elif [ -n "${NETWORK}" ]; then
    if [ -n "${HOST_NIC}" ] && [ -n "${LIBVIRT_NIC}" ] && [ -n "${LIBVIRT_BRIDGE}" ]; then
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
    else
        echo "[DEPLOYER] Error: Required parameter '--centos' or '--cloudvision' is missing" >&2
        exit 1
    fi
else
        echo "[DEPLOYER] Error: Neither network configuration nor VM configuration mode specified."
        exit 1
fi