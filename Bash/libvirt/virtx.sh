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
  snapshot|snap   snapshot related commands
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
  ARGS=("$@")
  if [ -n "${ARGS[0]}" ] && ! [[ "${ARGS[0]}" =~ ^- ]]; then
    RESOURCE_NAME="${ARGS[0]}"
  else
    log error "${RESOURCE_TYPE} name has to be provided"
    exit 1
  fi
  
  INTERACTIVE_MODE="true"
  for arg in "${ARGS[@]:1}"; do
    if [[ "$arg" =~ ^- ]]; then
      INTERACTIVE_MODE="false"
      break
    fi
  done
}

# ==============================================================================
# Generic Selection Helper (FZF with Bash 'select' Fallback)
# ==============================================================================

select_option() {
  local prompt="$1"
  shift
  local options=("$@")

  if command -v fzf >/dev/null 2>&1; then
    local selected
    selected=$(printf "%s\n" "${options[@]}" | fzf --prompt="$prompt: " --height=14)
    local fzf_exit=$?
    if [ $fzf_exit -eq 130 ]; then
      return 130
    fi
    echo "$selected"
  else
    echo "=== $prompt ===" >&2
    PS3="Select an option (1-${#options[@]}): "
    local selected=""
    select item in "${options[@]}"; do
      if [ -n "$item" ]; then
        selected="$item"
        break
      fi
    done < /dev/tty
    echo "$selected"
  fi
}

# Get list of storage pools formatted as "<pool-name> --> <path>"
get_storage_pools_formatted() {
  local pools=()
  readarray -t pools < <(virsh pool-list --all --name 2>/dev/null | awk '{print $1}')
  local count=0
  for pool in "${pools[@]}"; do
    [ -z "$pool" ] && continue
    local path
    path=$(virsh pool-dumpxml "$pool" 2>/dev/null | sed -n 's/.*<path>\(.*\)<\/path>.*/\1/p')
    if [ -n "$path" ]; then
      echo "${pool} --> ${path}"
      ((count++))
    fi
  done
  if [ $count -eq 0 ]; then
    echo "default --> /var/lib/libvirt/images"
  fi
}

# Get default datastore directory path
get_datastore_path() {
  local ds_path
  ds_path=$(virsh pool-dumpxml datastore 2>/dev/null | sed -n 's/.*<path>\(.*\)<\/path>.*/\1/p')
  if [ -z "$ds_path" ]; then
    ds_path=$(virsh pool-dumpxml default 2>/dev/null | sed -n 's/.*<path>\(.*\)<\/path>.*/\1/p')
  fi
  if [ -z "$ds_path" ]; then
    ds_path="/var/lib/libvirt/images"
  fi
  echo "$ds_path"
}

# Get available networks from virsh
get_available_networks() {
  local nets=()
  readarray -t nets < <(virsh net-list --name 2>/dev/null | awk '{print $1}')
  if [ ${#nets[@]} -eq 0 ]; then
    nets=("default")
  fi
  printf "%s\n" "${nets[@]}"
}

# ==============================================================================
# Interactive Back-steppable Step Functions
# ==============================================================================

select_cpu() {
  local choice
  choice=$(select_option "[Step 1/10] Select CPU Cores ($RESOURCE_NAME)" "[ > Next (Default: 2) ]" "[ < Back ]" "1" "2 (Default)" "4" "8" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1 # BACK
  elif [[ "$choice" == "[ > Next (Default: 2) ]" || -z "$choice" ]]; then
    CPU_CORE="${CPU_CORE:-2}"
    return 0 # NEXT
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter number of vCPU cores: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      log error "Invalid CPU core count."
      return 1
    fi
  else
    choice="${choice%% *}" # Extract number
  fi

  CPU_CORE="$choice"
  return 0 # NEXT
}

select_memory() {
  local choice
  choice=$(select_option "[Step 2/10] Select Memory Size in GB ($RESOURCE_NAME)" "[ > Next (Default: 2 GB) ]" "[ < Back ]" "1" "2 (Default)" "4" "8" "16" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: 2 GB) ]" || -z "$choice" ]]; then
    MEMORY="${MEMORY:-2}"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter memory size in GB: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      log error "Invalid memory size."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  MEMORY="$choice"
  return 0
}

# Step 3a: Select ISO Storage Pool
select_iso_pool() {
  local pools=()
  readarray -t pools < <(get_storage_pools_formatted)
  
  local default_pool="${pools[0]}"
  for p in "${pools[@]}"; do
    if [[ "$p" =~ ^ISO ]]; then
      default_pool="$p"
      break
    fi
  done
  local default_pool_name="${default_pool%% --> *}"

  local options=("[ > Next (Default Pool: ${default_pool_name}) ]" "[ < Back ]" "[ None / Skip ISO ]" "[ Manual Path Input ]" "${pools[@]}")

  local choice
  choice=$(select_option "[Step 3a/10] Select Storage Pool for ISO ($RESOURCE_NAME)" "${options[@]}")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default Pool: ${default_pool_name}) ]" || -z "$choice" ]]; then
    SELECTED_ISO_POOL_PATH="${default_pool#* --> }"
    SKIP_ISO_FILE_STEP="false"
  elif [[ "$choice" == "[ None / Skip ISO ]" ]]; then
    ISO=""
    SKIP_ISO_FILE_STEP="true"
  elif [[ "$choice" == "[ Manual Path Input ]" ]]; then
    read -e -p "Enter full path to ISO file: " choice
    if [[ ! -f "$choice" ]]; then
      log error "File does not exist: $choice"
      return 1
    fi
    ISO="$choice"
    SKIP_ISO_FILE_STEP="true"
  else
    # Extract path from "<pool-name> --> <path>"
    SELECTED_ISO_POOL_PATH="${choice#* --> }"
    SKIP_ISO_FILE_STEP="false"
  fi

  return 0
}

