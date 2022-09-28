#!/bin/bash

function showhelp() {
	cat <<EOD
Usage: install.sh HOSTNAME

Install an Arch Linux Distribution.
EOD
}

isvm=$(dmesg |grep "Hypervisor detected")
[ "$isvm" ] && isvm=yes

wanthelp=0
while :
do
	if [[ $1 == --* ]]; then
		case "$1" in
			--help )
				wanthelp=1
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

[[ $wanthelp -eq 1 ]] && showhelp && exit

hostname=$1
if [[ ! $hostname ]]; then
 	>&2 echo "must declare hostname"
	wanthelp=2
fi

[[ $wanthelp -eq 2 ]] && showhelp && exit 1

set -e
here=$(dirname $BASH_SOURCE)

timedatectl set-ntp true

if [[ $isvm ]]; then
	mkfs.ext4 /dev/sda3
	mount /dev/sda3 /mnt
	filesystem=ext4
else
	mkfs.f2fs -f -l root -O extra_attr,inode_checksum,sb_checksum,compression,encrypt /dev/sda3
	mount -o compress_algorithm=zstd:6,compress_chksum,gc_merge,lazytime /dev/sda3 /mnt
	filsystem=f2fs
fi

mkfs.fat -F 32 /dev/sda1
mount --mkdir /dev/sda1 /mnt/boot

mkswap /dev/sda2
swapon /dev/sda2

if [[ $isvm ]]; then
	firmware="e2fsprogs"
else
	firmware="linux-firmware intel-ucode broadcom-wl iwd f2fs-tools"
fi

# bootstrap the install with the base packages
pacstrap -i /mnt linux mkinitcpio $firmware \
	base efibootmgr dosfstools btrfs-progs \
	iptables-nft firewalld polkit \
	bash-completion man-db man-pages texinfo \
	tpm2-tss libfido2 sudo openssh \
	git arch-install-scripts vim

# set the time
arch-chroot /mnt /bin/bash <<EOD
ln -sf /usr/share/zoneinfo/US/Central /etc/localtime
hwclock --systohc
EOD

# generate the fstab -- compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime
genfstab -U /mnt >> /mnt/etc/fstab

# enable the required services
[[ ! $isvm ]] && arch-chroot /mnt systemctl enable iwd.service

arch-chroot /mnt /bin/bash <<EOD
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable firewalld.service
EOD

# setup the system language
LANG=en_US.UTF-8
# uncomment language from /mnt/etc/locale.gen
sed -i "/$LANG/s/^#//g" /mnt/etc/locale.gen
# set the lang environment variable
echo "LANG=$LANG" > /mnt/etc/locale.conf
# generate the language files
arch-chroot /mnt locale-gen

# set the hostname
echo $hostname > /mnt/etc/hostname

# enable wheel group in sudoers
awk '/wheel/ && /NOPASSWD/' /mnt/etc/sudoers | cut -c3- > /mnt/etc/sudoers.d/wheel
# copy the nopassword policykit config
cp $here/etc/polkit-1/rules.d/* /mnt/etc/polkit-1/rules.d/

# copy the profile scripts
cp $here/etc/profile.d/* /mnt/etc/profile.d/

# make the xdg config dir in skel
mkdir /mnt/etc/skel/.config
# copy the systemd user environment config files
cp -r $here/dot-config/environment.d /mnt/etc/skel/.config/

# install the gnupg config
git -C /mnt/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-gnupg.git gnupg
chmod go-rwx /mnt/etc/skel/.config/gnupg
cat >> /mnt/etc/skel/.bashrc <<'EOD'

# BEGIN set by install.sh
. $GNUPGHOME/.rc
set -o vi
# END set by install.sh
EOD
# install the ssh config
git -C /mnt/etc/skel clone --quiet https://github.com/ganreshnu/config-openssh.git .ssh
ssh-keyscan github.com > /mnt/etc/skel/.ssh/known_hosts

# install this repo
git -C /mnt/root clone --quiet https://github.com/ganreshnu/arch-linux-install.git

# setup the bootloader
bootctl --esp-path=/mnt/boot install

[[ ! $isvm ]] && fallbackopts="i915.fastboot=1 acpi_backlight=vendor"
cat > /mnt/boot/loader/entries/fallback.conf <<EOD
title		Arch Linux (fallback)
linux		/vmlinuz-linux
initrd	/initramfs-linux.img
options	root=PARTLABEL=archlinux resume=PARTLABEL=swap
options	rw quiet consoleblank=60 $fallbackopts
EOD

#cp $here/boot/loader/entries/fallback.conf /mnt/boot/loader/entries/
[[ ! $isvm ]] && microcode="--microcode /mnt/boot/intel-ucode.img"
[[ ! $isvm ]] && opts="--opt i915.fastboot=1 --opt acpi_backlight=vendor"

cat > /mnt/etc/systemd/system/firstboot.service <<EOD
[Unit]
Description=First Boot Script
ConditionFirstBoot=yes

[Service]
Type=oneshot
ExecStart=/root/arch-linux-install/boot/mkinitcpio.sh --reboot --resume PARTLABEL=swap $microcode $opts PARTLABEL=archlinux

[Install]
WantedBy=multi-user.target
EOD
arch-chroot /mnt systemctl enable firstboot.service

cat <<EOD

------------------------------
please add a user by running:
arch-chroot /mnt
useradd -m -G wheel,uucp <USER>
passwd <USER>
exit

EOD

cat <<EOD

-------------------------
to finish the install run:
umount -R /mnt
reboot

EOD

#uuidroot=$(blkid |awk -F\" '/sda3/ { print $10 }')
#uuidswap=$(blkid |awk -F\" '/sda2/ { print $6 }')
#efibootmgr --disk /dev/sda --part 1 --create --label "Arch Linux" --loader /vmlinuz-linux --unicode "root=PARTUUID=$uuidroot resume=PARTUUID=$uuidswap rw quiet i915.fastboot=1 consoleblank=1 initrd=\intel-ucode.img initrd=\initramfs-linux.img"

# vim: ts=3 sw=1 sts=0
