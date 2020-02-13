#!/bin/sh

XX='\e[0m'
BO='\e[1m'
UL='\e[4m'

RED='\e[31m'
GRE='\e[32m'
MAG='\e[35m'
YEL='\e[33m'

CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${CWD}/config

sysroot_install()
{
    if [ $(id -u) -ne 0 ]; then
        echo "error: must run as root"
        return 1
    fi

    ################################################################################
    echo -e $UL$MAG"Create Your Installation Settings"
    echo -e $XX

    for ((i=0; i< ${#INSTALL_VARS[@]}; i++)); do
            echo -e $BO${INSTALL_VARS[$i]} = ${!INSTALL_VARS[$i]};
    done;
    echo -e $XX

    if prompt_input_yN "does this look right"; then
        echo "Ok, running sysroot_install"
    else
        echo "Fix it and try again"
        return 1
    fi


    ################################################################################
    echo -e $UL$MAG"Install the Stage 3 Tarball"
    echo -e $XX
    SYSROOT=${SYSROOT_WORK}/${CHOST}
    STAGE3_ARCHIVE="/tmp/$(basename $STAGE3_URL)"
    #STAGE3_GPG="$(wget -qO- ${STAGE3_URL}.gpg)"
    STAGE3_GPG=${STAGE3_ARCHIVE}.gpg

    if [ -d ${SYSROOT} ]; then
        if prompt_input_yN "backup previous sysroot to ${SYSROOT}.old"; then
            sysroot_unique_backup ${SYSROOT}
        fi
        if prompt_input_yN "totally remove your previous sysroot"; then
            rm -rf ${SYSROOT}
        fi
        
    fi
    if [ ! -d ${SYSROOT} ]; then
        mkdir ${SYSROOT}
        if [ -f ${STAGE3_ARCHIVE} ]; then
            wget ${STAGE3_URL}.gpg -O ${STAGE3_GPG}
            #check for drobbins trust
            if [ "$(gpg --list-public-keys | grep D3B948F82EE8B4020A0410789A658306E986E8EE -)" = "" ]; then
                gpg --recv-key E986E8EE
            fi
            #check for arm32 trust
            if [ "$(gpg --list-public-keys | grep 38E84AD53B01590BA6785E882A7B0B2EEEE54A43 -)" = "" ]; then
                gpg --recv-key EEE54A43 
            fi
            if [ "$(gpg --trust-model always --verify ${STAGE3_GPG} ${STAGE3_ARCHIVE} 2>&1 | grep BAD)" != "" ]; then
                echo "gpg verification failed. Download a new stage 3 archive"
                if prompt_input_yN "download new stage3-latest for ARM architecture"; then
                    sysroot_unique_backup ${STAGE3_ARCHIVE}
                    wget ${STAGE3_URL} -O ${STAGE3_ARCHIVE}
                fi
            fi
        else
            if prompt_input_yN "download new stage3-latest for ARM architecture"; then
                wget ${STAGE3_URL} -O ${STAGE3_ARCHIVE}
            fi

        fi
        if prompt_input_yN "extract ${STAGE3_ARCHIVE} in ${SYSROOT}"; then
            tar xpfv ${STAGE3_ARCHIVE} -C ${SYSROOT}
        fi

    fi

    ################################################################################
    echo -e $UL$MAG"Install the Firmware"
    echo -e $XX


    if [ ! -d ${KERNEL_WORK}/firmware ]; then
        git clone --depth=1 git://github.com/raspberrypi/firmware/ ${KERNEL_WORK}/firmware
    fi


    if prompt_input_yN "update the firmware repos"; then
		sysroot_update_firmware_repos
	fi

    if prompt_input_yN "copy firmware"; then
        cp ${KERNEL_WORK}/firmware/boot/{bootcode.bin,fixup*.dat,start*.elf} ${SYSROOT}/boot
        cp -r ${KERNEL_WORK}/firmware/hardfp/opt ${SYSROOT}
    fi

    if prompt_input_yN "copy non-free wifi firmware for brcm"; then
        if [ ! -d ${KERNEL_WORK}/firmware-nonfree ]; then
            git clone --depth=1 https://github.com/RPi-Distro/firmware-nonfree ${KERNEL_WORK}/firmware-nonfree
        fi
        git --git-dir=${KERNEL_WORK}/firmware-nonfree/.git --work-tree=${KERNEL_WORK}/firmware-nonfree pull origin
        mkdir -p ${SYSROOT}/lib/firmware/brcm
        cp -r ${KERNEL_WORK}/firmware-nonfree/brcm/brcmfmac43430-sdio.{bin,txt} ${SYSROOT}/lib/firmware/brcm
        cp -r ${KERNEL_WORK}/firmware-nonfree/brcm/brcmfmac43455-sdio.{bin,txt,clm_blob} ${SYSROOT}/lib/firmware/brcm
    fi

    ################################################################################
    echo -e $UL$MAG"Configure Your System"
    echo -e $XX

    if prompt_input_yN "configure your system"; then

        ################################################################################
        #Set Up Mount Points
        sed -i "s/\/dev\/sda1.*/\/dev\/mmcblk0p1 \/boot vfat defaults 0 2/" ${SYSROOT}/etc/fstab 
        sed -i "s/\/dev\/sda2.*//" ${SYSROOT}/etc/fstab 
        sed -i "s/\/dev\/sda3.*/\/dev\/mmcblk0p2 \/ ext4  defaults 0 1/" ${SYSROOT}/etc/fstab 
        sed -i "s/\#\/dev\/cdrom.*//" ${SYSROOT}/etc/fstab

        ################################################################################
        # Set Up Root Password
        echo "Please enter a root password for the Raspberry Pi"
        sed -i "s|root\:\*|root\:$(openssl passwd -1)|" $SYSROOT/etc/shadow

        ################################################################################
        # Set Up Networking
        ln -sf /etc/init.d/dhcpcd ${SYSROOT}/etc/runlevels/default

        ################################################################################
        # Set Up SSH Access
        echo "PermitRootLogin yes" >> ${SYSROOT}/etc/ssh/sshd_config
        ln -sf /etc/init.d/sshd ${SYSROOT}/etc/runlevels/default

        ################################################################################
        # Set Up Software Clock
        ln -sf /etc/init.d/swclock ${SYSROOT}/etc/runlevels/boot
        rm ${SYSROOT}/etc/runlevels/boot/hwclock
        mkdir -p ${SYSROOT}/lib/rc/cache
        touch ${SYSROOT}/lib/rc/cache/shutdowntime


        ################################################################################
        # Disable Serial Console Access
        sed -i "s/s0\:.*/\#&/" ${SYSROOT}/etc/inittab


        ################################################################################
        # Link to Accelerated Video Libraries
        echo "LDPATH=\"/opt/vc/lib\"" > ${SYSROOT}/etc/env.d/99vc

        ################################################################################
        # Configure the Boot Parameters
        cat > ${SYSROOT}/boot/cmdline.txt << EOF
dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait
EOF

    fi

    ################################################################################
    echo -e $UL$MAG"Install Binary Kernel, Modules and dtbs"
    echo -e $XX
    if prompt_input_yN "install pre-compiled binary Raspberry Pi kernel, modules, dtbs and overlays"; then

        mkdir -p ${SYSROOT}/boot/overlays
        cp -r ${KERNEL_WORK}/firmware/boot ${SYSROOT}
        cp ${KERNEL_WORK}/firmware/boot/overlays/*.dtb* ${SYSROOT}/boot/overlays
        cp ${KERNEL_WORK}/firmware/boot/overlays/README ${SYSROOT}/boot/overlays
        cp ${KERNEL_WORK}/firmware/boot/kernel7.img  ${SYSROOT}/boot
        mkdir -p ${SYSROOT}/lib/modules
        cp -r ${KERNEL_WORK}/firmware/modules/* ${SYSROOT}/lib/modules
    fi

    ################################################################################
    echo -e $UL$MAG"Cross-compile Kernel, Modules and dtbs from Source"
    echo -e $XX
    if prompt_input_yN "build and install from source Raspberry Pi kernel, modules, dtbs and overlays"; then

        ################################################################################
        # Install Crossdev
        if prompt_input_yN "install Crossdev"; then
    
            # Check for directory structure in 
            portage_dirs="/etc/portage/package.keywords /etc/portage/package.mask /etc/portage/package.use"
            echo "${SYSROOT}/${portage_dirs}" | tr ' ' '\n' | while read dir; do
                if [ ! -d ${dir} ]; then
                    mv ${dir} ${dir}"_file"
                    mkdir -p ${dir}
                    mv ${dir}"_file" ${dir}
                fi
            done

            # Make a Local Overlay
            if [ ! -d /var/git/overlay/crossdev ]; then
                mkdir -p /var/git/overlay
                cd /var/git/overlay
                echo -e $YEL"now in $PWD"
                echo -e $XX
                git clone  https://github.com/funtoo/skeleton-overlay.git crossdev
                rm -rf /var/git/overlay/crossdev/.git
                echo "crossdev" > /var/git/overlay/crossdev/profiles/repo_name
                cat > /etc/portage/repos.conf/crossdev << EOF
[crossdev]
location = /var/git/overlay/crossdev
auto-sync = no
priority = 10
EOF
 
            fi

            #Sparse Checkout Gentoo GCC Ebuilds
            if [ ! -d /var/git/overlay/crossdev/.git ]; then
                cd /var/git/overlay/crossdev
                echo -e $YEL"now in $PWD"
                echo -e $XX
                git init
                git remote add origin git://github.com/gentoo/gentoo.git
                git config core.sparseCheckout true
                echo "sys-devel/gcc" > .git/info/sparse-checkout
                git pull --depth=1 origin master
            fi

            #Unmask and Emerge Crossdev
            if prompt_input_yN "emerge crossdev"; then
                if [ "$(grep crossdev-99999999 /etc/portage/package.unmask/crossdev)" = "" ]; then
                    echo "=sys-devel/crossdev-99999999" >> /etc/portage/package.unmask/crossdev
                fi
                if [ ! -d /etc/portage/package.keywords ]; then
                    echo "error: convert /etc/portage/package.keywords to a directory"
                    return 1
                else
                    if [ "$(grep crossdev-99999999 /etc/portage/package.keywords/crossdev)" = "" ]; then
                        echo "sys-devel/crossdev **" > /etc/portage/package.keywords/crossdev
                    fi
                fi
                emerge -q crossdev
            fi
        fi

        ################################################################################
        # Install Cross Compilation Tool Chain
        if prompt_input_yN "install cross-${CHOST} toolchain"; then
            crossdev -S --ov-gcc /var/git/overlay/crossdev -t ${CHOST}

        fi

        ################################################################################
        # Retrive Raspberry Pi Kernel Sources
        if prompt_input_yN "Retrieve Raspberry Pi Kernel Sources"; then
            if [ ! -d ${KERNEL_WORK}/linux ]; then
                git clone https://github.com/raspberrypi/linux.git ${KERNEL_WORK}/linux
            fi
        fi 
        ################################################################################
        #Clean and Update Kernel Sources
        if prompt_input_yN "clean and update sources from raspberrypi/linux"; then
            git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux clean -fdx
            git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux checkout master
            git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux fetch --all
            git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux branch -D ${RPI_KERN_BRANCH}
            git --git-dir=${KERNEL_WORK}/linux/.git --work-tree=${KERNEL_WORK}/linux checkout ${RPI_KERN_BRANCH}
        fi



        if [ ! -d ${KERNEL_WORK}/linux ]; then
            echo "error: no sources found in ${KERNEL_WORK}/linux"
            return 1
        fi

        ################################################################################
        # Make the Default Config
        cd ${KERNEL_WORK}/linux
        echo -e $YEL"now in $PWD"
        echo -e $XX
        if prompt_input_yN "make bcm2709_defconfig"; then
            make -j$(nproc) \
            ARCH=arm \
            CROSS_COMPILE=${CHOST}- \
            bcm2709_defconfig
        fi

        ################################################################################
        # Configure the Kernel
        if prompt_input_yN "make menuconfig"; then
            make -j$(nproc) \
            ARCH=arm \
            CROSS_COMPILE=${CHOST}- \
            MENUCONFIG_COLOR=mono \
            menuconfig
        fi

        ################################################################################
        # Build and Install the Kernel
        if prompt_input_yN "build kernel"; then
            make -j$(nproc) \
            ARCH=arm \
            CROSS_COMPILE=${CHOST}- \
            zImage dtbs modules

            make -j$(nproc) \
            ARCH=arm \
            CROSS_COMPILE=${CHOST}- \
            INSTALL_MOD_PATH=${SYSROOT} \
            modules_install

            mkdir -p ${SYSROOT}/boot/overlays
            cp arch/arm/boot/dts/*.dtb ${SYSROOT}/boot/
            cp arch/arm/boot/dts/overlays/*.dtb* ${SYSROOT}/boot/overlays/
            cp arch/arm/boot/dts/overlays/README ${SYSROOT}/boot/overlays/

            scripts/mkknlimg arch/arm/boot/zImage ${SYSROOT}/boot/kernel7.img

            ################################################################################
            # Remove Kernel Headers and Source Links
            if prompt_input_yN "remove kernel headers and source"; then
                rm ${SYSROOT}/lib/modules/`get_kernel_release`/{build,source}
            fi

            ################################################################################
            # Backup Kernel Config
            if prompt_input_yN "backup new kernel config"; then

                mkdir -p ${SYSROOT}/etc/kernels
                sysroot_unique_backup .config ${SYSROOT}/etc/kernels
            fi
        cd -
        echo -e $YEL"now in $PWD"
        echo -e $XX
        fi
    fi
    ################################################################################
    echo -e $UL$MAG"Use QEMU"
    echo -e $XX

    if prompt_input_yN "use QEMU"; then

        if prompt_input_yN "install a QEMU chroot"; then

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

            fi
            quickpkg app-emulation/qemu
            ROOT=${SYSROOT}/ emerge -q --usepkgonly --oneshot --nodeps qemu
        fi
        if prompt_input_yN "test QEMU chroot"; then
            cat > /tmp/test_chroot.sh << EOF
ego profile
EOF
            sysroot_run_in_chroot ${SYSROOT} /tmp/test_chroot.sh
        fi
    fi

    ################################################################################
    echo -e $UL$MAG"Parition and Format SDCard"
    echo -e $XX
    SDCARD=/dev/${SDCARD_DEV}
    if prompt_input_yN "partition and format ${SDCARD}";then

        ################################################################################
        # Randomize SDCard
        if prompt_input_yN "wipe and randomize ${SDCARD} bits"; then
            dd if=/dev/urandom of=${SDCARD} bs=1M status=progress
        fi

        ################################################################################
        # Write Parition Scheme to SDCard
        if prompt_input_yN "write partition scheme to ${SDCARD}"; then
            sysroot_partition_sdcard
        fi
        ################################################################################
        # Format SDCard
        if prompt_input_yN "format ${SDCARD}"; then
            mkfs.ext4 ${SDCARD}2
            mkfs.vfat ${SDCARD}1
        fi
    fi
    ################################################################################
    echo -e $UL$MAG"Deploy Installation to SDCard"
    echo -e $XX
    if prompt_input_yN "deploy ${SYSROOT} to ${SDCARD}"; then

#        mkdir -p /mnt/rpi
#        mount ${SDCARD}2 /mnt/rpi
#        mkdir -p /mnt/rpi/boot
#        mount ${SDCARD}1 /mnt/rpi/boot

        sysroot_mount_sdcard ${SDCARD} /mnt/rpi

        if prompt_input_yN "use --delete on rsync for ${SDCARD} files"; then
            RSYNC_DELETE=--delete
        fi
        rsync --archive \
              --verbose \
              --recursive \
              --exclude "var/git/*" \
            ${RSYNC_DELETE} \
            ${SYSROOT}/{boot,bin,etc,home,lib,mnt,opt,root,run,sbin,srv,tmp,usr,var,dev,proc,sys} \
            /mnt/rpi/

#        umount /mnt/rpi/boot
#        umount /mnt/rpi

        sysroot_umount_sdcard /mnt/rpi

    fi
    cd -

}

prompt_input_yN()
{
    echo -e "$1? [${GRE}y|${RED}N${XX}] " ; shift
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
    env -i HOME=/root TERM=$TERM /bin/chroot $1 bash -l
    sysroot_umount $1 || return 1
}

sysroot_run_in_chroot()
{
    if [ $# -lt 2 ]; then
        echo "usage: sysroot-chroot path shell_cmds_file"
        return 1
    fi
    cat $2 > $1/root/sysroot_run_in_chroot.sh
    sysroot_mount $1 || return 1
    chmod +x $1/root/sysroot_run_in_chroot.sh
    env -i HOME=/root TERM=$TERM /bin/chroot $1 /bin/sh /root/sysroot_run_in_chroot.sh
    rm $1/root/sysroot_run_in_chroot.sh
    sysroot_umount $1 || return 1
}

sysroot_install_distcc() {
    cat > /tmp/install_distcc_in_chroot.sh << EOF
emerge distcc
cd /usr/lib/distcc/bin
rm c++ g++ gcc cc
cat > ${CHOST}-wrapper << EOF2
#!/bin/bash
exec /usr/lib/distcc/bin/${CHOST}-g\${0:$[-2]} "\$@"
EOF2
ln -s ${CHOST}-wrapper cc
ln -s ${CHOST}-wrapper gcc
ln -s ${CHOST}-wrapper g++
ln -s ${CHOST}-wrapper c++

EOF
   sysroot_run_in_chroot $1 /tmp/install_distcc_in_chroot.sh

}

sysroot_mount()
{
    if [ $# -lt 1 ]; then
        echo "usage: sysroot-mount path"
        return 1
    fi
#    if [ "$(mount | grep $1)" != "" ]; then
#        return 0
#    fi
    if [ "$(/etc/init.d/qemu-binfmt status | grep started)" = "" ]; then
        /etc/init.d/qemu-binfmt start
    fi
    cp /etc/resolv.conf $1/etc/resolv.conf
    mkdir -p $1/dev  && mount --bind /dev $1/dev
    mkdir -p $1/proc && mount --bind /proc $1/proc
    mkdir -p $1/sys  && mount --bind /sys $1/sys

}

sysroot_umount()
{

    umount $1/dev
    umount $1/proc
    umount $1/sys
}

sysroot_unique_backup()
{

    if [ $# -lt 1 ]; then
        echo "usage: sysroot_unique_backup path [desination]"
        return 1
    fi

    today="$( date +"%Y%m%d" )"
    number=0


    if [ -z $2 ]; then
        while test -e "$1-$today$suffix.txt"; do
            (( ++number ))
            suffix="$( printf -- '-%02d' "$number" )"
        done

        fname="$1-$today$suffix"

    else
        while test -e "$2/`basename $1`-$today$suffix.txt"; do
            (( ++number ))
            suffix="$( printf -- '-%02d' "$number" )"
        done

        fname="$2/`basename $1`-$today$suffix.txt"

    fi

    cp -r $1 "$fname"
}

sysroot_mount_sdcard()
{
    mkdir -p ${2}
    mount ${1}2 ${2}
    mkdir -p ${2}/boot
    mount ${1}1 ${2}/boot

}

sysroot_umount_sdcard()
{
    umount ${1}/boot
    umount ${1}

}

sysroot_partition_sdcard()
{

    SDCARD=/dev/${SDCARD_DEV}

    if [ "$(mount | grep ${SDCARD})" != "" ]; then
        umount -Rl ${SDCARD}
    fi
    if [ ! -z "$1" ]; then
        sfdisk --no-reread --wipe always ${SDCARD} << EOF
label: dos
unit: sectors
${SDCARD}1 : start=        2048, size=     1048576, type=c
${SDCARD}2 : start=     1050624, size=          $1, type=83
EOF
    else
        sfdisk --no-reread --wipe always ${SDCARD} << EOF
label: dos
unit: sectors
${SDCARD}1 : start=        2048, size=     1048576, type=c
${SDCARD}2 : start=     1050624, type=83
EOF
    fi
}

get_kernel_release() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CHOST}- make kernelrelease;)}
get_kernel_version() {(cd ${KERNEL_WORK}/linux; ARCH=arm CROSS_COMPILE=${CHOST}- make kernelversion;)}
set_kernel_extraversion() {(cd ${KERNEL_WORK}/linux; sed -i "s/EXTRAVERSION =.*/EXTRAVERSION = $@/" Makefile;)}

sysroot_update_firmware_repos()
{
		git --git-dir=${KERNEL_WORK}/firmware/.git --work-tree=${KERNEL_WORK}/firmware fetch --depth=1
		git --git-dir=${KERNEL_WORK}/firmware/.git --work-tree=${KERNEL_WORK}/firmware pull

    	if [ -d ${KERNEL_WORK}/firmware-nonfree ]; then
			git --git-dir=${KERNEL_WORK}/firmware-nonfree/.git --work-tree=${KERNEL_WORK}/firmware-nonfree fetch --depth=1
			git --git-dir=${KERNEL_WORK}/firmware-nonfree/.git --work-tree=${KERNEL_WORK}/firmware-nonfree pull
		fi
}

sysroot_sync()
{
    if [ $# -lt 1 ]; then
        echo "usage: sysroot_sync [USER]@HOST"
        return 1
    fi

    echo -e $UL$MAG"Sync Installation to Running Pi"
    echo -e $XX
    if prompt_input_yN "deploy ${SYSROOT} to $1 via ssh?"; then

        if prompt_input_yN "use --delete on rsync for ${SDCARD} files"; then
            RSYNC_DELETE=--delete
        fi
        echo rsync -e "ssh" \
              --archive \
              --verbose \
              --recursive \
              --exclude "var/git/*" \
            ${RSYNC_DELETE} \
            ${SYSROOT}/{boot,bin,etc,home,lib,mnt,opt,root,run,sbin,srv,tmp,usr,var,dev,proc,sys} \
            $1:/


    fi

}
