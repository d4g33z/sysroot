#!/usr/bin/env zsh

CFLAGS="-O2 -pipe -march=armv7-a -mtune=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard"
CTARGET=armv7a-hardfloat-linux-gnueabi
SDCARD=/dev/mmcblk0
STAGEBALL=$HOME/Downloads/stage3-latest.tar.xz
STAGE_URL="http://ftp.osuosl.org/pub/funtoo/funtoo-current/arm-32bit/raspi3/stage3-latest.tar.xz"
SYSROOT=/home/sysroots/$CTARGET

[[ "$(lsmod | grep kvm_intel)" == "" ]] && {
    modprobe kvm_intel || {
        echo "Can't load kvm_intel kernel module."
        exit
    }
}

[[ -d $SYSROOT ]] && {
    read REPLY"?Backup previous sysroot to $SYSROOT.old? [y|N] "
    [[ $REPLY =~ ^[Yy]$ ]] && {
        mv $SYSROOT $SYSROOT.old
        mkdir -p $SYSROOT
    }
}

read REPLY"?Download stage3-latest for ARM architecture? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    mkdir -p $HOME/Downloads
    [[ -f "$STAGEBALL" ]] && mv $STAGEBALL $STAGEBALL.bak
    wget $STAGE_URL \
        -O $STAGEBALL
}

read REPLY"?Extract $STAGEBALL in $SYSROOT? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    mkdir -p $SYSROOT
    tar xpfv "$STAGEBALL" -C $SYSROOT
}

read REPLY"?Merge app-emulation/qemu? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ -d /etc/portage/package.use ]] \
        && echo 'app-emulation/qemu static-user' > /etc/portage/package.use/qemu \
        || echo 'app-emulation/qemu static-user' >> /etc/portage/package.use
    echo 'QEMU_SOFTMMU_TARGETS="arm"' >> /etc/portage/make.conf
    echo 'QEMU_USER_TARGETS="arm"' >> /etc/portage/make.conf
    emerge -a app-emulation/qemu
    dispatch-conf
    emerge -a app-emulation/qemu
}

read REPLY"?Install static qemu binary on $SYSROOT? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    quickpkg app-emulation/qemu
    ROOT=$SYSROOT/ emerge --usepkgonly --oneshot --nodeps qemu
}

sysroot-mount $SYSROOT

read REPLY"?Prepare the sysroot? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ ! -f $SYSROOT/prepare.sh ]] && {
        cat > $SYSROOT/prepare.sh << EOF
#!/bin/bash
passwd
echo '/dev/mapper/rpi-root    /           ext4    defaults,noatime,errors=remount-ro,discard   0 1' >  /etc/fstab
echo '/dev/mapper/rpi-swap    none        swap    defaults,noatime,discard                     0 0' >> /etc/fstab
ego sync
emerge -a cryptsetup genkernel dropbear raspberrypi-firmware networkmanager wireless-tools
dispatch-conf
emerge -a cryptsetup genkernel dropbear raspberrypi-firmware networkmanager wireless-tools
rc-update add NetworkManager default
rc-update add sshd default
rc-update add swclock boot
rc-update del hwclock boot
rm -f /etc/dropbear
mkdir -p /etc/dropbear
dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
echo '' > /etc/dropbear/authorized_keys
chmod 700 /etc/dropbear
EOF
        chmod +x $SYSROOT/prepare.sh
    }
    chroot $SYSROOT /bin/bash -c "/bin/bash /prepare.sh"
    rm $SYSROOT/prepare.sh
}

read REPLY"?Merge crossdev? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    echo "=sys-devel/crossdev-99999999" >> /etc/portage/package.unmask
    [[ -d /etc/portage/package.keywords ]] \
        && echo "sys-devel/crossdev **" >> /etc/portage/package.keywords \
        || echo "sys-devel/crossdev **" > /etc/portage/package.keywords/crossdev
    emerge -a crossdev
}

