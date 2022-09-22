#!/bin/bash

function showhelp() {
	cat <<EOD
Usage: install.sh [OPTIONS]

Install an Arch Linux Distribution.

Options:
  --vm		Runs on a virtual machine
EOD
}

usefirmware=1
wanthelp=0
while :
do
	if [[ "$1" == --* ]]; then
		case "$1" in
			--help )
				wanthelp=1
				shift
				;;
			--vm )
				usefirmware=0
				shift
				;;
			* )
				>&2 echo "unknown option: $1"
				wanthelp=2
				shift
				;;
		esac
	else
		break
	fi
done
[ $wanthelp -eq 1 ] && showhelp && exit
[ $wanthelp -eq 2 ] && showhelp && exit 1

timedatectl set-ntp true

mkswap /dev/sda2
swapon /dev/sda2

if [[ $usefirmware -eq 1 ]]; then
	mkfs.f2fs -f -l root -O extra_attr,inode_checksum,sb_checksum,compression,encrypt /dev/sda3
	mount -o compress_algorithm=zstd:6,compress_chksum,gc_merge,lazytime /dev/sda3 /mnt
else
	mkfs.ext4 /dev/sda3
	mount /dev/sda3 /mnt
fi

mkfs.fat -F 32 /dev/sda1
mount --mkdir /dev/sda1 /mnt/boot


[ $usefirmware -eq 1 ] && firmware="linux-firmware intel-ucode broadcom-wl"
# bootstrap the install with the base packages
pacstrap /mnt linux $firmware \
	base f2fs-tools dosfstools \
	iptables-nft networkmanager firewalld polkit \
	bash-completion man-db man-pages texinfo \
	libfido2 sudo openssh \
	git

# set the time
arch-chroot /mnt /bin/bash <<EOD
ln -sf /usr/share/zoneinfo/US/Central /etc/localtime
hwclock --systohc
EOD

# generate the fstab -- compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime
genfstab -U /mnt >> /mnt/etc/fstab

# enable the required services
arch-chroot /mnt /bin/bash <<EOD
systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl enable firewalld
systemctl mask systemd-backlight@backlight\:acpi_video0.service
EOD

# setup the system language
LANG=en_US.UTF-8
# uncomment language from /mnt/etc/locale.gen
sed -i "/$LANG/s/^#//g" /mnt/etc/locale.gen
# set the lang environment variable
echo "LANG=$LANG" > /mnt/etc/locale.conf
# generate the language files
arch-chroot /mnt /bin/bash locale-gen

# set the hostname
echo "jasmine" > /mnt/etc/hostname

# enable wheel group in sudoers
grep wheel /mnt/etc/sudoers | tail -n1 | cut -c3- > /mnt/etc/sudoers.d/wheel
# copy the nopassword policykit config
cp etc/polkit-1/rules.d/* /mnt/etc/polkit-1/rules.d/

# copy the profile scripts
cp etc/profile.d/* /mnt/etc/profile.d/

# make the xdg config dir in skel
mkdir /mnt/etc/skel/.config
# copy the systemd user environment config files
cp -r dot-config/environment.d /mnt/etc/skel/.config/

# install the gnupg config
git -C /mnt/etc/skel/.config clone https://github.com/ganreshnu/config-gnupg.git gnupg
chmod go-rwx /mnt/etc/skel/.config/gnupg

# install the ssh config
git -C /mnt/etc/skel clone https://github.com/ganreshnu/config-openssh.git .ssh
ssh-keyscan github.com > /mnt/etc/skel/.ssh/known_hosts
echo '. $HOME/.ssh/profile' >> /mnt/etc/skel/.bashrc

echo <<EOD
please add a user by running:
arch-chroot /mnt
useradd -m -G wheel,uucp john
passwd john
exit

EOD

echo <<EOD
to finish the install run:
umount -R /mnt
reboot

EOD


#uuidroot=$(blkid |awk -F\" '/sda3/ { print $8 }')
#uuidswap=$(blkid |awk -F\" '/sda2/ { print $6 }')
#efibootmgr --disk /dev/sda --part 1 --create --label "Arch Linux" --loader /vmlinuz-linux --unicode "root=PARTUUID=$uuidroot resume=PARTUUID=$uuidswap rw initrd=\intel-ucode.img initrd=\initramfs-linux.img"
