#!/bin/sh

source config.sh

get_kernel_release() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CTARGET}- make kernelrelease;)}
get_kernel_version() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CTARGET}- make kernelversion;)}
set_kernel_extraversion() {(cd ${KERNEL_WORK}/linux; sed -i "s/EXTRAVERSION =.*/EXTRAVERSION = $@/" Makefile;)}


prompt_input_yN()
{
    printf "$1? [y|N] " ; shift
    while true; do
        read YN
        case ${YN} in
            [Yy]* ) printf "\n"; return 0; break;;
            * ) printf "\n"; return 1; break;;
        esac
    done
}

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

    if prompt_input_yN "build cross-${CTARGET} toolchain"; then

        if [ ! -d /var/git/overlay/crossdev]; then
            mkdir -p /var/git/overlay
            cd /var/git/overlay
            git clone  https://github.com/funtoo/skeleton-overlay.git crossdev
            rm -rf /var/git/overlay/crossdev/.git
            echo "crossdev" > /var/git/overlay/crossdev/profiles/repo_name
        fi

        if [ ! -d /var/git/overlay/crossdev/.git]; then
            cd /var/git/overlay/crossdev
            git init
            git remote add origin git://github.com/gentoo/gentoo.git
            git config core.sparseCheckout true
            echo "sys-devel/gcc" > .git/info/sparse-checkout
            git pull --depth=1 origin master
            cat > /etc/portage/repos.conf/crossdev << EOF
[crossdev]
location = /var/git/overlay/crossdev
auto-sync = no
priority = 10
EOF
        fi

        if prompt_input_yN "merge crossdev"; then
            if [ "$(grep crossdev-99999999 /etc/portage/package.unmask)" = "" ]; then
                printf "=sys-devel/crossdev-99999999\n" >> /etc/portage/package.unmask
            fi
            if [ ! -d /etc/portage/package.keywords ]; then
                printf "error: convert /etc/portage/package.keywords to a directory\n"
                return 1
            else
                printf "sys-devel/crossdev **\n" > /etc/portage/package.keywords/crossdev
            fi
            emerge crossdev
        fi

        crossdev -S --ov-gcc /var/git/overlay/crossdev -t ${CTARGET}
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

        printf "app-emulation/qemu static-user\n" > /etc/portage/package.use/qemu
        printf "dev-libs/libpcre static-libs\n" >> /etc/portage/package.use/qemu
        printf "sys-apps/attr static-libs\n" >> /etc/portage/package.use/qemu
        printf "dev-libs/glib static-libs\n" >> /etc/portage/package.use/qemu
        printf "sys-libs/zlib static-libs\n" >> /etc/portage/package.use/qemu
        if [ "$(grep QEMU_SOFT_MMU_TARGETS /etc/portage/make.conf)" = "" ]; then
            printf "QEMU_SOFTMMU_TARGETS=\"arm\"\n" >> /etc/portage/make.conf
        else
            printf "QEMU_SOFTMMU_TARGETS=\"\${QEMU_SOFTMMU_TARGETS} arm\"\n" >> /etc/portage/make.conf
        fi

        if [ "$(grep QEMU_USER_TARGETS /etc/portage/make.conf)" = "" ]; then
            printf 'QEMU_USER_TARGETS="arm"' >> /etc/portage/make.conf
        else
            printf 'QEMU_USER_TARGETS="${QEMU_USER_TARGETS} arm"' >> /etc/portage/make.conf
        fi

        emerge app-emulation/qemu
    fi

    if prompt_input_yN "install static qemu binary on ${SYSROOT}"; then
        quickpkg app-emulation/qemu
        ROOT=${SYSROOT}/ emerge --usepkgonly --oneshot --nodeps qemu
    fi

    if prompt_input_yN "configure sysroot"; then
         cat > ${SYSROOT}/etc/portage/make.conf << EOF
FEATURES=\"\$\{FEATURES\} userfetch\"
PORTAGE_BINHOST=\"http://kantoo.org/funtoo/packages\"
EOF
        cat > ${SYSROOT}/boot/cmdline.txt << EOF
dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait
EOF
        sed -i "s/\/dev\/sda1.*/\/dev\/mmcblk0p1 \/boot vfat defaults 0 2/" ${SYSROOT}/etc/fstab 
        sed -i "s/\/dev\/sda2.*//" ${SYSROOT}/etc/fstab 
        sed -i "s/\/dev\/sda3.*/\/dev\/mmcblk0p2 \/ ext4  defaults 0 1/" ${SYSROOT}/etc/fstab 
        sed -i "s/\#\/dev\/cdrom.*//" ${SYSROOT}/etc/fstab


        echo "PermitRootLogin yes" >> ${SYSROOT}/etc/ssh/sshd_config

        sed -i "s/s0\:.*/\#&/" ${SYSROOT}/etc/inittab

        ln -sf /etc/init.d/swclock ${SYSROOT}/etc/runlevels/boot
        rm ${SYSROOT}/etc/runlevels/boot/hwclock
        mkdir -p ${SYSROOT}/lib/rc/cache
        touch ${SYSROOT}/lib/rc/cache/shutdowntime

        ln -sf /etc/init.d/sshd ${SYSROOT}/etc/runlevels/default
        ln -sf /etc/init.d/dhcpcd ${SYSROOT}/etc/runlevels/default

        echo "LDPATH=\"/opt/vc/lib\"" > ${SYSROOT}/etc/env.d/99vc

    fi
    sysroot_mount ${SYSROOT}

    if prompt_input_yN "prepare the sysroot"; then
        cat > ${SYSROOT}/prepare.sh << EOF