read REPLY"?Build cross-$CTARGET toolchain? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    dirs=(
        /etc/portage/package.keywords
        /etc/portage/package.mask
        /etc/portage/package.use
    )
    for dir in ${dirs[@]}; do
        [[ ! -d $dir ]] && {
            mv $dir $dir"_file"
            mkdir -p $dir
            mv $dir"_file" $dir
        }
    done

    [[ -d /var/git/gentoo-vanilla ]] \
        && git --git-dir=/var/git/gentoo-vanilla/.git --work-tree=/var/git/gentoo-vanilla pull origin \
        || git clone git://github.com/gentoo/gentoo.git /var/git/gentoo-vanilla
    echo "gentoo-vanilla" > /var/git/gentoo-vanilla/profiles/repo_name
    cat > /etc/portage/repos.conf/gentoo-vanilla << EOF
[gentoo-vanilla]
location = /var/git/gentoo-vanilla
sync-type = git
sync-uri = git://github.com/gentoo/gentoo.git
auto-sync = no
EOF
    cat > /etc/portage/repos.conf/crossdev << EOF
[crossdev]
location = /var/git/crossdev
masters = gentoo-vanilla
auto-sync = no
use-manifests = true
thin-manifests = true
EOF
    mkdir -p /var/git/crossdev/profiles
    chown -R portage:portage /var/git/crossdev
    echo "crossdev" > /var/git/crossdev/profiles/repo_name
    rm -rf /var/git/crossdev/cross-$CTARGET
    crossdev -S -oO /var/git/crossdev/ -t $CTARGET
    rm -f /etc/portage/repos.conf/{crossdev,gentoo-vanilla}
}

read REPLY"?Clean and update sources from raspberrypi/linux? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ ! -d /usr/src/linux-rpi-vanilla ]] \
        && git clone https://github.com/raspberrypi/linux.git /usr/src/linux-rpi-vanilla

    git --git-dir=/usr/src/linux-rpi-vanilla/.git --work-tree=/usr/src/linux-rpi-vanilla clean -fdx
    git --git-dir=/usr/src/linux-rpi-vanilla/.git --work-tree=/usr/src/linux-rpi-vanilla checkout master
    git --git-dir=/usr/src/linux-rpi-vanilla/.git --work-tree=/usr/src/linux-rpi-vanilla fetch --all
    git --git-dir=/usr/src/linux-rpi-vanilla/.git --work-tree=/usr/src/linux-rpi-vanilla branch -D rpi-4.9.y
    git --git-dir=/usr/src/linux-rpi-vanilla/.git --work-tree=/usr/src/linux-rpi-vanilla checkout rpi-4.9.y

    [[ -f /etc/kernels/kernel-config-arm ]] && cp /etc/kernels/kernel-config-arm /usr/src/linux-rpi-vanilla/.config
}

pwd=$(pwd)
cd /usr/src/linux-rpi-vanilla
read REPLY"?Make bcm2709_defconfig? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    make -j$(nproc) \
    ARCH=arm \
    CROSS_COMPILE=$CTARGET- \
    bcm2709_defconfig
}

read REPLY"?Make menuconfig? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    make -j$(nproc) \
    ARCH=arm \
    CROSS_COMPILE=$CTARGET- \
    MENUCONFIG_COLOR=mono \
    menuconfig
}