# Step 3b: Select ISO File from Chosen Pool
select_iso_file() {
  if [ "$SKIP_ISO_FILE_STEP" = "true" ]; then
    if [ "$LAST_DIRECTION" = "backward" ]; then
      return 1
    fi
    return 0
  fi

  local isos=()
  readarray -t isos < <(find "$SELECTED_ISO_POOL_PATH" -name "*.iso" 2>/dev/null)
  if [ ${#isos[@]} -eq 0 ]; then
    log error "No .iso files found in pool path ($SELECTED_ISO_POOL_PATH)"
    local options=("[ > Next (Skip ISO) ]" "[ < Back to Pool Selection ]" "[ Manual Path Input ]" "[ None / Skip ISO ]")
    local choice
    choice=$(select_option "ISO Selection Option" "${options[@]}")
    [ $? -eq 130 ] && return 130
    if [[ "$choice" == "[ < Back to Pool Selection ]" ]]; then
      return 1
    elif [[ "$choice" == "[ Manual Path Input ]" ]]; then
      read -e -p "Enter full path to ISO file: " choice
      if [[ ! -f "$choice" ]]; then
        log error "File does not exist: $choice"
        return 1
      fi
      ISO="$choice"
    else
      ISO=""
    fi
    return 0
  fi

  local default_iso="${isos[0]}"
  local default_iso_name
  default_iso_name="$(basename "$default_iso")"

  local options=("[ > Next (Default: ${default_iso_name}) ]" "[ < Back ]" "[ None / Skip ISO ]" "${isos[@]}")
  local choice
  choice=$(select_option "[Step 3b/10] Select ISO File from Pool ($RESOURCE_NAME)" "${options[@]}")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: ${default_iso_name}) ]" || -z "$choice" ]]; then
    ISO="$default_iso"
    return 0
  elif [[ "$choice" == "[ None / Skip ISO ]" ]]; then
    ISO=""
    return 0
  fi

  ISO="$choice"
  return 0
}

# Step 4: Select Disk Storage Pool & Path
select_disk_path() {
  local ds_path=$(get_datastore_path)
  local default_target="${ds_path}/${RESOURCE_NAME}.qcow2"
  local pools=()
  readarray -t pools < <(get_storage_pools_formatted)
  local options=("[ > Next (Default: $default_target) ]" "[ < Back ]" "${pools[@]}" "[ Custom Path ]")

  local choice
  choice=$(select_option "[Step 4/10] Select Storage Pool for Disk ($RESOURCE_NAME)" "${options[@]}")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: $default_target) ]" || -z "$choice" ]]; then
    DISK_PATH="$default_target"
    return 0
  elif [[ "$choice" == "[ Custom Path ]" ]]; then
    read -e -p "Enter full disk qcow2 path: " choice
    if [[ -z "$choice" ]]; then
      log error "Disk path cannot be empty."
      return 1
    fi
    DISK_PATH="$choice"
  else
    # Extract path from "<pool-name> --> <path>"
    local pool_path="${choice#* --> }"
    DISK_PATH="${pool_path}/${RESOURCE_NAME}.qcow2"
  fi

  return 0
}

select_disk_size() {
  local choice
  choice=$(select_option "[Step 5/10] Select Disk Size in GB ($RESOURCE_NAME)" "[ > Next (Default: 20 GB) ]" "[ < Back ]" "10" "20 (Default)" "40" "80" "100" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: 20 GB) ]" || -z "$choice" ]]; then
    DISK_SIZE="${DISK_SIZE:-20}"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter disk size in GB: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      log error "Invalid disk size."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  DISK_SIZE="$choice"
  return 0
}

select_firmware() {
  local choice
  choice=$(select_option "[Step 6/10] Select Firmware Mode ($RESOURCE_NAME)" "[ > Next (Default: bios) ]" "[ < Back ]" "bios (Default)" "uefi")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: bios) ]" || -z "$choice" ]]; then
    FIRMWARE="${FIRMWARE:-bios}"
    return 0
  else
    choice="${choice%% *}"
  fi

  FIRMWARE="$choice"
  return 0
}

select_network() {
  local nets=()
  readarray -t nets < <(get_available_networks)
  local options=("[ > Next (Default: default) ]" "[ < Back ]" "${nets[@]}")

  local choice
  choice=$(select_option "[Step 7/10] Select Network ($RESOURCE_NAME)" "${options[@]}")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: default) ]" || -z "$choice" ]]; then
    NETWORK="${NETWORK:-default}"
    return 0
  fi

  NETWORK="$choice"
  return 0
}

select_graphics() {
  local choice
  choice=$(select_option "[Step 8/10] Select Graphics Mode ($RESOURCE_NAME)" "[ > Next (Default: spice) ]" "[ < Back ]" "spice (Default)" "vnc" "none (Headless)")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: spice) ]" || -z "$choice" ]]; then
    GRAPHICS="${GRAPHICS:-spice}"
    return 0
  else
    choice="${choice%% *}"
  fi

  GRAPHICS="$choice"
  return 0
}

# Get list of OS variants from virt-install --osinfo list
get_osinfo_variants() {
  local os_list=()
  readarray -t os_list < <(virt-install --osinfo list 2>/dev/null | grep -v '^$')
  if [ ${#os_list[@]} -eq 0 ]; then
    os_list=("generic" "almalinux10" "almalinux9" "ubuntu24.04" "ubuntu22.04" "debian12" "rhel9.4" "rocky9")
  fi
  printf "%s\n" "${os_list[@]}"
}

select_os_variant() {
  local os_list=()
  readarray -t os_list < <(get_osinfo_variants)
  local options=("[ > Next (Default: generic) ]" "[ < Back ]" "[ None / Generic ]" "${os_list[@]}")

  local choice
  choice=$(select_option "[Step 9/10] Select OS Variant ($RESOURCE_NAME)" "${options[@]}")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: generic) ]" || "$choice" == "[ None / Generic ]" || -z "$choice" ]]; then
    OS_VARIANT="${OS_VARIANT:-generic}"
    return 0
  fi

  OS_VARIANT="$choice"
  return 0
}

select_confirm() {
  cat << EOF

==================================================
        Instance Provisioning Summary
==================================================
  Instance Name : $RESOURCE_NAME
  CPU Cores     : ${CPU_CORE:-2}
  Memory        : ${MEMORY:-2} GB
  ISO File      : ${ISO:-None}
  Disk Path     : $DISK_PATH
  Disk Size     : ${DISK_SIZE:-20} GB
  Firmware      : ${FIRMWARE:-bios}
  Network       : ${NETWORK:-default}
  Graphics      : ${GRAPHICS:-spice}
  OS Variant    : ${OS_VARIANT:-generic}
==================================================
EOF

  local choice
  choice=$(select_option "Confirm Provisioning" "[ Confirm & Create Instance ]" "[ < Back ]" "[ Cancel ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ Confirm & Create Instance ]" || -z "$choice" ]]; then
    return 0
  else
    log normal "Cancelled."
    exit 0
  fi
}