#!/bin/sh
#passwd
#printf '/dev/mapper/rpi-root    /           ext4    defaults,noatime,errors=remount-ro,discard   0 1' >  /etc/fstab
#printf '/dev/mapper/rpi-swap    none        swap    defaults,noatime,discard                     0 0' >> /etc/fstab
#echo "=sys-kernel/genkernel-3.4.40.23 **" > /etc/portage/package.accept_keywords
#echo ">app-crypt/gnupg-2" > /etc/portage/package.mask
#echo "app-crypt/gnupg static" > /etc/portage/package.use
#echo "sys-apps/util-linux static-libs" >> /etc/portage/package.use
#echo "sys-fs/cryptsetup static-libs" >> /etc/portage/package.use
#echo "sys-fs/lvm2 static static-libs" >> /etc/portage/package.use
#echo "sys-libs/e2fsprogs-libs static-libs" >> /etc/portage/package.use
#ego sync
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
#rc-update add NetworkManager default
#rc-update add ntp-client default
#rc-update add sshd default
#rc-update add swclock boot
#rc-update del hwclock boot
EOF
        if prompt_input_yN "install distcc to sysroot"; then
            cat >> ${SYSROOT} << EOF
echo Emerging distcc
emerge distcc
echo Setting distcc symlinks
cd /usr/lib/distcc/bin
rm c++ g++ gcc cc
cat > ${CTARGET} << EOF2
chmod a+x ${CTARGET}-wrapper
ln -s ${CTARGET}-wrapper cc
ln -s ${CTARGET}-wrapper gcc
ln -s ${CTARGET}-wrapper g++
ln -s ${CTARGET}-wrapper c++
EOF2
cat > /etc/portage/make.conf << EOF2
MAKEOPTS = j4 -l${DISTCC_REMOTE_JOBS}
FEATURES=\"distcc distcc-pump\"
distcc-config --set-hosts \"${DISTCC_REMOTE_HOSTS}\"
EOF

        fi

        chmod +x ${SYSROOT}/prepare.sh
        chroot ${SYSROOT} /bin/sh -c "/bin/sh /prepare.sh"
        rm ${SYSROOT}/prepare.sh
    fi


    mkdir -p ${KERNEL_WORK}

    if [ ! -d ${KERNEL_WORK}/firmware]; then
        git clone --depth 1 git://github.com/raspberrypi/firmware/ ${KERNEL_WORK}/firmware
    fi

    if [ ! -d ${KERNEL_WORK}/linux ]; then
        git clone https://github.com/raspberrypi/linux.git ${KERNEL_WORK}/linux
    fi

    if prompt_input_yN "clean and update sources from raspberrypi/linux"; then
        git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux clean -fdx
        git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux checkout master
        git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux fetch --all
        git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux branch -D ${RPI_KERN_BRANCH}
        git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux checkout ${RPI_KERN_BRANCH}
    fi

    if [ -f ${SYSROOT}/etc/kernels/arm.default ]; then
        cp ${SYSROOT}/etc/kernels/arm.default ${KERNEL_WORK}/linux/.config
    else
        mkdir -p ${SYSROOT}/etc/kernels
        cp ${dirname}/arm.default ${SYSROOT}/etc/kernels
    fi

    nproc=$(nproc)
    if [ ! -d ${KERNEL_WORK}/linux ]; then
        printf "error: no sources found in ${KERNEL_WORK}/linux\n"
        return 1
    fi
    cd ${KERNEL_WORK}/linux
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

        if prompt_input_yN "remove kernel headers and source"; then
            rm ${SYSROOT}/lib/modules/`get_kernel_release`/{build,source}
        fi

        if prompt_input_yN "save new kernel config to /etc/kernels"; then
            cp .config ${SYSROOT}/etc/kernels/arm.default
        fi
    fi

    cd -

    if prompt_input_yN "copy firmware"; then
        cp ${KERNEL_WORK}/firmware/boot/{bootcode.bin,fixup*.dat,start*.elf} ${SYSROOT}/boot
        cp -r ${KERNEL_WORK}/firmware/hardfp/opt ${SYSROOT}
    fi

    if prompt_input_yN "copy non-free wifi firmware for brcm"; then
        if [ ! -d ${KERNEL_WORK}/firmware-nonfree ]; then
            git clone --depth 1 https://github.com/RPi-Distro/firmware-nonfree ${KERNEL_WORK}/firmware-nonfree
        fi
        git --git-dir=${KERNEL_WORK}/firmware-nonfree/.git --work-tree=${KERNEL_WORK}/firmware-nonfree pull origin
        mkdir -p ${SYSROOT}/lib/firmware/brcm
        cp -r ${KERNEL_WORK}/firmware-nonfree/brcm/brcmfmac43430-sdio.{bin,txt} ${SYSROOT}/lib/firmware/brcm
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
#        cryptsetup luksFormat ${SDCARD}2
#        cryptsetup luksOpen ${SDCARD}2 rpi
#
#        pvcreate /dev/mapper/rpi
#        vgcreate rpi /dev/mapper/rpi
#        lvcreate --size 2GB --name swap rpi
#        lvcreate --extents 95%FREE --name root rpi
#
#        mkswap -L "swap" /dev/mapper/rpi-swap
#        mkfs.ext4 /dev/mapper/rpi-root
        mkfs.ext4 ${SDCARD}2
        mkfs.vfat ${SDCARD}1
