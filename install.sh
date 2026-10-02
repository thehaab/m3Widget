#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 KEYD_DEVICE_ID"
  echo
  echo "Find the mouse interface that reports middlemouse with:"
  echo "  sudo keyd.rvaiya monitor"
  echo "or:"
  echo "  sudo keyd monitor"
  exit 2
fi

DEVICE_ID="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
  echo "Warning: m3Widget currently targets X11. Current session: ${XDG_SESSION_TYPE:-unknown}"
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "Installing Python dependencies..."
  sudo apt-get update
  sudo apt-get install -y python3-xlib python3-tk
else
  echo "apt-get not found. Ensure Python 3, tkinter, and python-xlib are installed."
fi

if command -v keyd.rvaiya >/dev/null 2>&1; then
  KEYD_BIN="keyd.rvaiya"
elif command -v keyd >/dev/null 2>&1; then
  KEYD_BIN="keyd"
else
  echo "Error: keyd is not installed. Install keyd first, then rerun this script."
  exit 1
fi

mkdir -p \
  "$HOME/.local/bin" \
  "$HOME/.config/m3-radial" \
  "$HOME/.config/systemd/user" \
  "$HOME/.local/share/applications"

install -m 0755 "$ROOT_DIR/src/m3-radial.py" "$HOME/.local/bin/m3-radial"
install -m 0755 "$ROOT_DIR/src/m3-radial-settings" "$HOME/.local/bin/m3-radial-settings"
install -m 0644 "$ROOT_DIR/systemd/m3-radial.service" "$HOME/.config/systemd/user/m3-radial.service"

if [[ ! -e "$HOME/.config/m3-radial/config.json" ]]; then
  install -m 0644 "$ROOT_DIR/config/config.example.json" "$HOME/.config/m3-radial/config.json"
else
  echo "Keeping existing config: $HOME/.config/m3-radial/config.json"
fi

sudo mkdir -p /etc/keyd
sudo tee /etc/keyd/m3-radial.conf >/dev/null <<EOF
[ids]
$DEVICE_ID

[main]
middlemouse = f24
EOF

cat > "$HOME/.local/share/applications/m3-radial-settings.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=M3 Radial Settings
Comment=Configure m3Widget radial mouse gestures
Exec=$HOME/.local/bin/m3-radial-settings
Terminal=false
Categories=Settings;Utility;
EOF
chmod +x "$HOME/.local/share/applications/m3-radial-settings.desktop"

sudo systemctl restart keyd
systemctl --user daemon-reload
systemctl --user enable --now m3-radial.service

echo
echo "m3Widget installed."
echo "Settings: $HOME/.local/bin/m3-radial-settings"
echo "Config:   $HOME/.config/m3-radial/config.json"
echo "Logs:     journalctl --user -u m3-radial -f"
echo "keyd:     $KEYD_BIN"
