#!/bin/bash

main() {
	local mountpoint="$@"
	local mounts=$(findmnt --submounts --nofsroot --noheadings --output SOURCE,TARGET,FSTYPE,OPTIONS,FSROOT --canonicalize --evaluate --raw --notruncate $mountpoint)
	echo "$mounts" | while read -r src target fstype opts fsroot; do
		target="${target#$mountpoint}"
		[[ $target == '/boot' ]] && continue

		[[ ! "$target" ]] && opts=$(sed '/,subvolid.*//' <<< "$opts")

		printf '%s %s %s %s %i %i\n' \
			"UUID=$(blkid -o value -s UUID "$src")" \
			"${target:-/}" \
			"$fstype" \
			"$opts" \
			0 0
	done

}
main "$@"
