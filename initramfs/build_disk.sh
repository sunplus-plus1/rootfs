#!/bin/bash

# arguments:
# $1 : v5 or v7 (default: v7)
# $2 : update (default: completely rebuild)

# default to v7 build
V7_BUILD=1

if [ "$1" = "v5" ];then
	V7_BUILD=0
fi

UPDATE=0

if [ "$2" = "update" ];then
	UPDATE=1
fi

# Toolchain
ARCH=arm
if [ $V7_BUILD -eq 1 ];then
	CROSS=../../../build/tools/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
	DISK_LIB=lib-v7hf
else
	CROSS=../../../build/tools/armv5-eabi--glibc--stable/bin/armv5-glibc-linux-
	DISK_LIB=lib-v5
fi

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
${CROSS} -v 2>/dev/null
if [ $? -ne 0 ];then
	echo "Not found gcc : $CROSS"
	exit 1
fi
CROSS=${CROSS%gcc}

# Output
DISKZ=disk-base/
DISKOUT=`pwd`/disk

# Busybox
BBX=busybox-1.24.1
BBXZ=../busybox/$BBX.tar.bz2
#BBXCFG=configs/bbx_static_defconfig
BBXCFG=configs/bbx_dynamic_defconfig

# Check sources
if [ ! -d $DISKZ ];then
	echo "Not found base: $DISKZ"
fi

if [ ! -f $BBXZ ];then
	echo "Not found busybox: $BBXZ"
	exit 1
fi

if [ ! -d $DISKOUT ];then
	UPDATE=0
fi

if [ $UPDATE -eq 1 ];then
	echo "Use current disk folder"
else
	echo "Prepare new disk base"
	rm -rf $DISKOUT
	cp -a $DISKZ $DISKOUT
	cp -a ${DISK_LIB}/* $DISKOUT/
	cd $DISKOUT
	mkdir -p proc sys mnt tmp var overlay
	cd -

	echo "Build busybox with new config ($BBXCFG)"
	rm -rf $BBX
	tar xjf $BBXZ
	cp -vf $BBXCFG $BBX/.config
fi

echo "Build busybox"
echo make -C $BBX -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT install
make -C $BBX -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT all

echo "Install busybox"
cd $BBX && make -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS CONFIG_PREFIX=$DISKOUT install
cd -
size $BBX/busybox
echo "Installed ($BBXCFG)"

echo "Overwrite with extra/ ..."
if [ -d extra/ ];then
	cp -av extra/* $DISKOUT
fi
