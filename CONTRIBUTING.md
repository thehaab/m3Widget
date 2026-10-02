# Contributing to m3Widget

Thanks for helping improve m3Widget.

## Good contribution areas

- X11 compatibility across desktop environments
- multi-monitor behavior
- edge/corner handling
- settings UI improvements
- additional action types
- packaging for Linux distributions
- documentation and installation fixes
- investigation of a future Wayland backend

## Development setup

m3Widget currently targets an X11 session with `keyd`, Python 3, Tkinter, and python-xlib.

For local testing, keep a backup of your working launcher and configuration before changing input handling. The physical middle mouse button is intercepted by `keyd`, so a broken launcher can temporarily remove normal M3 behavior until the service or keyd mapping is reverted.

Useful commands:

```bash
systemctl --user restart m3-radial
journalctl --user -u m3-radial -f
```

## Pull requests

Please keep pull requests focused. For behavior changes, describe:

1. what changed,
2. how it was tested,
3. desktop environment / distro,
4. X11 setup,
5. mouse/input hardware when relevant.

Changes to gesture behavior should preserve these invariants unless the PR explicitly proposes changing them:

- a stationary M3 press does nothing while held,
- a normal M3 tap produces exactly one middle-click,
- radial actions do not fire until release,
- an open gesture can be cancelled by returning to the center,
- edge handling must not collapse or reorder the eight radial directions.

## Bug reports

Please include relevant service logs when possible:

```bash
journalctl --user -u m3-radial -n 50 --no-pager -l
```

For input-routing problems, `keyd` monitor output is also useful, but redact anything unrelated before posting logs publicly.

## License

By contributing, you agree that your contribution may be distributed under the project's MIT License.
