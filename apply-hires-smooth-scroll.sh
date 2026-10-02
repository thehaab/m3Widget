#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

[[ -f "$APP" ]] || { echo "Missing $APP"; exit 1; }
[[ -f "$CFG" ]] || { echo "Missing $CFG"; exit 1; }

cp "$APP" "$APP.before-hires-scroll-$STAMP"
cp "$CFG" "$CFG.before-hires-scroll-$STAMP"

echo "Installing python3-evdev and enabling uinput..."
sudo apt-get update
sudo apt-get install -y python3-evdev acl
sudo modprobe uinput

UINPUT_NODE=""
for n in /dev/uinput /dev/input/uinput; do
    if [[ -e "$n" ]]; then
        UINPUT_NODE="$n"
        break
    fi
done

if [[ -z "$UINPUT_NODE" ]]; then
    echo "Could not find /dev/uinput after modprobe."
    exit 2
fi

sudo setfacl -m "u:$USER:rw" "$UINPUT_NODE"
echo "uinput node: $UINPUT_NODE"

python3 - <<'PY'
from pathlib import Path
import py_compile, sys

p = Path.home() / ".local/bin/m3-radial"
s = p.read_text()

# Optional evdev import.
if "from evdev import UInput, ecodes" not in s:
    pos = s.find("from Xlib.ext import")
    if pos == -1:
        raise SystemExit("Could not find Xlib import block.")
    line_end = s.find("\n", pos)
    add = """
try:
    from evdev import UInput, ecodes
except Exception:
    UInput = None
    ecodes = None
"""
    s = s[:line_end+1] + add + s[line_end+1:]

# High-resolution virtual wheel helper.
marker = "\n\nclass RadialApp:"
if marker not in s:
    raise SystemExit("Could not find RadialApp.")

if "class HighResWheel:" not in s:
    helper = """
class HighResWheel:
    # Linux uinput high-resolution vertical wheel.
    # 120 REL_WHEEL_HI_RES units = one traditional wheel detent.

    def __init__(self):
        self.ui = None
        self.ok = False
        self.hi_code = None

        if UInput is None or ecodes is None:
            print("Smooth scroll unavailable; X11 fallback: python-evdev missing", flush=True)
            return

        self.hi_code = getattr(ecodes, "REL_WHEEL_HI_RES", 11)

        try:
            self.ui = UInput(
                {ecodes.EV_REL: [ecodes.REL_WHEEL, self.hi_code]},
                name="m3Widget High Resolution Wheel",
                bustype=0x03,
                vendor=0x1209,
                product=0x0001,
                version=1,
            )
            self.ok = True
            print("Smooth scroll backend: uinput REL_WHEEL_HI_RES", flush=True)
        except Exception as e:
            print(f"Smooth scroll unavailable; X11 fallback: {e}", flush=True)

    def emit(self, direction, units):
        if not self.ok or self.ui is None:
            return False

        units = int(units)
        if units <= 0:
            return True

        value = units if direction == "up" else -units

        try:
            self.ui.write(ecodes.EV_REL, self.hi_code, value)
            self.ui.syn()
            return True
        except Exception as e:
            print(f"High-res wheel emit failed; disabling: {e}", flush=True)
            try:
                self.ui.close()
            except Exception:
                pass
            self.ui = None
            self.ok = False
            return False

"""
    s = s.replace(marker, "\n\n" + helper + marker, 1)

# Instantiate.
needle = "        self.emitter = XEmitter()\n"
if needle not in s:
    raise SystemExit("Could not find XEmitter initialization.")

if "self.hires_wheel = HighResWheel()" not in s:
    s = s.replace(
        needle,
        needle +
        "        self.hires_wheel = HighResWheel()\n"
        "        self._hires_last_emit = 0.0\n"
        "        self._hires_unit_accumulator = 0.0\n",
        1,
    )

# Find _maybe_live_scroll and its existing discrete emission tail.
start = s.find("    def _maybe_live_scroll(")
end = s.find("\n    def ", start + 8)

