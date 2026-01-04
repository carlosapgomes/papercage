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
