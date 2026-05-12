# bspwm

Tiling window manager config. Companion to `sxhkd/` (keybindings).

## Files

- `bspwmrc` → `~/.config/bspwm/bspwmrc` (chmod +x by install.sh)

## What bspwmrc does

- Detects primary monitor via `xrandr` (internal: `eDP*`/`LVDS*`/`DSI*`,
  fallback first connected; external: `HDMI-*`)
- Creates 10 desktops on the primary monitor
- Sets gaps, borders, focus colors
- Starts `/lemonbar/bar &` (status bar)
- Re-runs idempotently when reloaded via `bspc wm -r`

## Monitor handling

Monitor names are detected dynamically — no hardcoded `eDP-1` or
`HDMI-A-0`. Works on any laptop or desktop without edits. The detection
logic is shared with `bin/monitor` and `lemonbar/bar.c`.

## Reloading

`install.sh` ends with `bspc wm -r` if bspwm is already running, so config
changes take effect without logout.
