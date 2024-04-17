#!/bin/bash

HOSTNAME='ubuntu'
DEFAULT_USER='sunplus'
DEFAULT_PASSWORD='sunplus'

UBUNTU_RELEASE='20.04'
UBUNTU_BASE_RELEASE='20.04.5'
UBUNTU_CODENAME='focal'

# server ,mate or xfce, lxqt
UBUNTU_TYPE='server'

UBUNTU_APT_SOURCE_URL='http://ports.ubuntu.com'

ARCH='arm'

UBUNTU_ROOTFS="ubuntu-${UBUNTU_TYPE}-${UBUNTU_RELEASE}-rootfs-${ARCH}"
UBUNTU_BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_RELEASE}/release"
if [ $ARCH == "arm" ];then
UBUNTU_BASE_NAME="ubuntu-base-${UBUNTU_BASE_RELEASE}-base-${ARCH}hf.tar.gz"
else
UBUNTU_BASE_NAME="ubuntu-base-${UBUNTU_BASE_RELEASE}-base-${ARCH}.tar.gz"
fi

UBUNTU_APT_SOURCES_LIST="\
deb ${UBUNTU_APT_SOURCE_URL}/ubuntu-ports/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${UBUNTU_APT_SOURCE_URL}/ubuntu-ports/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
deb ${UBUNTU_APT_SOURCE_URL}/ubuntu-ports/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
"
#UBUNTU_MATE_XFCE_OEM_CONFIG='true'
UBUNTU_APT_SOURCE_RESTORE_FROM_BACKUP='true'
UBUNTU_APT_SOURCES_LIST_FILE="${UBUNTU_ROOTFS}/etc/apt/sources.list"
UBUNTU_SERVER_PACKAGES="ubuntu-standard ubuntu-minimal ubuntu-server \
curl net-tools iputils-ping net-tools network-manager openssh-server \
xterm \
"
UBUNTU_MATE_PACKAGES="\
ubuntu-standard ubuntu-minimal ubuntu-mate-desktop \
curl iputils-ping net-tools openssh-server \
oem-config-gtk \
"
UBUNTU_XFCE_PACKAGES="\
ubuntu-standard ubuntu-minimal xubuntu-desktop \
curl iputils-ping net-tools openssh-server \
oem-config-gtk \
"
UBUNTU_XFCE_REMOVE_PACKAGES="\
light-locker xfce4-screensaver \
"
UBUNTU_LXQT_PACKAGES="\
ubuntu-standard ubuntu-minimal lubuntu-desktop \
curl iputils-ping net-tools openssh-server \
"
rootfs_base()
{
    if [ ! -f /usr/bin/qemu-arm-static ]; then
        echo "Please apt install qemu-user-static to get qemu-arm-static"
        exit 1
    fi

    if [ ! -f ${UBUNTU_BASE_NAME} ]; then
        wget ${UBUNTU_BASE_URL}/${UBUNTU_BASE_NAME}
    fi
    rm  -rf $UBUNTU_ROOTFS
    mkdir -p $UBUNTU_ROOTFS
    tar -xpf ${UBUNTU_BASE_NAME} -C ${UBUNTU_ROOTFS}

    if [ ! -f ${UBUNTU_ROOTFS}/usr/bin/qemu-arm-static ]; then
        cp /usr/bin/qemu-arm-static ${UBUNTU_ROOTFS}/usr/bin
    fi

    chmod 0777 ${UBUNTU_ROOTFS}/tmp
    echo "nameserver 8.8.8.8" > ${UBUNTU_ROOTFS}/etc/resolv.conf
    if [ "${UBUNTU_APT_SOURCES_LIST}" != "" ]; then
    if [ ! -f ${UBUNTU_APT_SOURCES_LIST_FILE}.backup ]; then
        cp ${UBUNTU_APT_SOURCES_LIST_FILE} ${UBUNTU_APT_SOURCES_LIST_FILE}.backup
    fi
        echo "${UBUNTU_APT_SOURCES_LIST}" > ${UBUNTU_APT_SOURCES_LIST_FILE}
    fi
}

rootfs_mount()
{
    mount -t proc /proc ${UBUNTU_ROOTFS}/proc
    mount -t sysfs /sys ${UBUNTU_ROOTFS}/sys
    mount -o bind /dev ${UBUNTU_ROOTFS}/dev
    mount -o bind /dev/pts ${UBUNTU_ROOTFS}/dev/pts
}

__rootfs_umount()
{
    while $(mountpoint -q ${UBUNTU_ROOTFS}/$1)
    do
        umount -lR ${UBUNTU_ROOTFS}/$1
    done

}
rootfs_umount() {
    __rootfs_umount proc
    __rootfs_umount sys
    __rootfs_umount dev
}

