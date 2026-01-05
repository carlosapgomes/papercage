#!/bin/bash
# PAPERCAGE: BUBBLEWRAP EDITION (v3.0 - With Arguments)
# Usage: ./launch-agent-with-args.sh <workdir> <prompt>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <workdir> <prompt>"
    echo "Example: $0 /home/user/my-project 'Help me debug this application'"
    exit 1
fi

WORKDIR="$1"
PROMPT="$2"
AGENT_USER="ai-agent"
SOCKET_DIR="/opt/ai-agent/sockets"
BINARY_CELL="/opt/ai-bin/claude"
HOST_ISOPROXY="/run/isoproxy/isoproxy.sock"

# Validate workdir exists
if [ ! -d "$WORKDIR" ]; then
    echo "Error: Working directory '$WORKDIR' does not exist"
    exit 1
fi

# --- 1. Host-Side Bridges ---
sudo rm -f "$SOCKET_DIR"/*.sock
socat UNIX-LISTEN:"$SOCKET_DIR/isoproxy.sock",reuseaddr,fork,mode=666 UNIX-CONNECT:"$HOST_ISOPROXY" &
socat UNIX-LISTEN:"$SOCKET_DIR/devpi.sock",reuseaddr,fork,mode=666 TCP4:127.0.0.1:3141 &
BRIDGE_PIDS=$!
trap "kill $BRIDGE_PIDS; exit" SIGINT SIGTERM
sleep 0.5

# --- 2. The Clean Launch ---
echo "🚀 Papercage: Starting $BINARY_CELL in $WORKDIR..."
echo "📝 Prompt: $PROMPT"

# NOTE: No --uid 0, no --cap-add. Just unprivileged namespaces.
sudo -u "$AGENT_USER" bwrap \
	--die-with-parent \
	--unshare-all \
	--unshare-user \
	--hostname papercage \
	--proc /proc \
	--dev /dev \
	--dir /tmp \
	--dir /var \
	--ro-bind /usr /usr \
	--ro-bind /lib /lib \
	--ro-bind /lib64 /lib64 \
	--ro-bind /bin /bin \
	--ro-bind /sbin /sbin \
	--ro-bind /etc/resolv.conf /etc/resolv.conf \
	--ro-bind /etc/hosts /etc/hosts \
	--ro-bind /etc/ssl /etc/ssl \
	--bind "$SOCKET_DIR" "$SOCKET_DIR" \
	--bind "$WORKDIR" "$WORKDIR" \
	--ro-bind /opt/ai-bin /opt/ai-bin \
	--chdir "$WORKDIR" \
	bash -c "
# 1. Turn on lo and hide the harmless error
        /usr/sbin/ip link set lo up 2>/dev/null || true

        # 2. Start Inner Bridges
        socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:$SOCKET_DIR/isoproxy.sock &
        socat TCP4-LISTEN:3141,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:$SOCKET_DIR/devpi.sock &

				# 3. SET PROXY ENV VARS (Essential for Claude)
        export ANTHROPIC_AUTH_TOKEN=\"dummy-token-overwritten-by-proxy\"
				export ANTHROPIC_BASE_URL=\"http://127.0.0.1:8080\"
				export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'
				export PIP_INDEX_URL=\"http://127.0.0.1:3141/root/pypi/+simple/\"
				export PIP_TRUSTED_HOST=\"127.0.0.1\"

        # 4. Corrected Identity Display
        echo \"--- Papercage Active in $WORKDIR ---\"
        echo \"Working directory: \$(pwd)\"

        # 5. Start Claude with prompt using -p flag
        $BINARY_CELL --dangerously-skip-permissions -p \"$PROMPT\"
    "