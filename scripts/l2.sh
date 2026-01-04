#!/bin/bash
# Papercage: Fences, not Fortresses

AGENT_USER="ai-agent"
SOCKET_DIR="/opt/ai-agent/sockets"
BINARY_CELL="/opt/ai-bin/claude"
HOST_ISOPROXY="/run/isoproxy/isoproxy.sock"

# --- 1. Cleanup ---
# We must remove old root-owned sockets to start fresh
sudo rm -f "$SOCKET_DIR/console.sock" "$SOCKET_DIR/devpi.sock" "$SOCKET_DIR/isoproxy.sock"

# --- 2. Host-Side Bridges ---
# We use sudo to create them, but set 'user=' so ai-agent owns the file.
# Bridge for Devpi
sudo socat UNIX-LISTEN:"$SOCKET_DIR/devpi.sock",reuseaddr,fork,mode=660,user=$AGENT_USER,group=$AGENT_USER TCP4:127.0.0.1:3141 &
DEVPI_PID=$!

# Bridge for LLM (Isoproxy)
sudo socat UNIX-LISTEN:"$SOCKET_DIR/isoproxy.sock",reuseaddr,fork,mode=660,user=$AGENT_USER,group=$AGENT_USER UNIX-CONNECT:"$HOST_ISOPROXY" &
ISO_BRIDGE_PID=$!

trap "sudo kill $DEVPI_PID $ISO_BRIDGE_PID; exit" SIGINT SIGTERM

# CRITICAL: Wait for sockets to actually appear on disk before launching Firejail
sleep 1

# --- 3. The Cage ---
echo "🚀 Papercage: Starting $BINARY_CELL..."
# We use --ignore=apparmor to bypass any strict OS-level socket blocking
sudo -u "$AGENT_USER" firejail --ignore=apparmor --profile=../profiles/ai-agent.profile \
  --env=ANTHROPIC_AUTH_TOKEN="$ANTHROPIC_AUTH_TOKEN" \
  --env=ANTHROPIC_BASE_URL="http://127.0.0.1:8080" \
  --env=PIP_INDEX_URL="http://127.0.0.1:3141/root/pypi/+simple/" \
  bash -c "
    # Inner Bridges (Inside Jail)
    # These connect to the sockets owned by ai-agent in the shared folder
    socat TCP4-LISTEN:8080,reuseaddr,fork UNIX-CONNECT:\"$SOCKET_DIR/isoproxy.sock\" &
    socat TCP4-LISTEN:3141,reuseaddr,fork UNIX-CONNECT:\"$SOCKET_DIR/devpi.sock\" &

    # Console Bridge
    socat UNIX-LISTEN:\"$SOCKET_DIR/console.sock\",reuseaddr,mode=666 EXEC:\"$BINARY_CELL --dangerously-skip-permissions\",pty,stderr
  "
