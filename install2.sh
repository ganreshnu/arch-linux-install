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
Usage: $(basename "$BASH_SOURCE") [OPTIONS]

Options:
  --help                         Show this message and exit.
  --value STRING                 A value.
  --message STRING               A message.

Install an Arch Linux Distribution.
EOD
}

declare -A args=(
	[value]=""
	[message]=""
)

parseargs() {
	local showusage=-1 value="" remove=0
	getvalue() {
		name="$1"; shift
		if [[ $# -gt 1 && "$2" != -?* ]]; then
			args["$name"]="$2"
			remove=2
		else
			msg error 1 "$1 requires an argument"
			showusage=1 remove=1
		fi
	}

	while true; do
		if [[ $# -gt 0 && "$1" == -* ]]; then
			case "$1" in
				--value )
					getvalue value "$@"
					shift $remove
					;;
				--message )
					getvalue message "$@"
					shift $remove
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


#
# define the main encapsulation function
#
main() {
	#
	# parse the arguments
	#
	parseargs "$@" && set -- ${args[_]}
	local showusage=$1; shift

	#
	# argument type validation goes here
	#

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
	timedatectl set-ntp true || true

	local here=$(dirname "$BASH_SOURCE")

	findpart() {
		lsblk --noheadings --output NAME,PARTTYPE --paths --raw | awk "/$1/ {print \$1}"
	}
	# find swap device
	swap=$(findpart '0657fd6d-a4ab-43c4-84e5-0933c84b4f4f')
	
	# find root device
	root=$(findpart '4f68bce3-e8cd-4db1-96e7-fbcaf984b709')
	# find efi device
	boot=$(findpart 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b')

	msg log 4 "swap=$swap root=$root boot=$boot"
	[[ $# -gt 0 ]] && msg warn 3 "extra args: $@"

	return 0
}
main "$@"

# vim: ts=3 sw=0 sts=0
