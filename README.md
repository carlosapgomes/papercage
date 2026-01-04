# Papercage: "Fences, not Fortresses"

> **⚠️ Work in Progress**: This project is in early development. Currently, we can run Claude Code in a sandboxed environment with basic isolation, but advanced interaction features and full functionality are still being implemented.

Papercage is a minimalist security architecture for running high-privilege AI agents (like Claude Code) in a restricted
Linux environment using Firejail and UNIX Domain Sockets.

## The Security Contract

| Component  | Host Path                | Cage Path | Implementation  | Security Benefit                                             |
| ---------- | ------------------------ | --------- | --------------- | ------------------------------------------------------------ |
| Network    | Physical NICs            | HIDDEN    | net none        | Zero egress. The agent cannot "phone home" or leak data.     |
| Identity   | /home/$USER              | HIDDEN    | ai-agent user   | Agent cannot access $HOME or sensitive SSH/GPG keys.         |
| Filesystem | Host filesystem          | tmpfs     | private (tmpfs) | No persistence. Malware or leaked files vanish on exit.      |
| Workspace  | /home/$USER/projects/app | Same      | whitelist       | Read/Write access only to explicitly permitted project dirs  |
| Binaries   | /opt/ai-bin              | Same      | whitelist       | Read-Only access to curated toolchain (Claude, Python, etc.) |
| Sockets    | /opt/ai-agent/sockets    | Same      | whitelist       | Communication is file-based and limited to specific "pipes." |
| Memory     | Host memory              | Isolated  | noexec removed  | Allows JIT/Node.js to run while keeping caps.drop all.       |
| Privileges | Root capabilities        | Dropped   | noroot          | Prevents the agent from escalating to root within the jail.  |

## Project Structure

```bash
papercage/
├── README.md
├── profiles/
│   └── ai-agent.profile
└── scripts/
    ├── watch-agent.sh           # Terminal UI for the agent
    ├── cp-claude-bin.sh         # Strategy for binary installation
    ├── init-user-and-folders.sh # One-time setup
    └── launch-agent.sh          # The main engine

```

## File Contents

- `scripts/init-user-and-folders.sh`

```bash
#!/bin/bash
# One-time setup for Papercage

# 1. User Creation
echo "[*] Creating ai-agent user..."
sudo useradd -r -s /usr/sbin/nologin ai-agent || echo "User already exists."

# 2. Folder Structure
echo "[*] Creating directory structure..."
sudo mkdir -p /opt/ai-bin
sudo mkdir -p /opt/ai-agent/sockets
sudo mkdir -p /opt/ai-agent/workspace

# 3. Permissions
echo "[*] Setting permissions..."
sudo chown -R $USER:$USER /opt/ai-bin
sudo chown -R ai-agent:ai-agent /opt/ai-agent/workspace
sudo chmod 777 /opt/ai-agent/sockets

# 4. Prerequisite Check
echo "-------------------------------------------------------"
echo "PRE-FLIGHT CHECKLIST:"
echo "-------------------------------------------------------"
if [[ -S "/run/isoproxy/isoproxy.sock" ]]; then
    echo "[OK] Isoproxy socket detected."
else
    echo "[!] WARNING: /run/isoproxy/isoproxy.sock not found."
fi

if netstat -tuln | grep -q ":3141 "; then
    echo "[OK] devpi-server detected on port 3141."
else
    echo "[!] WARNING: devpi-server not detected. Start it with:"
    echo "    devpi-server --host 127.0.0.1 --port 3141"
fi
echo "-------------------------------------------------------"

```

- `scripts/cp-claude-bin.sh`

```bash
#!/bin/bash
# Claude Code standalone binary strategy
# Install via: curl -fsSL https://claude.ai/install | sh
SOURCE_BIN="$HOME/.local/bin/claude"
TARGET_BIN="/opt/ai-bin/claude"

if [[ -f "$SOURCE_BIN" ]]; then
    cp "$SOURCE_BIN" "$TARGET_BIN"
    chmod +x "$TARGET_BIN"
    echo "[*] Claude binary copied to $TARGET_BIN"
    echo "[!] Reminder: Run 'claude update' in your userland and rerun this script to update the cage."
else
    echo "[E] Source binary not found at $SOURCE_BIN"
fi
```

- `profiles/ai-agent.profile`

```plaintext
# Papercage Firejail Profile
noroot
net none
private

# Whitelists
whitelist /opt/ai-bin
whitelist /opt/ai-agent/workspace
whitelist /opt/ai-agent/sockets
whitelist /run/isoproxy/isoproxy.sock
noblacklist /opt/ai-agent/sockets

# Hardening
caps.drop all
seccomp
nonewprivs

# Minimal Toolbox for Python/Node/Pip
private-bin bash,sh,ls,cat,git,python3,node,npm,pytest,claude,socat,tail,stdbuf,grep,sed,awk,tr,sleep,rm,mkdir,pkill,which,id,whoami,env,stty
```

- `scripts/launch-agent.sh`

