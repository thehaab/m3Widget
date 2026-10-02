#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
SETTINGS="$HOME/.local/bin/m3-radial-settings"
CFG="$HOME/.config/m3-radial/config.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

for f in "$APP" "$SETTINGS" "$CFG"; do
    [[ -f "$f" ]] || { echo "Missing: $f"; exit 1; }
done

cp "$APP" "$APP.before-compact-icons-v2-$STAMP"
cp "$SETTINGS" "$SETTINGS.before-compact-icons-v2-$STAMP"
cp "$CFG" "$CFG.before-compact-icons-v2-$STAMP"

python3 - <<'PY'
from pathlib import Path
import py_compile, sys

p = Path.home() / ".local/bin/m3-radial"
s = p.read_text()

old_text = '''            icon = action.get("icon", "")
            label = action.get("label", direction)
            text = f"{icon}  {label}" if icon else label
'''

new_text = '''            icon = action.get("icon", "")
            label = action.get("label", direction)

            mode = self.cfg.get("ui_mode", "icons")
            if mode == "icons":
                text = icon or label[:1]
            elif mode == "labels":
                text = label
            else:
                text = f"{icon}  {label}" if icon else label
'''

count = s.count(old_text)
if count < 1:
    print("Could not find the known m3Widget slot renderer.")
    print("No launcher changes written.")
    sys.exit(2)

s = s.replace(old_text, new_text)

old_label = '''                font=("Sans", 10, "bold"),
                padx=14,
                pady=8,
                bd=0,
'''

new_label = '''                font=(
                    "Sans",
                    int(self.cfg.get("icon_font_size", 17))
                    if self.cfg.get("ui_mode", "icons") == "icons"
                    else 10,
                    "bold",
                ),
                padx=(
                    int(self.cfg.get("icon_pad_x_px", 8))
                    if self.cfg.get("ui_mode", "icons") == "icons"
                    else 14
                ),
                pady=(
                    int(self.cfg.get("icon_pad_y_px", 6))
                    if self.cfg.get("ui_mode", "icons") == "icons"
                    else 8
                ),
                bd=0,
'''

if old_label not in s:
    print("Found renderer, but not known label-style block.")
    print("No launcher changes written.")
    sys.exit(3)

s = s.replace(old_label, new_label)

tmp = Path("/tmp/m3-radial-compact-v2-test.py")
tmp.write_text(s)

try:
    py_compile.compile(str(tmp), doraise=True)
except Exception as e:
    print("Patched launcher failed syntax check:", e)
    print("No launcher changes written.")
    sys.exit(4)

p.write_text(s)
print(f"Patched launcher renderer ({count} renderer block(s)).")
PY

python3 - <<'PY'
from pathlib import Path
import json

p = Path.home() / ".config/m3-radial/config.json"
cfg = json.loads(p.read_text())

cfg["ui_mode"] = "icons"
cfg["icon_font_size"] = 17
cfg["icon_pad_x_px"] = 8
cfg["icon_pad_y_px"] = 6
cfg["menu_radius_px"] = 92
cfg["center_size_px"] = 32
cfg["scroll_radius_px"] = 138

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
    a = actions.setdefault(key, {})
    a.setdefault("icon", icon)
    a.setdefault("label", label)

p.write_text(json.dumps(cfg, indent=2) + "\n")
print("Updated compact UI config:", p)
PY

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

