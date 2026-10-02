#!/usr/bin/env python3
import json
import math
import subprocess
import tkinter as tk
from pathlib import Path

from Xlib import X, XK, display
from Xlib.ext import xtest


CONFIG_PATH = Path.home() / ".config" / "m3-radial" / "config.json"

DIRECTIONS = [
    ("up", -90),
    ("up_right", -45),
    ("right", 0),
    ("down_right", 45),
    ("down", 90),
    ("down_left", 135),
    ("left", 180),
    ("up_left", -135),
]

DIRECTION_ORDER = [
    "right",
    "down_right",
    "down",
    "down_left",
    "left",
    "up_left",
    "up",
    "up_right",
]

KEY_ALIASES = {
    "ctrl": "Control_L",
    "control": "Control_L",
    "alt": "Alt_L",
    "shift": "Shift_L",
    "super": "Super_L",
    "meta": "Super_L",
    "enter": "Return",
    "return": "Return",
    "esc": "Escape",
    "escape": "Escape",
    "space": "space",
    "tab": "Tab",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "backspace": "BackSpace",
    "delete": "Delete",
    "print": "Print",
    "printscreen": "Print",
}

MOUSE_BUTTONS = {
    "left": 1,
    "middle": 2,
    "right": 3,
    "wheel_up": 4,
    "wheel_down": 5,
    "back": 8,
    "forward": 9,
}


def load_config():
    return json.loads(CONFIG_PATH.read_text())


class XEmitter:
    def __init__(self):
        self.disp = display.Display()

    def _keycode(self, name):
        xname = KEY_ALIASES.get(name.lower(), name)
        keysym = XK.string_to_keysym(xname)

        if not keysym and len(name) == 1:
            keysym = XK.string_to_keysym(name)

        if not keysym:
            raise ValueError(f"Unknown key: {name}")

        return self.disp.keysym_to_keycode(keysym)

    def keys(self, combo):
        parts = [p.strip() for p in combo.split("+") if p.strip()]
        codes = [self._keycode(p) for p in parts]

        for code in codes:
            xtest.fake_input(self.disp, X.KeyPress, code)

        for code in reversed(codes):
            xtest.fake_input(self.disp, X.KeyRelease, code)

        self.disp.sync()

    def mouse(self, button_name):
        button = MOUSE_BUTTONS[button_name]
        xtest.fake_input(self.disp, X.ButtonPress, button)
        xtest.fake_input(self.disp, X.ButtonRelease, button)
        self.disp.sync()


