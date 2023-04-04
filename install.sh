#!/bin/bash

#
# install.sh
#
# Install an archlinux system.
#

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
# define a usage function
#
usage() {
	cat <<EOD
Usage: $(basename "$BASH_SOURCE") [OPTIONS] [DIRECTORY]

Options:
  --lang LANGUAGE                The system language. Defaults to \$LANG.
  --timezone TIMEZONE            The system timezone. Defaults to the current
                                 system's timezone.
  --hostname STRING              The sytem hostname. Defaults to 'jwux'.

  --platform STRING              The target platform from which to derive
                                 configuration.
  --mirrorlist                   Generate a mirrorlist.
  --help                         Show this message and exit.

Install an Arch Linux Distribution to DIRECTORY.
EOD
}

declare -A ARGS=(
	[lang]="$LANG"
	[timezone]="$(realpath --relative-to /usr/share/zoneinfo $(readlink /etc/localtime))"
	[hostname]="jwux"
	[platform]="$([[ -f /sys/class/dmi/id/product_name ]] && cat /sys/class/dmi/id/product_name)"
	[mirrorlist]=0
)

original() {
	local file="$(arch-chroot "$MOUNTPOINT" readlink -f "$1")"
	local pkgname="$(arch-chroot "$MOUNTPOINT" pacman -Qoq "$file")"
	local url="$(arch-chroot "$MOUNTPOINT" pacman -Sp "$pkgname")"

	arch-chroot "$MOUNTPOINT" curl --silent "$url" | tar -x --zstd --to-stdout "${file#/}" > "$MOUNTPOINT/$1"
}

configure() {
	local packages="$@"
	haspackage() {
		[[ "$packages" =~ (^|[[:space:]])$1([[:space:]]|$) ]]
	}

	msg --tag install --color 4 "installing configurations"
	for f in "$HERE/config/"*; do
		if haspackage "$(basename "$f")"; then
			msg --tag config --color 4 "configuring $(basename "$f")"
			. "$f"
			config || msg --tag error --color 1 "configuration of $(basename "$f") failed"
		fi

	done; unset f
}

