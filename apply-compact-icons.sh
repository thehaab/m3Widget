#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
SETTINGS="$HOME/.local/bin/m3-radial-settings"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

for f in "$APP" "$SETTINGS" "$CFG"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing: $f"
    exit 1
  fi
done

cp "$APP" "$APP.before-compact-icons-$STAMP"
cp "$SETTINGS" "$SETTINGS.before-compact-icons-$STAMP"
cp "$CFG" "$CFG.before-compact-icons-$STAMP"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path.home() / ".local/bin/m3-radial"
s = p.read_text()
orig = s

# 1) Make action display text honor ui_mode.
#    This only changes visible text, not gesture/action logic.
patterns = [
    (
        r'(?P<i>\s*)label\s*=\s*action\.get\("label",\s*""\)',
        lambda m:
            f'{m.group("i")}label = action.get("label", "")\n'
            f'{m.group("i")}icon = action.get("icon", "")\n'
            f'{m.group("i")}mode = self.cfg.get("ui_mode", "icons")\n'
            f'{m.group("i")}display_text = icon if mode == "icons" else '
            f'(f"{{icon}}  {{label}}" if mode == "icons+labels" else label)'
    ),
]

for pat, repl in patterns:
    if "display_text =" not in s:
        s, n = re.subn(pat, repl, s, count=1)
        if n == 0:
            print("Could not find action label block. Launcher left untouched.")
            sys.exit(2)

# Replace the first option-window text assignment(s), conservatively.
replacements = [
    ("text=label,", "text=display_text,"),
    ("text = label,", "text = display_text,"),
]
changed_text = False
for a, b in replacements:
    if a in s:
        s = s.replace(a, b)
        changed_text = True

if not changed_text and "display_text" not in s:
    print("Could not locate option text assignment. Launcher left untouched.")
    sys.exit(3)

# 2) Compact fixed pill dimensions where the known defaults appear.
#    Preserve non-icon mode at old sizes.
subs = [
    (
        r'pill_w\s*=\s*144',
        'pill_w = int(self.cfg.get("icon_slot_size_px", 42)) if self.cfg.get("ui_mode", "icons") == "icons" else 144'
    ),
    (
        r'pill_h\s*=\s*50',
        'pill_h = int(self.cfg.get("icon_slot_size_px", 42)) if self.cfg.get("ui_mode", "icons") == "icons" else 50'
    ),
    (
        r'pill_width\s*=\s*144',
        'pill_width = int(self.cfg.get("icon_slot_size_px", 42)) if self.cfg.get("ui_mode", "icons") == "icons" else 144'
    ),
    (
        r'pill_height\s*=\s*50',
        'pill_height = int(self.cfg.get("icon_slot_size_px", 42)) if self.cfg.get("ui_mode", "icons") == "icons" else 50'
    ),
]
for pat, rep in subs:
    s = re.sub(pat, rep, s)

# 3) If a width is derived from label length, force square size in icon mode.
s = re.sub(
    r'(?P<i>\s*)(?P<v>width|w)\s*=\s*max\((?P<body>[^\n]+)\)',
    lambda m:
        f'{m.group("i")}{m.group("v")} = int(self.cfg.get("icon_slot_size_px", 42)) '
        f'if self.cfg.get("ui_mode", "icons") == "icons" else max({m.group("body")})',
    s,
    count=1
)

# 4) Keep existing scroll engine untouched. Only geometry defaults change via config.
#    Do NOT modify _maybe_live_scroll or AT-SPI code.

# Syntax check before replacing file.
tmp = Path("/tmp/m3-radial.compact-test")
tmp.write_text(s)

import py_compile
try:
    py_compile.compile(str(tmp), doraise=True)
except Exception as e:
    print("Patched launcher did not compile:", e)
    print("Original launcher left untouched.")
    sys.exit(4)

p.write_text(s)
print("Launcher renderer patched:", p)
PY

# Replace settings app with a compact preview/editor.
cat > "$SETTINGS" <<'PY'
#!/usr/bin/env python3
import json
import math
import subprocess
import tkinter as tk
from tkinter import ttk
from pathlib import Path