```bash
#!/bin/bash
# Main Papercage Launch Engine

# --- Configuration ---
AGENT_USER="ai-agent"
SOCKET_DIR="/opt/ai-agent/sockets"
ISOPROXY_UDS="/run/isoproxy/isoproxy.sock"
BINARY_CELL="/opt/ai-bin/claude"

# --- Pre-flight ---
sudo rm -f "$SOCKET_DIR/console.sock" "$SOCKET_DIR/devpi.sock"

# 1. Start Host-side devpi bridge (assumes devpi-server is running on 3141)
sudo socat UNIX-LISTEN:"$SOCKET_DIR/devpi.sock",reuseaddr,fork,mode=666 TCP4:127.0.0.1:3141 &
DEVPI_PID=$!

trap "sudo kill $DEVPI_PID; exit" SIGINT SIGTERM

# --- The Cage ---
echo "🚀 Papercage: Starting $BINARY_CELL..."
sudo -u "$AGENT_USER" firejail --profile=../profiles/ai-agent.profile \
  --env=ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN" \
  --env=ANTHROPIC_BASE_URL="http://127.0.0.1:8080" \
  --env=PIP_INDEX_URL="http://127.0.0.1:3141/root/pypi/+simple/" \
  --env=PIP_TRUSTED_HOST="127.0.0.1" \
  bash -c "
    # Inner Bridges
    socat TCP4-LISTEN:8080,reuseaddr,fork UNIX-CONNECT:\"$ISOPROXY_UDS\" &
    socat TCP4-LISTEN:3141,reuseaddr,fork UNIX-CONNECT:\"$SOCKET_DIR/devpi.sock\" &

    # Console Bridge (The UI)
    socat UNIX-LISTEN:\"$SOCKET_DIR/console.sock\",reuseaddr,mode=666 EXEC:\"$BINARY_CELL --dangerously-skip-permissions\",pty,stderr
  "

# Cleanup
# sudo kill $DEVPI_PID
```

- `scripts/watch-agent.sh`

```bash
#!/bin/bash
# Papercage Intercom
SOCKET="/opt/ai-agent/sockets/console.sock"

if [[ ! -S "$SOCKET" ]]; then
    echo "[E] Console socket not found. Is launch-agent.sh running?"
    exit 1
fi

echo "[*] Connecting to Papercage..."
# STDIO,raw,echo=0 provides the TTY experience Claude expects
socat STDIO,raw,echo=0 UNIX-CONNECT:"$SOCKET"
```

## Pre-flight Prerequisites

Before running `launch-agent.sh`, the following two services must be active on your host.

### 1. The LLM Gateway (Isoproxy)

Papercage does not allow direct internet access. It expects an LLM proxy (like `isoproxy`) to be listening on a UNIX socket.

- **Socket Path:** `/run/isoproxy/isoproxy.sock`
- **Requirement:** Ensure the `ai-agent` user has read/write permissions to this socket.
- **Verification:** `ls -l /run/isoproxy/isoproxy.sock` should show it exists.

### 2. The PyPI Mirror (devpi-server)

To allow the agent to install Python packages without an internet connection, you must run a local `devpi-server`.

> **Important:** You must run `launch-agent.sh` as the **same user** who is running the `devpi-server` to ensure the `socat` bridge can access the host's loopback ports.

**Installation via `uv`:**

```bash
# Create a dedicated environment for the server
uv venv devpi_env
source devpi_env/bin/activate
uv pip install devpi-server devpi-client
```

**Starting the server:**

```bash
# Initialize and run (first time only)
devpi-init
# Run the server on the standard port
devpi-server --host 127.0.0.1 --port 3141
```

## Setup Instructions (The Workflow)

- Initialize: Run init-user-and-folders.sh.
- Binaries: Ensure Claude is installed in your user account (curl -fsSL https://claude.ai/install | sh), then run cp-claude-bin.sh.
- Proxy Premises: Ensure isoproxy is running and its socket is available at /run/isoproxy/isoproxy.sock.
- Devpi: Ensure devpi-server is running on your host at 127.0.0.1:3141.
- Launch: Set your environment variable export ANTHROPIC_AUTH_TOKEN="your_token" and run ./launch-agent.sh.
- Connect: In a second terminal, run ./agent-watch.sh.

## Workspace Mounting (Existing Code)

By default, Papercage is an empty room. To let the agent see your project, you must explicitly "pass it through" the
cage bars.

### Updating the Profile

Add your project root to the `profiles/ai-agent.profile`. It is best to use a generic path or a specific one for the
project you are working on.

```plaintext
# Add this to /etc/firejail/ai-agent.profile
# Allow the agent to read/write to your project folder
whitelist /home/$USER/projects/my-existing-app
```

### Directing the Agent

When you launch the cage, the agent starts in its own home directory. You must tell the `launch-agent.sh` to "walk"
into the `whitelisted` folder immediately.

Update the `launch-agent.sh` EXEC line:

```bash
# In launch-agent.sh
# We add 'cd' to the command string before launching claude
sudo -u "$AGENT_USER" firejail --profile=../profiles/ai-agent.profile \
  ... \
  bash -c "
    ... (bridges) ...
    socat UNIX-LISTEN:\"$SOCKET_DIR/console.sock\",reuseaddr,mode=666 \
    EXEC:\"bash -c 'cd /home/$USER/projects/my-existing-app && $BINARY_CELL --dangerously-skip-permissions'\",pty,stderr
  "
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Attribution

This project was developed with assistance from:

- **Gemini Flash 3.0** - Initial architecture design and security model concepts
- **GPT-5** - Implementation strategy and documentation structure
- **Claude (Sonnet 4)** - Code implementation, testing, and final documentation