#
# define the main encapsulation function
#
main() {
	local HERE="$(dirname "$BASH_SOURCE")"
	. "$HERE/script-util/pargs.sh"
	. "$HERE/script-util/confirm.sh"
	. "$HERE/script-util/msg.sh"

	#
	# parse the arguments
	#
	local showusage=-1
	if pargs usage "$@"; then
		mapfile -s 1 -t args <<< "${ARGS[_]}"
		set -- "${args[@]}" && unset args ARGS[_]
	else
		[[ $? -eq 255 ]] && showusage=0 || showusage=$?
	fi

	local MOUNTPOINT='/mnt'
	if [[ $# -gt 0 && "$1" ]]; then
		MOUNTPOINT="$1"
		shift
	fi

	#
	# argument type validation goes here
	#

	[[ $# -gt 0 ]] && msg --tag warn --color 3 "$# extra args: \"$@\""

	#
	# show help if necessary
	#
	if [[ $showusage -ne -1 ]]; then
		usage
		return $showusage
	fi
	
	#
	# argument value validation goes here
	#

	#
	# script begins
	#

	# immediately set the host time
	timedatectl set-ntp true 2>/dev/null || true

	local BASE=(base iptables-nft polkit)
	local PACKAGES=()
	local DOCS=(man-db man-pages texinfo)
	local CMDLINE=(sudo bash-completion git vim openssh arch-install-scripts)
	local KERNEL=(linux linux-firmware mkinitcpio libfido2 tpm2-tss btrfs-progs)
	local AUDIO=(pipewire pipewire-alsa pipewire-audio pipewire-jack pipewire-pulse pipewire-docs \
		wireplumber wireplumber-docs)
	local VIDEO=(libva libva-utils libva-vdpau-driver vulkan-mesa-layers)
	local PRINTING=(cups)
	local DESKTOP=("${VIDEO[@]}" "${AUDIO[@]}" bemenu-wayland pinentry-bemenu mako \
		libva libva-utils vulkan-mesa-layers \
		noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
		wayland sway swaybg swayidle swaylock \
		xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
		"${DOCS[@]}" "${PRINTING[@]}")
	local WIFI=(iwd wireless-regdb)
	local BLUETOOTH=(bluez bluez-utils bluez-cups)


	# show configuration and prompt to continue
	for key in "${!ARGS[@]}"; do
		printf '%s = %s\n' "$key" "${ARGS[$key]}"
	done
	echo "MOUNTPOINT = $MOUNTPOINT"
	confirm "continue to install?" || return 2

	# update the mirrorlist
	if [[ ${ARGS[mirrorlist]} -eq 1 ]]; then
		msg --tag install --color 4 "updating the pacman mirrorlist"
		curl -s "https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=6&use_mirror_status=on" | sed -e 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
	fi

	# bootstrap the install
	msg --tag install --color 4 "installing the base system"
	local answer=0
	if [[ -x "$MOUNTPOINT/usr/bin/pacman" ]]; then
		confirm 'base seems installed... reinstall?' || answer=$?
	fi
	[[ $answer -eq 0 ]] && pacstrap -iK "$MOUNTPOINT" "${BASE[@]}"

	# sync pacman
	msg --tag install --color 4 "syncing pacman"
	arch-chroot "$MOUNTPOINT" pacman -Sy

	configure glibc

	case "${ARGS[platform]}" in
		'Virtual Machine' )
			PACKAGES+=(hyperv dosfstools
				"${CMDLINE[@]}" "${KERNEL[@]}")

			# setup the ethernet network
			cat > "$MOUNTPOINT/etc/systemd/network/default.network" <<-'EOD'
			[Match]
			Name=eth0

			[Network]
			DHCP=yes
			IPv6AcceptRA=yes
EOD

			arch-chroot "$MOUNTPOINT" systemctl enable nftables.service
			original /etc/fstab
			column -t /tmp/fstab.btrfs >> "$MOUNTPOINT/etc/fstab"
			;;
		'MacBookAir5,2' )
			# intel-media-driver for newer devices
			PACKAGES+=(dosfstools
				intel-ucode vulkan-intel libva-intel-driver
				"${WIFI[@]}" "${DESKTOP[@]}"
				"${CMDLINE[@]}" "${KERNEL[@]}")

			# setup the wireless network
			cat > "$MOUNTPOINT/etc/systemd/network/default.network" <<-'EOD'
			[Match]
			Name=wlan0

			[Network]
			DHCP=yes
			IPv6AcceptRA=yes
EOD

			arch-chroot "$MOUNTPOINT" systemctl enable nftables.service
			original /etc/fstab
			column -t /tmp/fstab.btrfs >> "$MOUNTPOINT/etc/fstab"
			;;
		'WSL' )
			PACKAGES+=(btrfs-progs
				"${CMDLINE[@]}" "${DOCS[@]}")

			cat > "$MOUNTPOINT/etc/wsl.conf" <<-'EOD'
			[boot]
			systemd=true
EOD
			;;
		'Desktop' )
			PACKAGES+=("${BASE[@]}" "${CMDLINE[@]}")
			;;
		* )
			msg --tag error --color 1 "unknown platform ${ARGS[platform]}"
			return 3
			;;
	esac

	msg --tag install --color 4 "installing additional packages for ${ARGS[platform]}"
	arch-chroot "$MOUNTPOINT" pacman -S --needed "${PACKAGES[@]}"

	configure "$(arch-chroot "$MOUNTPOINT" pacman -Qq)"

	msg --tag install --color 4 'clearing package cache'
	yes | arch-chroot "$MOUNTPOINT" pacman -Scc || true

	msg --tag install --color 4 'removing socket files'
	rm -f "$MOUNTPOINT/etc/pacman.d/gnupg/S.gpg-agent"*

	msg --color 1 'do not forget to add a user!'

	return 0
}
main "$@"

# vim: ts=3 sw=0 sts=0
