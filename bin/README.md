# bin

Personal scripts copied to `~/bin/` by `install.sh`. Mix of shell scripts
and C sources (compiled at install time).

## Shell scripts

| Script | Purpose |
|--------|---------|
| `b`               | Battery status (capacity, charging state, time-to-empty) |
| `c`, `cc`, `cpwd`, `v` | termclip clipboard wrappers |
| `s`               | git stage + Claude-generated commit + push (aborts on secret patterns) |
| `monitor`         | External display layout: `right-of`, `left-of`, `off`, `status` |
| `vm`              | Volume + mic status (PipeWire via `wpctl`) |
| `wifi`            | Interactive WiFi/LAN manager (nmcli wrapper) |
| `ws`              | Net status snapshot (LAN + WiFi) |
| `xp`, `xpc`       | xournalpp → PDF helpers |
| `alacritty-selectall` | vi-mode select-all + clipboard yank |

## C sources (compiled by install.sh)

| Source | Output | What it does |
|--------|--------|--------------|
| `clipcopy.c`       | `~/bin/clipcopy`       | GTK-3 multi-target clipboard tool used by screenshot pipeline |
| `alacritty-cwd.c`  | `~/bin/alacritty-cwd`  | Xlib + `/proc`; inherits cwd from focused alacritty (0 forks) |
| `r.c`              | `~/bin/r`              | Pure `/proc` top-N process snapshot (CPU%, RSS) |

Build deps: `gcc`, `pkg-config`, `gtk3`, `libx11`. `install.sh` checks
and pacman-installs them before compiling.

## Why C and not bash

`alacritty-cwd` and `r` ran on every split / status update; the bash+awk
versions burned forks. C versions read `/proc` directly via `fopen`/`read`
with zero subprocess calls.