read REPLY"?Build kernel? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    make -j$(nproc) \
    ARCH=arm \
    CROSS_COMPILE=$CTARGET- \
    zImage dtbs modules

    make -j$(nproc) \
    ARCH=arm \
    CROSS_COMPILE=$CTARGET- \
    INSTALL_MOD_PATH=$SYSROOT \
    modules_install

    mkdir -p $SYSROOT/boot/overlays
    cp arch/arm/boot/dts/*.dtb $SYSROOT/boot/
    cp arch/arm/boot/dts/overlays/*.dtb* $SYSROOT/boot/overlays/
    cp arch/arm/boot/dts/overlays/README $SYSROOT/boot/overlays/
    scripts/mkknlimg arch/arm/boot/zImage $SYSROOT/boot/kernel7.img

    read REPLY"?Save new kernel config to /etc/kernels? [y|N] "
    [[ $REPLY =~ ^[Yy]$ ]] && cp .config /etc/kernels/kernel-config-arm
}
cd $pwd

read REPLY"?Copy non-free firmware for brcm? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ -d /usr/src/firmware-nonfree ]] \
        && git --git-dir=/usr/src/firmware-nonfree/.git --work-tree=/usr/src/linux-rpi-vanilla pull origin \
        || git clone --depth 1 https://github.com/RPi-Distro/firmware-nonfree /usr/src/firmware-nonfree
    mkdir -p $SYSROOT/lib/firmware/brcm
    find /usr/src/firmware-nonfree/ -name 'brcmfmac43430-sdio.*' -exec cp {} $SYSROOT/lib/firmware/brcm/ \;
}

read REPLY"?Build initramfs? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    rm -f $SYSROOT/boot/*initramfs*
    rsync -avr --delete /usr/src/linux-rpi-vanilla/ $SYSROOT/usr/src/linux-rpi-vanilla/
    [[ -L $SYSROOT/usr/src/linux ]] && unlink $SYSROOT/usr/src/linux
    ln -s linux-rpi-vanilla $SYSROOT/usr/src/linux
    sed -e 's/#SSH="no"/SSH="YES"/g' $SYSROOT/etc/genkernel.conf > $SYSROOT/etc/genkernel.conf.
    mv $SYSROOT/etc/genkernel.conf. $SYSROOT/etc/genkernel.conf
    chroot $SYSROOT /bin/bash -c "genkernel --no-mountboot --luks --lvm --kernel-config=/usr/src/linux/.config initramfs"
    initramfs=$(ls $SYSROOT/boot | grep initramfs)
    echo "initramfs $initramfs followkernel" > $SYSROOT/boot/config.txt
}

read REPLY"?Wipe and randomize $SDCARD bits? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && dd if=/dev/urandom of=$SDCARD bs=1M status=progress

read REPLY"?Write partition scheme to $SDCARD? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ "$(mount | grep $SDCARD)" != "" ]] && umount -Rl $SDCARD
    sfdisk --no-reread --wipe always $SDCARD << EOF
label: dos
unit: sectors
${SDCARD}p1 : start=        2048, size=     1048576, type=c
${SDCARD}p2 : start=     1050624, type=83
EOF
}

read REPLY"?Format $SDCARD? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    cryptsetup luksFormat ${SDCARD}p2
    cryptsetup luksOpen ${SDCARD}p2 rpi

    pvcreate /dev/mapper/rpi
    vgcreate rpi /dev/mapper/rpi
    lvcreate --size 2GB --name swap rpi
    lvcreate --extents 95%FREE --name root rpi

    mkswap -L "swap" /dev/mapper/rpi-swap
    mkfs.ext4 /dev/mapper/rpi-root
    mkfs.vfat ${SDCARD}p1
}

read REPLY"?Deploy $SYSROOT to $SDCARD? [y|N] "
[[ $REPLY =~ ^[Yy]$ ]] && {
    [[ "$(cryptsetup status rpi | grep 'is active')" == "" ]] && {
        cryptsetup luksOpen ${SDCARD}p2 rpi || exit
        vgchange --available y rpi || exit
    }

    mkdir -p /mnt/rpi
    mount /dev/mapper/rpi-root /mnt/rpi
    mkdir -p /mnt/rpi/boot
    mount ${SDCARD}p1 /mnt/rpi/boot
    umount -Rl $SYSROOT/{proc,sys,dev}

    SDCARD_BOOT_UUID=$(blkid -s UUID -o value ${SDCARD}p1)
    [[ "$(grep boot /etc/fstab)" == "" ]] \
        && echo "UUID=$SDCARD_BOOT_UUID          /boot           vfat            noauto,noatime  2 2" >> $SYSROOT/etc/fstab

    SDCARD_ROOT_UUID=$(blkid -s UUID -o value ${SDCARD}p2)
    echo "ro crypt_root=UUID=$SDCARD_ROOT_UUID root=/dev/mapper/rpi-root dolvm rootfstype=ext4" > $SYSROOT/boot/cmdline.txt
    #echo "ro dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 crypt_root=UUID=$SDCARD_ROOT_UUID root=/dev/mapper/rpi-root dolvm rootfstype=ext4 elevator=deadline rootwait" > $SYSROOT/boot/cmdline.txt

    read REPLY"?Force write on $SDCARD files (--delete for rsync)? [y|N] "
    [[ $REPLY =~ ^[Yy]$ ]] && RSYNC_DELETE=--delete
    rsync -avr --exclude $RSYNC_DELETE "var/git/*" $SYSROOT/ /mnt/rpi/

    umount /mnt/rpi/boot
    umount /mnt/rpi
    vgchange --available n rpi
    cryptsetup luksClose rpi
}
