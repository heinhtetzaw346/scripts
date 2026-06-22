#!/usr/bin/env bash

declare log_dir="$HOME/.local/session-recorder/logs"
declare current_date_dir="$log_dir/$(date +%Y-%m-%d)"
declare log_file_name="$current_date_dir/sesh-$(date +%Y-%m-%d_%H-%M-%S).log"

help() {
	echo "----------------------------------------------------------------------------
Usage: $0 [ help | record | replay ] [ options ] [ arguments ]
Example
$0 record [ hit CTRL+D or enter 'exit' to stop recording ]
$0 record my-record.log [ provide explicit file name ]
$0 replay -s|--stream my-record.log [ replay with stream mode ];
$0 replay -i|--instant my-record.log [ replay with instant mode ];
$0 replay -s 2 my-record.log [ replay stream mode with double speed ];
$0 replay -s -I|--interactive [ select file to replay interactively ]
$0 showdir [ show default log directory ]
$0 cleanup [ clean up log date directories older than one month in default log directory ]
$0 cleanup -A|--all [ clean up all log date directories in default log directory ] "
	return 0
}

record() {

	if [ -z "$RECORDING" ]; then
		export RECORDING="true"
	fi

	if [ -z "$1" ]; then 
		mkdir -p $current_date_dir
		local output="$log_file_name" 
	else
		local output="$1"
	fi
	
	local timing="${output%.log}.timing"
	script --timing=$timing $output
	return 0
}

get_check_replay_file(){
	if [ -z "$1" ]; then
		echo "You have to select a log file to replay"; exit 1;
	else
		replay_file="$1"
		timing_file="${replay_file%.log}.timing"
		[ -f "$replay_file" ] || { echo "Selected log file [ $replay_file ] doesn't exist"; exit 1; }
		[ -f "$timing_file" ] || { echo "Selected timing file [ $timing_file ] doesn't exist"; exit 1; }
	fi
	return 0
}

instant() {
	get_check_replay_file "$1"
	less -Xfr $replay_file
	return 0
}

interactive_select() {
	if ! command -v fzf > /dev/null; then
		echo "fzf is not installed on this machine, please install it first to use interactive select"
		exit 1
	fi

	local selected_dir=$(find $log_dir/* -type d | fzf --reverse)
	interactive_selected_replay_file=$(find $selected_dir -type f -name "*.log" | fzf --reverse)
	echo "Selected $interactive_selected_replay_file for replay"
}

stream() {
	if [[ $1 =~ ^[+-]?([0-9]+\.?[0-9]*|[0-9]*\.[0-9]+)$ ]]; then
		replay_speed="$1"
		shift
	else
		replay_speed="1"
	fi

	file_input="$1"

	if [[ $file_input =~ ^(-I|--interactive)$ ]]; then
		interactive_select
		file_input="$interactive_selected_replay_file"
	fi

	get_check_replay_file "$file_input"

	scriptreplay -d $replay_speed --timing=$timing_file $replay_file
	return 0
}

replay() {
	local replay_mode="$1"
	shift

	case "$replay_mode" in
		--instant|-i)
			instant "$@";;
		--stream|-s)
			stream "$@";;
		*)
			echo "Please select a valid mode [ --instant/-i | --stream/-s ]"; exit 1;;
	esac
	return 0
}

showdir() {
	local temp_file=$(mktemp)
	trap "rm '$temp_file'" EXIT
	echo "Current default directory: $log_dir"
	echo "Available log files"
	echo "------------------------------------------"
	for date_dir in "$log_dir"/*/; do
		local dirname
		dirname=$(basename "$date_dir")

		echo "$dirname" >> $temp_file
		for file in "$date_dir"/*.log; do
				[ -e "$file" ] || continue
				echo "    $(basename "$file")" >> $temp_file
		done
	done
	less -F $temp_file
	return 0
}

cleanup() {
	local check_dates="true"

	if [[ "$1" == "-A" || "$1" == "--all" ]]; then
		read -p "Are you sure you want to clear all the logs? [Y|n]: " confirm
		[ "$confirm" == "Y" ] && check_dates="false"
	fi

	local a_month_ago=$(date -d "a month ago" +%s)
	found="false"

	for date_dir in "$log_dir"/*/; do

		local dir_name=$(basename "$date_dir")
		local should_delete="false"

		if [ "$check_dates" = "false" ]; then 
			should_delete="true"
		else
			local folder_date=$(date -d "$dir_name" +%s)
			(( folder_date < a_month_ago )) && should_delete="true"
		fi

		if [ "$should_delete" == "true" ]; then
			echo "Cleaning up $date_dir"
			rm -rf $date_dir
			found="true"
		fi
	done

	[ "$found" == "true" ] || { echo "Nothing to clean up"; exit 0; } && echo "Clean up process finished" 
}

mkdir -p $log_dir

declare mode="$1"
shift

case "$mode" in
	"help")
		help
		;;
	"record")
		record "$@"
		;;
	"replay")
		replay "$@"
		;;
	"showdir")
		showdir
		;;
	"cleanup")
		cleanup "$@"
		;;
	*)
		echo "Invalid Option [ $mode ]"
		help
		exit 0
		;;
esac
