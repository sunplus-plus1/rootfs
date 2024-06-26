#!/bin/bash

# arguments:
# $1 : v5 or v7 (default: v7)
# $2 : update (default: completely rebuild)

# default to v7 build

# Output
DISKZ=disk-base/
DISKOUT=`pwd`/disk
DISKLIB=${DISKOUT}/lib
DISKLIB64=${DISKOUT}/lib64

V7_BUILD=1
if [ "$1" = "v5" ]; then
	V7_BUILD=0
fi

if [ "${ROOTFS_CONTENT}" = "YOCTO" ]; then
	tar_rootfs=0

	if [ ! -d ${DISKOUT} ]; then
		tar_rootfs=1
	elif [ -f ${DISKOUT}/init ]; then
		rm -rf ${DISKOUT}
		tar_rootfs=1
	elif [ "$ARCH" = "arm64" ] && [ ! -f ${DISKLIB}/ld-linux-aarch64.so.1 ]; then
		rm -rf ${DISKOUT}
		tar_rootfs=1
	elif [ "$ARCH" != "arm64" ] && [ -f ${DISKLIB}/ld-linux-aarch64.so.1 ]; then
		rm -rf ${DISKLIB64}
		rm ${DISKLIB}/ld-linux-aarch64.so.1
		exit 0
	fi

	if [ ${tar_rootfs} -eq 1 ]; then
		tar jxvf rootfs.tar.bz2 &>/dev/null
		cp -R ${DISKZ}lib/firmware/ ${DISKLIB}
		if [ "$ARCH" = "arm64" ]; then
			cp -R ${DISKZ}usr/modules/ ${DISKOUT}/usr
		fi
	fi

	if [ "$ARCH" != "arm64" ]; then
		if [ -d ${DISKLIB64} ]; then
			rm -rf ${DISKLIB64}
			rm ${DISKLIB}/ld-linux-aarch64.so.1
		fi
		if [ $V7_BUILD -eq 1 ]; then
			if [ -d prebuilt/resize2fs/v7 ]; then
				cp -av prebuilt/resize2fs/v7/* $DISKOUT
			fi
		else
			if [ -d prebuilt/resize2fs/v5 ]; then
				cp -av prebuilt/resize2fs/v5/* $DISKOUT
			fi
		fi
	else
		cp -av prebuilt/resize2fs/v8/* $DISKOUT
	        check_remoteproc=`cat ${DISKOUT}/etc/profile | grep "REMOTEPROC"`
	        if [ "${check_remoteproc}" == "" ]; then
			echo '
			# ADD REMOTEPROC
			if [ -d /sys/class/remoteproc/remoteproc0 ]; then
	  			if [ -f /lib/firmware/firmware ]; then
	       				echo "Boot CM4 firmware by remoteproc"
	       				echo firmware > /sys/class/remoteproc/remoteproc0/firmware
	       				echo start > /sys/class/remoteproc/remoteproc0/state
	  			fi
			fi' >> ${DISKOUT}/etc/profile
	    	fi
	fi
	cp ${DISKZ}etc/init.d/rc.resizefs ${DISKOUT}/etc/init.d/rc.resizefs

	exit 0
elif [ "${ROOTFS_CONTENT:0:6}" = "ubuntu" ]; then
	if [ "$ARCH" == "arm64" ]; then
		exit 1
	fi

	if [ -f "${DISKOUT}/etc/lsb-release" ]; then
		. ${DISKOUT}/etc/lsb-release
		if [ "${DISTRIB_ID} == Ubuntu" ]; then
			exit 0
		fi
		rm -rf ${DISKOUT}
	fi

	mkdir -p ${DISKOUT}
	echo "Uncompressing ${ROOTFS_CONTENT}-rootfs-${ARCH}.tar.gz"
	if [ -x /usr/bin/pv ]; then
		pv -prb ubuntu/${ROOTFS_CONTENT}/${ROOTFS_CONTENT}-rootfs-${ARCH}.tar.gz* | tar -xzf - -C ${DISKOUT} --strip-components 1
	else
		cat ubuntu/${ROOTFS_CONTENT}/${ROOTFS_CONTENT}-rootfs-${ARCH}.tar.gz* | tar -xzf - -C ${DISKOUT} --strip-components 1
        fi
	mkdir -p .tmp
	ln -sf ../ubuntu/${ROOTFS_CONTENT}/${ROOTFS_CONTENT}-rootfs-${ARCH}-attr.list .tmp/attr.list

	cp -R ${DISKZ}lib/firmware/ ${DISKLIB}

	# ADD systemd rc-local.service
	FILE_RC_LOCAL_SERVICE="${DISKOUT}/etc/systemd/system/rc-local.service"
	if [ -d ${DISKOUT}/etc/systemd/system ]; then
		cat <<EOF > ${FILE_RC_LOCAL_SERVICE}
[Unit]
  Description=/etc/rc.local Compatibility
  ConditionPathExists=/etc/rc.local

[Service]
  Type=forking
  ExecStart=/etc/rc.local start
  TimeoutSec=0
  StandardOutput=tty
  RemainAfterExit=yes
  SysVStartPriority=99

[Install]
  WantedBy=multi-user.target
EOF
	fi

	# Copy rc.local file to /etc of rootfs, this file is used for systemd rc-local.service.
	# Action within this file:
	# 1. Do CM4-REMOTEPROC
	# 2. Change NPU(galcore) device file attribute
	# 3. Extend rootfs partition and resize partition base on disk size limitation.
	cp ubuntu/etc/rc.local ${DISKOUT}/etc
	exit 0
else
	if [ ! -f ${DISKOUT}/init ]; then
		rm -rf ${DISKOUT}
	fi
fi

UPDATE=0

if [ "$2" = "update" ]; then
	UPDATE=1
fi

# Toolchain
if [ "$ARCH" = "riscv" ]; then
	DISK_LIB=lib-riscv
elif [ "$ARCH" = "arm64" ]; then
	DISK_LIB="lib-v7hf lib-arm64"
elif [ $V7_BUILD -eq 1 ]; then
	DISK_LIB=lib-v7hf
else
	DISK_LIB=lib-v5
fi

if [ -z "${CROSS}" ]; then
	echo "CROSS=... is undefined"
	exit 1;
fi;

function abspath() {
	# generate absolute path from relative path
	# $1     : relative filename
	# return : absolute path
	if [ -d "$1" ]; then
		# dir
		(cd "$1"; pwd)
	elif [ -f "$1" ]; then
		# file
		if [[ $1 = /* ]]; then
			echo "$1"
		elif [[ $1 == */* ]]; then
			echo "$(cd "${1%/*}"; pwd)/${1##*/}"
		else
			echo "$(pwd)/$1"
		fi
	fi
}

