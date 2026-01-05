#!/bin/bash
# PAPERCAGE: BUBBLEWRAP EDITION (v3.0 - The Clean Version)

AGENT_USER="ai-agent"
SOCKET_DIR="/opt/ai-agent/sockets"
BINARY_CELL="/opt/ai-bin/claude"
HOST_ISOPROXY="/run/isoproxy/isoproxy.sock"
WORKSPACE="/opt/ai-agent/workspace"

# --- 1. Host-Side Bridges ---
sudo rm -f "$SOCKET_DIR"/*.sock
socat UNIX-LISTEN:"$SOCKET_DIR/isoproxy.sock",reuseaddr,fork,mode=666 UNIX-CONNECT:"$HOST_ISOPROXY" &
socat UNIX-LISTEN:"$SOCKET_DIR/devpi.sock",reuseaddr,fork,mode=666 TCP4:127.0.0.1:3141 &
BRIDGE_PIDS=$!
trap "kill $BRIDGE_PIDS; exit" SIGINT SIGTERM
sleep 0.5

# --- 2. The Clean Launch ---
echo "🚀 Papercage: Starting $BINARY_CELL..."

# NOTE: No --uid 0, no --cap-add. Just unprivileged namespaces.
sudo -u "$AGENT_USER" bwrap \
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
	--bind "$WORKSPACE" "$WORKSPACE" \
	--ro-bind /opt/ai-bin /opt/ai-bin \
	--chdir "$WORKSPACE" \
	bash -c "
# 1. Turn on lo and hide the harmless error
        /usr/sbin/ip link set lo up 2>/dev/null || true

        # 2. Start Inner Bridges
        socat TCP4-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:$SOCKET_DIR/isoproxy.sock &
        socat TCP4-LISTEN:3141,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:$SOCKET_DIR/devpi.sock &

				# 3. SET PROXY ENV VARS (Essential for Claude)
        export ANTHROPIC_AUTH_TOKEN="secretkey"
				export ANTHROPIC_BASE_URL="http://127.0.0.1:8080"
				export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC='1'
				export PIP_INDEX_URL="http://127.0.0.1:3141/root/pypi/+simple/"
				export PIP_TRUSTED_HOST="127.0.0.1"

        # 3. Corrected Identity Display
        echo \"--- Papercage Active ---\"

        # 4. Start Claude
        socat UNIX-LISTEN:$SOCKET_DIR/console.sock,reuseaddr,mode=666 \
              EXEC:\"$BINARY_CELL --dangerously-skip-permissions\",pty,stderr
    "