#
#        export GPG_TTY=$(tty)
#        dd if=/dev/urandom bs=1024 count=512 | gpg --symmetric --cipher-algo AES256 --output ~/.ssh/rpi.gpg
#        echo RELOADAGENT | gpg-connect-agent
#        gpg --decrypt ~/.ssh/rpi.gpg > rpi
#        cryptsetup luksAddKey ${SDCARD}2 rpi
#        shred -u rpi
    fi

#    if [ ! -e ~/.ssh/id_rpi ]; then
#        ssh-keygen -f ~/.ssh/id_rpi -t rsa -N ''
#    fi
#    if [ ! -d ${SYSROOT}/root/.ssh ]; then
#        mkdir -p ${SYSROOT}/root/.ssh
#        ssh-keygen -y -f ~/.ssh/id_rpi > ${SYSROOT}/root/.ssh/authorized_keys
#    fi

    if prompt_input_yN "deploy ${SYSROOT} to ${SDCARD}"; then
#        if [ "$(cryptsetup status rpi | grep 'is active')" = "" ]; then
#            cryptsetup luksOpen ${SDCARD}2 rpi
#            if [ $? -ne 0 ]; then
#                printf "error: could not open ${SDCARD}2 luks partition"
#                return 1
#            fi
#            vgchange --available y rpi
#            if [ $? -ne 0 ]; then
#                printf "error: could not make volumes available"
#            fi
#        fi

        mkdir -p /mnt/rpi
#        mount /dev/mapper/rpi-root /mnt/rpi
        mount ${SDCARD}2 /mnt/rpi
        mkdir -p /mnt/rpi/boot
        mount ${SDCARD}1 /mnt/rpi/boot
        umount -Rl ${SYSROOT}/{proc,sys,dev}

#        SDCARD_BOOT_UUID=$(blkid -s UUID -o value ${SDCARD}1)
#        if [ "$(grep boot /etc/fstab)" = "" ]; then
#            printf "UUID=${SDCARD_BOOT_UUID}          /boot           vfat            noauto,noatime  2 2" >> ${SYSROOT}/etc/fstab
#        fi
#
#        SDCARD_ROOT_UUID=$(blkid -s UUID -o value ${SDCARD}2)
#        printf "ro crypt_root=UUID=${SDCARD_ROOT_UUID} dolvm real_root=/dev/mapper/rpi-root root=/dev/mapper/rpi-root rootfstype=ext4" > ${SYSROOT}/boot/cmdline.txt
#
        if prompt_input_yN "use --delete on rsync for ${SDCARD} files"; then
            RSYNC_DELETE=--delete
        fi
        rsync --archive \
              --verbose \
              --recursive \
              --exclude "var/git/*" \
            ${RSYNC_DELETE} \
            ${SYSROOT}/{boot,bin,etc,home,lib,mnt,opt,root,run,sbin,srv,tmp,usr,var,dev} \
            /mnt/rpi/

        umount /mnt/rpi/boot
        umount /mnt/rpi
#        vgchange --available n rpi
#        cryptsetup luksClose rpi
    fi

#    if [ "$(grep 'Host dropbear' ~/.ssh/config || grep 'Host rpi' ~/.ssh/config)" = "" ]; then
#        if prompt_input_yN "add dropbear and rpi hosts to ~/.ssh/config"; then
#            mkdir -p ~/.ssh
#            printf "what is the hostname? "
#            read ip
#            cat >> ~/.ssh/config << EOF
#Host dropbear
#    Hostname ${ip}
#    UserKnownHostsFile ~/.ssh/known_hosts.dropbear
#    IdentityFile ~/.ssh/id_dropbear
#    User root
#EOF
#            cat >> ~/.ssh/config << EOF
#Host rpi
#    Hostname ${ip}
#    UserKnownHostsFile ~/.ssh/known_hosts.rpi
#    IdentityFile ~/.ssh/id_rpi
#    User root
#EOF
#        fi
#    fi

#    printf "use this to unlock the root:\n"
#    printf "cat ~/.ssh/rpi.gpg | ssh dropbear post root; ssh dropbear\n\n"
}

