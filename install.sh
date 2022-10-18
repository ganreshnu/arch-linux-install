#!/bin/bash

#
# install.sh
#
# Install an archlinux system.
#

#
# define a usage function
#
usage() {
	cat <<EOD
Usage: $(basename "$BASH_SOURCE") [OPTIONS] [MOUNTPOINT]

Options:
  --help                         Show this message and exit.
  --platform PLATFORM            Configure for a specific platform.
  --boot DEVICE                  The device to configure as an EFI boot
                                 partition.
  --root DEVICE                  The device to configure as the filesystem
                                 root.
  --swap DEVICE                  The device to configure as swap/resume.
  --locale LOCALE                The locales to install. May be passed
                                 multiple times. Defaults to en_US.UTF-8.
  --lang LANGUAGE                The system language. Defaults to the last
                                 value passed to --locale.
  --timezone TIMEZONE            The timezone to configure.
  --hostname HOSTNAME            The system hostname.

Install an Arch Linux Distribution. MOUNTPOINT defaults to /mnt.
EOD
}


#
# script autocomplete
#
if [[ "$0" != "$BASH_SOURCE" ]]; then
	set -uo pipefail

	# generic autocomplete function that parses the script help
	_install_dot_sh_completions() {
		local completions="$(usage |sed -e '/^  -/!d' \
			-e 's/^  \(-[[:alnum:]]\)\(, \(--[[:alnum:]-]\+\)\)\?\( \[\?\([[:upper:]]\+\)\)\?.*/\1=\5\n\3=\5/' \
			-e 's/^  \(--[[:alnum:]-]\+\)\( \[\?\([[:upper:]]\+\)\)\?.*/\1=\3/')"

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
			compopt -o filenames
			;;
		DIRECTORY )
			COMPREPLY=($(compgen -d -- "$cur"))
			compopt -o filenames
			;;
		[A-Z]* )
			;;
		* )
			COMPREPLY=($(compgen -W "$completions" -- "$cur"))
			;;
		esac
	}
	complete -o noquote -o bashdefault -o default \
		-F _install_dot_sh_completions $(basename "$BASH_SOURCE")
	return
fi


#
# something is running the script
#
set -euo pipefail

#
# define an error function
#
error() {
	>&2 printf "$(tput bold; tput setaf 1)error:$(tput sgr0) %s\n" "$@"
}

