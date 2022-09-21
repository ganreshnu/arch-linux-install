#!/bin/bash
echo 'I hope you created the partitions!'
timedatectl set-ntp true
mkfs.f2fs -l root -O extra_attr,inode_checksum,sb_checksum,compression,encrypt /dev/sda3
mkswap /dev/sda2
mkfs.fat -F 32 /dev/sda1

mount -o compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime /dev/sda3 /mnt
mount --mkdir /dev/sda1 /mnt/boot
swapon /dev/sda2

# bootstrap the install with the base packages
pacstrap /mnt linux linux-firmware intel-ucode libva-intel-driver broadcom-wl \
	efibootmgr base iwd networkmanager iptables-nft firewalld polkit \
	bash-completion man-db man-pages texinfo libfido2 sudo openssh \
	git vim brightnessctl f2fs-tools \
	pipewire-alsa pipewire-jack pipewire-pulse pipewire-docs \
	noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
	dosfstools

# generate the fstab
genfstab -U /mnt >> /mnt/etc/fstab
# compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime

# setup the system language
LANG=en_US.UTF-8
# uncomment language from /mnt/etc/locale.gen
sed -i "/$LANG/s/^#//g" /mnt/etc/locale.gen
# set the lang environment variable
echo "LANG=$LANG" > /mnt/etc/locale.conf

# set the hostname
echo "jasmine" > /mnt/etc/hostname
# enable wheel group in sudoers
grep wheel /mnt/etc/sudoers | tail -n1 | cut -c3- > /mnt/etc/sudoers.d/wheel

arch-chroot /mnt /bin/bash <<EOD
ln -sf /usr/share/zoneinfo/US/Central /etc/localtime
hwclock --systohc
locale-gen
useradd -m -G wheel,uucp john
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable firewalld
systemctl mask systemd-backlight@backlight\:acpi_video0.service
EOD

echo "set password now"

#umount -R /mnt
#echo "Safe to reboot now"

#pacman -S sway swaybg swayidle swaylock bemenu-wayland alacritty firefox

#uuidroot=$(blkid |awk -F\" '/sda3/ { print $8 }')
#uuidswap=$(blkid |awk -F\" '/sda2/ { print $6 }')
#efibootmgr --disk /dev/sda --part 1 --create --label "Arch Linux" --loader /vmlinuz-linux --unicode "root=PARTUUID=$uuidroot resume=PARTUUID=$uuidswap rw initrd=\intel-ucode.img initrd=\initramfs-linux.img"
