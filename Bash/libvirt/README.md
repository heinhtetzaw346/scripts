# virtx - Libvirt KVM Management Wrapper

`virtx` is an interactive and non-interactive CLI wrapper for **Libvirt / KVM**. It simplifies creating, managing, editing, cloning, snapshotting, and networking virtual machines, storage pools, and virtual networks with `fzf` fuzzy-search wizards and CLI flags.

---

## Features

- 🧙 **Interactive Wizards**: 10-step back-steppable (`[ < Back ]`) fuzzy-search UI powered by `fzf`.
- ⚡ **Non-Interactive Automation**: Support for CLI flags (`-c`, `-m`, `-s`, `-n`, `-o`, `-g`, `--dns`, `--file`) for scripting and CI/CD.
- 💻 **Detailed VM Overview**: Rich `instance ls` table displaying State, vCPU, RAM, Firmware (BIOS/UEFI), Network, IP Address, Autostart, and Disk Path.
- 🎨 **Live/Persistent Hardware Edits**: Easily modify vCPU core count, RAM allocation, and Graphics mode (`spice`, `vnc`, `none`/headless) using `virt-xml` and XML conflict resolution.
- 💾 **ISO-Safe Storage Purging**: `instance delete` purges datastore `.qcow2` disks and NVRAM variables while protecting shared ISO images.
- 📸 **VM Snapshot Management**: Create timestamped or named snapshots with descriptions, revert VM states, list, and delete snapshots.
- 🌐 **Virtual Networks**: Create NAT, routed, open, or isolated networks with custom subnets, DHCP ranges, and a toggle to disable libvirt DNS resolution (`--dns no`).
- 📁 **Storage Pools**: Manage `dir`, `logical`, `fs`, and `netfs` storage pools with autostart settings.
- 🐑 **Instance Cloning**: Duplicate VMs using `virt-clone` with auto-generated or custom storage paths.
- 🌍 **Universal Portability**: Zero hardcoded user paths or machine dependencies; dynamically queries the local `libvirt` daemon.

---

## Prerequisites

Ensure the following tools are installed on your Linux host:

```bash
# Ubuntu / Debian
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst fzf python3

# AlmaLinux / RHEL / Rocky / Fedora
sudo dnf install -y qemu-kvm libvirt virt-install virt-viewer fzf python3
```

---

## Installation

### 1. Download and move to binary directory

Download and install `virtx` directly from GitHub to `$HOME/.local/bin/virtx`:

```bash
curl -fsSL https://raw.githubusercontent.com/FuReAsu/virtx/main/virtx.sh -o ~/.local/bin/virtx && chmod +x ~/.local/bin/virtx
```

Or execute the self-installer remotely:

```bash
curl -fsSL https://raw.githubusercontent.com/FuReAsu/virtx/main/virtx.sh | bash -s -- install
```

---

### 2. Direct Local Command Execution

If running from a cloned local repository:

```bash
# Make script executable
chmod +x virtx.sh

# Run direct command or self-install
./virtx.sh install
```

> **Note:** Ensure `$HOME/.local/bin` is in your system `PATH`. You can override the installation directory using `VIRTX_INSTALL_PATH=/usr/local/bin/virtx ./virtx.sh install`.

---

## Command Reference & Usage

### 1. Instance Management (`virtx instance` / `virtx i`)

```bash
# Interactive instance creation wizard
virtx instance create

# Non-interactive instance creation
virtx instance create my-server \
  --cpu 4 \
  --memory 8 \
  --disk-size 40 \
  --os-variant ubuntu24.04 \
  --firmware uefi \
  --graphics spice \
  --network default \
  --iso /path/to/ubuntu-24.04.iso \
  --verbose

# Detailed list of all instances (State, vCPU, RAM, Firmware, Network, IP, Autostart, Disk)
virtx instance ls

# Interactive hardware edit (CPU, Memory, Graphics)
virtx instance edit my-server

# Non-interactive hardware edit
virtx instance edit my-server -c 8 -m 16 -g vnc

# Delete instance (purges datastore disk & NVRAM, preserves ISO files)
virtx instance delete my-server
```

---

### 2. Instance Cloning (`virtx clone` / `virtx cl`)

```bash
# Interactive clone wizard (Select source VM, clone name, storage target)
virtx clone

# Non-interactive clone (Auto-generated storage path)
virtx clone my-server my-server-clone

# Clone with custom storage filepath
virtx clone my-server my-server-clone --file /path/to/custom-disk.qcow2 --verbose
```

---

### 3. Snapshot Management (`virtx snapshot` / `virtx snap` / `virtx sp`)

```bash
# Interactive snapshot wizard
virtx snapshot create

# Create snapshot with description
virtx snapshot create my-server snap-v1 --description "Before Kubernetes installation" --atomic

# List snapshots for an instance
virtx snapshot ls my-server

# Revert instance to snapshot state
virtx snapshot revert my-server snap-v1

# Delete snapshot
virtx snapshot delete my-server snap-v1
```

---

### 4. Virtual Network Management (`virtx network` / `virtx n`)

```bash
# Interactive network wizard
virtx network create

# Create NAT virtual network with custom subnet and DNS disabled
virtx network create k8s-net \
  --mode nat \
  --subnet 192.168.200.1 \
  --netmask 255.255.255.0 \
  --dns no \
  --autostart yes \
  --verbose

# List all virtual networks
virtx network ls

# Delete virtual network
virtx network delete k8s-net
```

---

### 5. Storage Pool Management (`virtx storage` / `virtx s`)

```bash
# Interactive storage pool wizard
virtx storage create

# Create directory storage pool
virtx storage create datastore2 --type dir --path /data/kvm-images --autostart yes

# List all storage pools
virtx storage ls

# Delete storage pool
virtx storage delete datastore2
```

---

## Guest OS Optimizations & Tips

### Auto-Scaling Console Display
To enable automatic resolution scaling when resizing the Virt-Viewer / Virt-Manager window:
1. Ensure the VM uses Virtio video driver (auto-configured by `virtx`).
2. Install `spice-vdagent` inside the guest OS:
   - **AlmaLinux/RHEL**: `sudo dnf install -y spice-vdagent && sudo systemctl enable --now spice-vdagent`
   - **Ubuntu/Debian**: `sudo apt install -y spice-vdagent`
3. In Virt-Viewer / Virt-Manager: Go to **View** $\rightarrow$ **Scale Display** $\rightarrow$ check **Always**.

### Enabling `virsh console` Serial Login
To access serial console (`virsh console <vm>`) on standard Linux ISO installs:
- **AlmaLinux**: `sudo systemctl enable --now serial-getty@ttyS0.service && sudo grubby --update-kernel=ALL --args="console=tty0 console=ttyS0,115200n8"`
- **Ubuntu**: `sudo systemctl enable --now serial-getty@ttyS0.service` and add `console=tty0 console=ttyS0,115200n8` to `/etc/default/grub` $\rightarrow$ `sudo update-grub`.
- **Alpine**: Uncomment `ttyS0::respawn:...` in `/etc/inittab` and add `console=tty0 console=ttyS0,115200n8` to GRUB / extlinux.

---

## License

MIT License. Free to use, modify, and distribute for DevOps and SysAdmin automation.
