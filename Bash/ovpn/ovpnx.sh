#!/usr/bin/env bash

import() {
	CONFIG_FILE=$(realpath "$1" 2>/dev/null)
	CONFIG_NAME="$2"
	[ -f "${CONFIG_FILE}" ] || { echo "[$CONFIG_FILE] file doesn't exist..."; exit 1; }
	[ -z "${CONFIG_NAME}" ] && { echo "CONFIG_NAME can't be empty"; exit 1; }
	openvpn3 config-import --config "$CONFIG_FILE" --name "$CONFIG_NAME" --persistent
}

list() {
	OPTION="$1"
	[ -z "${OPTION}" ] && { openvpn3 configs-list; exit 0; }
	{ [ "$OPTION" = "s" ] || [ "$OPTION" = "session" ]; } || { echo "Invalid list option [$OPTION]"; exit 1; } && { openvpn3 sessions-list; exit 0; }
}

remove() {
	REMOVE_CONFIG_NAME="$1"
	[ -n "${REMOVE_CONFIG_NAME}" ] && grep "$REMOVE_CONFIG_NAME" <<< $(list) > /dev/null || { echo "The connection [$REMOVE_CONFIG_NAME] doesn't exist"; exit 1; }
	openvpn3 config-remove --config "$REMOVE_CONFIG_NAME"
}

connect() {
	CONNECT_CONFIG_NAME="$1"
	CONFIG_LIST=($(list | tail -n +3 | head -n -1 | awk '{print $1}'))
	[ -z "${CONNECT_CONFIG_NAME}" ] && CONNECT_CONFIG_NAME="${CONFIG_LIST[0]}" || { grep "\-\-\-$CONNECT_CONFIG_NAME---" <<< $(echo -n "---";printf "%s---" "${CONFIG_LIST[@]}") > /dev/null || { echo "The connection [$CONNECT_CONFIG_NAME] doesn't exist"; exit 1; }; }
	
	openvpn3 session-start --config "${CONNECT_CONFIG_NAME}"
}

disconnect() {
	DISCONNECT_CONFIG_NAME="$1"
	SESSION_LIST=($(list s | grep "Config name:" | sed 's|Config name:||' | sed 's|^[[:space:]]*||'))
	[ -z "${DISCONNECT_CONFIG_NAME}" ] && DISCONNECT_CONFIG_NAME="${SESSION_LIST[0]}" || { grep "\-\-\-$DISCONNECT_CONFIG_NAME---" <<< $(echo -n "---";printf "%s---" "${SESSION_LIST[@]}") > /dev/null || { echo "The connection [$DISCONNECT_CONFIG_NAME] doesn't have an active session"; exit 1; }; }

	openvpn3 session-manage --disconnect --config "${DISCONNECT_CONFIG_NAME}"
}

stats() {
	STATS_CONFIG_NAME="$1"
	SESSION_LIST=($(list s | grep "Config name:" | sed 's|Config name:||' | sed 's|^[[:space:]]*||'))
	[ -z "${STATS_CONFIG_NAME}" ] && STATS_CONFIG_NAME="${SESSION_LIST[0]}" || { grep "\-\-\-$STATS_CONFIG_NAME---" <<< $(echo -n "---";printf "%s---" "${SESSION_LIST[@]}") > /dev/null || { echo "The connection [$STATS_CONFIG_NAME] doesn't have an active session"; exit 1; }; }

	openvpn3 session-stats --config "${STATS_CONFIG_NAME}"
}

log() {

	OPTION="$1"
	[ "$OPTION" = "all" ] && { sudo openvpn3-admin journal; exit 0; }

	LOG_FILE=$(mktemp)
	trap 'rm "$LOG_FILE"' EXIT
	(
		while true; do
			sudo openvpn3-admin journal --since "$(date -d "1 second ago" +%Y-%m-%d\ %H:%M:%S)" 2> /dev/null >> $LOG_FILE
			sleep 1
		done
	) &
	LOOP_PID="$!"

	trap 'kill "$LOOP_PID"' SIGINT
	tail -n 0 -f $LOG_FILE
}

help() {
	cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  import <file> <name>       Import an OpenVPN configuration file with a name
  list, ls [s|session]       List imported configurations (or active sessions with 's' or 'session')
  remove, rm <name>          Remove an imported configuration
  c, connect, start [name]   Connect to a VPN configuration (defaults to first available)
  d, disconnect, stop [name] Disconnect an active VPN session (defaults to first active)
  stats [name]               Show statistics for an active VPN session (defaults to first active)
  log [all]                  Stream live logs (or view system journal logs with 'all')
  help, -h, --help           Display this help message
EOF
}

main() {
	#binary check
	command -v openvpn3 > /dev/null || { echo "openvpn3 command can't be found"; exit 1;}

	ACTION="$1"
	[ $# -gt 0 ] && shift

	case "$ACTION" in
		import)
			import "$@"
			;;
		list|ls)
			list "$@"
			;;
		remove|rm)
			remove "$@"
			;;
		c|connect|start)
			connect "$@"
			;;
		d|disconnect|stop)
			disconnect "$@"
			;;
		stats)
			stats "$@"
			;;
		log)
			log "$@"
			;;
		help|-h|--help)
			help
			;;
		*)
			[ -n "$ACTION" ] && echo "Invalid action [$ACTION]"
			help
			[ -z "$ACTION" ] && exit 0 || exit 1
			;;
	esac

}

main "$@"