# sub builds need absolute path
CROSS=`abspath ${CROSS}gcc`
echo $CROSS
${CROSS} --version 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Not found gcc : $CROSS"
	exit 1
fi
CROSS=${CROSS%gcc}

# Busybox
BBX=busybox-1.31.1
BBXZ=../busybox/$BBX.tar.xz
#BBXCFG=configs/bbx_static_defconfig
BBXCFG=configs/bbx_dynamic_defconfig

# Check sources
if [ ! -d $DISKZ ]; then
	echo "Not found base: $DISKZ"
fi

if [ ! -f $BBXZ ]; then
	echo "Not found busybox: $BBXZ"
	exit 1
fi

if [ ! -d $DISKOUT ]; then
	UPDATE=0
fi

if [ $UPDATE -eq 1 ]; then
	echo "Use current disk folder"
else
	echo "Prepare new disk base"
	rm -rf $DISKOUT
	cp -a $DISKZ $DISKOUT
	for d in ${DISK_LIB}; do cp -a $d/* $DISKOUT/; done
	cd $DISKOUT
	mkdir -p proc sys mnt tmp var run
	cd -

	echo "Build busybox with new config ($BBXCFG)"
	rm -rf $BBX
	tar xf $BBXZ
	cp -vf $BBXCFG $BBX/.config
fi

echo "Build busybox"
echo make -C $BBX -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT all
make -C $BBX -j ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT all

echo "Install busybox"
cd $BBX && make -j ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT install
cd -
size $BBX/busybox
echo "Installed ($BBXCFG)"

echo "Overwrite with extra/ ..."
if [ -d extra/ ]; then
	cp -av extra/* $DISKOUT
fi

if [ "$ARCH" = "riscv" ]; then
	if [ -d prebuilt/riscv ]; then
		cp -av prebuilt/riscv/* $DISKOUT
	fi
elif [ "$ARCH" = "arm64" ]; then
	if [ -d prebuilt/arm64 ]; then
		cp -av prebuilt/arm64/* $DISKOUT
		cp -av prebuilt/resize2fs/v8/* $DISKOUT
	fi
elif [ $V7_BUILD -eq 1 ]; then
	if [ -d prebuilt/resize2fs/v7 ]; then
		cp -av prebuilt/resize2fs/v7/* $DISKOUT
	fi
else
	if [ -d prebuilt/resize2fs/v5 ]; then
		cp -av prebuilt/resize2fs/v5/* $DISKOUT
	fi
fi
