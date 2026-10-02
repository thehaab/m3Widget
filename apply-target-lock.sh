#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
STAMP="$(date +%Y%m%d-%H%M%S)"

cp "$APP" "$APP.before-target-lock-$STAMP"
install -m 0755 "$(dirname "$0")/m3-radial" "$APP"
systemctl --user restart m3-radial

echo
echo "Scroll target lock installed."
echo "The gesture still tracks the pointer anywhere,"
echo "but live scrolling pauses if the pointer leaves the X11 window"
echo "where M3 was originally pressed."
