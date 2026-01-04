bash
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
