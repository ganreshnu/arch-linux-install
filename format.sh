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

