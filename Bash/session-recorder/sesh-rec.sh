#!/usr/bin/env bash

declare log_dir="$HOME/.local/session-recorder/logs"
declare current_date_dir="$log_dir/$(date +%Y-%m-%d)"
declare log_file_name="$current_date_dir/sesh-$(date +%Y-%m-%d_%H-%M-%S).log"

record() {
	if [ -z "$1" ]; then
		local output="$log_file_name"
	else
		local output="$1"
	fi
	
	local timing="${output%.log}.timing"
	script --timing=$timing $output
}

replay() {
	local replay_mode="$1"
	[[ "$replay_mode" =~ ^(instant|stream|-s|-i)$ ]] || { echo "Please select a valid mode [ instant/-i | stream/-s ]" && exit 1; }

	if [ -z "$2" ]; then
		echo "You have to select a log file to replay"; exit 1;
	else
		local replay_file="$2"
		local timing="${replay_file%.log}.timing"
		[ -f "$replay_file" ] || { echo "Selected log file [ $replay_file ] doesn't exist"; exit 1; }
		[ -f "$timing" ] || { echo "Selected timing file [ $timing ] doesn't exist"; exit 1; }
	fi

	case "$replay_mode" in
		"instant|-i")
			less -Xfr $replay_file;;
		"stream|-s")
			scriptreplay -d 2 --timing=$timing $replay_file;;
		*)
			echo "Please select a valid mode [ --instant/-i | --stream/-s ]"; exit 1;;
	esac
}

mkdir -p $current_date_dir

declare mode="$1"
shift

case "$mode" in
	"record")
		record "$@";;
	"replay")
		replay "$@";;
	*)
		echo "Invalid Option [ $mode ]"; exit 1;;
esac
