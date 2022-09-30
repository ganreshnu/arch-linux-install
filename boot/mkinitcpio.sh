#!/bin/bash
set -euo pipefail

showhelp() {
	cat <<EOD
Usage: mkinitcpio.sh [OPTIONS] ROOT_PARTITION

Make a kernel initial filesystem. Outputs esp-path/EFI/Linux/archlinux-systemd.efi

Options:
  --cmdline			Show commandline and exit
  --microcode		Microcode to run first
  --module			Additional modules to add
  --resume			The resume partition
  --opt				A kernel option (may be passed multiple times)
  --esp-path		Alternate esp path (default /boot)
  --reboot			Reboot after install

EOD
}

main() {
	local opts=()
	local modules=()
	local esp_path=/boot
	local showcmdline
	local microcode
	local wanthelp=0
	local resume
	local reboot
	while :
	do
		if [[ "$1" == --* ]]; then
			case "$1" in
				--help )
					wanthelp=1
					shift
					;;
				--cmdline )
					showcmdline=yes
					shift
					;;
				--microcode )
				 	microcode="$2"
					shift 2
					;;
				--module )
				 	modules+=("$2")
					shift 2
					;;
				--resume )
				 	resume="$2"
					shift 2
					;;
				--opt )
				 	opts+=("$2")
					shift 2
					;;
				--esp-path )
					esp_path="$2"
					shift 2
					;;
				--reboot )
					reboot=yes
					shift
					;;
				* )
					>&2 echo "unknown option $1"
					wanthelp=2
					shift
					;;
			esac
		else
			break
		fi
	done
	
	if [[ ! $1 ]]; then
	 	>&2 echo "ROOT_PARTITION must be set"
		wanthelp=2
	fi
	
	[[ $wanthelp -eq 1 ]] && showhelp && exit
	[[ $wanthelp -eq 2 ]] && showhelp && exit 1
	
	# directory containing this script
	local here=$(dirname $BASH_SOURCE)
	
	# generate command line
	local cmdline_file=$(mktemp)
	local cmdline="root=$1 quiet consoleblank=60"
	[[ $resume ]] && cmdline="$cmdline resume=$resume"
	for i in ${opts[@]}; do
		cmdline="$cmdline $i"
	done
	echo $cmdline > $cmdline_file
	
	if [[ $showcmdline ]]; then
		cat $cmdline_file
		rm $cmdline_file
		exit
	fi
	
	# setup the microcode argument
	[[ $microcode ]] && microcode="--microcode $microcode"
	
	# generate config file
	local mods
	for i in ${modules[@]}; do
		mods="$mods $i"
	done
	local config_file=$(mktemp)
	cat > $config_file <<-EOD
	MODULES=($mods)
	HOOKS=(keyboard autodetect systemd modconf block filesystems fsck)
EOD
	mkinitcpio --config $config_file --splash /usr/share/systemd/bootctl/splash-arch.bmp \
		--cmdline $cmdline_file --uefi $esp_path/EFI/Linux/archlinux-systemd.efi $microcode

	rm $cmdline_file
	rm $config_file
	
	[[ $reboot ]] && reboot now
}
main "$@"

# vim: ts=3 sw=1 sts=0
