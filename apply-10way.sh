#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$APP" ]]; then
  echo "Missing $APP"
  exit 1
fi

if [[ ! -f "$CFG" ]]; then
  echo "Missing $CFG"
  exit 1
fi

cp "$APP" "$APP.before-10way-$STAMP"
cp "$CFG" "$CFG.before-10way-$STAMP"

install -m 0755 "$(dirname "$0")/m3-radial" "$APP"

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg.setdefault("scroll_radius_px", 205)
cfg.setdefault("scroll_slow_interval_ms", 115)
cfg.setdefault("scroll_fast_interval_ms", 28)

actions = cfg.setdefault("actions", {})
actions.setdefault("scroll_up", {
    "label": "Scroll Up",
    "icon": "⇈",
    "type": "scroll",
    "value": "up"
})
actions.setdefault("scroll_down", {
    "label": "Scroll Down",
    "icon": "⇊",
    "type": "scroll",
    "value": "down"
})

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated:", p)
PY

systemctl --user restart m3-radial

echo
echo "10-way scroll build installed."
echo "Backups:"
echo "  $APP.before-10way-$STAMP"
echo "  $CFG.before-10way-$STAMP"
echo
echo "Expected layout:"
echo "  Scroll Up is outside the normal Up slot."
echo "  Scroll Down is outside the normal Down slot."
echo "  Hold M3 over either scroll slot to scroll continuously."
