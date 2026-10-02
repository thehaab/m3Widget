#!/usr/bin/env bash
set -euo pipefail

PURGE=false
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=true
fi

systemctl --user disable --now m3-radial.service 2>/dev/null || true

rm -f "$HOME/.local/bin/m3-radial"
rm -f "$HOME/.local/bin/m3-radial-settings"
rm -f "$HOME/.config/systemd/user/m3-radial.service"
rm -f "$HOME/.local/share/applications/m3-radial-settings.desktop"

if [[ -f /etc/keyd/m3-radial.conf ]]; then
  sudo rm -f /etc/keyd/m3-radial.conf
  sudo systemctl restart keyd || true
fi

systemctl --user daemon-reload

if $PURGE; then
  rm -rf "$HOME/.config/m3-radial"
  echo "Removed m3Widget and user configuration."
else
  echo "Removed m3Widget."
  echo "Preserved configuration: $HOME/.config/m3-radial"
  echo "Use '$0 --purge' to remove it too."
fi
