#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

cp "$APP" "$APP.before-reading-speed-$STAMP"
cp "$CFG" "$CFG.before-reading-speed-$STAMP"

python3 - <<'PY'
from pathlib import Path
import py_compile, sys

p = Path.home() / ".local/bin/m3-radial"
s = p.read_text()

old = '''        start_radius = float(
            self.cfg.get(
                "scroll_speed_start_px",
                menu_radius + 28,
            )
        )
'''

new = '''        start_radius = float(
            self.cfg.get(
                "scroll_speed_start_px",
                self.cfg.get("scroll_radius_px", menu_radius + 46),
            )
        )
'''

if old not in s:
    print("Could not find scroll start-radius block.")
    print("No changes written.")
    sys.exit(2)

s = s.replace(old, new, 1)

old2 = '''        base_rate = (
            min_rate
            + (
                max_rate
                - min_rate
            ) * shaped
        )

        rate = (
            base_rate
            * self._scroll_range_scale
        )
'''

new2 = '''        # Reading-speed floor is intentionally NOT multiplied by
        # document-length scale. This keeps the scroll icon itself slow
        # and predictable even on extremely long pages.
        reading_rate = float(
            self.cfg.get(
                "scroll_reading_rate_hz",
                min_rate,
            )
        )

        scaled_max_rate = (
            max_rate
            * self._scroll_range_scale
        )

        rate = (
            reading_rate
            + (
                scaled_max_rate
                - reading_rate
            ) * shaped
        )
'''

if old2 not in s:
    print("Could not find wheel-rate scaling block.")
    print("No changes written.")
    sys.exit(3)

s = s.replace(old2, new2, 1)

tmp = Path("/tmp/m3-radial-reading-speed-test.py")
tmp.write_text(s)
py_compile.compile(str(tmp), doraise=True)

p.write_text(s)
print("Patched reading-speed scroll behavior:", p)
PY

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg["scroll_speed_start_px"] = int(cfg.get("scroll_radius_px", 138))
cfg["scroll_reading_rate_hz"] = 3.0
cfg["scroll_speed_span_px"] = 150

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated:", p)
PY

systemctl --user restart m3-radial

echo
echo "Reading-speed scroll installed."
echo
echo "Behavior:"
echo "  pointer on scroll icon  -> slow steady reading scroll"
echo "  move outward            -> progressively faster"
echo "  page-length scaling     -> affects fast end, not slow floor"
echo
echo "Tune reading speed with:"
echo '  "scroll_reading_rate_hz": 3.0'
