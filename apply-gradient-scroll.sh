#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

cp "$APP" "$APP.before-gradient-scroll-$STAMP"
cp "$CFG" "$CFG.before-gradient-scroll-$STAMP"

install -m 0755 "$(dirname "$0")/m3-radial" "$APP"

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

# Remove the old two-interval controls if present.
cfg.pop("scroll_slow_interval_ms", None)
cfg.pop("scroll_fast_interval_ms", None)

# Continuous scroll velocity controls.
cfg.setdefault("scroll_speed_start_px", 160)
cfg.setdefault("scroll_speed_span_px", 170)
cfg.setdefault("scroll_min_rate_hz", 1.5)
cfg.setdefault("scroll_max_rate_hz", 38.0)
cfg.setdefault("scroll_speed_curve", 1.35)

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated gradient scroll config:", p)
PY

systemctl --user restart m3-radial

echo
echo "Gradient scroll installed."
echo "Near the scroll sector: very slow/fine."
echo "Push farther outward: continuously faster."
