#!/bin/sh

dirname=$(dirname "$0")
source ${dirname}/prompt_input_yN/prompt_input_yN.sh

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
    #SDCARD_DEV=mmcblk0p
    SDCARD_DEV=sdb
    SDCARD=/dev/${SDCARD_DEV}
    STAGE_BALL=${HOME}/Downloads/stage3-latest.tar.xz
    STAGE_URL="http://ftp.osuosl.org/pub/funtoo/funtoo-current/arm-32bit/raspi3/stage3-latest.tar.xz"
    SYSROOT=/home/sysroots/${CTARGET}
    RPI_KERN_BRANCH=rpi-4.9.y

    if [ "$(lsmod | grep -E kvm_\(intel\|amd\))" = "" ]; then
        modprobe kvm_intel
        if [ $? -ne 0 ]; then
            printf "error: can't load kvm_intel kernel module\n"
            modprobe kvm_amd
            if [ $? -ne 0 ]; then
                printf "error: can't load kvm_amd kernel module\n"
                return 1;
            fi
        fi
        printf "loaded kvm kernel module\n"
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
#echo "=sys-kernel/genkernel-3.4.40.23 **" > /etc/portage/package.accept_keywords
#echo ">app-crypt/gnupg-2" > /etc/portage/package.mask
#echo "app-crypt/gnupg static" > /etc/portage/package.use
#echo "sys-apps/util-linux static-libs" >> /etc/portage/package.use
#echo "sys-fs/cryptsetup static-libs" >> /etc/portage/package.use
#echo "sys-fs/lvm2 static static-libs" >> /etc/portage/package.use
#echo "sys-libs/e2fsprogs-libs static-libs" >> /etc/portage/package.use
ego sync
#sed -e 's/VERSION_GPG=\'1.4.11\'/VERSION_GPG=\'1.4.21\'/g' /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild > /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild.
#mv /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild. /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild
#ebuild /var/git/meta-repo/kits/core-kit/sys-kernel/genkernel/genkernel-3.4.40.23.ebuild manifest
#emerge "=sys-kernel/genkernel-3.4.40.23" "=app-crypt/gnupg-1.4.21" app-admin/sudo app-editors/vim app-misc/tmux app-shells/zsh  net-misc/dropbear net-misc/networkmanager net-misc/ntp net-wireless/wireless-tools sys-fs/cryptsetup sys-fs/lvm2
#sed -e 's/GPG_VER="1.4.11"/GPG_VER="1.4.21"/g' /etc/genkernel.conf > /etc/genkernel.conf.
#mv /etc/genkernel.conf. /etc/genkernel.conf
#git clone https://github.com/raspberrypi/linux.git /usr/src/linux
#git clone --depth 1 git://github.com/raspberrypi/firmware/ /usr/src/firmware
#cp -r firmware/boot/* /boot
#cp -r firmware/modules /lib
rc-update add NetworkManager default
rc-update add ntp-client default
rc-update add sshd default
rc-update add swclock boot
rc-update del hwclock boot
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
        if [ ! -d /var/git/overlay/crossdev]; then
            mkdir -p /var/git/overlay
            cd /var/git/overlay
            git clone  https://github.com/funtoo/skeleton-overlay.git crossdev
            rm -rf /var/git/overlay/crossdev/.git
            echo "crossdev" > /var/git/overlay/crossdev/profiles/repo_name
        fi
        cd /var/git/overlay/crossdev
        git init
        git remote add origin git://github.com/gentoo/gentoo.git
        git config core.sparseCheckout true
        echo "sys-devel/gcc" >> .git/info/sparse-checkout
        git pull --depth=1 origin master
        cat > /etc/portage/repos.conf/crossdev << EOF