class RadialApp:
    def __init__(self):
        self.cfg = load_config()
        self.emitter = XEmitter()

        self.trigger_down = False
        self.gesture_active = False
        self.press_pos = None
        self.selected = None
        self._trigger_release_job = None

        self.menu_center = None
        self.slot_centers = {}

        self.root = tk.Tk()
        self.root.withdraw()

        self.slot_windows = {}
        self.slot_frames = {}
        self.slot_labels = {}

        self.center_window = None
        self.center_canvas = None
        self.center_pie = None

        self._build_windows()

        self.trigger_disp = display.Display()
        self.trigger_root = self.trigger_disp.screen().root
        self.trigger_code = 202

        self.trigger_root.grab_key(
            self.trigger_code,
            X.AnyModifier,
            True,
            X.GrabModeAsync,
            X.GrabModeAsync,
        )
        self.trigger_disp.sync()

        print("M3 radial active: X11 keycode 202", flush=True)

        self.root.after(5, self._poll_trigger)
        self.root.after(10, self._tick)

    def _make_toplevel(self):
        win = tk.Toplevel(self.root)
        win.withdraw()
        win.overrideredirect(True)
        win.attributes("-topmost", True)

        try:
            win.attributes("-alpha", 1.0)
        except tk.TclError:
            pass

        return win

    def _build_windows(self):
        actions = self.cfg.get("actions", {})

        for direction, _deg in DIRECTIONS:
            action = actions.get(direction, {})
            icon = action.get("icon", "")
            label = action.get("label", direction)
            text = f"{icon}  {label}" if icon else label

            win = self._make_toplevel()

            frame = tk.Frame(
                win,
                bg="#1b1d21",
                highlightbackground="#4a4e55",
                highlightcolor="#4a4e55",
                highlightthickness=1,
                bd=0,
            )
            frame.pack()

            lbl = tk.Label(
                frame,
                text=text,
                bg="#1b1d21",
                fg="#e7e9ec",
                font=("Sans", 10, "bold"),
                padx=14,
                pady=8,
                bd=0,
            )
            lbl.pack()

            self.slot_windows[direction] = win
            self.slot_frames[direction] = frame
            self.slot_labels[direction] = lbl

        self.center_window = self._make_toplevel()

        self.center_size = int(self.cfg.get("center_size_px", 46))
        self.center_canvas = tk.Canvas(
            self.center_window,
            width=self.center_size,
            height=self.center_size,
            bg="#15171a",
            highlightthickness=0,
            bd=0,
        )
        self.center_canvas.pack()

        inset = 3
        self.center_canvas.create_oval(
            inset,
            inset,
            self.center_size - inset,
            self.center_size - inset,
            fill="#1c1e22",
            outline="#747982",
            width=2,
        )

        pie_inset = 6
        self.center_pie = self.center_canvas.create_arc(
            pie_inset,
            pie_inset,
            self.center_size - pie_inset,
            self.center_size - pie_inset,
            start=0,
            extent=44,
            style=tk.PIESLICE,
            fill="#f1f2f4",
            outline="",
            state="hidden",
        )

    def _measure_layout(self):
        radius = int(self.cfg.get("menu_radius_px", 132))

        self.center_window.update_idletasks()
        center_w = self.center_window.winfo_reqwidth()
        center_h = self.center_window.winfo_reqheight()

        min_x = -center_w / 2
        max_x = center_w / 2
        min_y = -center_h / 2
        max_y = center_h / 2

        geometry = {}

        for direction, deg in DIRECTIONS:
            win = self.slot_windows[direction]
            win.update_idletasks()

            width = win.winfo_reqwidth()
            height = win.winfo_reqheight()

            angle = math.radians(deg)
            ox = math.cos(angle) * radius
            oy = math.sin(angle) * radius

            geometry[direction] = (ox, oy, width, height)

            min_x = min(min_x, ox - width / 2)
            max_x = max(max_x, ox + width / 2)
            min_y = min(min_y, oy - height / 2)
            max_y = max(max_y, oy + height / 2)

        return (
            center_w,
            center_h,
            geometry,
            min_x,
            max_x,
            min_y,
            max_y,
        )

    def _compute_menu_center(self):
        if not self.press_pos:
            return None

        (
            _center_w,
            _center_h,
            _geometry,
            min_x,
            max_x,
            min_y,
            max_y,
        ) = self._measure_layout()

        x, y = self.press_pos
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        margin = int(self.cfg.get("screen_margin_px", 10))

        if x + min_x < margin:
            x += margin - (x + min_x)

        if x + max_x > screen_w - margin:
            x -= (x + max_x) - (screen_w - margin)

        if y + min_y < margin:
            y += margin - (y + min_y)

        if y + max_y > screen_h - margin:
            y -= (y + max_y) - (screen_h - margin)

        return (x, y)

    def _position_windows(self):
        if not self.press_pos:
            return

        (
            center_w,
            center_h,
            geometry,
            _min_x,
            _max_x,
            _min_y,
            _max_y,
        ) = self._measure_layout()

        self.menu_center = self._compute_menu_center()
        if not self.menu_center:
            return

        cx, cy = self.menu_center

        self.center_window.geometry(
            f"+{int(cx - center_w / 2)}+{int(cy - center_h / 2)}"
        )

        self.slot_centers = {}

        for direction, _deg in DIRECTIONS:
            ox, oy, width, height = geometry[direction]

            slot_cx = cx + ox
            slot_cy = cy + oy
            self.slot_centers[direction] = (slot_cx, slot_cy)

            x = int(slot_cx - width / 2)
            y = int(slot_cy - height / 2)

            self.slot_windows[direction].geometry(f"+{x}+{y}")

    def _show(self):
        self._position_windows()

        self.center_window.deiconify()
        self.center_window.lift()

        for win in self.slot_windows.values():
            win.deiconify()
            win.lift()

        self.root.after_idle(self._position_windows)

    def _hide(self):
        self.center_window.withdraw()

        for win in self.slot_windows.values():
            win.withdraw()

        self._highlight(None)
        self._update_center_pie(None, None)

    def _highlight(self, direction):
        for d in self.slot_windows:
            frame = self.slot_frames[d]
            label = self.slot_labels[d]

            if d == direction:
                frame.configure(
                    bg="#464a52",
                    highlightbackground="#f1f2f4",
                    highlightcolor="#f1f2f4",
                    highlightthickness=2,
                )
                label.configure(
                    bg="#464a52",
                    fg="#ffffff",
                )
            else:
                frame.configure(
                    bg="#1b1d21",
                    highlightbackground="#4a4e55",
                    highlightcolor="#4a4e55",
                    highlightthickness=1,
                )
                label.configure(
                    bg="#1b1d21",
                    fg="#e7e9ec",
                )

    def _update_center_pie(self, dx, dy):
        if dx is None or dy is None:
            self.center_canvas.itemconfigure(
                self.center_pie,
                state="hidden",
            )
            return

        angle = math.degrees(math.atan2(-dy, dx))

        self.center_canvas.itemconfigure(
            self.center_pie,
            start=angle - 22,
            extent=44,
            state="normal",
        )

    def _pointer(self):
        return (
            self.root.winfo_pointerx(),
            self.root.winfo_pointery(),
        )

    def _direction_from_visual_center(self, px, py):
        if not self.menu_center:
            return None

        dx = px - self.menu_center[0]
        dy = py - self.menu_center[1]

        angle = math.degrees(math.atan2(dy, dx))
        idx = int(round(angle / 45.0)) % 8

        return DIRECTION_ORDER[idx]

    def _run_action(self, direction):
        action = self.cfg.get("actions", {}).get(direction)
        if not action:
            return

        typ = action.get("type")
        value = action.get("value", "")

        try:
            if typ == "keys":
                self.emitter.keys(value)

            elif typ == "mouse":
                self.emitter.mouse(value)

            elif typ == "command":
                subprocess.Popen(
                    value,
                    shell=True,
                    start_new_session=True,
                )

        except Exception as e:
            print(
                f"Action error ({direction}): {e}",
                flush=True,
            )

    def _tap_middle(self):
        self.emitter.mouse("middle")

    def _tick(self):
        if self.trigger_down and self.press_pos:
            px, py = self._pointer()

            press_dx = px - self.press_pos[0]
            press_dy = py - self.press_pos[1]
            press_dist = math.hypot(press_dx, press_dy)

            threshold = int(
                self.cfg.get("movement_threshold_px", 28)
            )

            if not self.gesture_active and press_dist >= threshold:
                self.gesture_active = True
                self._show()

            if self.gesture_active and self.menu_center:
                menu_dx = px - self.menu_center[0]
                menu_dy = py - self.menu_center[1]
                menu_dist = math.hypot(menu_dx, menu_dy)

                cancel_radius = int(
                    self.cfg.get("cancel_radius_px", threshold)
                )

                if menu_dist < cancel_radius:
                    if self.selected is not None:
                        self.selected = None
                        self._highlight(None)

                    self._update_center_pie(None, None)

                else:
                    self._update_center_pie(menu_dx, menu_dy)

                    direction = self._direction_from_visual_center(px, py)

                    if direction != self.selected:
                        self.selected = direction
                        self._highlight(direction)

        self.root.after(10, self._tick)

    def _handle_trigger(self, pressed):
        if pressed:
            if self.trigger_down:
                return

            self.trigger_down = True
            self.gesture_active = False
            self.press_pos = self._pointer()
            self.menu_center = None
            self.slot_centers = {}
            self.selected = None

        else:
            if not self.trigger_down:
                return

            active = self.gesture_active
            selected = self.selected

            self.trigger_down = False
            self.gesture_active = False

            self._hide()

            self.press_pos = None
            self.menu_center = None
            self.slot_centers = {}
            self.selected = None

            if active:
                if selected:
                    self.root.after(
                        1,
                        lambda d=selected: self._run_action(d),
                    )
            else:
                self.root.after(1, self._tap_middle)

    def _poll_trigger(self):
        try:
            while self.trigger_disp.pending_events():
                event = self.trigger_disp.next_event()

                if (
                    event.type == X.KeyPress
                    and event.detail == self.trigger_code
                ):
                    if self._trigger_release_job is not None:
                        try:
                            self.root.after_cancel(
                                self._trigger_release_job
                            )
                        except Exception:
                            pass
                        self._trigger_release_job = None

                    if not self.trigger_down:
                        self._handle_trigger(True)

                elif (
                    event.type == X.KeyRelease
                    and event.detail == self.trigger_code
                ):
                    if self._trigger_release_job is not None:
                        try:
                            self.root.after_cancel(
                                self._trigger_release_job
                            )
                        except Exception:
                            pass

                    self._trigger_release_job = self.root.after(
                        35,
                        self._commit_trigger_release,
                    )

        except Exception as e:
            print(f"Trigger error: {e!r}", flush=True)

        self.root.after(5, self._poll_trigger)

    def _commit_trigger_release(self):
        self._trigger_release_job = None

        if self.trigger_down:
            self._handle_trigger(False)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    RadialApp().run()
