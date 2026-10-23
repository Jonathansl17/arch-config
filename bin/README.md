# bin

Personal scripts copied to `~/bin/` by `install.sh`. Mix of shell scripts
and C sources (compiled at install time).

## Shell scripts

| Script | Purpose |
|--------|---------|
| `b`               | Battery status (capacity, charging state, time-to-empty) |
| `clc`             | Clean every cache (pacman, AUR, pnpm/npm/pip/go, journal, Docker) and report freed space |
| `fc`              | Fix claude: repins `~/.local/bin/claude` to the newest build that survives a `--version` smoke test (aliased over the `fc` builtin) |
| `freeoffice-textmaker`, `freeoffice-planmaker`, `freeoffice-presentations` | FreeOffice launchers (detached); shadow the `/usr/bin/` binaries of the same name |
| `s`               | git stage + auto-generated commit message + push (aborts on secret patterns) |
| `sqlserver`       | Local SQL Server in Docker: pulls the image, creates the container on first run, asks the SA password every time (never stored). Subcommands: `shell`, `stop`, `restart`, `status`, `logs`, `destroy` |
| `S`               | git stage + generic `updates` commit + push (aborts on secret patterns) |
| `ptw`             | PDF to Word: converts each PDF to a `.docx` next to it with `pdf2docx` (only the final extension changes), then opens it with `f` via `setsid -f` |
| `monitor`         | External display layout: `right-of`, `left-of`, `off`, `status` |
| `vm`              | Volume + mic status (PipeWire via `wpctl`) |
| `wifi`            | Interactive WiFi/LAN manager (nmcli wrapper). New networks ask for the MAC type: stable (default), random or real. Option 5 changes the MAC type of a saved network; option 6 edits a saved network's password, user (Enterprise only) or autoconnect. Helpers sourced from `wifi-mac.sh`, `wifi-profile.sh`, `wifi-saved.sh` and `wifi-edit.sh` |
| `wifi-reset`      | Recovers a hung PCI WiFi card without rebooting: detects the card and its driver, unloads it, removes the card from the PCI bus, rescans and reloads. Tells you to power off fully if the chip stays latched |
| `ws`              | Net status snapshot (LAN + WiFi) |
| `x`               | Xournal++ launcher (detached; seeds new `.xopp` from `~/templates/template.xopp`) |
| `xp`, `xpc`       | xournalpp → PDF helpers |
| `alacritty-selectall` | vi-mode select-all + clipboard yank |

Clipboard tools `c`, `cc`, `cpwd`, `v` live in [`termclip/`](../termclip/README.md)
(vendored upstream, **optional** — not run by `install.sh`). Run
`bash termclip/instalation.sh` to deploy them to `~/bin/`.

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
