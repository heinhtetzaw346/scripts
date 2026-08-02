#!/usr/bin/env bash

#Variables
declare AGYX_INSTALL_PATH="$HOME/.local/bin/agyx"
declare AGYX_SESSIONS_DIR="$HOME/.local/agyx/sessions"

#Colors
declare WHITE="\033[0m" #white
declare RED="\033[1;31m" #red
declare GREEN="\033[1;32m" #green
declare YELLOW="\033[1;33m" #yellow

log() {

	case "$1" in
		success)
			echo -e "$GREEN$2$WHITE"
			;;
		failure)
			echo -e "$RED$2$WHITE"
			;;
		progress)
			echo -e "$YELLOW$2$WHITE"
			;;
		normal)
			echo -e "$2"
			;;
	esac

}

help() {
	local HELP_MESSAGE="## AGY Wrapper - agyx ##
usage:
$0 path/to/dir - cd to the directory and run agy. Save the dir as a session for later use.
$0 sessions/s - select and run agy -c in directories with previous sessions
$0 sessions/s ls - print out all the stored sessions
$0 sessions/s rm - remove the stored session. Next time will only run with agy instead of agy -c
$0 install - install the current script in the AGYX_INSTALL_PATH"
	printf "%s\n" "${HELP_MESSAGE}"
}


install() {
	log progress "Installing $0 to ${AGYX_INSTALL_PATH}"

	mkdir -p $(dirname ${AGYX_INSTALL_PATH})
	cp $0 ${AGYX_INSTALL_PATH}
	chmod +x ${AGYX_INSTALL_PATH}

	log success "agyx has been installed to ${AGYX_INSTALL_PATH}"
	
	local INSTALL_HELP_MESSAGE="Please run the following command to add the agyx path to PATH if it's not already done so.

##for bash
echo \"export PATH=\$PATH:$(dirname ${AGYX_INSTALL_PATH})\" >> $HOME/.bashrc 

##for zsh
echo \"export PATH=\$PATH:$(dirname ${AGYX_INSTALL_PATH})\" >> $HOME/.zshrc
"

	printf "%s\n" "${INSTALL_HELP_MESSAGE}"
	log normal "Run -[ agyx help ]- to confirm the installation"

}

init() {
	if ! [ -d "${AGYX_SESSIONS_DIR}" ]; then
		log progress "Creating ${AGYX_SESSIONS_DIR}"
		mkdir -p "${AGYX_SESSIONS_DIR}"
	fi
}

session_name_exists() {
	SESSION_NAME="$1"
	if find ${AGYX_SESSIONS_DIR} -type file -name "${SESSION_NAME}"; then
		echo "true"
	else
		echo "false"
	fi
}

session_path_exists() {
	SESSION_PATH="$1"

}

direct_access() {
	DIRECT_ACCESS_PATH="$1"
	SESSION_NAME="$2"
	if [ -z "${DIRECT_ACCESS_PATH}" ]; then
		log failure "Invalide Input"
		help
		exit 1
	elif ! [ -d "$(realpath ${DIRECT_ACCESS_PATH})" ]; then
		log failure "No directory exists at ${DIRECT_ACCESS_PATH}"
		exit 1
	fi

	ln -sf ${DIRECT_ACCESS_PATH} ${AGYX_SESSIONS_DIR}/${SESSION_NAME}
}

main() {
	init
	case "$1" in
		help)
			help
			;;
		install)
			install
			;;
		*)
			direct_access "$@"
			;;
	esac
}

main "$@"