#
# define the main encapsulation function
#
install_dot_sh() { local showusage=-1

	#
	# declare the variables derived from the arguments
	#
	local platform="" boot="" root="" swap="" mount="/mnt" firstboot=0 timezone="" hostname=""
	local locales=("en_US.UTF-8") lang=""

	#
	# parse the arguments
	#
	while true; do
		if [[ $# -gt 0 && "$1" == -* ]]; then
			case "$1" in
				--platform )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						platform="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--boot )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						boot="$2"
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
				--swap )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						swap="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--locale )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						locales+=("$2")
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--lang )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						lang="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--timezone )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						timezone="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--hostname )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						hostname="$2"
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
	
	[[ $# -gt 0 ]] && mount="$@"

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

	local uuid_boot="" uuid_root="" uuid_swap=""
	partuuid() {
		(blkid | grep "^$1" | sed 's/.*PARTUUID="\([[:alnum:]-]\+\)".*/\1/g') || \
			(error "could not find a uuid for device $1"; return 1)
	}
	if [[ "$boot" ]]; then
		# find the uuid
		uuid_boot=$(partuuid "$boot")
	fi
	if [[ "$root" ]]; then
		# find the uuid and device name
		uuid_root=$(partuuid "$root")
	fi
	if [[ "$swap" ]]; then
		# find the uuid and device name
		uuid_swap=$(partuuid "$swap")
	fi

	#
	# script begins
	#

	# immediately set the host time
	timedatectl set-ntp true || true

	# default the system language variable
	[[ ! "$lang" ]] && lang="${locales[-1]}"

	local here=$(dirname "$BASH_SOURCE")
	[[ ! "$platform" ]] && platform="$(dmesg | grep '\] DMI: ' || '')"

	if [[ "$swap" ]]; then
		mkswap "$swap"
		swapon "$swap"
	fi

	if [[ "$boot" ]]; then
		mkfs.fat -F 32 "$boot"
	fi

	local KERNEL_PACKAGES="linux wireless-regdb mkinitcpio"
	local CONTAINER_PACKAGES="base iptables-nft btrfs-progs reflector rsync"
	local WORKSTATION_PACKAGES="$CONTAINER_PACKAGES
		dosfstools cifs-utils exfatprogs udftools nilfs-utils
		firewalld polkit
		bash-completion man-db man-pages texinfo
		tpm2-tss libfido2 sudo openssh
		git arch-install-scripts vim"

	local packages=""
	case "$platform" in
		*Hyper-v\ UEFI* )
			packages="$KERNEL_PACKAGES $WORKSTATION_PACKAGES
				hyperv e2fsprogs
			"

			if [[ ! "$root" || ! "$boot" ]]; then
				error "need root device and boot device for hyper-v"
				return 1
			fi

			mkfs.ext4 "$root"
			mount "$root" "$mount"
			mount --mkdir "$boot" "$mount/boot"

			# setup the bootloader
			bootctl --esp-path="$mount/boot" install

			# bootstrap the install
			pacstrap -i $mount $packages

			# generate the fstab
			genfstab -U $mount >> $mount/etc/fstab

			# setup the hw clock
			arch-chroot $mount hwclock --systohc --update-drift
			# set the keymap
			echo 'KEYMAP=us' > $mount/etc/vconsole.conf

			kernel_options=""
			;;
		*MacBookAir5,2* )
			packages="$KERNEL_PACKAGES $WORKSTATION_PACKAGES
				linux-firmware intel-ucode
				broadcom-wl iwd
				f2fs-tools
			"

			if [[ ! "$root" || ! "$boot" ]]; then
				error "need root device and boot device for macbook"
				return 1
			fi
	
			mkfs.f2fs -f -l root -O extra_attr,inode_checksum,sb_checksum,compression,encrypt "$root"
			mount -o compress_algorithm=zstd:6,compress_chksum,gc_merge,lazytime "$root" "$mount"
			mount --mkdir "$boot" "$mount/boot"
	
			# setup the bootloader
			bootctl --esp-path="$mount/boot" install

			# bootstrap the install
			pacstrap -i $mount $packages

			# generate the fstab
			genfstab -U $mount >> $mount/etc/fstab

			# setup the hw clock
			arch-chroot $mount hwclock --systohc --update-drift
			# set the keymap
			echo 'KEYMAP=us' > $mount/etc/vconsole.conf

			kernel_options="i915.fastboot=1 acpi_backlight=vendor"
			;;
		WSL2 )
			packages="$CONTAINER_PACKAGES git vim sudo libfido2 openssh
				bash-completion man-db man-pages texinfo
				arch-install-scripts
			"

			if [[ ! "$root" ]]; then
				error "need root device for WSL2"
				return 1
			fi
			mkfs.ext4 "$root"
			mount "$root" "$mount"
			pacstrap -cGiM $mount $packages
			;;
		container )
			packages="$CONTAINER_PACKAGES"
			if [[ ! "$root" ]]; then
				error "need root device for container"
				return 1
			fi
			mkfs.ext4 "$root"
			mount "$root" "$mount"
			pacstrap -cGiM $mount $packages
			;;
		LIVESTICK )
			packages="$KERNEL_PACKAGES $WORKSTATION_PACKAGES
				linux-firmware intel-ucode amd-ucode
				broadcom-wl iwd
				f2fs-tools e2fsprogs
			"

			if [[ ! "$root" || ! "$boot" ]]; then
				error "need root device and boot device for livestick"
				return 1
			fi

			mkfs.ext4 "$root"
			mount "$root" "$mount"
			mount --mkdir "$boot" "$mount/boot"

			# setup the bootloader
			bootctl --esp-path="$mount/boot" install

			pacstrap -cGiM $mount $packages

			# generate the fstab
			genfstab -U $mount >> $mount/etc/fstab

			# setup the hw clock
			arch-chroot $mount hwclock --systohc --update-drift
			# set the keymap
			echo 'KEYMAP=us' > $mount/etc/vconsole.conf
			[[ ! "$hostname" ]] && hostname="jwux"
			kernel_options=""
			;;
		* )
			printf "$(tput setaf 3)unknown platform:$(tput sgr0) %s\n" "$platform"
			return 1
			;;
	esac

	packages="$(arch-chroot $mount pacman -Qq)"
	haspackage() {
		[[ "$packages" =~ (^|[[:space:]])$1([[:space:]]|$) ]]
	}

	#
	# configure the linux kernel
	#
	if haspackage "linux"; then

		local microcode="" initrd=""
		for mc in $mount/boot/*-ucode.img; do
			microcode="$microcode --microcode /boot/$(basename $mc)"
			initrd="${initrd}initrd /$(basename $mc)
"
		done

		local resume=""
		[[ "$swap" ]] && resume="resume=PARTUUID=$uuid_swap"
		cat > $mount/boot/loader/entries/fallback.conf <<-EOD
		title		Arch Linux (fallback)
		linux		/vmlinuz-linux
		$initrd
		initrd	/initramfs-linux.img
		options	root=PARTUUID=$uuid_root $resume
		options	rw quiet consoleblank=60 $kernel_options
EOD

		local opts=""
		for opt in $kernel_options; do
			opts="$opts --opt $opt"
		done
		
		resume=""
		[[ "$swap" ]] && resume="--resume PARTUUID=$uuid_swap"
		cat > $mount/etc/systemd/system/make-unified-init.service <<-EOD
		[Unit]
		Description=Make unified kernel image
		After=local-fs.target
		
		[Service]
		Type=oneshot
		ExecStart=-/root/arch-linux-install/boot/mkinitcpio.sh $resume $microcode $opts PARTUUID=$uuid_root
		StandardOutput=journal
		StandardError=journal+console
EOD
	fi

	#
	# timezone configuration
	#
	if haspackage "tzdata"; then
		[[ "$timezone" ]] && arch-chroot ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
	fi

	#
	# systemd configuration
	#
	if haspackage "systemd"; then

		# setup the ethernet network
		cat > $mount/etc/systemd/network/ethernet.network <<-'EOD'
		[Match]
		Name=e*

		[Network]
		DHCP=ipv4

		[DHCPv4]
		RouteMetric=10

		[IPv6AcceptRA]
		RouteMetric=10
EOD
		# setup the wireless network
		cat > $mount/etc/systemd/network/wireless.network <<-'EOD'
		[Match]
		Name=w*

		[Network]
		DHCP=ipv4

		[DHCPv4]
		RouteMetric=20

		[IPv6AcceptRA]
		RouteMetric=20
EOD

		# set the hostname
		[[ "$hostname" ]] && echo "$hostname" > $mount/etc/hostname

		# set the system language
		[[ "$lang" ]] && echo "LANG=$lang" > $mount/etc/locale.conf

#		# use firstboot to get system information
#		mkdir -p $mount/etc/systemd/system/systemd-firstboot.service.d
#		cat > $mount/etc/systemd/system/systemd-firstboot.service.d/override.conf <<-EOD
#		[Service]
#		ExecStart=/usr/bin/systemd-firstboot --prompt-locale --prompt-timezone --prompt-hostname
#		
#		[Install]
#		WantedBy=sysinit.target
#EOD
#		rm -f $mount/etc/machine-id
#		arch-chroot $mount systemctl enable systemd-firstboot.service

		# enable the services
		arch-chroot $mount /bin/bash <<-EOD
		systemctl enable systemd-networkd.service
		systemctl enable systemd-resolved.service
EOD
		ln -sf /run/systemd/resolve/stub-resolv.conf $mount/etc/resolv.conf

		# setup the user environment.d
		echo 'eval "export $(/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator)"' > "$mount/etc/profile.d/user-environment-d.sh"
	fi

	#
	# configure hyperv
	#
	if haspackage "hyperv"; then
		arch-chroot $mount /bin/bash <<-EOD
		systemctl enable hv_fcopy_daemon.service
		systemctl enable hv_kvp_daemon.service
		systemctl enable hv_vss_daemon.service
EOD
	fi

	#
	# configure iwd
	#
	if haspackage "iwd"; then
		arch-chroot $mount systemctl enable iwd.service
	fi

	#
	# glibc configuration
	#
	if haspackage "glibc"; then
		# uncomment languages from $mount/etc/locale.gen
		local cmd="sed -i"
		for l in "${locales[@]}"; do
			cmd="$cmd -e '/$l/s/^#//g'"
		done
		eval "$cmd $mount/etc/locale.gen"
		
		# generate the language files
		arch-chroot $mount locale-gen
	fi

	#
	# polkit configuration
	#
	if haspackage "polkit"; then
		cat > $mount/etc/polkit-1/rules.d/50-nopasswd_global.rules <<-'EOD'
		/*
		 * Allow members of the wheel group to execute any actions
		 * without password authentication.
		 */
		polkit.addRule(function(action, subject) {
			if (subject.isInGroup("wheel")) {
				return polkit.Result.YES;
			}
			return polkit.Result.NOT_HANDLED
		});
