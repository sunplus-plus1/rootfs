#!/bin/bash

# arguments: create different rootfs by boot mode
# $1 : NAND EMMC SDCARD SPINOR NOR_JFFS2 PNAND
# $2 : FLASH_SIZE (Size of SPI-NOR, SPI-NAND, 8-bit NAND and eMMC)
# $3 : NAND_PAGE_SIZE
# $4 : NAND_PAGE_CNT
OUT_IMG=rootfs.img
WORK_DIR=./initramfs/disk

if [ "$1" = "EMMC" ]; then
############################################  ext4 fs ############################################
	echo -e  "\E[1;33m ========make ext4 fs========== \E[0m"
	FAKEROOT="fakeroot -- "
	RESIZE=./tools/resize2fs

	if [ ! -d $WORK_DIR ]; then
		echo "Error: $WORK_DIR doesn't exist!"
		exit 1
	fi

	cp -av wifi_fw/* $WORK_DIR
	diskdir_sz=`du -sb $WORK_DIR | cut -f1`
	echo "rootfs total size = $diskdir_sz bytes"

	# Assume 40% +20MB overhead for creating ext4 fs.
	diskdir_sz=$((diskdir_sz*14/10))
	EXT_SIZE=$((diskdir_sz/1024/1024+20))
	rm -rf $OUT_IMG

	$FAKEROOT /bin/bash -c "./tools/setting_attr.py $WORK_DIR ./initramfs/.tmp/attr.list; mke2fs -t ext4 -b 4096 -d $WORK_DIR $OUT_IMG $((EXT_SIZE))M"

	# Resize to 10% more than minimum.
	minimum_sz=`$RESIZE -P $OUT_IMG | cut -d: -f2`
	minimum_sz=$((minimum_sz*11/10+1))
	$RESIZE $OUT_IMG $minimum_sz

elif [ "$1" = "SDCARD" ]; then
	cp -av wifi_fw/* $WORK_DIR
	echo "Skip generating rootfs.img for SDCARD!"

elif [ "$1" = "NAND" -o "$1" = "PNAND" ]; then
############################################  ubi fs ############################################

#mkfs.ubifs+ubi write: Can automatically set the size of the root file system by partition size in ISP,
#                      use the ubi cmd to write rootfs into nand in ISP, need add ubi config in uboot; used it!!!
#mkfs.ubifs+ubinize+nand write: the rootfs size is fixed in ubi.cfg that used in ubinize function. this
#                               can use the nand write cmd to write dat into nand, no need do something in uboot.
	echo -e  "\E[1;33m ========make ubi fs========== \E[0m"
	MKFS_UBIFS="fakeroot -- mkfs.ubifs"
	UBINIZE=./tools/ubinize
	UBI_CFG=./ubi.cfg

	NAND_PAGESIZE=$(($3*1024))
	NAND_BLK_PAGESIZE=$4
	MAX_ERASE_BLK_CNT=$((($2*1024)/($3*$4)/1024*1015))
	echo " NAND_PAGESIZE=$NAND_PAGESIZE"
	echo " NAND_BLK_PAGESIZE=$NAND_BLK_PAGESIZE"
	echo " MAX_ERASE_BLK_CNT=$MAX_ERASE_BLK_CNT"

	NAND_LOGIC_REASE_SIZE=$(($NAND_BLK_PAGESIZE-2))*$NAND_PAGESIZE  # size = (blockcnt-2)*2048

	if [ ! -d $WORK_DIR ]; then
		echo "Error: $WORK_DIR doesn't exist!"
		exit 1
	fi

	$MKFS_UBIFS -r $WORK_DIR -m $NAND_PAGESIZE -e $(($NAND_LOGIC_REASE_SIZE)) -c $MAX_ERASE_BLK_CNT -F -o $OUT_IMG

	if [ "$1" = "ZEBU_PNAND" ]; then #mkfs.ubifs+ubinize is used to paranand boot in zebu

		NAND_ROOTFS_SIZE=100MiB
		NAND_BLK_SIZE=$NAND_BLK_PAGESIZE*$NAND_PAGESIZE  # size = blockcnt*2048
		## rootfs size need to smaller than rootfs partition size set in isp
		if [ 1020 -eq $MAX_ERASE_BLK_CNT ];then
			NAND_ROOTFS_SIZE=100MiB
			echo -e  "\E[1;33m 1G nand  \E[0m"
		elif [ 2030 -eq $MAX_ERASE_BLK_CNT ];then
			NAND_ROOTFS_SIZE=210MiB
			echo -e  "\E[1;33m 2G nand  \E[0m"
		fi

		echo "[ubifs]" >$UBI_CFG
		echo "mode=ubi" >>$UBI_CFG
		echo "image=nand.img" >>$UBI_CFG
		echo "vol_id=0" >>$UBI_CFG
		echo "vol_type=dynamic" >>$UBI_CFG
		echo "vol_name=rootfs" >>$UBI_CFG
		echo "vol_flag=autoresize" >>$UBI_CFG
		echo "vol_size=$NAND_ROOTFS_SIZE" >>$UBI_CFG

		echo -e  "\E[1;33m ========rootfs = $NAND_ROOTFS_SIZE  pagesize=$NAND_PAGESIZE========== \E[0m"
		$MKFS_UBIFS -r $WORK_DIR -m $NAND_PAGESIZE -e $(($NAND_LOGIC_REASE_SIZE)) -c $MAX_ERASE_BLK_CNT -F -o nand.img
		$UBINIZE -v -o $OUT_IMG -m $NAND_PAGESIZE -p $(($NAND_BLK_SIZE/1024))KiB $UBI_CFG
		rm -rf nand.img
	fi

elif [ "$1" = "SPINOR" ]; then
	echo "Skip generating rootfs.img for SPINOR!"

	# Due to limit size of SPI-NOR flash,
	# remove EthosN firmware, EthosN libraries,
	# and some utilities.
	rm -f initramfs/disk/lib/firmware/ethosn.bin
	rm -f initramfs/disk/lib64/libEthosNDriver.so
	rm -f initramfs/disk/lib64/libEthosNSupport.so
	rm -f initramfs/disk/sbin/resize2fs
	rm -f initramfs/disk/bin/7za
	rm -f initramfs/disk/bin/perf
	rm -f initramfs/disk/bin/enable_arm_pmu.ko
	rm -f initramfs/disk/bin/perf_arm_pum
	rm -f initramfs/disk/usr/modules/galcore.ko
	rm -f initramfs/disk/usr/lib64/libArchModelSw.so
	rm -f initramfs/disk/usr/lib64/libCLC.so
	rm -f initramfs/disk/usr/lib64/libGAL.so
	rm -f initramfs/disk/usr/lib64/libNNArchPerf.so
	rm -f initramfs/disk/usr/lib64/libNNGPUBinary.so
	rm -f initramfs/disk/usr/lib64/libNNVXCBinary.so
	rm -f initramfs/disk/usr/lib64/libOpenCL.so
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.1
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.3
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.3.0.0
	rm -f initramfs/disk/usr/lib64/libOpenVX.so
	rm -f initramfs/disk/usr/lib64/libOpenVX.so.1
	rm -f initramfs/disk/usr/lib64/libOpenVX.so.1.3.0
	rm -f initramfs/disk/usr/lib64/libOpenVXU.so
	rm -f initramfs/disk/usr/lib64/libOvx12VXCBinary.so
	rm -f initramfs/disk/usr/lib64/libOvxGPUVXCBinary.so
	rm -f initramfs/disk/usr/lib64/libovxlib.so
	rm -f initramfs/disk/usr/lib64/libSPIRV_viv.so
	rm -f initramfs/disk/usr/lib64/libVSC.so

elif [ "$1" = "NOR_JFFS2" ]; then
	echo "Skip generating rootfs.img for NOR_JFFS2!"

	# Due to limit size of SPI-NOR flash,
	# remove EthosN firmware, EthosN libraries,
	# and some utilities.
	rm -f initramfs/disk/lib/firmware/ethosn.bin
	rm -f initramfs/disk/lib64/libEthosNDriver.so
	rm -f initramfs/disk/lib64/libEthosNSupport.so
	rm -f initramfs/disk/sbin/resize2fs
	rm -f initramfs/disk/bin/7za
	rm -f initramfs/disk/bin/perf
	rm -f initramfs/disk/bin/enable_arm_pmu.ko
	rm -f initramfs/disk/bin/perf_arm_pum
	rm -f initramfs/disk/usr/modules/galcore.ko
	rm -f initramfs/disk/usr/lib64/libArchModelSw.so
	rm -f initramfs/disk/usr/lib64/libCLC.so
	rm -f initramfs/disk/usr/lib64/libGAL.so
	rm -f initramfs/disk/usr/lib64/libNNArchPerf.so
	rm -f initramfs/disk/usr/lib64/libNNGPUBinary.so
	rm -f initramfs/disk/usr/lib64/libNNVXCBinary.so
	rm -f initramfs/disk/usr/lib64/libOpenCL.so
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.1
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.3
	rm -f initramfs/disk/usr/lib64/libOpenCL.so.3.0.0
	rm -f initramfs/disk/usr/lib64/libOpenVX.so
	rm -f initramfs/disk/usr/lib64/libOpenVX.so.1
	rm -f initramfs/disk/usr/lib64/libOpenVX.so.1.3.0
	rm -f initramfs/disk/usr/lib64/libOpenVXU.so
	rm -f initramfs/disk/usr/lib64/libOvx12VXCBinary.so
	rm -f initramfs/disk/usr/lib64/libOvxGPUVXCBinary.so
	rm -f initramfs/disk/usr/lib64/libovxlib.so
	rm -f initramfs/disk/usr/lib64/libSPIRV_viv.so
	rm -f initramfs/disk/usr/lib64/libVSC.so

elif [ "$1" = "USB" ]; then
	echo "Skip generating rootfs.img for USB!"

elif [ "$1" = "TFTP" ]; then
	echo "Skip generating rootfs.img for TFTP!"

else
#####################################  squash fs ############################################
	echo -e  "\E[1;33m ========make squash fs========== \E[0m"
	MKSQFS_COMPOPT="-comp lzo -Xcompression-level 9"
	MKSQFS=./tools/mksquashfs

	if [ ! -d $WORK_DIR ]; then
		echo "Error: $WORK_DIR doesn't exist!"
		exit 1
	fi

	$MKSQFS $WORK_DIR $OUT_IMG -all-root -noappend $MKSQFS_COMPOPT
fi