interactive_select() {
  trap 'log normal "\nInstance creation cancelled by user."; exit 0' INT
  local steps=(
    "select_cpu"
    "select_memory"
    "select_iso_pool"
    "select_iso_file"
    "select_disk_path"
    "select_disk_size"
    "select_firmware"
    "select_network"
    "select_graphics"
    "select_os_variant"
    "select_confirm"
  )
  local current_step=0
  LAST_DIRECTION="forward"

  while (( current_step >= 0 && current_step < ${#steps[@]} )); do
    "${steps[$current_step]}"
    local status=$?

    if [[ $status -eq 0 ]]; then
      LAST_DIRECTION="forward"
      ((current_step++))
    elif [[ $status -eq 1 ]]; then
      LAST_DIRECTION="backward"
      ((current_step--))
    elif [[ $status -eq 130 ]]; then
      log normal "Instance creation cancelled by user."
      exit 0
    else
      log error "Selection aborted."
      exit 1
    fi
  done

  if (( current_step < 0 )); then
    log normal "Instance creation cancelled."
    exit 0
  fi
}

# ==============================================================================
# Instance Subcommand Handlers
# ==============================================================================

instance_help() {
  cat << EOF
## Libvirt KVM Wrapper - virtx ##
Usage: $(basename "$0") instance <command> [options]

Commands:
  create|c <name>   create instance
  delete|d [name]   delete instance (interactive if name omitted)
  list|ls           list all instances with detailed info
  edit|e [name]     edit instance CPU & Memory (interactive if name omitted)
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
  --os-variant|-o   os variant name (e.g. almalinux10, ubuntu24.04, generic) [default: generic]
  --verbose|-v      show what's being done in detail
EOF
}

instance_create() {
  process_subcommand_args Instance "$@"
  ARGS=("$@")
  
  if [ "$INTERACTIVE_MODE" = "true" ]; then
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
        --os-variant|-o)
          OS_VARIANT="${ARGS[$((i+1))]}"
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

  # Apply defaults if still unassigned
  CPU_CORE="${CPU_CORE:-2}"
  MEMORY="${MEMORY:-2}"
  DISK_SIZE="${DISK_SIZE:-20}"
  FIRMWARE="${FIRMWARE:-bios}"
  GRAPHICS="${GRAPHICS:-spice}"
  NETWORK="${NETWORK:-default}"
  OS_VARIANT="${OS_VARIANT:-generic}"

  if [ -z "$DISK_PATH" ]; then
    local ds_path=$(get_datastore_path)
    DISK_PATH="${ds_path}/${RESOURCE_NAME}.qcow2"
  fi

  if [ "$VERBOSE" = "true" ]; then
    echo "CPU_CORE: $CPU_CORE"
    echo "DISK_PATH: $DISK_PATH"
    echo "DISK_SIZE: $DISK_SIZE"
    echo "FIRMWARE: $FIRMWARE"
    echo "GRAPHICS: $GRAPHICS"
    echo "ISO: $ISO"
    echo "MEMORY: $MEMORY"
    echo "NETWORK: $NETWORK"
    echo "OS_VARIANT: $OS_VARIANT"
    echo "VERBOSE: $VERBOSE"
  fi

  log progress "Provisioning VM instance '$RESOURCE_NAME'..."

  local memory_mb=$(( MEMORY * 1024 ))
  local virt_cmd=("virt-install" "--name" "$RESOURCE_NAME" "--memory" "$memory_mb" "--vcpus" "$CPU_CORE" "--cpu" "host-passthrough" "--os-variant" "$OS_VARIANT")

  if [ "$FIRMWARE" = "uefi" ]; then
    virt_cmd+=("--boot" "uefi")
  fi

  virt_cmd+=("--disk" "path=${DISK_PATH},size=${DISK_SIZE},bus=virtio")

  if [ -n "$ISO" ] && [ -f "$ISO" ]; then
    virt_cmd+=("--cdrom" "$ISO")
  fi

  virt_cmd+=("--network" "network=${NETWORK},model=virtio")

  if [ "$GRAPHICS" = "none" ]; then
    virt_cmd+=("--graphics" "none" "--console" "pty,target.type=serial" "--noautoconsole")
  else
    virt_cmd+=("--graphics" "$GRAPHICS" "--noautoconsole")
  fi

  virt_cmd+=("--print-xml" "1")

  if [ "$VERBOSE" = "true" ]; then
    log normal "Running: ${virt_cmd[*]} | virsh define /dev/stdin"
  fi

  "${virt_cmd[@]}" | virsh define /dev/stdin

  if [ $? -eq 0 ]; then
    log success "Instance '$RESOURCE_NAME' successfully defined (shut off)!"
  else
    log error "Failed to create instance '$RESOURCE_NAME'."
  fi
}

get_all_instances() {
  local vms=()
  readarray -t vms < <(virsh list --all --name 2>/dev/null | awk '{print $1}')
  printf "%s\n" "${vms[@]}"
}

instance_delete() {
  if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
    RESOURCE_NAME="$1"
  else
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance to Delete" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Deletion cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  log progress "Deleting instance '$RESOURCE_NAME'..."
  
  # Identify target disks safely (excluding .iso images)
  local storage_args=()
  local targets=()
  readarray -t targets < <(virsh domblklist "$RESOURCE_NAME" 2>/dev/null | awk 'NR>2 && $1!="" {print $1}')
  for target in "${targets[@]}"; do
    local src
    src=$(virsh domblklist "$RESOURCE_NAME" 2>/dev/null | awk -v t="$target" '$1==t {print $2}')
    if [[ "$src" =~ \.iso$ ]]; then
      continue
    fi
    storage_args+=("--storage" "$target")
  done
  if [ ${#storage_args[@]} -eq 0 ]; then
    storage_args=("--remove-all-storage")
  fi

  virsh destroy "$RESOURCE_NAME" 2>/dev/null
  virsh undefine "$RESOURCE_NAME" "${storage_args[@]}" --nvram --managed-save --snapshots-metadata
  if [ $? -eq 0 ]; then
    log success "Instance '$RESOURCE_NAME' successfully deleted (purged storage & NVRAM)."
  else
    log error "Failed to delete instance '$RESOURCE_NAME'."
  fi
}

instance_list() {
  local vms=()
  readarray -t vms < <(virsh list --all --name 2>/dev/null | awk '{print $1}')
  if [ ${#vms[@]} -eq 0 ]; then
    log normal "No instances found."
    return 0
  fi

  log progress "Libvirt KVM Instances Overview:"
  printf "%-20s %-10s %-6s %-10s %-10s %-12s %-16s %-10s %s\n" "NAME" "STATE" "VCPU" "MEMORY" "FIRMWARE" "NETWORK" "IP ADDRESS" "AUTOSTART" "DISK PATH"
  printf "%s\n" "---------------------------------------------------------------------------------------------------------------------------------------"

  for vm in "${vms[@]}"; do
    [ -z "$vm" ] && continue
    local info
    info=$(virsh dominfo "$vm" 2>/dev/null)
    local state=$(echo "$info" | awk -F':' '/State:/ {gsub(/^[ \t]+/, "", $2); print $2}')
    local vcpu=$(echo "$info" | awk -F':' '/CPU\(s\):/ {gsub(/^[ \t]+/, "", $2); print $2}')
    local mem_kib=$(echo "$info" | awk -F':' '/Max memory:/ {gsub(/^[ \t]+/, "", $2); print $2}')
    mem_kib="${mem_kib%% *}"
    local mem_gb="N/A"
    if [ -n "$mem_kib" ]; then
      local gb=$(( mem_kib / 1024 / 1024 ))
      if [ $gb -gt 0 ]; then
        mem_gb="${gb} GB"
      else
        mem_gb="$(( mem_kib / 1024 )) MB"
      fi
    fi
    local autostart=$(echo "$info" | awk -F':' '/Autostart:/ {gsub(/^[ \t]+/, "", $2); print $2}')
    
    local fw="bios"
    if virsh dumpxml "$vm" 2>/dev/null | grep -qE "firmware='efi'|type='pflash'"; then
      fw="uefi"
    fi

    local net=$(virsh domiflist "$vm" 2>/dev/null | awk 'NR>2 && $1!="" {print $3}' | head -n 1)
    [ -z "$net" ] && net="default"

    local ip="-"
    if [ "$state" = "running" ]; then
      local ip_out=$(virsh domifaddr "$vm" 2>/dev/null | awk '/ipv4/ {print $4}')
      ip="${ip_out%%/*}"
      [ -z "$ip" ] && ip="-"
    fi

    local disk_path=$(virsh domblklist "$vm" 2>/dev/null | awk 'NR>2 && $1!="" {print $2}' | grep -v '^-' | head -n 1)
    [ -z "$disk_path" ] && disk_path="-"

    printf "%-20s %-10s %-6s %-10s %-10s %-12s %-16s %-10s %s\n" "$vm" "$state" "${vcpu:-1}" "$mem_gb" "$fw" "$net" "$ip" "$autostart" "$disk_path"
  done
}

# ==============================================================================
# Instance Edit Interactive Wizard & Handler
# ==============================================================================

select_edit_cpu() {
  local cur_info=$(virsh dominfo "$RESOURCE_NAME" 2>/dev/null)
  local cur_vcpu=$(echo "$cur_info" | awk -F':' '/CPU\(s\):/ {gsub(/^[ \t]+/, "", $2); print $2}')
  cur_vcpu="${cur_vcpu:-2}"

  local choice
  choice=$(select_option "[Step 1/2] Select vCPU Cores for ($RESOURCE_NAME)" "[ > Keep Current ($cur_vcpu vCPU) ]" "[ < Back ]" "1" "2" "4" "8" "16" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Keep Current ("* || -z "$choice" ]]; then
    EDIT_CPU="$cur_vcpu"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter number of vCPU cores: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      log error "Invalid CPU core count."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  EDIT_CPU="$choice"
  return 0
}

select_edit_memory() {
  local cur_info=$(virsh dominfo "$RESOURCE_NAME" 2>/dev/null)
  local cur_mem_kib=$(echo "$cur_info" | awk -F':' '/Max memory:/ {gsub(/^[ \t]+/, "", $2); print $2}')
  cur_mem_kib="${cur_mem_kib%% *}"
  local cur_mem_gb=$(( cur_mem_kib / 1024 / 1024 ))
  [ $cur_mem_gb -eq 0 ] && cur_mem_gb=1

  local choice
  choice=$(select_option "[Step 2/2] Select Memory Size in GB for ($RESOURCE_NAME)" "[ > Keep Current (${cur_mem_gb} GB) ]" "[ < Back ]" "1" "2" "4" "8" "16" "32" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Keep Current ("* || -z "$choice" ]]; then
    EDIT_MEMORY="$cur_mem_gb"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter memory size in GB: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      log error "Invalid memory size."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  EDIT_MEMORY="$choice"
  return 0
}

select_edit_confirm() {
  cat << EOF

==================================================
        Instance Edit Summary ($RESOURCE_NAME)
==================================================
  Instance Name : $RESOURCE_NAME
  New vCPU Cores: $EDIT_CPU
  New Memory    : $EDIT_MEMORY GB
==================================================
EOF

  local choice
  choice=$(select_option "Confirm Edits" "[ Confirm & Apply Edits ]" "[ < Back ]" "[ Cancel ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ Confirm & Apply Edits ]" || -z "$choice" ]]; then
    return 0
  else
    log normal "Cancelled."
    exit 0
  fi
}

interactive_select_edit() {
  trap 'log normal "\nInstance edit cancelled by user."; exit 0' INT
  local steps=(
    "select_edit_cpu"
    "select_edit_memory"
    "select_edit_confirm"
  )
  local current_step=0
  LAST_DIRECTION="forward"

  while (( current_step >= 0 && current_step < ${#steps[@]} )); do
    "${steps[$current_step]}"
    local status=$?

    if [[ $status -eq 0 ]]; then
      LAST_DIRECTION="forward"
      ((current_step++))
    elif [[ $status -eq 1 ]]; then
      LAST_DIRECTION="backward"
      ((current_step--))
    elif [[ $status -eq 130 ]]; then
      log normal "Instance edit cancelled by user."
      exit 0
    else
      log error "Selection aborted."
      exit 1
    fi
  done

  if (( current_step < 0 )); then
    log normal "Instance edit cancelled."
    exit 0
  fi
}

instance_edit() {
  ARGS=("$@")
  if [ -n "${ARGS[0]}" ] && ! [[ "${ARGS[0]}" =~ ^- ]]; then
    RESOURCE_NAME="${ARGS[0]}"
    ARGS=("${ARGS[@]:1}")
  else
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance to Edit" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Edit cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  local non_interactive="false"
  for arg in "${ARGS[@]}"; do
    if [[ "$arg" =~ ^- ]]; then
      non_interactive="true"
      break
    fi
  done

  if [ "$non_interactive" = "true" ]; then
    array_length="${#ARGS[@]}"
    i=0
    while [ "$i" -lt "$array_length" ]; do
      case "${ARGS[$i]}" in
        --cpu|-c)
          EDIT_CPU="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --memory|-m)
          EDIT_MEMORY="${ARGS[$((i+1))]}"
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
  else
    interactive_select_edit
  fi

  log progress "Updating instance '$RESOURCE_NAME' (vCPU: ${EDIT_CPU:-Unchanged}, Memory: ${EDIT_MEMORY:+$EDIT_MEMORY GB})..."

  if [ -n "$EDIT_CPU" ]; then
    if [ "$VERBOSE" = "true" ]; then
      log normal "Running: virt-xml $RESOURCE_NAME --edit --vcpus $EDIT_CPU"
    fi
    virt-xml "$RESOURCE_NAME" --edit --vcpus "$EDIT_CPU" >/dev/null 2>&1
  fi

  if [ -n "$EDIT_MEMORY" ]; then
    local mem_mb=$(( EDIT_MEMORY * 1024 ))
    if [ "$VERBOSE" = "true" ]; then
      log normal "Running: virt-xml $RESOURCE_NAME --edit --memory $mem_mb"
    fi
    virt-xml "$RESOURCE_NAME" --edit --memory "$mem_mb" >/dev/null 2>&1
  fi

  if [ $? -eq 0 ]; then
    log success "Instance '$RESOURCE_NAME' successfully updated!"
  else
    log error "Failed to update instance '$RESOURCE_NAME'."
  fi
}

instance() {
  INSTANCE_ACTION="$1"
  shift || true
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
    list|ls)
      instance_list "$@"
      ;;
    edit|e)
      instance_edit "$@"
      ;;
    snapshot|snap|sp)
      snapshot "$@"
      ;;
    *)
      [ -n "$INSTANCE_ACTION" ] && echo "Invalid action [$INSTANCE_ACTION]"
      instance_help
      [ -z "$INSTANCE_ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

# ==============================================================================
# Storage Pool Step Functions & Handlers
# ==============================================================================

select_storage_type() {
  local choice
  choice=$(select_option "[Step 1/3] Select Storage Pool Type ($RESOURCE_NAME)" "[ > Next (Default: dir) ]" "[ < Back ]" "dir (Directory - Default)" "logical (LVM Volume Group)" "netfs (NFS Mount)" "fs (Filesystem Partition)" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: dir) ]" || -z "$choice" ]]; then
    POOL_TYPE="${POOL_TYPE:-dir}"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter storage pool type: " choice
    if [[ -z "$choice" ]]; then
      log error "Pool type cannot be empty."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  POOL_TYPE="$choice"
  return 0
}

select_storage_path() {
  local ds_path=$(get_datastore_path)
  local default_target="${ds_path}/${RESOURCE_NAME}"
  local choice
  choice=$(select_option "[Step 2/3] Select Target Path for Storage Pool ($RESOURCE_NAME)" "[ > Next (Default: $default_target) ]" "[ < Back ]" "[ Custom Path ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: $default_target) ]" || -z "$choice" ]]; then
    POOL_PATH="$default_target"
    return 0
  elif [[ "$choice" == "[ Custom Path ]" ]]; then
    read -e -p "Enter target path: " choice
    if [[ -z "$choice" ]]; then
      log error "Path cannot be empty."
      return 1
    fi
    POOL_PATH="$choice"
  fi

  return 0
}

select_storage_autostart() {
  local choice
  choice=$(select_option "[Step 3/3] Autostart Pool on Host Boot ($RESOURCE_NAME)" "[ > Next (Default: yes) ]" "[ < Back ]" "yes (Default)" "no")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: yes) ]" || -z "$choice" ]]; then
    AUTOSTART="${AUTOSTART:-yes}"
    return 0
  else
    choice="${choice%% *}"
  fi

  AUTOSTART="$choice"
  return 0
}

select_storage_confirm() {
  cat << EOF

==================================================
        Storage Pool Provisioning Summary
==================================================
  Pool Name : $RESOURCE_NAME
  Pool Type : ${POOL_TYPE:-dir}
  Target Path: $POOL_PATH
  Autostart : ${AUTOSTART:-yes}
==================================================
EOF

  local choice
  choice=$(select_option "Confirm Storage Pool" "[ Confirm & Create Pool ]" "[ < Back ]" "[ Cancel ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ Confirm & Create Pool ]" || -z "$choice" ]]; then
    return 0
  else
    log normal "Cancelled."
    exit 0
  fi
}

interactive_select_storage() {
  trap 'log normal "\nStorage pool creation cancelled by user."; exit 0' INT
  local steps=(
    "select_storage_type"
    "select_storage_path"
    "select_storage_autostart"
    "select_storage_confirm"
  )
  local current_step=0
  LAST_DIRECTION="forward"

  while (( current_step >= 0 && current_step < ${#steps[@]} )); do
    "${steps[$current_step]}"
    local status=$?

    if [[ $status -eq 0 ]]; then
      LAST_DIRECTION="forward"
      ((current_step++))
    elif [[ $status -eq 1 ]]; then
      LAST_DIRECTION="backward"
      ((current_step--))
    elif [[ $status -eq 130 ]]; then
      log normal "Storage pool creation cancelled by user."
      exit 0
    else
      log error "Selection aborted."
      exit 1
    fi
  done

  if (( current_step < 0 )); then
    log normal "Storage pool creation cancelled."
    exit 0
  fi
}

storage_help() {
  cat << EOF
## Libvirt KVM Wrapper - virtx storage ##
Usage: $(basename "$0") storage <command> [options]

Commands:
  create|c <name>   create storage pool
  delete|d [name]   delete storage pool (interactive if name omitted)
  list|ls           list all storage pools
  help|--help|-h    show this page

Options:
  --type|-t         storage pool type (dir, logical, fs, netfs) [default: dir]
  --path|-p         directory target path for storage pool
  --autostart|-a    autostart pool on host boot (yes/no) [default: yes]
  --verbose|-v      show what's being done in detail
EOF
}

storage_create() {
  process_subcommand_args Storage "$@"
  ARGS=("$@")

  if [ "$INTERACTIVE_MODE" = "true" ]; then
    interactive_select_storage
  else
    array_length="${#ARGS[@]}"
    i=1
    while [ "$i" -le "$array_length" ]; do
      case "${ARGS[$i]}" in
        --type|-t)
          POOL_TYPE="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --path|-p)
          POOL_PATH="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --autostart|-a)
          AUTOSTART="${ARGS[$((i+1))]}"
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

  POOL_TYPE="${POOL_TYPE:-dir}"
  AUTOSTART="${AUTOSTART:-yes}"

  if [ -z "$POOL_PATH" ]; then
    local ds_path=$(get_datastore_path)
    POOL_PATH="${ds_path}/${RESOURCE_NAME}"
  fi

  log progress "Creating storage pool '$RESOURCE_NAME' ($POOL_TYPE) at '$POOL_PATH'..."
  mkdir -p "$POOL_PATH" 2>/dev/null

  if [ "$VERBOSE" = "true" ]; then
    log normal "Running: virsh pool-define-as $RESOURCE_NAME $POOL_TYPE --target $POOL_PATH"
  fi

  virsh pool-define-as "$RESOURCE_NAME" "$POOL_TYPE" --target "$POOL_PATH" 2>/dev/null
  virsh pool-build "$RESOURCE_NAME" 2>/dev/null
  virsh pool-start "$RESOURCE_NAME" 2>/dev/null

  if [ "$AUTOSTART" = "yes" ]; then
    virsh pool-autostart "$RESOURCE_NAME" 2>/dev/null
  fi

  if [ $? -eq 0 ]; then
    log success "Storage pool '$RESOURCE_NAME' successfully created and started!"
  else
    log error "Failed to create storage pool '$RESOURCE_NAME'."
  fi
}

storage_delete() {
  if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
    RESOURCE_NAME="$1"
  else
    local pools=()
    readarray -t pools < <(get_storage_pools_formatted)
    if [ ${#pools[@]} -eq 0 ]; then
      log error "No storage pools found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${pools[@]}")
    local choice
    choice=$(select_option "Select Storage Pool to Delete" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Deletion cancelled."
      exit 0
    fi
    RESOURCE_NAME="${choice%% --> *}" # Extract pool name
  fi

  log progress "Deleting storage pool '$RESOURCE_NAME'..."
  virsh pool-destroy "$RESOURCE_NAME" 2>/dev/null
  virsh pool-undefine "$RESOURCE_NAME" 2>/dev/null
  if [ $? -eq 0 ]; then
    log success "Storage pool '$RESOURCE_NAME' successfully deleted."
  else
    log error "Failed to delete storage pool '$RESOURCE_NAME'."
  fi
}

storage_list() {
  log progress "Listing libvirt storage pools:"
  virsh pool-list --all
}

storage() {
  STORAGE_ACTION="$1"
  shift || true
  case "$STORAGE_ACTION" in
    help|-h|--help)
      storage_help
      ;;
    create|c)
      storage_create "$@"
      ;;
    delete|d)
      storage_delete "$@"
      ;;
    list|ls)
      storage_list "$@"
      ;;
    *)
      [ -n "$STORAGE_ACTION" ] && echo "Invalid action [$STORAGE_ACTION]"
      storage_help
      [ -z "$STORAGE_ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

# ==============================================================================
# Virtual Network Step Functions & Handlers
# ==============================================================================

select_network_mode() {
  local choice
  choice=$(select_option "[Step 1/3] Select Network Forward Mode ($RESOURCE_NAME)" "[ > Next (Default: nat) ]" "[ < Back ]" "nat (NAT Mode - Default)" "route (Routed Mode)" "open (Open Mode)" "isolated (Isolated / No Forwarding)" "[ Custom Input ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: nat) ]" || -z "$choice" ]]; then
    NET_MODE="${NET_MODE:-nat}"
    return 0
  elif [[ "$choice" == "[ Custom Input ]" ]]; then
    read -p "Enter forward mode (nat, route, open, isolated): " choice
    if [[ -z "$choice" ]]; then
      log error "Mode cannot be empty."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  NET_MODE="$choice"
  return 0
}

select_network_subnet() {
  local default_ip="192.168.100.1"
  local choice
  choice=$(select_option "[Step 2/4] Select Subnet Gateway IP ($RESOURCE_NAME)" "[ > Next (Default: $default_ip) ]" "[ < Back ]" "192.168.100.1 (Default)" "192.168.200.1" "10.10.10.1" "[ Custom Subnet IP ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: $default_ip) ]" || -z "$choice" ]]; then
    NET_SUBNET="${NET_SUBNET:-$default_ip}"
    return 0
  elif [[ "$choice" == "[ Custom Subnet IP ]" ]]; then
    read -p "Enter Gateway IP (e.g. 192.168.100.1): " choice
    if [[ -z "$choice" ]]; then
      log error "Subnet IP cannot be empty."
      return 1
    fi
  else
    choice="${choice%% *}"
  fi

  NET_SUBNET="$choice"
  return 0
}

select_network_dns() {
  local choice
  choice=$(select_option "[Step 3/4] Enable DNS Resolution ($RESOURCE_NAME)" "[ > Next (Default: yes) ]" "[ < Back ]" "yes (Default)" "no")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: yes) ]" || -z "$choice" ]]; then
    ENABLE_DNS="${ENABLE_DNS:-yes}"
    return 0
  else
    choice="${choice%% *}"
  fi

  ENABLE_DNS="$choice"
  return 0
}

select_network_autostart() {
  local choice
  choice=$(select_option "[Step 4/4] Autostart Network on Host Boot ($RESOURCE_NAME)" "[ > Next (Default: yes) ]" "[ < Back ]" "yes (Default)" "no")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ > Next (Default: yes) ]" || -z "$choice" ]]; then
    AUTOSTART="${AUTOSTART:-yes}"
    return 0
  else
    choice="${choice%% *}"
  fi

  AUTOSTART="$choice"
  return 0
}

