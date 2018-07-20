# Raspberry Pi Funtoo Sysroot Creation 

This script is used on Funtoo to automate the boring task of setting up a Raspberry Pi 3 cross environment and a full working sysroot with a custom kernel build that can be easily deployed on a SD card.

Review the variables on the sysroot_install function and, for the first time running it, you should answer 'y' for every question:

```sh
. sysroot.sh
```

This creates a sysroot on the default path /home/sysroots/armv7a-hardfloat-linux-gnueabi and you can use sysroot_chroot to grab a shell inside it:

sysroot_chroot /home/sysroots/armv7a-hardfloat-linux-gnueabi

The third function, sysroot_mount, is a dependency for both.
