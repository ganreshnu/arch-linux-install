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
Usage: $(basename "$BASH_SOURCE") [OPTIONS] [PLATFORM]

Options:
  --help                         Show this message and exit.
  --lang LANGUAGE                The system language. Defaults to \$LANG.
  --timezone TIMEZONE            The system timezone. Defaults to the current
                                 system's timezone.
  --hostname STRING              The sytem hostname. Defaults to 'jwux'.

  --platform DIRECTORY           The target platform from which to derive
                                 configuration.

Install an Arch Linux Distribution.
EOD
}

declare -A args=(
	[lang]="$LANG"
	[timezone]="$(realpath --relative-to /usr/share/zoneinfo $(readlink /etc/localtime))"
	[hostname]="jwux"
	[platform]="$([[ -f /sys/class/dmi/id/product_name ]] && cat /sys/class/dmi/id/product_name)"
)

parseargs() {
	local showusage=-1 value="" sc=0
	getvalue() {
		name="$1"; shift
		if [[ $# -gt 1 && "$2" != -?* ]]; then
			args["$name"]="$2"
			sc=2
		else
			msg error 1 "$1 requires an argument"
			showusage=1 sc=1
		fi
	}

	while true; do
		if [[ $# -gt 0 && "$1" == -* ]]; then
			case "$1" in
				--lang )
					getvalue lang "$@"
					shift $sc
					;;
				--timezone )
					getvalue timezone "$@"
					shift $sc
					;;
				--hostname )
					getvalue hostname "$@"
					shift $sc
					;;
				--platform )
					getvalue platform "$@"
					shift $sc
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
					msg error 1 "unknown argument $1"
					showusage=1
					shift
					;;
			esac
		else
			break
		fi
	done
	args[_]="$showusage $@"
}

#
# define a message function
#
msg() {
	local tag=$1 color=$2 
	shift 2
	>&2 printf "$(tput bold; tput setaf $color)%s:$(tput sgr0) %s\n" "$tag" "$@"
}

format() {
	local swapuuid='0657fd6d-a4ab-43c4-84e5-0933c84b4f4f'
	local rootuuid='4f68bce3-e8cd-4db1-96e7-fbcaf984b709'
	local bootuuid='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'

	local partitions=$(lsblk --noheadings --paths --raw --output PARTTYPE,NAME,FSTYPE,MOUNTPOINT)
	getprop() {
		echo "$partitions" | awk "\$1 == \"$1\" { print \$$2 }"
	}

	local mounted='' dev=''
	dev="$(getprop $swapuuid 2)"
	if [[  "$dev" ]]; then
		[[ "$(getprop $swapuuid 3)" != 'swap' ]] && mkswap "$dev"
		mounted="$(getprop $swapuuid 4)"
		[[ "$mounted" ]] || swapon "$dev"
	fi

	dev="$(getprop $rootuuid 2)"
	if [[ "$dev" ]]; then
		[[ "$(getprop $rootuuid 3)" != 'ext4' ]] && mkfs.ext4 "$dev"
		mounted="$(getprop $rootuuid 4)"
		[[ "$mounted" ]] || mount "$dev" "$MOUNTPOINT"
	fi

	dev="$(getprop $bootuuid 2)"
	if [[ "$dev" ]]; then
		[[ "$(getprop $bootuuid 3)" != 'vfat' ]] && mkfs.fat -F 32 "$dev"
		mounted="$(getprop $bootuuid 4)"
		if [[ ! "$mounted" ]]; then
			mkdir -p "$MOUNTPOINT/boot"
			mount "$dev" "$MOUNTPOINT/boot"
			bootctl --esp-path="$MOUNTPOINT/boot" install
		fi
	fi

	return 0
}

#
# define the main encapsulation function
#
main() {
	#
	# parse the arguments
	#
	parseargs "$@" && set -- ${args[_]} && unset args[_]
	local showusage=$1; shift

	local MOUNTPOINT=''
	[[ $# -gt 0 && "$1" ]] && MOUNTPOINT="$1" || MOUNTPOINT="/mnt"

	#
	# argument type validation goes here
	#

	[[ $# -gt 0 ]] && msg warn 3 "extra args: $@"
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

	local PACKAGES=(base iptables-nft reflector polkit)
	local DOCS=(man-db man-pages texinfo)
	local CMDLINE=(sudo bash-completion git vim openssh)
	local KERNEL=(linux linux-firmware wireless-regdb mkinitcpio tpm2-tss)

	local filesystem
	case "${args[platform]}" in
		'Virtual Machine' )
			PACKAGES+=(hyperv firewalld dosfstools 
				"${CMDLINE[@]}" "${KERNEL[@]}")
#			format 'ext4'
			;;
		'MacBookAir5,2' )
#			format 'f2fs'
			echo mba
			;;
		* )
			format 'fat'
			echo unk
			;;
	esac


	for key in "${!args[@]}"; do
		printf '%s = %s\n' "$key" "${args[$key]}"
	done
	echo "MOUNTPOINT = $MOUNTPOINT"

	read -n 1 -p "continue to install? (y/N) " go
	[[ $go =~ y|Y ]] && echo || return 1

	msg install 4 "updating the pacman mirrorlist"
	reflector --save /etc/pacman.d/mirrorlist --country US --age 1 --score 6 --fastest 3 --protocol 'https'
	pacman -Sy

	# bootstrap the install
	msg install 4 "installing the packages"
	if ! pacstrap -iK $MOUNTPOINT "${PACKAGES[@]}"; then
		read -n 1 -p "pacstrap failed. continue? (y/N) " go
		[[ $go =~ y|Y ]] && echo || return 1
	fi

	# setup the hw clock
	msg install 4 "setting up the hardware clock"
	arch-chroot $MOUNTPOINT hwclock --systohc --update-drift


	PACKAGES="$(arch-chroot $MOUNTPOINT pacman -Qq)"
	haspackage() {
		[[ "$PACKAGES" =~ (^|[[:space:]])$1([[:space:]]|$) ]]
	}

	# sync pacman
#	arch-chroot "$MOUNTPOINT" pacman -Sy

	msg install 4 "installing configurations"
	local here=$(dirname "$BASH_SOURCE")
	for f in $here/config/*; do
		if haspackage $(basename "$f"); then
			. "$f"
			config
		fi
	done; unset f

	return 0
}
main "$@"

# vim: ts=3 sw=0 sts=0
