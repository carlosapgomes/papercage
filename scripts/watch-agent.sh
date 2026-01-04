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
