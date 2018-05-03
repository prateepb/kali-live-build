#!/bin/bash
#
# http://docs.kali.org/downloading/kali-linux-live-usb-install
# http://docs.kali.org/downloading/kali-linux-live-usb-persistence

DEVICE="/dev/sdb"

if [ "$1" != "fuckyes" ]; then
    exit 1
fi

dosfslabel ${DEVICE}2 KALI-BOOT
dosfslabel ${DEVICE}3 KALI-DATA

cryptsetup --verbose --verify-passphrase luksFormat ${DEVICE}4
cryptsetup luksOpen ${DEVICE}4 my_usb
mkfs.ext3 -L persistence /dev/mapper/my_usb
e2label /dev/mapper/my_usb persistence
mkdir -p /mnt/my_usb
mount /dev/mapper/my_usb /mnt/my_usb
echo "/ union" > /mnt/my_usb/persistence.conf
umount /dev/mapper/my_usb
cryptsetup luksClose /dev/mapper/my_usb
