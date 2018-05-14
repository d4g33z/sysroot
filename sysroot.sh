#!/bin/sh

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

sysroot_chroot()
{
    if [ $# -lt 1 ]; then
        printf "usage: sysroot-chroot path\n"
        return 1
    fi
    sysroot_mount $1 || return 1
    chroot $1 /bin/sh --login
    umount $1/dev
    umount $1/proc
    umount $1/sys
}

sysroot_mount()
{
    if [ $# -lt 1 ]; then
        printf "usage: sysroot-mount path\n"
        return 1
    fi
    if [ "$(mount | grep $1)" != "" ]; then
        return 0
    fi
    if [ "$(/etc/init.d/qemu-binfmt status | grep started)" = "" ]; then
        /etc/init.d/qemu-binfmt start
    fi
    cp /etc/resolv.conf $1/etc/resolv.conf
    mkdir -p $1/dev  && mount --bind /dev $1/dev
    mkdir -p $1/proc && mount --bind /proc $1/proc
    mkdir -p $1/sys  && mount --bind /sys $1/sys
}

sysroot_install()
{
    if [ $(id -u) -ne 0 ]; then
        printf "error: must run as root\n"
        return 1;
    fi

    CFLAGS="-O2 -pipe -march=armv7-a -mtune=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard"
    CTARGET=armv7a-hardfloat-linux-gnueabi
    SDCARD=/dev/mmcblk0
    STAGE_BALL=${HOME}/Downloads/stage3-latest.tar.xz
    STAGE_URL="http://ftp.osuosl.org/pub/funtoo/funtoo-current/arm-32bit/raspi3/stage3-latest.tar.xz"
    SYSROOT=/home/sysroots/${CTARGET}

    if [ "$(lsmod | grep kvm_intel)" = "" ]; then
        modprobe kvm_intel
        if [ $? -ne 0 ]; then
            printf "error: can't load kvm_intel kernel module\n"
            return 1;
        fi
    fi

    if [ -d ${SYSROOT} ]; then
        if prompt_input_yN "backup previous sysroot to ${SYSROOT}.old"; then
            mv ${SYSROOT} ${SYSROOT}.old
            mkdir -p ${SYSROOT}
        fi
    fi

    if prompt_input_yN "download stage3-latest for ARM architecture"; then
        mkdir -p ${HOME}/Downloads
        [ -f ${STAGE_BALL} ] && mv ${STAGE_BALL} ${STAGE_BALL}.bak
        wget ${STAGE_URL} -O ${STAGE_BALL}
    fi

    if prompt_input_yN "extract ${STAGE_BALL} in ${SYSROOT}"; then
        mkdir -p ${SYSROOT}
        tar xpfv ${STAGE_BALL} -C ${SYSROOT}
    fi

    portage_dirs="/etc/portage/package.keywords /etc/portage/package.mask /etc/portage/package.use"
    printf "${portage_dirs}\n" | tr ' ' '\n' | while read dir; do
        if [ ! -d ${dir} ]; then
            mv ${dir} ${dir}"_file"
            mkdir -p ${dir}
            mv ${dir}"_file" ${dir}
        fi
    done

    if prompt_input_yN "merge app-emulation/qemu"; then
        printf 'app-emulation/qemu static-user' > /etc/portage/package.use/qemu
        printf 'dev-libs/libpcre static-libs' >> /etc/portage/package.use/qemu
        printf 'sys-apps/attr static-libs' >> /etc/portage/package.use/qemu
        printf 'dev-libs/glib static-libs' >> /etc/portage/package.use/qemu
        printf 'sys-libs/zlib static-libs' >> /etc/portage/package.use/qemu
        if [ "$(grep QEMU_SOFT_MMU_TARGETS /etc/portage/make.conf)" = "" ]; then
            printf 'QEMU_SOFTMMU_TARGETS="arm"' >> /etc/portage/make.conf
        fi
        if [ "$(grep QEMU_USER_TARGETS /etc/portage/make.conf)" = "" ]; then
            printf 'QEMU_USER_TARGETS="arm"' >> /etc/portage/make.conf
        fi
        emerge app-emulation/qemu
    fi

    if prompt_input_yN "install static qemu binary on ${SYSROOT}"; then
        quickpkg app-emulation/qemu
        ROOT=${SYSROOT}/ emerge --usepkgonly --oneshot --nodeps qemu
    fi

    sysroot_mount ${SYSROOT}

    if prompt_input_yN "prepare the sysroot"; then
        if [ ! -f ${SYSROOT}/prepare.sh ]; then
            cat > ${SYSROOT}/prepare.sh << EOF
#!/bin/sh
passwd
printf '/dev/mapper/rpi-root    /           ext4    defaults,noatime,errors=remount-ro,discard   0 1' >  /etc/fstab
printf '/dev/mapper/rpi-swap    none        swap    defaults,noatime,discard                     0 0' >> /etc/fstab
echo "app-crypt/gnupg static" > /etc/portage/package.use
echo "sys-apps/util-linux static-libs" >> /etc/portage/package.use
echo "sys-fs/cryptsetup static-libs" >> /etc/portage/package.use
echo "sys-fs/lvm2 static static-libs" >> /etc/portage/package.use
echo "sys-libs/e2fsprogs-libs static-libs" >> /etc/portage/package.use
echo "=sys-kernel/genkernel-3.4.40.23 **" >> /etc/portage/package.accept_keywords
ego sync
sed -e 's/VERSION_GPG=\'1.4.11\'/VERSION_GPG=\'1.4.21\'/g' /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild > /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild.
mv /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild. /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild
ebuild /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild manifest
emerge -a "=app-crypt/gnupg-1.4.21" "=sys-kernel/genkernel-3.4.40.23" net-misc/dropbear net-misc/networkmanager net-misc/ntp net-wireless/wireless-tools sys-fs/cryptsetup sys-fs/lvm2 sys-kernel/raspberrypi-firmware
dispatch-conf
emerge "=app-crypt/gnupg-1.4.21" "=sys-kernel/genkernel-3.4.40.23" net-misc/dropbear net-misc/networkmanager net-misc/ntp net-wireless/wireless-tools sys-fs/cryptsetup sys-fs/lvm2 sys-kernel/raspberrypi-firmware
sed -e 's/GPG_VER="1.4.11"/GPG_VER="1.4.21"/g' /etc/genkernel.conf > /etc/genkernel.conf.
mv /etc/genkernel.conf. /etc/genkernel.conf
rc-update add NetworkManager default
rc-update add sshd default
rc-update add swclock boot
rc-update del hwclock boot
rc-update add ntp-client default
EOF
            chmod +x ${SYSROOT}/prepare.sh
        fi
        chroot ${SYSROOT} /bin/sh -c "/bin/sh /prepare.sh"
        rm ${SYSROOT}/prepare.sh
    fi

    if prompt_input_yN "merge crossdev"; then
        if [ "$(grep crossdev-99999999 /etc/portage/package.unmask)" = "" ]; then
            printf "=sys-devel/crossdev-99999999" >> /etc/portage/package.unmask
        fi
        if [ ! -d /etc/portage/package.keywords ]; then
            printf 'error: convert /etc/portage/package.keywords to a directory'
            return 1
        else
            printf "sys-devel/crossdev **" > /etc/portage/package.keywords/crossdev
        fi
        emerge crossdev
    fi

    if prompt_input_yN "build cross-${CTARGET} toolchain"; then
        if [ ! -d /var/git/gentoo ]; then
            git clone git://github.com/gentoo/gentoo.git /var/git/gentoo
        fi
        git --git-dir=/var/git/gentoo/.git --work-tree=/var/git/gentoo pull origin
        echo "gentoo" > /var/git/gentoo/profiles/repo_name
        cat > /etc/portage/repos.conf/gentoo << EOF
[gentoo]
location = /var/git/gentoo
sync-type = git
sync-uri = git://github.com/gentoo/gentoo.git
auto-sync = no
EOF
        cat > /etc/portage/repos.conf/crossdev << EOF
[crossdev]
location = /var/git/crossdev
masters = gentoo
auto-sync = no
use-manifests = true
thin-manifests = true
EOF
        mkdir -p /var/git/crossdev/profiles
        chown -R portage:portage /var/git/crossdev
        echo "crossdev" > /var/git/crossdev/profiles/repo_name
        rm -rf /var/git/crossdev/cross-${CTARGET}
        crossdev -S -oO /var/git/crossdev/ -t ${CTARGET}
        rm -f /etc/portage/repos.conf/{crossdev,gentoo}
    fi

    if [ ! -d ${SYSROOT}/usr/src/linux ]; then
        git clone https://github.com/raspberrypi/linux.git ${SYSROOT}/usr/src/linux
    fi

    if prompt_input_yN "clean and update sources from raspberrypi/linux"; then
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux clean -fdx
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux checkout master
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux fetch --all
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux branch -D rpi-4.9.y
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux checkout rpi-4.9.y
    fi

    if [ -f ${SYSROOT}/etc/kernels/arm.default ]; then
        cp ${SYSROOT}/etc/kernels/arm.default ${SYSROOT}/usr/src/linux/.config
    else
        mkdir -p ${SYSROOT}/etc/kernels
        cp ${dirname}/arm.default ${SYSROOT}/etc/kernels
    fi

    nproc=$(nproc)
    pwd=$(pwd)
    if [ ! -d ${SYSROOT}/usr/src/linux ]; then
        printf "error: no sources found in ${SYSROOT}/usr/src/linux\n"
        return 1
    fi
    cd ${SYSROOT}/usr/src/linux
    if prompt_input_yN "make bcm2709_defconfig"; then
        make -j${nproc} \
        ARCH=arm \
        CROSS_COMPILE=${CTARGET}- \
        bcm2709_defconfig
    fi

    if prompt_input_yN "make menuconfig"; then
        make -j${nproc} \
        ARCH=arm \
        CROSS_COMPILE=${CTARGET}- \
        MENUCONFIG_COLOR=mono \
        menuconfig
    fi

    if prompt_input_yN "build kernel"; then
        make -j${nproc} \
        ARCH=arm \
        CROSS_COMPILE=${CTARGET}- \
        zImage dtbs modules

        make -j${nproc} \
        ARCH=arm \
        CROSS_COMPILE=${CTARGET}- \
        INSTALL_MOD_PATH=${SYSROOT} \
        modules_install

        mkdir -p ${SYSROOT}/boot/overlays
        cp arch/arm/boot/dts/*.dtb ${SYSROOT}/boot/
        cp arch/arm/boot/dts/overlays/*.dtb* ${SYSROOT}/boot/overlays/
        cp arch/arm/boot/dts/overlays/README ${SYSROOT}/boot/overlays/
        scripts/mkknlimg arch/arm/boot/zImage ${SYSROOT}/boot/kernel7.img

        if prompt_input_yN "save new kernel config to /etc/kernels"; then
            cp .config ${SYSROOT}/etc/kernels/arm.default
        fi
    fi
    cd ${pwd}

    if prompt_input_yN "copy non-free firmware for brcm"; then
        if [ ! -d /usr/src/firmware-nonfree ]; then
            git clone --depth 1 https://github.com/RPi-Distro/firmware-nonfree /usr/src/firmware-nonfree
        fi
        git --git-dir=/usr/src/firmware-nonfree/.git --work-tree=/usr/src/linux-rpi-vanilla pull origin \
        mkdir -p ${SYSROOT}/lib/firmware/brcm
        find /usr/src/firmware-nonfree/ -name 'brcmfmac43430-sdio.*' -exec cp {} ${SYSROOT}/lib/firmware/brcm/ \;
    fi

    if prompt_input_yN "build initramfs"; then
        rm -f ${SYSROOT}/boot/*initramfs*
        rsync -avr --delete /usr/src/linux-rpi-vanilla/ ${SYSROOT}/usr/src/linux-rpi-vanilla/
        [ -L ${SYSROOT}/usr/src/linux ] && unlink ${SYSROOT}/usr/src/linux
        ln -s linux-rpi-vanilla ${SYSROOT}/usr/src/linux
        sed -e 's/#SSH="no"/SSH="YES"/g' ${SYSROOT}/etc/genkernel.conf > ${SYSROOT}/etc/genkernel.conf.
        mv ${SYSROOT}/etc/genkernel.conf. ${SYSROOT}/etc/genkernel.conf
        chroot ${SYSROOT} /bin/sh -c "genkernel --no-mountboot --lvm --luks --kernel-config=/usr/src/linux/.config initramfs"
        initramfs=$(ls ${SYSROOT}/boot | grep initramfs)
        printf "initramfs ${initramfs} followkernel" > ${SYSROOT}/boot/config.txt
    fi

    if prompt_input_yN "wipe and randomize ${SDCARD} bits"; then
        dd if=/dev/urandom of=${SDCARD} bs=1M status=progress
    fi

    if prompt_input_yN "write partition scheme to ${SDCARD}"; then
        if [ "$(mount | grep ${SDCARD})" != "" ]; then
            umount -Rl ${SDCARD}
        fi
        sfdisk --no-reread --wipe always ${SDCARD} << EOF
label: dos
unit: sectors
${SDCARD}p1 : start=        2048, size=     1048576, type=c
${SDCARD}p2 : start=     1050624, type=83
EOF
    fi

    if prompt_input_yN "format ${SDCARD}"; then
        cryptsetup luksFormat ${SDCARD}p2
        cryptsetup luksOpen ${SDCARD}p2 rpi

        pvcreate /dev/mapper/rpi
        vgcreate rpi /dev/mapper/rpi
        lvcreate --size 2GB --name swap rpi
        lvcreate --extents 95%FREE --name root rpi

        mkswap -L "swap" /dev/mapper/rpi-swap
        mkfs.ext4 /dev/mapper/rpi-root
        mkfs.vfat ${SDCARD}p1
    fi

    if prompt_input_yN "deploy ${SYSROOT} to ${SDCARD}"; then
        if [ "$(cryptsetup status rpi | grep 'is active')" = "" ]; then
            cryptsetup luksOpen ${SDCARD}p2 rpi
            if [ $? -ne 0 ]; then
                printf "error: could not open ${SDCARD}p2 luks partition"
                return 1
            fi
            vgchange --available y rpi
            if [ $? -ne 0 ]; then
                printf "error: could not make volumes available"
            fi
        fi

        mkdir -p /mnt/rpi
        mount /dev/mapper/rpi-root /mnt/rpi
        mkdir -p /mnt/rpi/boot
        mount ${SDCARD}p1 /mnt/rpi/boot
        umount -Rl ${SYSROOT}/{proc,sys,dev}

        SDCARD_BOOT_UUID=$(blkid -s UUID -o value ${SDCARD}p1)
        if [ "$(grep boot /etc/fstab)" = "" ]; then
            printf "UUID=${SDCARD_BOOT_UUID}          /boot           vfat            noauto,noatime  2 2" >> ${SYSROOT}/etc/fstab
        fi

        SDCARD_ROOT_UUID=$(blkid -s UUID -o value ${SDCARD}p2)
        printf "ro crypt_root=UUID=${SDCARD_ROOT_UUID} real_root=/dev/mapper/rpi-root dolvm rootfstype=ext4" > ${SYSROOT}/boot/cmdline.txt
        #printf "ro dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 crypt_root=UUID=${SDCARD_ROOT_UUID} root=/dev/mapper/rpi-root dolvm rootfstype=ext4 elevator=deadline rootwait" > ${SYSROOT}/boot/cmdline.txt

        if prompt_input_yN "use --delete on rsync for ${SDCARD} files"; then
            RSYNC_DELETE=--delete
        fi
        rsync -avr --exclude ${RSYNC_DELETE} "var/git/*" ${SYSROOT}/ /mnt/rpi/

        umount /mnt/rpi/boot
        umount /mnt/rpi
        vgchange --available n rpi
        cryptsetup luksClose rpi
    fi
}