select_network_confirm() {
  local base_prefix="${NET_SUBNET%.*}"
  local dhcp_s="${DHCP_START:-${base_prefix}.10}"
  local dhcp_e="${DHCP_END:-${base_prefix}.254}"

  cat << EOF

==================================================
        Virtual Network Provisioning Summary
==================================================
  Network Name : $RESOURCE_NAME
  Forward Mode : ${NET_MODE:-nat}
  Gateway IP   : ${NET_SUBNET:-192.168.100.1}
  Netmask      : ${NET_NETMASK:-255.255.255.0}
  DNS Enabled  : ${ENABLE_DNS:-yes}
  DHCP Range   : $dhcp_s - $dhcp_e
  Autostart    : ${AUTOSTART:-yes}
==================================================
EOF

  local choice
  choice=$(select_option "Confirm Virtual Network" "[ Confirm & Create Network ]" "[ < Back ]" "[ Cancel ]")
  [ $? -eq 130 ] && return 130

  if [[ "$choice" == "[ < Back ]" ]]; then
    return 1
  elif [[ "$choice" == "[ Confirm & Create Network ]" || -z "$choice" ]]; then
    return 0
  else
    log normal "Cancelled."
    exit 0
  fi
}

interactive_select_network() {
  trap 'log normal "\nNetwork creation cancelled by user."; exit 0' INT
  local steps=(
    "select_network_mode"
    "select_network_subnet"
    "select_network_dns"
    "select_network_autostart"
    "select_network_confirm"
  )
  local current_step=0
  LAST_DIRECTION="forward"

  while (( current_step >= 0 && current_step < ${#steps[@]} )); do
    "${steps[$current_step]}"
    local status=$?

    if [[ $status -eq 0 ]]; then
      LAST_DIRECTION="forward"
      ((current_step++))
    elif [[ $status -eq 1 ]]; then
      LAST_DIRECTION="backward"
      ((current_step--))
    elif [[ $status -eq 130 ]]; then
      log normal "Network creation cancelled by user."
      exit 0
    else
      log error "Selection aborted."
      exit 1
    fi
  done

  if (( current_step < 0 )); then
    log normal "Network creation cancelled."
    exit 0
  fi
}

network_help() {
  cat << EOF
## Libvirt KVM Wrapper - virtx network ##
Usage: $(basename "$0") network <command> [options]

Commands:
  create|c <name>   create virtual network
  delete|d [name]   delete virtual network (interactive if name omitted)
  list|ls           list all virtual networks
  help|--help|-h    show this page

Options:
  --mode|-m         forward mode (nat, route, open, isolated) [default: nat]
  --subnet|-s       gateway subnet IP (e.g. 192.168.100.1) [default: 192.168.100.1]
  --netmask|-n      netmask [default: 255.255.255.0]
  --dns             enable DNS resolution (yes/no) [default: yes]
  --dhcp-start      DHCP range start IP
  --dhcp-end        DHCP range end IP
  --autostart|-a    autostart network on host boot (yes/no) [default: yes]
  --verbose|-v      show what's being done in detail
EOF
}

network_create() {
  process_subcommand_args Network "$@"
  ARGS=("$@")

  if [ "$INTERACTIVE_MODE" = "true" ]; then
    interactive_select_network
  else
    array_length="${#ARGS[@]}"
    i=1
    while [ "$i" -le "$array_length" ]; do
      case "${ARGS[$i]}" in
        --mode|-m)
          NET_MODE="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --subnet|-s)
          NET_SUBNET="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --netmask|-n)
          NET_NETMASK="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --dns)
          ENABLE_DNS="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --dhcp-start)
          DHCP_START="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --dhcp-end)
          DHCP_END="${ARGS[$((i+1))]}"
          i=$((i+2))
          continue
          ;;
        --autostart|-a)
          AUTOSTART="${ARGS[$((i+1))]}"
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

  NET_MODE="${NET_MODE:-nat}"
  NET_SUBNET="${NET_SUBNET:-192.168.100.1}"
  NET_NETMASK="${NET_NETMASK:-255.255.255.0}"
  ENABLE_DNS="${ENABLE_DNS:-yes}"
  AUTOSTART="${AUTOSTART:-yes}"

  local base_prefix="${NET_SUBNET%.*}"
  DHCP_START="${DHCP_START:-${base_prefix}.10}"
  DHCP_END="${DHCP_END:-${base_prefix}.254}"
  local bridge_name="virbr-${RESOURCE_NAME}"

  log progress "Creating virtual network '$RESOURCE_NAME' ($NET_MODE mode, IP: $NET_SUBNET, DNS: $ENABLE_DNS)..."

  local forward_tag=""
  if [ "$NET_MODE" != "isolated" ] && [ "$NET_MODE" != "none" ]; then
    forward_tag="<forward mode='${NET_MODE}'/>"
  fi

  local dns_tag=""
  if [ "$ENABLE_DNS" = "no" ] || [ "$ENABLE_DNS" = "false" ] || [ "$ENABLE_DNS" = "disabled" ]; then
    dns_tag="<dns enable='no'/>"
  fi

  local net_xml=$(cat << EOF
<network>
  <name>${RESOURCE_NAME}</name>
  ${dns_tag}
  ${forward_tag}
  <bridge name='${bridge_name}' stp='on' delay='0'/>
  <ip address='${NET_SUBNET}' netmask='${NET_NETMASK}'>
    <dhcp>
      <range start='${DHCP_START}' end='${DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF
  )

  if [ "$VERBOSE" = "true" ]; then
    log normal "Network XML:\n$net_xml"
  fi

  echo "$net_xml" | virsh net-define /dev/stdin 2>/dev/null
  virsh net-start "$RESOURCE_NAME" 2>/dev/null

  if [ "$AUTOSTART" = "yes" ]; then
    virsh net-autostart "$RESOURCE_NAME" 2>/dev/null
  fi

  if [ $? -eq 0 ]; then
    log success "Virtual network '$RESOURCE_NAME' successfully created and started!"
  else
    log error "Failed to create virtual network '$RESOURCE_NAME'."
  fi
}

get_all_networks() {
  local nets=()
  readarray -t nets < <(virsh net-list --all --name 2>/dev/null | awk '{print $1}')
  printf "%s\n" "${nets[@]}"
}

network_delete() {
  if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
    RESOURCE_NAME="$1"
  else
    local nets=()
    readarray -t nets < <(get_all_networks)
    if [ ${#nets[@]} -eq 0 ]; then
      log error "No virtual networks found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${nets[@]}")
    local choice
    choice=$(select_option "Select Virtual Network to Delete" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Deletion cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  log progress "Deleting virtual network '$RESOURCE_NAME'..."
  virsh net-destroy "$RESOURCE_NAME" 2>/dev/null
  virsh net-undefine "$RESOURCE_NAME" 2>/dev/null
  if [ $? -eq 0 ]; then
    log success "Virtual network '$RESOURCE_NAME' successfully deleted."
  else
    log error "Failed to delete virtual network '$RESOURCE_NAME'."
  fi
}

network_list() {
  log progress "Listing libvirt virtual networks:"
  virsh net-list --all
}

network() {
  NETWORK_ACTION="$1"
  shift || true
  case "$NETWORK_ACTION" in
    help|-h|--help)
      network_help
      ;;
    create|c)
      network_create "$@"
      ;;
    delete|d)
      network_delete "$@"
      ;;
    list|ls)
      network_list "$@"
      ;;
    *)
      [ -n "$NETWORK_ACTION" ] && echo "Invalid action [$NETWORK_ACTION]"
      network_help
      [ -z "$NETWORK_ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

# ==============================================================================
# VM Snapshot Step Functions & Handlers
# ==============================================================================

get_instance_snapshots() {
  local vm="$1"
  local snaps=()
  readarray -t snaps < <(virsh snapshot-list "$vm" --name 2>/dev/null | awk '{print $1}')
  printf "%s\n" "${snaps[@]}"
}

snapshot_help() {
  cat << EOF
## Libvirt KVM Wrapper - virtx snapshot ##
Usage: $(basename "$0") snapshot <command> [options]

Commands:
  create|c [instance] [snap]   create snapshot (interactive if omitted)
  delete|d [instance] [snap]   delete snapshot (interactive if omitted)
  revert|r [instance] [snap]   revert instance to snapshot (interactive if omitted)
  list|ls [instance]           list snapshots for instance (interactive if omitted)
  help|--help|-h               show this page

Options:
  --description|-d "text"      optional description for snapshot
  --atomic                     take atomic snapshot
  --verbose|-v                 show what's being done in detail
EOF
}

snapshot_create() {
  local vm_name="$1"
  local snap_name="$2"

  if [ -n "$vm_name" ] && ! [[ "$vm_name" =~ ^- ]]; then
    RESOURCE_NAME="$vm_name"
    shift || true
    if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
      SNAP_NAME="$1"
      shift || true
    fi
  fi

  if [ -z "$RESOURCE_NAME" ]; then
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance for Snapshot Creation" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Snapshot creation cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  if [ -z "$SNAP_NAME" ]; then
    local default_snap="snap-$(date +%Y%m%d-%H%M%S)"
    read -p "Enter snapshot name [default: $default_snap]: " input_snap
    SNAP_NAME="${input_snap:-$default_snap}"
  fi

  local description=""
  local atomic_flag=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --description|-d)
        description="$2"
        shift 2
        ;;
      --atomic)
        atomic_flag="--atomic"
        shift
        ;;
      --verbose|-v)
        VERBOSE="true"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  log progress "Creating snapshot '$SNAP_NAME' for instance '$RESOURCE_NAME'..."

  local snap_cmd=("virsh" "snapshot-create-as" "--domain" "$RESOURCE_NAME" "--name" "$SNAP_NAME")
  if [ -n "$description" ]; then
    snap_cmd+=("--description" "$description")
  fi
  if [ -n "$atomic_flag" ]; then
    snap_cmd+=("$atomic_flag")
  fi

  if [ "$VERBOSE" = "true" ]; then
    log normal "Running: ${snap_cmd[*]}"
  fi

  "${snap_cmd[@]}" 2>/dev/null

  if [ $? -eq 0 ]; then
    log success "Snapshot '$SNAP_NAME' successfully created for '$RESOURCE_NAME'!"
  else
    log error "Failed to create snapshot for '$RESOURCE_NAME'."
  fi
}