FALLBACK = {
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

class App:
    def __init__(self, root):
        self.root = root
        root.title("M3 Radial Settings — Compact UI")
        self.load_cfg()

        outer = ttk.Frame(root, padding=12)
        outer.pack(fill="both", expand=True)

        left = ttk.Frame(outer)
        left.grid(row=0, column=0, sticky="nsew", padx=(0,16))
        right = ttk.Frame(outer)
        right.grid(row=0, column=1, sticky="ns")

        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(0, weight=1)

        ttk.Label(
            left,
            text="Compact radial preview",
            font=("TkDefaultFont", 11, "bold")
        ).pack(anchor="w")

        self.canvas = tk.Canvas(
            left,
            width=390,
            height=390,
            bg="#111214",
            highlightthickness=0
        )
        self.canvas.pack(fill="both", expand=True, pady=(8,0))

        self.mode = tk.StringVar(value=self.cfg.get("ui_mode","icons"))
        self.font_size = tk.IntVar(value=int(self.cfg.get("icon_font_size",17)))
        self.radius = tk.IntVar(value=int(self.cfg.get("menu_radius_px",92)))
        self.center = tk.IntVar(value=int(self.cfg.get("center_size_px",32)))
        self.pad_x = tk.IntVar(value=int(self.cfg.get("icon_pad_x_px",8)))
        self.pad_y = tk.IntVar(value=int(self.cfg.get("icon_pad_y_px",6)))
        self.scroll_radius = tk.IntVar(value=int(self.cfg.get("scroll_radius_px",138)))

        ttk.Label(right, text="Display mode").pack(anchor="w")
        mode = ttk.Combobox(
            right,
            textvariable=self.mode,
            values=("icons","icons+labels","labels"),
            state="readonly",
            width=18
        )
        mode.pack(fill="x")
        mode.bind("<<ComboboxSelected>>", lambda _e:self.redraw())

        self.scale(right, "Icon size", self.font_size, 11, 26)
        self.scale(right, "Horizontal padding", self.pad_x, 2, 18)
        self.scale(right, "Vertical padding", self.pad_y, 2, 14)
        self.scale(right, "Menu radius", self.radius, 65, 145)
        self.scale(right, "Center size", self.center, 22, 50)
        self.scale(right, "Scroll radius", self.scroll_radius, 105, 210)

        ttk.Separator(right).pack(fill="x", pady=12)

        ttk.Button(
            right,
            text="Save + Restart Radial",
            command=self.save
        ).pack(fill="x", pady=(0,5))

        ttk.Button(
            right,
            text="Reload from Disk",
            command=self.reload
        ).pack(fill="x")

        ttk.Label(
            right,
            text="Visual geometry only.\nAction mappings and scroll tuning are preserved.",
            foreground="#666"
        ).pack(anchor="w", pady=(12,0))

        self.canvas.bind("<Configure>", lambda _e:self.redraw())
        self.redraw()

    def load_cfg(self):
        self.cfg = json.loads(CFG.read_text())

    def scale(self, parent, title, var, lo, hi):
        ttk.Label(parent, text=title).pack(anchor="w", pady=(9,0))
        ttk.Scale(
            parent,
            from_=lo,
            to=hi,
            variable=var,
            orient="horizontal",
            command=lambda _v:self.redraw()
        ).pack(fill="x")

    def display_text(self, key):
        action = self.cfg.get("actions",{}).get(key,{})
        icon = action.get("icon", FALLBACK.get(key,"•"))
        label = action.get("label", key.replace("_"," ").title())

        if self.mode.get() == "icons":
            return icon
        if self.mode.get() == "labels":
            return label
        return f"{icon}  {label}"

    def redraw(self):
        c = self.canvas
        c.delete("all")

        w = max(c.winfo_width(),390)
        h = max(c.winfo_height(),390)
        cx, cy = w/2, h/2

        r = int(self.radius.get())
        fs = int(self.font_size.get())
        box_w = max(28, fs + int(self.pad_x.get())*2 + 8)
        box_h = max(26, fs + int(self.pad_y.get())*2 + 6)

        for key, deg in ANGLES.items():
            a = math.radians(deg)
            x = cx + math.cos(a)*r
            y = cy + math.sin(a)*r

            c.create_rectangle(
                x-box_w/2, y-box_h/2,
                x+box_w/2, y+box_h/2,
                fill="#1b1d21",
                outline="#555b63"
            )
            c.create_text(
                x, y,
                text=self.display_text(key),
                fill="#f1f2f4",
                font=("Sans", fs, "bold")
            )

        sr = int(self.scroll_radius.get())
        for key, sign in (("scroll_up",-1),("scroll_down",1)):
            y = cy + sign*sr
            c.create_rectangle(
                cx-box_w/2, y-box_h/2,
                cx+box_w/2, y+box_h/2,
                fill="#1b1d21",
                outline="#555b63"
            )
            c.create_text(
                cx, y,
                text=self.display_text(key),
                fill="#f1f2f4",
                font=("Sans", fs, "bold")
            )

        cs = int(self.center.get())
        c.create_oval(
            cx-cs/2, cy-cs/2,
            cx+cs/2, cy+cs/2,
            fill="#1c1e22",
            outline="#747982"
        )

    def save(self):
        self.cfg["ui_mode"] = self.mode.get()
        self.cfg["icon_font_size"] = int(self.font_size.get())
        self.cfg["icon_pad_x_px"] = int(self.pad_x.get())
        self.cfg["icon_pad_y_px"] = int(self.pad_y.get())
        self.cfg["menu_radius_px"] = int(self.radius.get())
        self.cfg["center_size_px"] = int(self.center.get())
        self.cfg["scroll_radius_px"] = int(self.scroll_radius.get())

        CFG.write_text(json.dumps(self.cfg,indent=2)+"\n")
        subprocess.run(["systemctl","--user","restart","m3-radial"])
        self.redraw()

    def reload(self):
        self.load_cfg()
        self.mode.set(self.cfg.get("ui_mode","icons"))
        self.font_size.set(int(self.cfg.get("icon_font_size",17)))
        self.radius.set(int(self.cfg.get("menu_radius_px",92)))
        self.center.set(int(self.cfg.get("center_size_px",32)))
        self.pad_x.set(int(self.cfg.get("icon_pad_x_px",8)))
        self.pad_y.set(int(self.cfg.get("icon_pad_y_px",6)))
        self.scroll_radius.set(int(self.cfg.get("scroll_radius_px",138)))
        self.redraw()

root = tk.Tk()
App(root)
root.mainloop()
PY

chmod +x "$SETTINGS"
systemctl --user restart m3-radial

echo
echo "Compact icon renderer installed."
echo "Open settings:"
echo "  ~/.local/bin/m3-radial-settings"
echo
echo "Backups:"
echo "  $APP.before-compact-icons-v2-$STAMP"
echo "  $SETTINGS.before-compact-icons-v2-$STAMP"
echo "  $CFG.before-compact-icons-v2-$STAMP"
