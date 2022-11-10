#!/bin/bash

#
# mkinitcpio.sh
#
# Make a unified initial ram disk
#

#
# define a usage function
#
usage() {
	cat <<EOD
Usage: mkinitcpio.sh [OPTIONS] ROOT_PARTITION

Make a kernel initial filesystem. Outputs esp-path/EFI/Linux/archlinux-systemd.efi

Options:
  --help                        Show this message and exit.
  --cmdline                     Show commandline and exit.
  --microcode FILENAME          Path to the microcode file.
  --module MODULE               Additional module to add. May be passed
                                multiple times.
  --resume GPTIDENTIFIER        The resume GPT partition identifier.
  --opt OPTION                  Additional kernel option. May be passed
                                multiple times.
  --esp-path DIRECTORY          Alternate esp path. (default /boot)
  --reboot                      Reboot after install.

EOD
}

#
# script autocomplete
#
if [[ "$0" != "$BASH_SOURCE" ]]; then
	set -uo pipefail
	# generic autocomplete function that parses the script help
	_mkinitcpio_dot_sh_completions() {
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
		GPTIDENTIFIER )
			completions="$(blkid | awk '{ for(i=1;i<=NF;i++){ if($i ~ /^PART(LABEL|UUID)/) print $i }}')"
			COMPREPLY=($(compgen -W "$completions" -- "$cur"))
			;;
		[A-Z]* )
			;;
		* )
			COMPREPLY=($(compgen -W "$completions" -- "$cur"))
			;;
		esac
	}
	complete -o noquote -o bashdefault -o default \
		-F _mkinitcpio_dot_sh_completions $(basename "$BASH_SOURCE")
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
mkinitcpio_dot_sh() { local showusage=-1

	#
	# declare the variables derived from the arguments
	#
	local opts=()
	local modules=()
	local esp_path=/boot
	local showcmdline=""
	local microcode=""
	local resume=""
	local reboot=""

	#
	# parse the arguments
	#
	while true; do
		if [[ $# -gt 0 && "$1" == -* ]]; then
			case "$1" in
				--cmdline )
					showcmdline=yes
					shift
					;;
				--microcode )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						microcode="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--module )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						modules+=("$2")
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--resume )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						resume="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--opt )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						opts+=("$2")
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--esp-path )
					if [[ $# -gt 1 && "$2" != -?* ]]; then
						esp_path="$2"
						shift 2
					else
						error "$1 requires an argument"
						showusage=1
						shift
					fi
					;;
				--reboot )
					reboot=yes
					shift
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
	if [[ $# -lt 1 ]]; then
	 	error "ROOT_PARTITION must be set"
		showusage=1
	fi

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
	local mods=""
	for i in ${modules[@]}; do
		mods="$mods $i"
	done
	local config_file=$(mktemp)
	cat > $config_file <<-EOD
	MODULES=($mods)
	HOOKS=(keyboard autodetect systemd modconf block filesystems fsck)
EOD
	mkinitcpio --config $config_file --splash /usr/share/systemd/bootctl/splash-arch.bmp \
		--cmdline $cmdline_file --kernel "$(ls /usr/lib/modules |tail -n1)" \
		--uefi $esp_path/EFI/Linux/archlinux-systemd.efi $microcode

	rm $cmdline_file
	rm $config_file
	
	[[ $reboot ]] && reboot now
}
mkinitcpio_dot_sh "$@"

# vim: ts=3 sw=3 sts=0
