#!/bin/sh

CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

################################################################################
# Load Your Installation Settings
source ${CWD}/config

get_kernel_release() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CHOST}- make kernelrelease;)}
get_kernel_version() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CHOST}- make kernelversion;)}
set_kernel_extraversion() {(cd ${KERNEL_WORK}/linux; sed -i "s/EXTRAVERSION =.*/EXTRAVERSION = $@/" Makefile;)}

sysroot_install()
{
    if [ $(id -u) -ne 0 ]; then
        echo "error: must run as root"
        return 1
    fi

    ################################################################################
    # Install the Stage 3 Tarball

    SYSROOT=${SYSROOT_WORK}/${CHOST}
    STAGE3_ARCHIVE=/tmp/stage3-latest.tar.xz

    if [ -d ${SYSROOT} ]; then
        if prompt_input_yN "backup previous sysroot to ${SYSROOT}.old"; then
            mv ${SYSROOT} ${SYSROOT}.old
            mkdir -p ${SYSROOT}
        fi
    fi

    if prompt_input_yN "download stage3-latest for ARM architecture"; then
        [ -f ${STAGE3_ARCHIVE} ] && mv ${STAGE3_ARCHIVE} ${STAGE3_ARCHIVE}.bak
        wget ${STAGE_URL} -O ${STAGE3_ARCHIVE}
    fi

    if prompt_input_yN "extract ${STAGE3_ARCHIVE} in ${SYSROOT}"; then
        mkdir -p ${SYSROOT}
        tar xpfv ${STAGE3_ARCHIVE} -C ${SYSROOT}
    fi

    ################################################################################
    # Install the Firmware

    mkdir -p ${KERNEL_WORK}

    if [ ! -d ${KERNEL_WORK}/firmware]; then
        git clone --depth 1 git://github.com/raspberrypi/firmware/ ${KERNEL_WORK}/firmware
    fi

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

    ################################################################################
    # Configure Your System

    if prompt_input_yN "configure your system"; then
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

    ################################################################################
    # Install Binary Kernel, Modules and dtbs

    if prompt_input_yN "install pre-compiled current Raspberry Pi kernel, modules, dtbs and overlays"; then

        mkdir -p ${SYSROOT}/boot/overlays
        cp ${KERNEL_WORK}/firmware/boot/dts/*.dtb ${SYSROOT}/boot/
        cp ${KERNEL_WORK}/firmware/boot/dts/overlays/*.dtb* ${SYSROOT}/boot/overlays/
        cp ${KERNEL_WORK}/firmware/boot/dts/overlays/README ${SYSROOT}/boot/overlays/
        cp ${KERNEL_WORK}/firmware/boot/kernel7.img  ${SYSROOT}/boot/

    else 

    ################################################################################
    # Cross-compile Kernel, Modules and dtbs from Source

        if prompt_input_yN "install cross-${CHOST} toolchain and build kernel, modules, dtbs and overlays"; then

            portage_dirs="/etc/portage/package.keywords /etc/portage/package.mask /etc/portage/package.use"
            echo "${portage_dirs}" | tr ' ' '\n' | while read dir; do
                if [ ! -d ${dir} ]; then
                    mv ${dir} ${dir}"_file"
                    mkdir -p ${dir}
                    mv ${dir}"_file" ${dir}
                fi
            done

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
                    echo "=sys-devel/crossdev-99999999" >> /etc/portage/package.unmask
                fi
                if [ ! -d /etc/portage/package.keywords ]; then
                    echo "error: convert /etc/portage/package.keywords to a directory"
                    return 1
                else
                    echo "sys-devel/crossdev **" > /etc/portage/package.keywords/crossdev
                fi
                emerge -q crossdev
            fi

            crossdev -S --ov-gcc /var/git/overlay/crossdev -t ${CHOST}


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


            nproc=$(nproc)

            if [ ! -d ${KERNEL_WORK}/linux ]; then
                echo "error: no sources found in ${KERNEL_WORK}/linux"
                return 1
            fi

            cd ${KERNEL_WORK}/linux

            if prompt_input_yN "make bcm2709_defconfig"; then
                make -j${nproc} \
                ARCH=arm \
                CROSS_COMPILE=${CHOST}- \
                bcm2709_defconfig
            fi

            if prompt_input_yN "make menuconfig"; then
                make -j${nproc} \
                ARCH=arm \
                CROSS_COMPILE=${CHOST}- \
                MENUCONFIG_COLOR=mono \
                menuconfig
            fi

            if prompt_input_yN "build kernel"; then
                make -j${nproc} \
                ARCH=arm \
                CROSS_COMPILE=${CHOST}- \
                zImage dtbs modules

                make -j${nproc} \
                ARCH=arm \
                CROSS_COMPILE=${CHOST}- \
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
        else
            echo "are you sure you have a kernel installed to ${SYSROOT}"
        fi
    fi

    ################################################################################
    # Optionally Install Distcc via QEMU Chroot

    if prompt_input_yN "install distcc to the sysroot"; then

        if [ "$(lsmod | grep -E kvm_\(intel\|amd\))" = "" ]; then
            modprobe kvm_intel
            if [ $? -ne 0 ]; then
                echo "error: can't load kvm_intel kernel module"
                modprobe kvm_amd
                if [ $? -ne 0 ]; then
                    echo "error: can't load kvm_amd kernel module"
                    echo "please consult https://www.funtoo.org/KVM and try again"
                    return 1
                fi
            fi
            if ["$(groups $USER | grep kvm)" = ""]; then
                echo "add yourself to the kvm group and try again"
                return 1
            fi
            echo "loaded kvm kernel module"
        fi

        if [ "$(which qemu-arm 2>/dev/null)" != "/usr/bin/qemu-arm" ]; then

            echo "app-emulation/qemu static-user" > /etc/portage/package.use/qemu
            echo "dev-libs/libpcre static-libs" >> /etc/portage/package.use/qemu
            echo "sys-apps/attr static-libs" >> /etc/portage/package.use/qemu
            echo "dev-libs/glib static-libs" >> /etc/portage/package.use/qemu
            echo "sys-libs/zlib static-libs" >> /etc/portage/package.use/qemu
            if [ "$(grep QEMU_SOFT_MMU_TARGETS /etc/portage/make.conf)" = "" ]; then
                echo "QEMU_SOFTMMU_TARGETS=\"arm\"" >> /etc/portage/make.conf
            else
                echo "QEMU_SOFTMMU_TARGETS=\"\${QEMU_SOFTMMU_TARGETS} arm\"" >> /etc/portage/make.conf
            fi

            if [ "$(grep QEMU_USER_TARGETS /etc/portage/make.conf)" = "" ]; then
                echo 'QEMU_USER_TARGETS="arm"' >> /etc/portage/make.conf
            else
                echo 'QEMU_USER_TARGETS="${QEMU_USER_TARGETS} arm"' >> /etc/portage/make.conf
            fi

            emerge -q app-emulation/qemu

            quickpkg app-emulation/qemu
            ROOT=${SYSROOT}/ emerge -q --usepkgonly --oneshot --nodeps qemu
        fi


        cat > ${SYSROOT}/prepare.sh << EOF
#!/bin/sh
echo Emerging distcc
emerge -q distcc
echo Setting distcc symlinks
cd /usr/lib/distcc/bin
rm c++ g++ gcc cc
cat > ${CHOST} << EOF2
chmod a+x ${CHOST}-wrapper
ln -s ${CHOST}-wrapper cc
ln -s ${CHOST}-wrapper gcc
ln -s ${CHOST}-wrapper g++
ln -s ${CHOST}-wrapper c++
EOF2
cat > /etc/portage/make.conf << EOF2
MAKEOPTS = j4 -l${DISTCC_REMOTE_JOBS}
FEATURES=\"distcc distcc-pump\"
distcc-config --set-hosts \"${DISTCC_REMOTE_HOSTS}\"
EOF

        sysroot_mount ${SYSROOT}
        chmod +x ${SYSROOT}/prepare.sh
        chroot ${SYSROOT} /bin/sh -c "/bin/sh /prepare.sh"
        rm ${SYSROOT}/prepare.sh
        umount -Rl ${SYSROOT}/{proc,sys,dev}

    fi

    ################################################################################
    # Parition and Format an SDCard

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
        mkfs.ext4 ${SDCARD}2
        mkfs.vfat ${SDCARD}1
    fi

    ################################################################################
    # Deploy Installation to SDCard

    SDCARD=/dev/${SDCARD_DEV}
    
    if prompt_input_yN "deploy ${SYSROOT} to ${SDCARD}"; then

        mkdir -p /mnt/rpi
        mount ${SDCARD}2 /mnt/rpi
        mkdir -p /mnt/rpi/boot
        mount ${SDCARD}1 /mnt/rpi/boot

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
    fi

}

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
        echo "usage: sysroot-chroot path"
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
        echo "usage: sysroot-mount path"
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