if start == -1 or end == -1:
    raise SystemExit("Could not locate _maybe_live_scroll.")

block = s[start:end]
acc_start = block.find("        self._scroll_accumulator +=")
if acc_start == -1:
    raise SystemExit("Could not find scroll accumulator.")

mouse_pos = block.find("            self.emitter.mouse(", acc_start)
if mouse_pos == -1:
    raise SystemExit("Could not find X11 wheel emission.")

# Find end of self.emitter.mouse(...) expression.
sub = block[mouse_pos:]
depth = 0
seen = False
end_rel = None
for i, ch in enumerate(sub):
    if ch == "(":
        depth += 1
        seen = True
    elif ch == ")":
        depth -= 1
        if seen and depth == 0:
            nl = sub.find("\n", i)
            end_rel = len(sub) if nl == -1 else nl + 1
            break

if end_rel is None:
    raise SystemExit("Could not parse X11 wheel emission.")

emit_end = mouse_pos + end_rel

replacement = """        # High-resolution backend. Keep all existing proportional
        # speed math above; only replace how the resulting rate is emitted.
        if getattr(self, "hires_wheel", None) and self.hires_wheel.ok:
            hires_hz = float(self.cfg.get("scroll_hires_rate_hz", 60.0))
            hires_hz = max(30.0, min(120.0, hires_hz))

            # Existing 'rate' is traditional wheel detents per second.
            # Convert to high-resolution units (120 units = 1 detent).
            units_per_second = rate * 120.0
            self._hires_unit_accumulator += units_per_second * dt

            interval = 1.0 / hires_hz

            if (
                self._hires_last_emit == 0.0
                or now - self._hires_last_emit >= interval
            ):
                units = int(self._hires_unit_accumulator)

                if units > 0:
                    max_units = int(
                        self.cfg.get(
                            "scroll_hires_max_units_per_frame",
                            120,
                        )
                    )
                    units = min(max_units, units)

                    if self.hires_wheel.emit(direction, units):
                        self._hires_unit_accumulator -= units
                        self._hires_last_emit = now
                        return

                self._hires_last_emit = now
                return

        # Existing X11 discrete-wheel fallback.
        self._scroll_accumulator += (
            rate * dt
        )

        ticks = int(
            self._scroll_accumulator
        )

        if ticks <= 0:
            return

        ticks = min(
            ticks,
            int(
                self.cfg.get(
                    "scroll_max_burst_ticks",
                    6,
                )
            ),
        )

        self._scroll_accumulator -= ticks

        button = (
            "wheel_up"
            if direction == "up"
            else "wheel_down"
        )

        for _ in range(ticks):
            self.emitter.mouse(button)
"""

block = block[:acc_start] + replacement + block[emit_end:]
s = s[:start] + block + s[end:]

tmp = Path("/tmp/m3-radial-hires-test.py")
tmp.write_text(s)

try:
    py_compile.compile(str(tmp), doraise=True)
except Exception as e:
    print("Patched launcher failed syntax check:", e)
    print("Live launcher left unchanged.")
    sys.exit(3)

p.write_text(s)
print("High-resolution scroll backend patched into:", p)
PY

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg["scroll_reading_rate_hz"] = 1.0
cfg["scroll_hires_rate_hz"] = 60.0
cfg["scroll_hires_max_units_per_frame"] = 120

p.write_text(json.dumps(cfg, indent=2) + "\n")

print("Configured:")
print("  scroll_reading_rate_hz =", cfg["scroll_reading_rate_hz"])
print("  scroll_hires_rate_hz =", cfg["scroll_hires_rate_hz"])
PY

systemctl --user restart m3-radial

echo
echo "High-resolution smooth-scroll prototype installed."
echo
echo "Check backend:"
echo "  journalctl --user -u m3-radial -n 30 --no-pager"
echo
echo "Expected:"
echo "  Smooth scroll backend: uinput REL_WHEEL_HI_RES"