[crossdev]
location = /var/git/overlay/crossdev
auto-sync = no
priority = 10
EOF
        crossdev -S --ov-gcc /var/git/overlay/crossdev -t ${CTARGET}
    fi

    if prompt_input_yN "clean and update sources from raspberrypi/linux"; then
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux clean -fdx
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux checkout master
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux fetch --all
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux branch -D ${RPI_KERN_BRANCH}
        git --git-dir=${SYSROOT}/usr/src/linux/.git --work-tree=${SYSROOT}/usr/src/linux checkout ${RPI_KERN_BRANCH}
    fi

    if [ -f ${SYSROOT}/etc/kernels/arm.default ]; then
        cp ${SYSROOT}/etc/kernels/arm.default ${SYSROOT}/usr/src/linux/.config
    else
        mkdir -p ${SYSROOT}/etc/kernels
        cp ${dirname}/arm.default ${SYSROOT}/etc/kernels
    fi

    nproc=$(nproc)
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
    cd -

    if prompt_input_yN "copy non-free wifi firmware for brcm"; then
        if [ ! -d /usr/src/firmware-nonfree ]; then
            git clone --depth 1 https://github.com/RPi-Distro/firmware-nonfree ${SYSROOT}/usr/src/firmware-nonfree
        fi
        git --git-dir=${SYSROOT}/usr/src/firmware-nonfree/.git --work-tree=${SYSROOT}/usr/src/firmware-nonfree pull origin \
        mkdir -p ${SYSROOT}/lib/firmware/brcm
        cp -r ${SYSROOT}/usr/src/firmware-nonfree/brcm/* ${SYSROOT}/lib/firmware/brcm
    fi

#    if prompt_input_yN "build initramfs"; then
#        rm -f ${SYSROOT}/boot/*initramfs*
#        patch /usr/share/genkernel/defaults/initrd.scripts ${dirname}/initrd.scripts.patch
#        patch /usr/share/genkernel/defaults/login-remote.sh ${dirname}/login-remote.sh.patch
#        sed -e 's/#SSH="no"/SSH="YES"/g' ${SYSROOT}/etc/genkernel.conf > ${SYSROOT}/etc/genkernel.conf.
#        mv ${SYSROOT}/etc/genkernel.conf. ${SYSROOT}/etc/genkernel.conf
#        [ ! -f ~/.ssh/id_dropbear ] && ssh-keygen -f ~/.ssh/id_dropbear -t rsa -N ''
#        ssh-keygen -y -f ~/.ssh/id_dropbear > ${SYSROOT}/etc/dropbear/authorized_keys
#        chroot ${SYSROOT} /bin/sh -c "genkernel --no-mountboot --gpg --lvm --luks --disklabel --kerneldir=/usr/src/linux --kernel-config=/usr/src/linux/.config initramfs"
#        printf "\n* Use ~/.ssh/id_dropbear to ssh into the initramfs.\n"
#        initramfs=$(ls ${SYSROOT}/boot | grep initramfs)
#        printf "initramfs ${initramfs} followkernel" > ${SYSROOT}/boot/config.txt
#    fi

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
${SDCARD}1 : start=        2048, size=     1048576, type=c
${SDCARD}2 : start=     1050624, type=83
EOF
    fi

    if prompt_input_yN "format ${SDCARD}"; then
        cryptsetup luksFormat ${SDCARD}2
        cryptsetup luksOpen ${SDCARD}2 rpi

        pvcreate /dev/mapper/rpi
        vgcreate rpi /dev/mapper/rpi
        lvcreate --size 2GB --name swap rpi
        lvcreate --extents 95%FREE --name root rpi

        mkswap -L "swap" /dev/mapper/rpi-swap
        mkfs.ext4 /dev/mapper/rpi-root
        mkfs.vfat ${SDCARD}1

        export GPG_TTY=$(tty)
        dd if=/dev/urandom bs=1024 count=512 | gpg --symmetric --cipher-algo AES256 --output ~/.ssh/rpi.gpg
        echo RELOADAGENT | gpg-connect-agent
        gpg --decrypt ~/.ssh/rpi.gpg > rpi
        cryptsetup luksAddKey ${SDCARD}2 rpi
        shred -u rpi
    fi

    if [ ! -e ~/.ssh/id_rpi ]; then
        ssh-keygen -f ~/.ssh/id_rpi -t rsa -N ''
    fi
    if [ ! -d ${SYSROOT}/root/.ssh ]; then
        mkdir -p ${SYSROOT}/root/.ssh
        ssh-keygen -y -f ~/.ssh/id_rpi > ${SYSROOT}/root/.ssh/authorized_keys
    fi

    if prompt_input_yN "deploy ${SYSROOT} to ${SDCARD}"; then
        if [ "$(cryptsetup status rpi | grep 'is active')" = "" ]; then
            cryptsetup luksOpen ${SDCARD}2 rpi
            if [ $? -ne 0 ]; then
                printf "error: could not open ${SDCARD}2 luks partition"
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
        mount ${SDCARD}1 /mnt/rpi/boot
        umount -Rl ${SYSROOT}/{proc,sys,dev}

        SDCARD_BOOT_UUID=$(blkid -s UUID -o value ${SDCARD}1)
        if [ "$(grep boot /etc/fstab)" = "" ]; then
            printf "UUID=${SDCARD_BOOT_UUID}          /boot           vfat            noauto,noatime  2 2" >> ${SYSROOT}/etc/fstab
        fi

        SDCARD_ROOT_UUID=$(blkid -s UUID -o value ${SDCARD}2)
        printf "ro crypt_root=UUID=${SDCARD_ROOT_UUID} dolvm real_root=/dev/mapper/rpi-root root=/dev/mapper/rpi-root rootfstype=ext4" > ${SYSROOT}/boot/cmdline.txt

        if prompt_input_yN "use --delete on rsync for ${SDCARD} files"; then
            RSYNC_DELETE=--delete
        fi
        rsync --archive \
              --verbose \
              --recursive \
              --exclude "var/git/*" \
            ${RSYNC_DELETE} \
            ${SYSROOT}/ /mnt/rpi/

        umount /mnt/rpi/boot
        umount /mnt/rpi
        vgchange --available n rpi
        cryptsetup luksClose rpi
    fi

    if [ "$(grep 'Host dropbear' ~/.ssh/config || grep 'Host rpi' ~/.ssh/config)" = "" ]; then
        if prompt_input_yN "add dropbear and rpi hosts to ~/.ssh/config"; then
            mkdir -p ~/.ssh
            printf "what is the hostname? "
            read ip
            cat >> ~/.ssh/config << EOF
Host dropbear
    Hostname ${ip}
    UserKnownHostsFile ~/.ssh/known_hosts.dropbear
    IdentityFile ~/.ssh/id_dropbear
    User root
EOF
            cat >> ~/.ssh/config << EOF
Host rpi
    Hostname ${ip}
    UserKnownHostsFile ~/.ssh/known_hosts.rpi
    IdentityFile ~/.ssh/id_rpi
    User root
EOF
        fi
    fi

    printf "use this to unlock the root:\n"
    printf "cat ~/.ssh/rpi.gpg | ssh dropbear post root; ssh dropbear\n\n"
}

