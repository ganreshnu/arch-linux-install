#!/bin/bash

#
# install.sh
#
# Install an archlinux system.
#

#
# something is running the script
#
if [[ "$0" == "$BASH_SOURCE" ]]; then
set -euo pipefail

#
# define a usage function
#
usage() {
	cat <<EOD
Usage: $(basename "$BASH_SOURCE") [OPTIONS]

Options:
  --help                       Show this message and exit.
  --hypervisor HYPERVISOR      Force a specific hypervisor.
  --root DIRECTORY             The directory in which to install. Defaults to /mnt.

Install an Arch Linux Distribution.
EOD
}

#
# define an error function
#
error() {
	>&2 printf "$(tput bold; tput setaf 1)error:$(tput sgr0) %s\n" "$@"
	showusage=1
}

#
# define the main encapsulation function
#
install_dot_sh() {
	local here=$(dirname $BASH_SOURCE)
	local showusage=-1

	#
	# declare the variables derived from the arguments
	#
	local hypervisor=$(dmesg |grep "Hypervisor detected")
	hypervisor="${hypervisor#*: }"

	local root="/mnt"

	#
	# parse the arguments
	#
	while true; do
		if [[ $# -gt 0 && "$1" == -* ]]; then
			case "$1" in
				--hypervisor )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						hypervisor="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--root )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						root="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--help )
					showusage=0
					shift
					;;
				-- )
					shift
					break
					;;
				* )
					error "unknown argument $1"
					showusage=1
					shift
					;;
			esac
		else
			break
		fi
	done
	
	#
	# argument validation goes here
	#
		
	#
	# show help if necessary
	#
	if [[ $showusage -ne -1 ]]; then
		usage
		return $showusage
	fi
	
	#
	# value validation goes here
	#

	#
	# script begins
	#

	# immediately set the time
	timedatectl set-ntp true
	
	#
	# format the physical disks if present
	#
	local has_swap=0 has_boot=0 has_root=0
	[[ $(blkid | grep 'PARTLABEL="swap"') ]] && has_swap=1
	[[ $(blkid | grep 'PARTLABEL="boot"') ]] && has_boot=1
	[[ $(blkid | grep 'PARTLABEL="archlinux"') ]] && has_root=1

	if [[ $has_root -eq 1 && $has_boot -eq 1 ]]; then
		if [[ "$hypervisor" ]]; then
			mkfs.ext4 /dev/sda3
			mount /dev/sda3 "$root"
		else
			mkfs.f2fs -f -l root -O extra_attr,inode_checksum,sb_checksum,compression,encrypt /dev/sda3
			mount -o compress_algorithm=zstd:6,compress_chksum,gc_merge,lazytime /dev/sda3 "$root"
		fi

		mkfs.fat -F 32 /dev/sda1
		mount --mkdir /dev/sda1 $root/boot
	
		# setup the bootloader
		bootctl --esp-path=$root/boot install
	fi
	
	if [[ $has_swap -eq 1 ]]; then
		mkswap /dev/sda2
		swapon /dev/sda2
	fi

	local firmware
	if [[ "$hypervisor" ]]; then
		firmware="e2fsprogs"
	else
		firmware="linux-firmware intel-ucode broadcom-wl iwd f2fs-tools"
	fi
	
	# bootstrap the install with the base packages
	pacstrap -i $root linux mkinitcpio $firmware \
		base dosfstools btrfs-progs \
		iptables-nft firewalld polkit \
		bash-completion man-db man-pages texinfo \
		tpm2-tss libfido2 sudo openssh \
		git arch-install-scripts vim
	
	
	# generate the fstab -- compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime
	genfstab -U $root >> $root/etc/fstab
	
	# enable the required services
	[[ ! "$hypervisor" ]] && arch-chroot $root systemctl enable iwd.service
	
	arch-chroot $root /bin/bash <<-EOD
	systemctl enable systemd-networkd.service
	systemctl enable systemd-resolved.service
	systemctl enable firewalld.service
EOD
	
	# setup the hw clock
	arch-chroot $root hwclock --systohc
	
	# uncomment language from $root/etc/locale.gen
	sed -i \
		-e "/en_US.UTF-8/s/^#//g" \
		$root/etc/locale.gen
	
	# generate the language files
	arch-chroot $root locale-gen
	
	# enable the firstboot service
	mkdir -p $root/etc/systemd/system/systemd-firstboot.service.d
	cat > $root/etc/systemd/system/systemd-firstboot.service.d/override.conf <<-EOD
	[Service]
	ExecStart=/usr/bin/systemd-firstboot --prompt-locale --prompt-keymap --prompt-timezone --prompt-hostname
	ExecStart=ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
	
	[Install]
	WantedBy=sysinit.target
