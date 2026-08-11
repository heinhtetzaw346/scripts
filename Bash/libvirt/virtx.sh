#!/usr/bin/env bash

#Variables
declare VIRTX_INSTALL_PATH="$HOME/.local/bin/virtx"
declare VIRTX_SESSIONS_DIR="$HOME/.local/virtx/sessions"

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
	local HELP_MESSAGE="## Libvirt KVM Wrapper - virtx ##
usage:
"
	printf "%s\n" "${HELP_MESSAGE}"
}


install() {
	log progress "Installing $0 to ${VIRTX_INSTALL_PATH}"

	mkdir -p $(dirname ${VIRTX_INSTALL_PATH})
	cp $0 ${VIRTX_INSTALL_PATH}
	chmod +x ${VIRTX_INSTALL_PATH}

	log success "virtx has been installed to ${VIRTX_INSTALL_PATH}"
	
	local INSTALL_HELP_MESSAGE="Please run the following command to add the virtx path to PATH if it's not already done so.

##for bash
echo \"export PATH=\$PATH:$(dirname ${VIRTX_INSTALL_PATH})\" >> $HOME/.bashrc 

##for zsh
echo \"export PATH=\$PATH:$(dirname ${VIRTX_INSTALL_PATH})\" >> $HOME/.zshrc
"

	printf "%s\n" "${INSTALL_HELP_MESSAGE}"
	log normal "Run -[ virtx help ]- to confirm the installation"

}

instance() {
	echo "launch"
}

main() {
	OPTION="$1"
	shift
	case "$OPTION" in
		help)
			help
			;;
		install)
			install
			;;
		instance)
			instance
			;;
		*)
			echo "boop"
			;;
	esac
}

main "$@"

