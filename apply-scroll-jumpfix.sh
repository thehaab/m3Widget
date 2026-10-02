#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/.local/bin/m3-radial"
STAMP="$(date +%Y%m%d-%H%M%S)"

cp "$APP" "$APP.before-jumpfix-$STAMP"
install -m 0755 "$(dirname "$0")/m3-radial" "$APP"
systemctl --user restart m3-radial

echo
echo "Jump-fix installed."
echo "Changes:"
echo "  - reset high-res accumulators on every scroll-state reset"
echo "  - emit REL_WHEEL_HI_RES with paired REL_WHEEL=0"
echo "  - removed SCROLLDBG spam for cleaner timing"