CFG = Path.home() / ".config/m3-radial/config.json"

ANGLES = {
    "up": -90,
    "up_right": -45,
    "right": 0,
    "down_right": 45,
    "down": 90,
    "down_left": 135,
    "left": 180,
    "up_left": 225,
}

FALLBACK_ICONS = {
    "up": "⧉",
    "up_right": "▣",
    "right": "→",
    "down_right": "↵",
    "down": "⌘",
    "down_left": "⌖",
    "left": "←",
    "up_left": "↶",
    "scroll_up": "⇈",
    "scroll_down": "⇊",
}

class SettingsApp:
    def __init__(self, root):
        self.root = root
        self.root.title("M3 Radial Settings — Compact")
        self.cfg = json.loads(CFG.read_text())

        outer = ttk.Frame(root, padding=12)
        outer.pack(fill="both", expand=True)

        left = ttk.Frame(outer)
        left.grid(row=0, column=0, sticky="nsew", padx=(0, 14))
        right = ttk.Frame(outer)
        right.grid(row=0, column=1, sticky="ns")

        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(0, weight=1)

        ttk.Label(
            left,
            text="Compact radial preview",
            font=("TkDefaultFont", 11, "bold"),
        ).pack(anchor="w")

        self.canvas = tk.Canvas(
            left,
            width=420,
            height=420,
            bg="#111214",
            highlightthickness=0,
        )
        self.canvas.pack(fill="both", expand=True, pady=(8, 0))

        self.mode = tk.StringVar(value=self.cfg.get("ui_mode", "icons"))
        self.slot = tk.IntVar(value=int(self.cfg.get("icon_slot_size_px", 42)))
        self.font = tk.IntVar(value=int(self.cfg.get("icon_font_size", 17)))
        self.radius = tk.IntVar(value=int(self.cfg.get("menu_radius_px", 96)))
        self.center = tk.IntVar(value=int(self.cfg.get("center_size_px", 34)))
        self.scroll_radius = tk.IntVar(value=int(self.cfg.get("scroll_radius_px", 145)))

        ttk.Label(right, text="Display").pack(anchor="w")
        cb = ttk.Combobox(
            right,
            textvariable=self.mode,
            values=("icons", "icons+labels", "labels"),
            state="readonly",
            width=18,
        )
        cb.pack(fill="x")
        cb.bind("<<ComboboxSelected>>", lambda _e: self.redraw())

        self.add_scale(right, "Icon slot size", self.slot, 30, 64)
        self.add_scale(right, "Icon font size", self.font, 12, 28)
        self.add_scale(right, "Menu radius", self.radius, 70, 145)
        self.add_scale(right, "Center size", self.center, 24, 50)
        self.add_scale(right, "Scroll radius", self.scroll_radius, 110, 210)

        ttk.Separator(right).pack(fill="x", pady=12)

        ttk.Button(
            right,
            text="Save + Restart Radial",
            command=self.save,
        ).pack(fill="x", pady=(0, 6))

        ttk.Button(
            right,
            text="Reload from Disk",
            command=self.reload,
        ).pack(fill="x")

        self.canvas.bind("<Configure>", lambda _e: self.redraw())
        self.redraw()

    def add_scale(self, parent, label, var, lo, hi):
        ttk.Label(parent, text=label).pack(anchor="w", pady=(10, 0))
        ttk.Scale(
            parent,
            from_=lo,
            to=hi,
            variable=var,
            orient="horizontal",
            command=lambda _v: self.redraw(),
        ).pack(fill="x")

    def text_for(self, key):
        a = self.cfg.get("actions", {}).get(key, {})
        icon = a.get("icon", FALLBACK_ICONS.get(key, "•"))
        label = a.get("label", key.replace("_", " ").title())
        mode = self.mode.get()

        if mode == "icons":
            return icon
        if mode == "labels":
            return label
        return f"{icon}  {label}"

    def redraw(self):
        c = self.canvas
        c.delete("all")

        w = max(c.winfo_width(), 420)
        h = max(c.winfo_height(), 420)
        cx, cy = w / 2, h / 2

        size = int(self.slot.get())
        radius = int(self.radius.get())
        font_size = int(self.font.get())

        for key, deg in ANGLES.items():
            a = math.radians(deg)
            x = cx + math.cos(a) * radius
            y = cy + math.sin(a) * radius

            c.create_oval(
                x - size/2,
                y - size/2,
                x + size/2,
                y + size/2,
                fill="#202226",
                outline="#5e636b",
                width=1,
            )
            c.create_text(
                x,
                y,
                text=self.text_for(key),
                fill="white",
                font=("TkDefaultFont", font_size, "bold"),
            )

        scroll_r = int(self.scroll_radius.get())

        for key, sign in (("scroll_up", -1), ("scroll_down", 1)):
            x = cx
            y = cy + sign * scroll_r

            c.create_oval(
                x - size/2,
                y - size/2,
                x + size/2,
                y + size/2,
                fill="#202226",
                outline="#5e636b",
                width=1,
            )
            c.create_text(
                x,
                y,
                text=self.text_for(key),
                fill="white",
                font=("TkDefaultFont", font_size, "bold"),
            )

        cs = int(self.center.get())
        c.create_oval(
            cx - cs/2,
            cy - cs/2,
            cx + cs/2,
            cy + cs/2,
            fill="#2b2d31",
            outline="#b7bbc1",
            width=1,
        )

    def save(self):
        self.cfg["ui_mode"] = self.mode.get()
        self.cfg["icon_slot_size_px"] = int(self.slot.get())
        self.cfg["icon_font_size"] = int(self.font.get())
        self.cfg["menu_radius_px"] = int(self.radius.get())
        self.cfg["center_size_px"] = int(self.center.get())
        self.cfg["scroll_radius_px"] = int(self.scroll_radius.get())

        CFG.write_text(json.dumps(self.cfg, indent=2) + "\n")
        subprocess.run(["systemctl", "--user", "restart", "m3-radial"])
        self.redraw()

    def reload(self):
        self.cfg = json.loads(CFG.read_text())
        self.mode.set(self.cfg.get("ui_mode", "icons"))
        self.slot.set(int(self.cfg.get("icon_slot_size_px", 42)))
        self.font.set(int(self.cfg.get("icon_font_size", 17)))
        self.radius.set(int(self.cfg.get("menu_radius_px", 96)))
        self.center.set(int(self.cfg.get("center_size_px", 34)))
        self.scroll_radius.set(int(self.cfg.get("scroll_radius_px", 145)))
        self.redraw()

