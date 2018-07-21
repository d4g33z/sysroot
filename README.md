# Raspberry Pi Funtoo Sysroot Creation 

See https://www.funtoo.org/Funtoo_Linux_Installation_on_RPI

This is a originally a fork of rbmarliere/sysroot.git.

This script is used on Funtoo to automate the boring task of setting up a Raspberry Pi 3 cross environment and a full working sysroot with a custom kernel build that can be easily deployed on a SD card.

Review the variables on the sysroot_install function and, for the first time running it, you should answer 'y' for every question:

```sh
. sysroot.sh
```
