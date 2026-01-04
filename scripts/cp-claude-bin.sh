#!/bin/bash
# Claude Code standalone binary strategy
# Install as a normal user via: curl -fsSL https://claude.ai/install | sh
SOURCE_BIN="$HOME/.local/bin/claude"
TARGET_BIN="/opt/ai-bin/claude"

if [[ -f "$SOURCE_BIN" ]]; then
  sudo cp "$SOURCE_BIN" "$TARGET_BIN"
  sudo chmod +x "$TARGET_BIN"
  sudo chown root:root "$TARGET_BIN"
  echo "[*] Claude binary copied to $TARGET_BIN"
  echo "[!] Reminder: Run 'claude update' in your userland and rerun this script to update the cage."
else
  echo "[E] Source binary not found at $SOURCE_BIN"
fi
