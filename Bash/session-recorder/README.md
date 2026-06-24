# sesh-rec (Session Recorder)

`sesh-rec` is a lightweight Bash script designed to record, replay, search, and manage your terminal sessions. Under the hood, it leverages the standard `script` and `scriptreplay` utilities to record both typescript and timing data, allowing you to replay terminal sessions exactly as they happened, adjust playback speed, search log history (with ANSI color stripping), and manage log files easily.

## Features

- **Session Recording**: Log full terminal output along with exact timing info. Prevents accidental nested recording.
- **Interactive Replay**: Play back recorded sessions with adjustable speeds.
- **Interactive Log Selection**: Quickly find and select logs using `fzf`.
- **Instant Mode**: View log files instantly as static files with ANSI coloring intact.
- **Searchable Logs**: Search across log files by keyword, automatically stripping ANSI escape codes and terminal artifacts for clean matching.
- **Log Management**: List logged sessions grouped by date, and clean up older log directories automatically or all at once.
- **Self-Installation**: Installs itself cleanly into your local path.

---

## Installation

You can install the script to your local bin directory (`~/.local/bin`) by running:

```bash
./sesh-rec.sh install
```

Make sure your shell configuration includes `~/.local/bin` in your `PATH`. If it doesn't, add the following line to your shell configuration file (e.g., `~/.bashrc` or `~/.zshrc`):

```bash
export PATH="$PATH:$HOME/.local/bin"
```

Once installed, you can invoke the utility globally as `sesh-rec`.

---

## Requirements

- **Bash** (tested on Linux)
- **util-linux** (provides the `script` and `scriptreplay` commands)
- **fzf** (optional, required for the interactive replay selection mode)
- **col** (optional, required for the `find` command to strip backspaces/control characters)

---

## Directory Structure

By default, all session logs are stored under:
`~/.local/session-recorder/logs/`

Logs are grouped by date subdirectories (`YYYY-MM-DD`):
```text
~/.local/session-recorder/logs/
└── 2026-06-24/
    ├── sesh-2026-06-24_09-30-15.log       # Terminal output typescript
    └── sesh-2026-06-24_09-30-15.timing    # Timing information for replay
```

---

## Usage

```bash
sesh-rec [ help | record | replay | showdir | cleanup | find ] [ options ] [ arguments ]
```

### 1. Recording a Session
Start recording your current terminal session:
```bash
sesh-rec record
```
*Note: Press `CTRL+D` or type `exit` to stop recording.*

You can also specify a custom filename or location:
```bash
sesh-rec record custom-session.log
```

### 2. Replaying a Session
`sesh-rec` supports two replay modes: **Stream Mode** (animated playback) and **Instant Mode** (static viewer).

#### Stream Mode (`-s` or `--stream`)
Replay the session in real-time:
```bash
sesh-rec replay -s path/to/session.log
```

Adjust replay speed (e.g., double speed):
```bash
sesh-rec replay -s 2 path/to/session.log
```

Select a log file interactively using `fzf`:
```bash
sesh-rec replay -s -I
# or
sesh-rec replay -s --interactive
```

#### Instant Mode (`-i` or `--instant`)
Open the session log in `less` with ANSI colors parsed:
```bash
sesh-rec replay -i path/to/session.log
```

### 3. Finding and Searching Logs
Search for a keyword inside your logs. The search strips out ANSI control sequences, ensuring your search keyword matches the actual text.

Search in a specific date directory:
```bash
sesh-rec find 2026-06-24 "git commit"
```

Search across all logged dates:
```bash
sesh-rec find -A "error"
# or
sesh-rec find --all "error"
```

### 4. Viewing Available Log Directory
List all date folders and the session logs inside them:
```bash
sesh-rec showdir
```

### 5. Cleaning Up Logs
Keep your disk usage clean by managing old logs.

Clean up logs older than 1 month:
```bash
sesh-rec cleanup
```

Clean up all logs (requires verification prompt):
```bash
sesh-rec cleanup -A
# or
sesh-rec cleanup --all
```

---

## Help
To view the command-line usage manual:
```bash
sesh-rec help
```
