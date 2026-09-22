# ovpnx - OpenVPN 3 Wrapper Script

`ovpnx.sh` is a lightweight Bash wrapper script for the **OpenVPN 3 Linux client**. It simplifies managing OpenVPN 3 configuration profiles, initiating and terminating VPN sessions, viewing connection statistics, and monitoring real-time logs through a clean CLI interface.

---

## Features

- ⚡ **Simplified Command Syntax**: Short aliases for common actions (`c`, `d`, `ls`, `rm`).
- 🎯 **Smart Defaults**: Automatically picks the first available configuration or active session when arguments are omitted for `connect`, `disconnect`, and `stats`.
- 📊 **Session Statistics**: Quick access to live session metrics.
- 📜 **Live Log Streaming**: Real-time log monitoring with automatic cleanup of temporary files.
- 🛠️ **Built-in Help**: Integrated help manual accessible via `help`, `-h`, or `--help`.

---

## Prerequisites

- Linux operating system
- `openvpn3` client installed and configured on your system (`command -v openvpn3`)
- `sudo` privileges (required for `log all` journal access)

---

## Installation & Setup

1. **Clone or download the script**:
   ```bash
   git clone https://github.com/FuReAsu/scripts.git
   cd scripts/Bash/ovpn
   ```

2. **Make the script executable**:
   ```bash
   chmod +x ovpnx.sh
   ```

3. *(Optional)* **Add to your `PATH` or create an alias**:
   ```bash
   # Create a symlink to user binary folder
   sudo ln -s "$(realpath ovpnx.sh)" /usr/local/bin/ovpnx

   # Or add an alias in your ~/.bashrc or ~/.zshrc
   alias ovpnx="$(realpath ovpnx.sh)"
   ```

---

## Usage Summary

```bash
ovpnx.sh <command> [options]
```

### Command Reference

| Command | Aliases | Description |
| :--- | :--- | :--- |
| `import <file> <name>` | — | Import an `.ovpn` configuration file persistently |
| `list [s\|session]` | `ls` | List imported configurations (or active sessions with `s` or `session`) |
| `connect [name]` | `c`, `start` | Connect to a VPN profile (defaults to the first configuration if name is omitted) |
| `disconnect [name]` | `d`, `stop` | Disconnect an active VPN session (defaults to the first active session if name is omitted) |
| `stats [name]` | — | View session statistics (defaults to the first active session if name is omitted) |
| `log [all]` | — | Stream real-time logs (use `all` to view full system journal logs via `sudo`) |
| `remove <name>` | `rm` | Remove an imported VPN profile |
| `help` | `-h`, `--help` | Display usage instructions |

---

## Examples

### 1. Import a Configuration
Import an OpenVPN configuration file and assign it a persistent profile name:
```bash
./ovpnx.sh import /path/to/my-vpn.ovpn work-vpn
```

### 2. List Profiles and Active Sessions
List all imported VPN configurations:
```bash
./ovpnx.sh list
# or
./ovpnx.sh ls
```

List active VPN sessions:
```bash
./ovpnx.sh list s
# or
./ovpnx.sh ls session
```

### 3. Connect to a VPN
Connect to a specific imported profile:
```bash
./ovpnx.sh connect work-vpn
```
Or connect using smart default (first imported profile):
```bash
./ovpnx.sh c
```

### 4. Check Session Statistics
View connection stats for an active session:
```bash
./ovpnx.sh stats work-vpn
```
Or use default active session:
```bash
./ovpnx.sh stats
```

### 5. Stream Real-Time Logs
Follow live OpenVPN 3 logs:
```bash
./ovpnx.sh log
```
View full system journal logs (requires `sudo`):
```bash
./ovpnx.sh log all
```

### 6. Disconnect from a VPN
Disconnect a specific session:
```bash
./ovpnx.sh disconnect work-vpn
```
Or disconnect using smart default (first active session):
```bash
./ovpnx.sh d
```

### 7. Remove a Configuration
Remove an imported VPN profile:
```bash
./ovpnx.sh remove work-vpn
```

---

## Error Handling

- **Binary Check**: The script automatically checks for `openvpn3` availability before running any command.
- **Validation**: Verifies existence of profile names and active sessions before attempting connection or disconnection operations.