snapshot_delete() {
  local vm_name="$1"
  local snap_name="$2"

  if [ -n "$vm_name" ] && ! [[ "$vm_name" =~ ^- ]]; then
    RESOURCE_NAME="$vm_name"
    shift || true
    if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
      SNAP_NAME="$1"
      shift || true
    fi
  fi

  if [ -z "$RESOURCE_NAME" ]; then
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance for Snapshot Deletion" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Snapshot deletion cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  if [ -z "$SNAP_NAME" ]; then
    local snaps=()
    readarray -t snaps < <(get_instance_snapshots "$RESOURCE_NAME")
    if [ ${#snaps[@]} -eq 0 ]; then
      log error "No snapshots found for instance '$RESOURCE_NAME'."
      exit 1
    fi
    local options=("[ < Cancel ]" "${snaps[@]}")
    local choice
    choice=$(select_option "Select Snapshot to Delete ($RESOURCE_NAME)" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Snapshot deletion cancelled."
      exit 0
    fi
    SNAP_NAME="$choice"
  fi

  log progress "Deleting snapshot '$SNAP_NAME' from instance '$RESOURCE_NAME'..."
  virsh snapshot-delete --domain "$RESOURCE_NAME" --snapshotname "$SNAP_NAME" 2>/dev/null

  if [ $? -eq 0 ]; then
    log success "Snapshot '$SNAP_NAME' successfully deleted from '$RESOURCE_NAME'!"
  else
    log error "Failed to delete snapshot '$SNAP_NAME' from '$RESOURCE_NAME'."
  fi
}

snapshot_revert() {
  local vm_name="$1"
  local snap_name="$2"

  if [ -n "$vm_name" ] && ! [[ "$vm_name" =~ ^- ]]; then
    RESOURCE_NAME="$vm_name"
    shift || true
    if [ -n "$1" ] && ! [[ "$1" =~ ^- ]]; then
      SNAP_NAME="$1"
      shift || true
    fi
  fi

  if [ -z "$RESOURCE_NAME" ]; then
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance to Revert" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Snapshot revert cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  if [ -z "$SNAP_NAME" ]; then
    local snaps=()
    readarray -t snaps < <(get_instance_snapshots "$RESOURCE_NAME")
    if [ ${#snaps[@]} -eq 0 ]; then
      log error "No snapshots found for instance '$RESOURCE_NAME'."
      exit 1
    fi
    local options=("[ < Cancel ]" "${snaps[@]}")
    local choice
    choice=$(select_option "Select Snapshot to Revert To ($RESOURCE_NAME)" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Snapshot revert cancelled."
      exit 0
    fi
    SNAP_NAME="$choice"
  fi

  log progress "Reverting instance '$RESOURCE_NAME' to snapshot '$SNAP_NAME'..."
  virsh snapshot-revert --domain "$RESOURCE_NAME" --snapshotname "$SNAP_NAME" 2>/dev/null

  if [ $? -eq 0 ]; then
    log success "Instance '$RESOURCE_NAME' successfully reverted to snapshot '$SNAP_NAME'!"
  else
    log error "Failed to revert instance '$RESOURCE_NAME' to snapshot '$SNAP_NAME'."
  fi
}

snapshot_list() {
  local vm_name="$1"
  if [ -n "$vm_name" ] && ! [[ "$vm_name" =~ ^- ]]; then
    RESOURCE_NAME="$vm_name"
  else
    local vms=()
    readarray -t vms < <(get_all_instances)
    if [ ${#vms[@]} -eq 0 ]; then
      log error "No instances found."
      exit 1
    fi
    local options=("[ < Cancel ]" "${vms[@]}")
    local choice
    choice=$(select_option "Select Instance to List Snapshots" "${options[@]}")
    [ $? -eq 130 ] && exit 0
    if [[ "$choice" == "[ < Cancel ]" || -z "$choice" ]]; then
      log normal "Listing cancelled."
      exit 0
    fi
    RESOURCE_NAME="$choice"
  fi

  log progress "Listing snapshots for instance '$RESOURCE_NAME':"
  virsh snapshot-list --domain "$RESOURCE_NAME"
}

snapshot() {
  SNAP_ACTION="$1"
  shift || true
  case "$SNAP_ACTION" in
    help|-h|--help)
      snapshot_help
      ;;
    create|c)
      snapshot_create "$@"
      ;;
    delete|d)
      snapshot_delete "$@"
      ;;
    revert|r|restore)
      snapshot_revert "$@"
      ;;
    list|ls)
      snapshot_list "$@"
      ;;
    *)
      [ -n "$SNAP_ACTION" ] && echo "Invalid action [$SNAP_ACTION]"
      snapshot_help
      [ -z "$SNAP_ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

main() {
  ACTION="$1"
  shift || true
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
    snapshot|snap|sp)
      snapshot "$@"
      ;;
    *)
      [ -n "$ACTION" ] && echo "Invalid action [$ACTION]"
      help
      [ -z "$ACTION" ] && exit 0 || exit 1
      ;;
  esac
}

main "$@"