rootfs_install()
{
    export LC_ALL=C
    export LANG=C
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt update"
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt -y upgrade"
    if [ "$UBUNTU_TYPE" == "mate" ]; then
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get install -y ${UBUNTU_MATE_PACKAGES}"
    elif [ "$UBUNTU_TYPE" == "xfce" ]; then
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get install -y ${UBUNTU_XFCE_PACKAGES}"
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get remove -y ${UBUNTU_XFCE_REMOVE_PACKAGES}"
    elif [ "$UBUNTU_TYPE" == "lxqt" ]; then
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get install -y ${UBUNTU_LXQT_PACKAGES}"    
    else
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get install -y ${UBUNTU_SERVER_PACKAGES}"
    fi
}

rootfs_config()
{
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "locale-gen en_US en_US.UTF-8"
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8"
    if [ -n "$DEFAULT_USER" ]; then
            if [ "$UBUNTU_TYPE" == "server" ] || [ -z "$UBUNTU_MATE_XFCE_OEM_CONFIG" ]; then
                chroot ${UBUNTU_ROOTFS} /bin/bash -c "adduser $DEFAULT_USER --gecos \"\" --disabled-password"
                chroot ${UBUNTU_ROOTFS} /bin/bash -c "echo \"${DEFAULT_USER}:${DEFAULT_PASSWORD}\"|chpasswd"
            fi
            chroot ${UBUNTU_ROOTFS} /bin/bash -c "usermod -aG adm,cdrom,sudo,dip,plugdev,audio,video $DEFAULT_USER"
            if [ "$UBUNTU_TYPE" == "mate" ] || [ "$UBUNTU_TYPE" == "xfce" ]; then
                chroot ${UBUNTU_ROOTFS} /bin/bash -c "usermod -aG lpadmin,lightdm $DEFAULT_USER"
            fi
            if [ "$UBUNTU_MATE_XFCE_OEM_CONFIG" == "true" ]; then
                chroot ${UBUNTU_ROOTFS} /bin/bash -c "oem-config-prepare"
            fi
    fi
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "echo ${HOSTNAME} > /etc/hostname" 
    chroot ${UBUNTU_ROOTFS} /bin/bash -c "echo -n '\
network:
    version: 2
    renderer: NetworkManager
'" > ${UBUNTU_ROOTFS}/etc/netplan/01-network-manager-all.yaml
}

rootfs_clean()
{
    if [ "$UBUNTU_TYPE" == "server" ]; then
        chroot ${UBUNTU_ROOTFS} /bin/bash -c "systemctl disable multipathd.service"
    fi

    chroot ${UBUNTU_ROOTFS} /bin/bash -c "apt-get clean"
    rm -rf ${UBUNTU_ROOTFS}/var/lib/dbus/machine-id
    rm -rf ${UBUNTU_ROOTFS}/var/lib/apt/lists
    rm -rf ${UBUNTU_ROOTFS}/tmp/*
    rm -rf ${UBUNTU_ROOTFS}/run/*
    rm -rf ${UBUNTU_ROOTFS}/root/.cache
    rm -rf ${UBUNTU_ROOTFS}/usr/bin/qemu-arm-static
    if [ "${UBUNTU_APT_SOURCE_RESTORE_FROM_BACKUP}" == "true" ]; then
        if [ -f ${UBUNTU_APT_SOURCES_LIST_FILE}.backup ]; then
            mv ${UBUNTU_APT_SOURCES_LIST_FILE}.backup ${UBUNTU_APT_SOURCES_LIST_FILE}
        fi
    fi
}

rootfs_attr()
{
    cd ${UBUNTU_ROOTFS}
    find ./* ! -type l  -printf '%#m:%U:%G:%p\n' > ../${UBUNTU_ROOTFS}-attr.list
    cd - > /dev/null
    chmod 0755 ${UBUNTU_ROOTFS}/var/lib/snapd/void
}

rootfs_output()
{
    echo "Compressing $UBUNTU_ROOTFS.tar.gz"
    if [ -x /usr/bin/pv ]; then
        tar cf - $UBUNTU_ROOTFS --numeric-owner | \
            pv -prb -s $(du -sb $UBUNTU_ROOTFS | awk '{print $1}') | \
            gzip -9 > ${UBUNTU_ROOTFS}.tar.gz
    else
        tar --numeric-owner -czf ${UBUNTU_ROOTFS}.tar.gz ${UBUNTU_ROOTFS}
    fi
}

rootfs_signal()
{
    rootfs_umount
    exit 0
}

trap "rootfs_signal" 2

main()
{
    rootfs_umount
    rootfs_base
    rootfs_mount
    rootfs_install
    rootfs_config
    rootfs_clean
    rootfs_umount
    rootfs_attr
    rootfs_output
}

main
