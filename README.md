# m3Widget

A fast, configurable **M3 (middle mouse button) radial gesture launcher for Linux/X11**.

Hold the middle mouse button and move the pointer to open an eight-way radial menu. Release over a direction to trigger its action. A normal M3 tap is preserved as a normal middle-click/paste.

m3Widget was built around a simple goal: make one mouse button useful without making it slower.

## Features

- Eight-way radial gesture menu
- Normal middle-click preserved on tap
- Actions fire once, on release
- Return to the center to cancel an open gesture
- Directional center pie follows the pointer
- No giant overlay window: each menu item is its own tiny borderless window
- Whole-menu edge handling keeps the radial intact near screen edges
- Configurable keyboard shortcuts, mouse actions, and shell commands
- Separate graphical settings app
- JSON configuration
- Runs as a systemd user service

## Current platform support

m3Widget currently targets **Linux on X11** and has been developed/tested on Pop!_OS.

The current input path uses `keyd` to convert the physical middle mouse button to F24. The Python launcher grabs the resulting X11 keycode, tracks pointer movement, and emits the configured action with XTest.

**Wayland is not supported yet.**

## Interaction model

```text
M3 down + don't move
    nothing happens

release without crossing threshold
    one normal middle-click

M3 down + move past threshold
    radial appears

continue holding
    move through directions; nothing fires yet

return to center
    selection clears / gesture becomes cancel

release on a direction
    selected action fires once

release in center cancel zone
    nothing fires
```

## Requirements

- X11 session
- Python 3
- Tkinter (`python3-tk`)
- python-xlib (`python3-xlib`)
- `keyd`
- systemd user services

On Ubuntu/Pop!_OS, the Python dependencies are:

```bash
sudo apt install python3-xlib python3-tk
```

`keyd` must also be installed and running. Package availability varies by distribution.

## Install

Clone the repository:

```bash
git clone https://github.com/thehaab/m3Widget.git
cd m3Widget
```

Find the `keyd` device ID for the mouse interface that reports `middlemouse`:

```bash
sudo keyd.rvaiya monitor
```

On some distributions the executable is simply:

```bash
sudo keyd monitor
```

Press the middle mouse button and note the device ID printed for that event.

Then install using that ID:

```bash
bash install.sh YOUR_DEVICE_ID
```

Example:

```bash
bash install.sh 1532:008a:2e08caa2
```

The installer places:

```text
~/.local/bin/m3-radial
~/.local/bin/m3-radial-settings
~/.config/m3-radial/config.json
~/.config/systemd/user/m3-radial.service
~/.local/share/applications/m3-radial-settings.desktop
/etc/keyd/m3-radial.conf
```

## Settings

Launch the settings app with:

```bash
m3-radial-settings
```

or open **M3 Radial Settings** from the desktop application launcher.

The settings app supports:

- editing all eight slots
- preset actions
- custom key combinations
- custom shell commands
- mouse actions
- icons and labels
- drag-to-swap slots
- movement threshold
- menu radius
- Save + Restart

## Configuration

The live configuration is stored at:

```text
~/.config/m3-radial/config.json
```

Actions have three supported types.

### Keyboard shortcut

```json
{
  "label": "Copy",
  "icon": "⧉",
  "type": "keys",
  "value": "ctrl+c"
}
```

### Mouse action

```json
{
  "label": "Middle Click",
  "icon": "●",
  "type": "mouse",
  "value": "middle"
}
```

### Command

```json
{
  "label": "Terminal",
  "icon": "⌘",
  "type": "command",
  "value": "gnome-terminal"
}
```

Key names include `ctrl`, `alt`, `shift`, `super`, `enter`, arrow keys, `print`, and ordinary characters.

## Logs

```bash
journalctl --user -u m3-radial -f
```

Restart after manual config/source changes:

```bash
systemctl --user restart m3-radial
```

## Uninstall

```bash
bash uninstall.sh
```

To also remove your saved m3Widget configuration:

```bash
bash uninstall.sh --purge
```

## Architecture

The project deliberately separates input handling from rendering:

1. `keyd` maps physical M3 to F24 so the normal middle-click can be delayed safely.
2. `m3-radial` grabs the resulting X11 keycode.
3. A short movement threshold distinguishes a normal tap from a gesture.
4. The menu is rendered as nine small borderless Tk windows: eight action pills plus a center indicator.
5. Near a screen edge, the entire radial is shifted as one rigid layout instead of clamping individual buttons.
6. Releasing either emits one configured action, silently cancels, or re-emits one normal middle-click.

## Project status

This is an early open-source release. The current implementation is useful and functional, but the project is still evolving.

Likely next areas:

- multi-monitor edge handling
- richer settings UI
- configurable visual themes
- easier device discovery
- packaged installation
- broader desktop/distribution testing
- Wayland investigation

## Contributing

Issues, bug reports, compatibility notes, and pull requests are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).
