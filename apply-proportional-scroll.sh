#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "Installing AT-SPI Python bindings..."
sudo apt update
sudo apt install -y python3-pyatspi

cp "$APP" "$APP.before-proportional-scroll-$STAMP"
cp "$CFG" "$CFG.before-proportional-scroll-$STAMP"

install -m 0755 "$(dirname "$0")/m3-radial" "$APP"

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg["scroll_backend"] = "auto"
cfg.setdefault("proportional_full_traversal_seconds", 1.5)
cfg.setdefault("proportional_min_fraction_per_second", 0.0025)
cfg.setdefault("atspi_discovery_max_nodes", 2500)

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated:", p)
PY

systemctl --user restart m3-radial

echo
echo "Installed proportional-scroll test."
echo
echo "Watch backend selection with:"
echo "  journalctl --user -u m3-radial -f"
echo
echo "When supported you should see:"
echo "  Scroll backend: AT-SPI proportional"
echo
echo "Otherwise:"
echo "  Scroll backend: wheel fallback"
