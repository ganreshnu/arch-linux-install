#!/bin/bash

usage() {
	cat <<EOD
Usage: $(basename "$BASH_SOURCE") [OPTIONS] DEVICE

Create preconfigured subvolumes on DEVICE.

Options:
  --mount DIRECTORY       The mountpoint on which to mount the subvolumes.
  --fstab FILE            Write the fstab to this file.
  -h, --help              Show this message and exit.

Other info here.
EOD
}

declare -A ARGS=(
	[mount]='/mnt'
	[fstab]='/tmp/fstab.btrfs'
)

set -euo pipefail

main() {
	declare -r HERE=$(dirname "$BASH_SOURCE")

	#
	# include the util functions
	#
	. "$HERE/script-util/pargs.sh"

	#
	# parse arguments
	#
	local showhelp=-1
	if pargs usage "$@"; then
		mapfile -t args <<< "${ARGS[_]}"
		set -- "${args[@]}" && unset args ARGS[_]
	else
		[[ $? -eq 255 ]] && showhelp=0 || showhelp=$?
	fi

	if [[ $# -lt 1 ]]; then
		msg error 1 'must pass root filesystem device'
		return 1
	fi

	#
	# argument type validation goes here
	#


	#
	# show help if necessary
	#
	if [[ $showhelp -ne -1 ]]; then
		usage
		return $showhelp
	fi
	unset showhelp

	#
	# argument value validation goes here
	#


	#
	# script begins
	#

	local ROOTDEVICE="$1"
	local MOUNTPOINT="${ARGS[mount]}"

	mkfs.btrfs -L linux -f "$ROOTDEVICE"
	local BTRFSROOT=$(mktemp -d)
	mount -o subvol=/ "$ROOTDEVICE" "$BTRFSROOT"

	rm -f "${ARGS[fstab]}"
	local opts= uuid="$(blkid -o value -s UUID "$ROOTDEVICE")"

	btrfs subvolume create "$BTRFSROOT/@current"
	btrfs subvolume set-default "$BTRFSROOT/@current"
	opts='defaults,noatime,compress=zstd'
	mount -o "$opts" "$ROOTDEVICE" "$MOUNTPOINT"
	printf 'UUID=%s / btrfs %s 0 0 \n' "$uuid" "$opts" >> "${ARGS[fstab]}"

	for path in home srv var/cache var/log var/tmp var/lib/machines var/lib/portables; do
		case "$path" in
			home)
				opts='defaults,relatime,autodefrag,compress=zstd'
				;;
			*)
				opts='defaults,noatime,autodefrag,compress=zstd'
				;;
		esac

		local sv= dn="$(dirname "$path")" bn="$(basename "$path")"
		if [[ "$dn" == '.' ]]; then
			sv="@$bn"
		else
			mkdir -p "$BTRFSROOT/$dn"
			sv="$dn/@$bn"
		fi

		btrfs subvolume create "$BTRFSROOT/$sv"
		mkdir -p "$MOUNTPOINT/$path"
		mount -o "$opts,subvol=$sv" "$ROOTDEVICE" "$MOUNTPOINT/$path"
		printf "UUID=%s /%s btrfs %s,subvol=%s 0 0\n" "$uuid" "$path" "$opts" "$sv" >> "${ARGS[fstab]}"
	done

	umount "$BTRFSROOT" && rmdir "$BTRFSROOT"
}
main "$@"

