#!/bin/bash
ROOTDEVICE="$1"
MOUNTPOINT="$2"

mkfs.btrfs -L linux -f "$ROOTDEVICE"
BTRFSROOT=$(mktemp -d)
mount -o subvol=/ "$ROOTDEVICE" "$BTRFSROOT"
mkdir -p "$BTRFSROOT/var/lib" "$BTRFSROOT/os"
btrfs subvolume create "$BTRFSROOT/os/@current"
btrfs subvolume set-default "$BTRFSROOT/os/@current"
mount -o defaults,noatime,compress=lzo "$ROOTDEVICE" "$MOUNTPOINT"

mkdir "$MOUNTPOINT/home"
btrfs subvolume create "$BTRFSROOT/@home"
mount -o defaults,relatime,autodefrag,compress=lzo,subvol=@home "$ROOTDEVICE" "$MOUNTPOINT/home"

mkdir "$MOUNTPOINT/srv"
btrfs subvolume create "$BTRFSROOT/@srv"
mount -o defaults,relatime,autodefrag,compress=lzo,subvol=@srv "$ROOTDEVICE" "$MOUNTPOINT/srv"

mkdir -p "$MOUNTPOINT/var/cache"
btrfs subvolume create "$BTRFSROOT/var/@cache"
mount -o defaults,noatime,autodefrag,compress=lzo,subvol=var/@cache "$ROOTDEVICE" "$MOUNTPOINT/var/cache"

mkdir -p "$MOUNTPOINT/var/log"
btrfs subvolume create "$BTRFSROOT/var/@log"
mount -o defaults,noatime,autodefrag,compress=lzo,subvol=var/@log "$ROOTDEVICE" "$MOUNTPOINT/var/log"

mkdir -p "$MOUNTPOINT/var/tmp"
btrfs subvolume create "$BTRFSROOT/var/@tmp"
mount -o defaults,noatime,autodefrag,compress=lzo,subvol=var/@tmp "$ROOTDEVICE" "$MOUNTPOINT/var/tmp"

mkdir -p "$MOUNTPOINT/var/lib/machines"
btrfs subvolume create "$BTRFSROOT/var/lib/@machines"
mount -o defaults,relatime,compress=lzo,subvol=var/lib/@machines "$ROOTDEVICE" "$MOUNTPOINT/var/lib/machines"

mkdir -p "$MOUNTPOINT/var/lib/portables"
btrfs subvolume create "$BTRFSROOT/var/lib/@portables"
mount -o defaults,relatime,compress=lzo,subvol=var/lib/@portables "$ROOTDEVICE" "$MOUNTPOINT/var/lib/portables"

umount "$BTRFSROOT" && rmdir "$BTRFSROOT"
