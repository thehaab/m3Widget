m3Widget scroll jump fix

Based on inspection of the live launcher.

Fixes:
1. High-resolution accumulator was not reset in _reset_scroll_motion().
2. Virtual device advertised REL_WHEEL + REL_WHEEL_HI_RES but only emitted
   REL_WHEEL_HI_RES. This patch emits REL_WHEEL=0 in the same frame so
   the legacy axis never contributes an extra detent.

Install:
  chmod +x apply-scroll-jumpfix.sh
  ./apply-scroll-jumpfix.sh
