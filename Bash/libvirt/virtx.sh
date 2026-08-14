#!/usr/bin/env bash

#Variables
declare VIRTX_INSTALL_PATH="$HOME/.local/bin/virtx"

#Colors
declare WHITE="\033[0m" #white
declare RED="\033[1;31m" #red
declare GREEN="\033[1;32m" #green
declare YELLOW="\033[1;33m" #yellow

#global default
VERBOSE="false"

log() {
  case "$1" in
    success)
      echo -e "$GREEN$2$WHITE"
      ;;
    error)
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
  cat << EOF
## Libvirt KVM Wrapper - virtx ##
Usage: $(basename "$0") <command> [options]

Commands:
  instance|i      instance related commands
  storage|s       storage related commands
  network|n       network related commands
  help|--help|-h  show this page

Options:
  --verbose|-v    show what's being done in detail
  
Hint: help can be run after each command for more details.
EOF
}

install() {
  log progress "Installing $0 to ${VIRTX_INSTALL_PATH}"

  mkdir -p $(dirname ${VIRTX_INSTALL_PATH})
  cp $0 ${VIRTX_INSTALL_PATH}
  chmod +x ${VIRTX_INSTALL_PATH}

  log success "virtx has been installed to ${VIRTX_INSTALL_PATH}"
  
cat << EOF 
Please run the following command to add the virtx path to PATH if it's not already done so.

##for bash
echo \"export PATH=\$PATH:$(dirname ${VIRTX_INSTALL_PATH})\" >> $HOME/.bashrc 

##for zsh
echo \"export PATH=\$PATH:$(dirname ${VIRTX_INSTALL_PATH})\" >> $HOME/.zshrc

Run [ virtx help ] to confirm the installation
EOF
}

process_subcommand_args() {
  RESOURCE_TYPE="$1"
  shift
  IFS=" " read -a ARGS <<< "$@"
  if grep -v "^--.*$" > /dev/null <<< "${ARGS[0]}"; then
    RESOURCE_NAME="${ARGS[0]}"
  else
    log error "${RESOURCE_TYPE} name has to be provided"
    exit 1
  fi
  if grep "^--.*$" > /dev/null <<< "${ARGS[1]}"; then
    INTERACTIVE_MODE="false"
  else
    INTERACTIVE_MODE="true"
  fi
}

interactive_select() {
  echo "pass"
}

instance_help() {
  cat << EOF
## Libvirt KVM Wrapper - virtx ##
Usage: $(basename "$0") instance <command> [options]

Commands:
  create|c <name>   create instance
  delete|d <name>   delete instance
  edit|e <name>     edit instance
  help|--help|-h  show this page

Options:
  --cpu|-c          number of vcpu cores [default: 2]
  --disk-path|-d    disk path to qcow2
  --disk-size|-s    disk size GigaBytes [default: 20]
  --firmware|-f     firmware mode bios or uefi [default: bios]
  --graphics|-g     graphics mode spice or vnc [default: spice]
  --iso|-i          path to ISO file
  --memory|-m       memory size GigaBytes [default: 2]
  --network|-n      network name [default: default]
  --verbose|-v      show what's being done in detail
EOF
}

instance_create(){
  process_subcommand_args Instance "$@"
  log normal "INSTANCE_NAME=$RESOURCE_NAME"
  ARGS="$@"
  
  if [ "$INTERACTIVE_MODE" = "true" ]; then
    CREATE_STEPS="select_cpu,select_memory,select_iso,select_disk_path,select_disk_size,select_firmware,select_network,select_graphics"
    log normal "Command Mode is interactive"
    interactive_select 
  else
		array_length="${#ARGS[@]}"
		i=1
		while [ "$i" -le "$array_length" ]; do
			case "${ARGS[$i]}" in
				--cpu|-c)
					CPU_CORE="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--disk-path|-d)
					DISK_PATH="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--disk-size|-s)
					DISK_SIZE="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--firmware|-f)
					FIRMWARE="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--graphics|-g)
					GRAPHICS="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--iso|-i)
					ISO="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--memory|-m)
					MEMORY="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--network|-n)
					NETWORK="${ARGS[$((i+1))]}"
					i=$((i+2))
					continue
					;;
				--verbose|-v)
					VERBOSE="true"
					i=$((i+1))
					continue
					;;
				*)
					i=$((i+1))
			esac
		done
  fi

	echo "CPU_CORE: $CPU_CORE"
	echo "DISK_PATH: $DISK_PATH"
	echo "DISK_SIZE: $DISK_SIZE"
	echo "FIRMWARE: $FIRMWARE"
	echo "GRAPHICS: $GRAPHICS"
	echo "ISO: $ISO"
	echo "MEMORY: $MEMORY"
	echo "NETWORK: $NETWORK"
	echo "VERBOSE: $VERBOSE"
}

instance() {
  INSTANCE_ACTION="$1"
  shift
  case "$INSTANCE_ACTION" in
    help|-h|--help)
      instance_help
      ;;
    create|c)
      instance_create "$@"
      ;;
    delete|d)
      instance_delete "$@"
      ;;
    edit|e)
      instance_delete "$@"
      ;;
    *)
      [ -n "$INSTANCE_ACTION" ] && echo "Invalid action [$INSTANCE_ACTION]"
      instance_help
      [ -z "$INSTANCE_ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

main() {
  ACTION="$1"
  shift
  case "$ACTION" in
    help|-h|--help)
      help
      ;;
    install)
      install
      ;;
    instance|i)
      instance "$@"
      ;;
    storage|s)
      storage "$@"
      ;;
    network|n)
      network "$@"
      ;;
    *)
      [ -n "$ACTION" ] && echo "Invalid action [$ACTION]"
      help
      [ -z "$ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

main "$@"
