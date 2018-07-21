KERNEL_WORK=/usr/src/rpi_kernel
RPI_KERN_BRANCH=rpi-4.9.y

SYSROOT_WORK=/usr/src/sysroots
STAGE_URL="http://ftp.osuosl.org/pub/funtoo/funtoo-current/arm-32bit/raspi3/stage3-latest.tar.xz"
CTARGET=armv7a-hardfloat-linux-gnueabi
CFLAGS="-O2 -pipe -march=armv7-a -mtune=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard"

#SDCARD_DEV=mmcblk0p
SDCARD_DEV=sdb

#optional
DISTCC_REMOTE_JOBS=21
DISTCC_REMOTE_HOSTS="10.0.0.1,cpp,lzo"