EOD
	fi

	#
	# firewalld configuration
	#
	if haspackage "firewalld"; then
		arch-chroot $mount systemctl enable firewalld.service
	fi

	#
	# sudo configuration
	#
	if haspackage "sudo"; then
		awk '/wheel/ && /NOPASSWD/' $mount/etc/sudoers | cut -c3- > $mount/etc/sudoers.d/wheel
		chmod 0750 $mount/etc/sudoers.d
	fi


	#
	# filesystem configuration
	#
	if haspackage "filesystem"; then
		mkdir -p "$mount/etc/skel/.config/environment.d"
		mkdir -p "$mount/etc/skel/.local/"{"state","share","bin"}
		haspackage "systemd" && \
			echo 'PATH="$HOME/.local/bin:$PATH' > "$mount/etc/skel/.config/environment.d/50-local-bin.conf"
	fi

	#
	# readline configuration
	#
	if haspackage "readline"; then
		# install the readline config
		git -C $mount/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-readline.git readline
	fi

	#
	# gnupg configuration
	#
	if haspackage "gnupg"; then
		git -C $mount/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-gnupg.git gnupg
		chmod go-rwx $mount/etc/skel/.config/gnupg

		[[ ! -d "$mount/etc/skel/.config/environment.d" ]] && mkdir -p "$mount/etc/skel/.config/environment.d"
		echo 'GNUPGHOME=${XDG_CONFIG_HOME:-$HOME/.config}/gnupg' > "$mount/etc/skel/.config/environment.d/20-gnupg.conf"
	fi

	#
	# openssh configuration
	#
	if haspackage "openssh"; then
		git -C $mount/etc/skel clone --quiet https://github.com/ganreshnu/config-openssh.git .ssh
		ssh-keyscan github.com > $mount/etc/skel/.ssh/known_hosts
	fi

	#
	# vim configuration
	#
	if haspackage "vim"; then
		mkdir -p "$mount/etc/skel/.config"
		git -C $mount/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-vim.git vim
	fi

	#
	# bash configuration
	#
	if haspackage "bash"; then
		mkdir -p "$mount/etc/skel/.config" "$mount/etc/skel/.local/state" "$mount/etc/skel/.local/share"
		git -C $mount/etc/skel/.config clone --quiet https://github.com/ganreshnu/config-bash.git bash

		cat > $mount/etc/profile.d/bash-config-profiles.sh <<-'EOD'
		for prof in "${XDG_CONFIG_HOME:-$HOME/.config}"/*/.profile; do
			[[ -r "$prof" ]] && . "$prof"
		done
		unset prof
EOD

		cat >> $mount/etc/skel/.bashrc <<-'EOD'
		for rc in "${XDG_CONFIG_HOME:-$HOME/.config}"/*/.rc; do
			[[ -r "$rc" ]] && . "$rc"
		done
		unset rc
EOD

		haspackage "bash-completion" && arch-chroot $mount /bin/bash <<-EOD
		cd /etc/skel
		ln -s .config/bash/bash_completion .bash_completion
EOD
	fi

	cat <<-EOD
	
	------------------------------
	please add a user by running:
	arch-chroot $mount
	useradd -m -G wheel,uucp <USER>
	passwd <USER>
	exit
	
EOD

	cat <<-EOD
	
	-------------------------
	to finish the install run:
	umount -R $mount
	reboot
	
EOD
}
install_dot_sh "$@"

# vim: ts=3 sw=0 sts=0
