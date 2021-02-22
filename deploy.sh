#!/bin/bash
# ===========================================================================================
# == Deployment of CloudVision KVM VM
# == Specs can be customized below
# == RHEL/CentOS 8 has been used as a hypervisor
# ===========================================================================================
# == Florian Hibler <florian@arista.com>
# ===========================================================================================

PWD=$(pwd)
ARISTA_APIKEY=
CVP_VERSION=2020.3.0
VM_VCPU=8
VM_MEM=17408
VM_DISKSIZE_ROOT=35
VM_DISKSIZE_DATA=200
VM_NET=virbr0
VM_FQDN=cloudvision.test.aristanetworks.com
VM_IP=192.168.112.30
VM_NETMASK=255.255.255.0
VM_GW=192.168.112.1
VM_DNS=192.168.112.2
VM_NTP=192.168.178.1

PARAMS=""
while (( "$#" )); do
  case "$1" in
    --centos)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        CENTOS=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    --cloudvision)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        CLOUDVISION=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -a|--apikey)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        ARISTA_APIKEY=$2
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

function init {
    if test -f "/etc/redhat-release"; then
        DISTRO=$(gawk 'match($0, /.*^ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        VERSION=$(gawk 'match($0, /.*^VERSION_ID=\"\s*([^\n\r]*)\"/, m) { print m[1]; }' < /etc/os-release)
        if [ "$DISTRO" = "centos" ]; then
            if [ "$VERSION" = "8" ]; then
                echo "Detected $DISTRO $VERSION"
                dependencies_rhel8
            else
                echo "Unsupported distro version (Detected $DISTRO $VERSION)"
                exit 1
            fi
        else
            echo "Unsupported distro (Detected $DISTRO)"
            exit 1
        fi
    fi
    mkdir -p /tmp/cvp/cloudvision
}

function dependencies_rhel8 {
    dnf install -y libvirt virt-install python3 python3-pip
}

function download_centos {
    # curl https://vault.centos.org/7.7.1908/isos/x86_64/CentOS-7-x86_64-Minimal-1908.iso --output /var/lib/libvirt/boot/CentOS-7-x86_64-Minimal-1908.iso
    curl http://mirror.nsc.liu.se/centos-store/7.7.1908/isos/x86_64/CentOS-7-x86_64-Minimal-1908.iso --output /var/lib/libvirt/boot/CentOS-7-x86_64-Minimal-1908.iso
}

function download_cloudvision {
    curl https://raw.githubusercontent.com/arista-netdevops-community/eos-scripts/main/eos_download.py --output /tmp/cvp/cloudvision/eos_download.py
    pip3 install scp paramiko tqdm requests
    cd /tmp/cvp/cloudvision/
    python3 ./eos_download.py --api $ARISTA_APIKEY --ver cvp-$CVP_VERSION --img rpm
}

function generate_cloudvision_image {
    genisoimage -allow-limited-size -l -J -r -iso-level 3 -o /var/lib/libvirt/images/cvp.iso /tmp/cvp/cloudvision/cvp-rpm-installer-$CVP_VERSION
}

function cleanup {
    rm -Rf /tmp/cvp
}

function cleanup_vm {
    virsh destroy cvp
    virsh undefine cvp
    rm -Rf /var/lib/libvirt/images/cvp.root.img /var/lib/libvirt/images/cvp.data.img
}

function generate_ks {
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

# Enforce password policies
%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
EOF
}

function install {
    virt-install \
        --virt-type=kvm \
        --name cvp \
        --memory=$VM_MEM,maxmemory=$VM_MEM \
        --cpu host-passthrough \
        --vcpus=$VM_VCPU --os-variant=rhel7.7 \
        --location=/var/lib/libvirt/boot/CentOS-7-x86_64-Minimal-1908.iso \
        --network=bridge=$VM_NET,model=virtio \
        --disk path=/var/lib/libvirt/images/cvp.root.img,size=$VM_DISKSIZE_ROOT,bus=virtio,format=raw \
        --disk path=/var/lib/libvirt/images/cvp.data.img,size=$VM_DISKSIZE_DATA,bus=virtio,format=raw \
        --disk path=/var/lib/libvirt/images/cvp.iso,device=cdrom,bus=sata,readonly=yes \
        --initrd-inject=/tmp/cvp/ks.cfg \
        --extra-args "console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH ks=file:/ks.cfg inst.sshd" \
        --graphics none \
        --autostart \
        --noreboot

    virt-xml cvp --remove-device --disk 3
    virt-xml cvp --remove-device --disk 3
    virsh define /etc/libvirt/qemu/cvp.xml

    virsh start cvp
    virsh console cvp
}

cleanup_vm
init
if [ -n "${CENTOS}" ]; then
    if [ "${CENTOS}" == 'download' ]; then
        echo "Downloading CentOS base image and copying to /var/lib/libvirt/boot"
        download_centos;
        copy_centos;
    else
        echo "'--centos' requires either the parameter 'download' or a local path to the CentOS image"
    fi
else
    echo "Error: Required parameter '--centos' is missing" >&2
    exit 1
fi
if [ -n "${CLOUDVISION}" ]; then 
    echo "Downloading Arista CloudVision $CVP_VERSION and copying to /var/lib/libvirt/boot"
    download_cloudvision
    generate_cloudvision_image;
fi
generate_ks
install