EOD
	rm $root/etc/machine-id
	arch-chroot $root systemctl enable systemd-firstboot.service
	
	# install the root /etc dropins
	git -C $root/root clone --bare https://github.com/ganreshnu/config-etc.git
	local git_etc="git -C $root/etc --git-dir=$root/root/config-etc.git --work-tree=$root/etc"
	$git_etc config --local status.showUntrackedFiles no
	$git_etc checkout

	# make the xdg config dir in skel along with the environment.d dir
	mkdir -p $root/etc/skel/.config/environment.d
	# install the readline config
	git -C $root/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-readline.git readline
	echo 'INPUTRC=$HOME/.config/readline/inputrc' > $root/etc/skel/.config/environment.d/50-readline.conf

	# install the gnupg config
	git -C $root/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-gnupg.git gnupg
	chmod go-rwx $root/etc/skel/.config/gnupg
	echo 'GNUPGHOME=$HOME/.config/gnupg' > $root/etc/skel/.config/environment.d/20-gnupg.conf
	echo '. $GNUPGHOME/.rc' >> $root/etc/skel/.bashrc

	# install the ssh config
	git -C $root/etc/skel clone --quiet https://github.com/ganreshnu/config-openssh.git .ssh
	ssh-keyscan github.com > $root/etc/skel/.ssh/known_hosts

	# install the vim config
	git -C $root/etc/skel clone --quiet https://github.com/ganreshnu/config-vim.git vim
	printf "export VIMINIT='%s | %s'" 'let $MYVIMRC=$HOME/.config/vim/vimrc' 'source $MYVIMRC' >> $root/etc/skel/.bashrc

	# install the bash config
	git -C $root/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-bash.git bash
	cat $root/etc/skel/.bashrc  $root/etc/skel/.config/bash/bashrc.sh > $root/etc/skel/.config/bash/bashrc
	cat $root/etc/skel/.bash_profile $root/etc/skel/.config/bash/bash_profile.sh > $root/etc/skel/.config/bash/bash_profile
	rm $root/etc/skel/.bash_profile $root/etc/skel/.bashrc $root/etc/skel/.bash_logout

	arch-chroot $root /bin/bash <<-EOD
	cd /etc/skel
	ln -s .config/bash/bashrc .bashrc
	ln -s .config/bash/bash_completion .bash_completion
EOD

	# install this repo
	git -C $root/root clone --quiet https://github.com/ganreshnu/arch-linux-install.git
	
	local fallbackopts=""
	[[ ! "$hypervisor" ]] && fallbackopts="i915.fastboot=1 acpi_backlight=vendor"
	cat > $root/boot/loader/entries/fallback.conf <<-EOD
	title		Arch Linux (fallback)
	linux		/vmlinuz-linux
	initrd	/initramfs-linux.img
	options	root=PARTLABEL=archlinux resume=PARTLABEL=swap
	options	rw quiet consoleblank=60 $fallbackopts
EOD
	
	local microcode=""
	[[ ! "$hypervisor" ]] && microcode="--microcode $root/boot/intel-ucode.img"
	local opts=""
	[[ ! "$hypervisor" ]] && opts="--opt i915.fastboot=1 --opt acpi_backlight=vendor"
	
	cat > $root/etc/systemd/system/mkunifiedimage.service <<-EOD
	[Unit]
	Description=Make unified kernel image
	After=local-fs.target
	ConditionPathExists=!/boot/EFI/Linux/archlinux-systemd.efi
	
	[Service]
	Type=oneshot
	RemainAfterExit=true
	ExecStart=-/root/arch-linux-install/boot/mkinitcpio.sh --reboot --resume PARTLABEL=swap $microcode $opts PARTLABEL=archlinux
	StandardOutput=inherit
	StandardError=journal+console
	
	[Install]
	WantedBy=graphical.target
EOD
	arch-chroot $root systemctl enable mkunifiedimage.service
	
	cat <<-EOD
	
	------------------------------
	please add a user by running:
	arch-chroot $root
	useradd -m -G wheel,uucp <USER>
	passwd <USER>
	exit
	
EOD
	
	cat <<-EOD
	
	-------------------------
	to finish the install run:
	umount -R $root
	reboot
	
EOD
}
install_dot_sh "$@"

#
# script has been sourced
#
else
set -uo pipefail
_install_dot_sh_completions() {
	local completions="$($1 --help |sed -e '/^  -/!d' \
		-e 's/^  \(-[[:alnum:]]\)\(, \(--[[:alnum:]]\+\)\)\?\( \(FILENAME\|DIRECTORY\)\)\?.*/\1=\5\n\3=\5/' \
		-e 's/^  \(--[[:alnum:]]\+\)\( \(FILENAME\|DIRECTORY\)\)\?.*/\1=\3/')"

	declare -A completion
	for c in $completions; do
		local key="${c%=*}"
		[[ "$key" ]] && completion[$key]="${c#*=}"
	done
	completions="${!completion[@]}"

	[[ $# -lt 3 ]] && local prev="$1" || prev="$3"
	[[ $# -lt 2 ]] && local cur="" || cur="$2"

	local type=""
	[[ ${completion[$prev]+_} ]] && type=${completion[$prev]}

	case "$type" in
	FILENAME )
	 	COMPREPLY=($(compgen -f -- "$cur"))
		;;
	DIRECTORY )
		COMPREPLY=($(compgen -d -- "$cur"))
		;;
	* )
		COMPREPLY=($(compgen -W "$completions" -- "$cur"))
		compopt +o filenames
		;;
	esac
}
complete -o filenames -o noquote -o bashdefault -o default -F _install_dot_sh_completions install.sh
fi

# vim: ts=3 sw=1 sts=0