root = tk.Tk()
SettingsApp(root)
root.mainloop()
PY

chmod +x "$SETTINGS"

# Apply compact defaults without touching existing action behavior or scroll tuning.
python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg["ui_mode"] = "icons"
cfg["icon_slot_size_px"] = 42
cfg["icon_font_size"] = 17
cfg["menu_radius_px"] = 96
cfg["center_size_px"] = 34
cfg["scroll_radius_px"] = 145

fallback = {
    "up": ("⧉", "Copy"),
    "up_right": ("▣", "Paste"),
    "right": ("→", "Forward"),
    "down_right": ("↵", "Enter"),
    "down": ("⌘", "Terminal"),
    "down_left": ("⌖", "Screenshot"),
    "left": ("←", "Back"),
    "up_left": ("↶", "Undo"),
    "scroll_up": ("⇈", "Scroll Up"),
    "scroll_down": ("⇊", "Scroll Down"),
}

actions = cfg.setdefault("actions", {})

for key, (icon, label) in fallback.items():
    action = actions.setdefault(key, {})
    action.setdefault("icon", icon)
    action.setdefault("label", label)

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated:", p)
PY

systemctl --user restart m3-radial

echo
echo "Compact icon mode installed."
echo
echo "Open settings with:"
echo "  ~/.local/bin/m3-radial-settings"
echo
echo "Backups:"
echo "  $APP.before-compact-icons-$STAMP"
echo "  $SETTINGS.before-compact-icons-$STAMP"
echo "  $CFG.before-compact-icons-$STAMP"
