# lemonbar

Custom status bar rendered by `lemonbar-xft-git`, driven by a **single C
daemon** at `/lemonbar/bar` (compiled from `lemonbar/bar.c`).

## Bar content

```
1 *2* 3 4 5    Tue 14 Apr 09:52 PM    CPU 3% 0.9GHz 48°C  |  RAM 4.2/30.6GB
```

Per-metric refresh intervals: CPU% 2s, GHz 5s, RAM 3s, temp 5s, date 60s.
Desktop list updates instantly on every bspwm event.

Font: `monospace:size=12` (matches alacritty). 22 px tall. White on
translucent black.

## Files

| File | Purpose |
|------|---------|
| `bar.c`            | Unified daemon: metrics + fullscreen watcher → compiled to `/lemonbar/bar` |
| `bspwm-desktops.c` | bspwm-IPC client emitting the desktops string → compiled to `/lemonbar/bspwm-desktops` |

`install.sh` builds both into `/lemonbar/` (no intermediate artifacts in
the repo).

## Architecture

`/lemonbar/bar` is a single binary that:

1. Detects the primary monitor (name + geometry) via XRandR.
2. Spawns `/lemonbar/bspwm-desktops` (also C; talks bspwm directly) and
   reads its stdout.
3. Spawns `lemonbar -p -d -g <geom>` and writes formatted lines to stdin.
4. Subscribes to `node_state node_focus node_remove node_transfer
   desktop_focus` on a separate bspwm socket for fullscreen detection.
5. `select()` on 1 Hz `timerfd` + desktops pipe + event socket; re-renders
   only what's dirty.
6. On fullscreen toggle: `XUnmapWindow`/`XMapWindow` on the lemonbar
   window + `bspc config -m <primary> top_padding 0|22`.
7. Auto-respawns lemonbar if the child dies — `bin/monitor --off` and
   similar `pkill lemonbar`, and the bar comes back automatically.

All metrics read from `/proc` and `/sys` via plain `read`/`fopen`. Zero
forks in the hot path.

Single-instance via `flock("/tmp/lemonbar-bar.lock")` — running the binary
twice is a silent no-op.

## How it is launched

`bspwmrc` runs `/lemonbar/bar &` inside a marked block:

```sh
# LEMONBAR-START
/lemonbar/bar &
# LEMONBAR-END
```

## Why lemonbar-xft-git is built outside aur-packages.txt

The PKGBUILD ships `CFLAGS` that include `-march=x86-64`, rejected by
clang (Arch default `cc`). `install.sh` runs:

```sh
CC=gcc yay -S --needed --noconfirm lemonbar-xft-git
```

Everything else in `aur-packages.txt` goes through a single plain
`yay -S` call.

## Build commands

```sh
gcc -O2 -Wall -o /lemonbar/bar             lemonbar/bar.c             -lX11 -lXrandr
gcc -O2 -Wall -o /lemonbar/bspwm-desktops  lemonbar/bspwm-desktops.c
```
