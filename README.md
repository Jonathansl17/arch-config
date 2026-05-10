# arch-config

My personal Arch Linux setup: packages, configs, and a single `install.sh`
that reproduces the whole system on a fresh install.

Window manager is **bspwm** driven by **sxhkd**, terminal is **alacritty**,
login goes straight from TTY1 into X via `.bash_profile` → `startx` →
`.xinitrc`. No display manager, no desktop environment.

## What it installs

- **~80 official packages** (`pacman/pacman-packages.txt`): base system, kernel, drivers
  (Intel/AMD/Nouveau + Vulkan), PipeWire audio stack, NetworkManager,
  Bluetooth, bspwm/sxhkd/dmenu/i3lock, alacritty, Thunar, screenshot tools,
  common desktop apps, and a full dev toolchain (git, docker, postgres,
  JDK 21, Android tools, etc.).
- **8 AUR packages** (`aur/aur-packages.txt`): brave-bin, visual-studio-code-bin,
  intellij-idea-ultimate-edition, postman-bin, pgadmin4-desktop-bin,
  ngrok, zoom, android-sdk-cmdline-tools-latest. `yay` is
  bootstrapped from source automatically if it's missing.
- **Node.js toolchain**: `nodejs` from the official repos, **nvm** cloned
  into `~/.nvm` (pinned via `NVM_VERSION`), and **pnpm** installed via the
  official `get.pnpm.io` script into `~/.local/share/pnpm` (pnpm-bin in AUR
  is orphaned). `JAVA_HOME`, `ANDROID_HOME`, `NVM_DIR`, `PNPM_HOME` and the
  combined `PATH` live in `bash/bash_profile` (one-time login setup, no
  per-shell idempotence checks); the nvm lazy-load functions live in
  `bash/bashrc` so `nvm` / `node` / `pnpm` work out of the box after install.
- **Custom lemonbar status bar** (`lemonbar/`): a minimal top bar showing
  date, CPU%, GHz, temp and RAM. The whole stack is C: a single
  `/lemonbar/bar` daemon (compiled from `lemonbar/bar.c` with libX11 +
  libXrandr) replaces the old `bar.sh + start.sh + watcher.sh` trio. It
  spawns lemonbar and `bspwm-desktops` as children, multiplexes a 1 Hz
  timerfd + the bspwm event socket + the desktops pipe with `select()`,
  reads metrics directly from `/proc` and `/sys`, and calls
  `XUnmapWindow` / `XMapWindow` on the lemonbar window when fullscreen
  toggles. Zero forks per tick. `lemonbar-xft-git` is built from AUR with
  `CC=gcc` (clang rejects `-march=x86-64`).
- **2 pipx packages** (`pipx/pipx-packages.txt`): `sherlock-project`, `holehe`
  (OSINT tools installed in isolated venvs by `install.sh` after `python-pipx`).
- **2 systemd services enabled at boot:** `NetworkManager.service` (via
  `services/services.txt`) and `ufw.service` (enabled inline by `install.sh`
  after applying its default deny-inbound / allow-outbound rules).
  Other daemons (`bluetooth`, `sshd`, `docker`) are **installed but not
  enabled** — start them manually with `sudo systemctl start <name>` when
  you actually need them. `openssh` is included so the `ssh` client is
  available for connecting *out*; the `sshd` server is left disabled so
  the machine never accepts inbound SSH unless you opt in.
- **6 config files** copied into `~` / `~/.config`:
  `bspwm/bspwmrc`, `sxhkd/sxhkdrc`, `alacritty/alacritty.toml`, `bash/bashrc`,
  `bash/bash_profile`, `xinit/xinitrc`.
- **Personal `bin/` scripts** copied into `~/bin/`: shell wrappers around the
  custom termclip helpers (`c`, `cc`, `cpwd`, `v`), short aliases as scripts
  (`s` git stage+commit+push with secret-pattern abort, `b` battery status,
  `wifi` interactive nmcli manager, `ws` net status, `vm` audio status, `r`
  process snapshot, `monitor` external display layout, `xp` / `xpc` xournalpp
  → PDF, `alacritty-selectall`). Two of them are compiled C: `clipcopy.c`
  (GTK-3 multi-target clipboard) and `alacritty-cwd.c` (Xlib + `/proc`,
  inherits cwd from the focused alacritty when launching a new one — 0 forks).
- **Xournal++ default template** at `templates/template.xopp` →
  `~/templates/template.xopp`. The `xournalpp` shell function in `bash/bashrc`
  uses it: when invoked as `xournalpp file.xopp` with a non-existent path, it
  copies the template to that path before launching. If the file already
  exists, it opens normally without touching it. With no args, xournalpp
  opens as usual.

## Usage

On a fresh Arch base install (you already have a user, sudo, network):

```sh
sudo pacman -S git           # only thing you have to do by hand
git clone https://github.com/Jonathansl17/arch-config.git
cd arch-config
./install.sh
reboot
```

After the reboot, logging into TTY1 auto-starts X and drops you into bspwm
with Wi-Fi, audio, Bluetooth, and all the keybindings working.

The script is **idempotent**: running it again on an up-to-date system does
nothing — `pacman --needed`, `yay --needed` and byte-for-byte compare on
config files. Any config file that exists and differs is **overwritten in
place** — the repo is the source of truth, so local divergence is
intentionally clobbered. Commit or stash anything you want to preserve
before running.

## Keybindings (sxhkdrc summary)

| Keys | Action |
|---|---|
| `ctrl + <` | Launch alacritty |
| `ctrl + q` | Close focused window |
| `ctrl + shift + {a,d,w,s}` | Split left / right / up / down (new alacritty) |
| `ctrl + {←↑↓→}` | Focus neighbor |
| `ctrl + shift + {←↑↓→}` | Move window within desktop |
| `ctrl + alt + {←→}` | Move window to prev/next monitor |
| `alt + Tab` | Toggle between the last two focused windows |
| `ctrl + .` | Fullscreen toggle |
| `super + {1..0}` | Switch to desktop I..X |
| `super + shift + {1..0}` | Move window to desktop I..X |
| `super + b` | Brave |
| `super + e` | Thunar |
| `super + l` | i3lock (black screen, PAM password) |
| `Print` | Area screenshot → clipboard (maim + slop + xclip) |
| `XF86Audio*` | Volume up / down / mute via wpctl |

## Status bar (lemonbar)

A minimal top bar rendered by `lemonbar-xft-git`, driven by a **single C
daemon** at `/lemonbar/bar` (built from `lemonbar/bar.c` with libX11 +
libXrandr). Content, centered on a single line:

```
1 *2* 3 4 5    Tue 14 Apr 09:52 PM    CPU 3% 0.9GHz 48°C  |  RAM 4.2/30.6GB
```

Per-metric refresh intervals: CPU% 2 s, GHz 5 s, RAM 3 s, temp 5 s, date 60 s.
The desktop list updates instantly on every bspwm event. All metrics come
from `/proc` and `/sys` via plain `read`/`fopen` (no forks in the hot path);
the bspwm IPC for fullscreen detection runs over a Unix socket directly.

Font: `monospace:size=12` (matches the alacritty size), 22 px tall. Colors:
white text on translucent black background.

### Architecture

`/lemonbar/bar` is a single binary that:

1. Detects the primary monitor (name + geometry) via XRandR.
2. Spawns `/lemonbar/bspwm-desktops` (also C; talks to bspwm directly and
   emits a preformatted desktops string on stdout) and reads its stdout.
3. Spawns `lemonbar -p -d -g <geom>` and writes formatted lines to its stdin.
4. Subscribes to `node_state node_focus node_remove node_transfer
   desktop_focus` on a separate bspwm socket connection for fullscreen
   detection.
5. `select()` on a 1 Hz `timerfd` + the desktops pipe + the event socket;
   re-renders only what's dirty.
6. On fullscreen toggle: `XUnmapWindow` / `XMapWindow` on the lemonbar
   window + `bspc config -m <primary> top_padding 0|22`.
7. Auto-respawns lemonbar (with re-detected geometry) if the child dies —
   `bin/monitor --off` and similar tools `pkill lemonbar`, and the bar
   comes back automatically.

Single-instance via `flock("/tmp/lemonbar-bar.lock")` — running the binary
twice is a silent no-op.

### How it is launched

`bspwmrc` runs `/lemonbar/bar &` in a marked block:

```sh
# LEMONBAR-START
/lemonbar/bar &
# LEMONBAR-END
```

`install.sh` builds both binaries straight into `/lemonbar/` (no
intermediate artifacts in the repo):

```sh
gcc -O2 -Wall -o /lemonbar/bar             lemonbar/bar.c            -lX11 -lXrandr
gcc -O2 -Wall -o /lemonbar/bspwm-desktops  lemonbar/bspwm-desktops.c
```

### Why `lemonbar-xft-git` is handled outside `aur.txt`

The PKGBUILD ships `CFLAGS` that include `-march=x86-64`, which the default
`cc` (clang on Arch) rejects. `install.sh` runs that one package with
`CC=gcc yay -S --needed --noconfirm lemonbar-xft-git`; everything else in
`aur.txt` goes through a single plain `yay -S` call.

### Files

- `lemonbar/bar.c` — unified C daemon (metrics + fullscreen watcher).
- `lemonbar/bspwm-desktops.c` — bspwm-IPC client that emits the desktops
  string for the bar.

## Screenshot setup

`Print` runs this inline:

```sh
maim -s | xclip -selection clipboard -t image/png
```

`maim -s` uses `slop` internally for area selection (drag & release, Esc
cancels). `xclip` automatically forks into background and holds the
X11 clipboard selection until another app claims ownership — that sidesteps
the classic X11 clipboard-dies-with-the-process issue without needing a
clipboard manager daemon.

## Local-only overrides (`~/.bashrc.local`)

Anything machine-specific or sensitive — credentials, tokens, API keys,
aliases that embed private hostnames, paths to files that only exist on one
laptop — goes into `~/.bashrc.local`, which is **not** part of this repo.
The versioned `bashrc` ends with:

```sh
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
```

If `~/.bashrc.local` doesn't exist, the block is a no-op and everything
still works. This is how secrets stay out of a public dotfiles repo.

### Creating it on a fresh machine

```sh
touch ~/.bashrc.local
chmod 600 ~/.bashrc.local      # readable only by you
```

The `chmod 600` matters — anything you put there is plaintext on disk, so at
least lock it to your user.

### What belongs in it

Rule of thumb: **if you would be uncomfortable pasting the line into a public
GitHub issue, it goes in `~/.bashrc.local`, not in the versioned `bashrc`.**

Typical contents (one-per-line, as env vars or aliases):

```sh
# --- API keys / tokens ---
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export GITHUB_TOKEN="ghp_..."

# --- SSH / RDP shortcuts that embed hostnames or users ---
alias work-ssh='ssh myuser@internal.box.example.com'
alias rdp-home='xfreerdp /u:me /v:10.0.0.5 /p:"$MY_RDP_PASS"'
export MY_RDP_PASS='...'

# --- Database connection strings ---
export DATABASE_URL='postgres://user:pass@host:5432/db'

# --- Per-machine paths ---
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
```

After editing, reload with `source ~/.bashrc` (which re-sources
`~/.bashrc.local`) or just open a new terminal.

### Sanity check before committing to this repo

Before `git push` on `arch-config`, make sure nothing private slipped into
`bash/bashrc`:

```sh
grep -nE 'sk-|ghp_|AKIA|password=|token=|@[0-9.]+' bash/bashrc
```

Expected output: nothing. Anything that matches should be moved to
`~/.bashrc.local`.

## Optional extras

### Optional helper scripts (`optional-scripts/`)

Standalone scripts not run by `install.sh`. Each is idempotent — safe to
re-run; they skip cleanly when their target state is already in place.
See `optional-scripts/README.md` for full details.

- `system-hardening.sh` — apply security defaults: `/boot` vfat
  `fmask=0077,dmask=0077`, deploy `sysctl/99-hardening.conf`, GRUB hidden
  menu (`GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`; hold **Shift** at
  POST to force the menu), and chmod 700 on `~/.aws` / `~/aws` if present.
- `migrate-to-mnt-data.sh` — move heavy caches and dev tool stores from
  `/` and `/home` to `/mnt/data` via symlinks.
- `migrate-to-home.sh` — mirror of the above; consolidates everything back
  to `~/storage/`.

```sh
bash optional-scripts/system-hardening.sh    # security defaults
sudo ./optional-scripts/migrate-to-mnt-data.sh
```

### NVIDIA driver (hybrid AMD + NVIDIA laptops)

This repo ships an **optional, idempotent** installer at
`nvidia/install-nvidia.sh` for the exact NVIDIA setup I run on an ASUS
hybrid laptop (AMD iGPU handles the desktop, NVIDIA dGPU wakes only for
CUDA/NVENC). It is **not** called by `install.sh` — run it manually when
you need it.

```sh
./nvidia/install-nvidia.sh --check    # preflight + state probe, no changes
./nvidia/install-nvidia.sh            # idempotent install/repair
./nvidia/install-nvidia.sh --force    # re-run every phase, skip early-exit
./nvidia/install-nvidia.sh --nuke     # wipe everything NVIDIA and reinstall from scratch
```

What it does (only runs the phases that aren't already in the desired state):

- Installs `linux-headers`, `dkms`, `linux-firmware-nvidia`,
  `nvidia-open-dkms`, `nvidia-utils`
- Removes `xf86-video-nouveau` and `vulkan-nouveau` userspace
- Cleans up orphan files left by legacy `.run` installs
- Writes `/etc/modprobe.d/blacklist-nouveau.conf` so the nouveau kernel
  module doesn't fight the proprietary driver
- Regenerates the initramfs via `mkinitcpio -P` only if the blacklist
  actually changed

See `nvidia/README.md` for the full phase list, preflight checks, and
rollback notes. Logs go to `nvidia/logs/` (gitignored).

If you don't have an NVIDIA GPU, ignore this directory.

## Assumptions

This config is not portable to arbitrary setups without edits. It assumes:

- **Arch Linux or derivative** with `pacman`.
- **X11**, not Wayland. The screenshot pipeline, `xrandr`, `xsetroot` and
  everything in `.xinitrc` are X11-only.
- **PipeWire** audio (the volume keybindings use `wpctl`).
- **Monitor names** in `bspwmrc` are hardcoded to `eDP` and `HDMI-1-1`.
  On most laptops they're named differently (`eDP-1`, `HDMI-1`, etc.) —
  if you don't match, the multi-monitor branch silently falls through to
  the single-monitor fallback. Edit those two lines if needed.
- `postgresql` is installed but **not** enabled or initialized automatically
  because it needs a manual `initdb` on first use.
- Brave is on AUR, so it's installed through yay in step 3 (not via pacman).

## Repository layout

```
arch-config/
├── install.sh            # the installer (prereqs → pacman → yay bootstrap → AUR → pipx → configs → services)
├── pacman/
│   └── pacman-packages.txt   # official packages list
├── aur/
│   └── aur-packages.txt      # AUR packages list
├── pipx/
│   └── pipx-packages.txt     # Python CLIs installed via pipx (sherlock, holehe, ...)
├── services/
│   └── services.txt          # systemd services to enable
├── alacritty/
│   └── alacritty.toml
├── bash/
│   ├── bashrc
│   └── bash_profile
├── bspwm/
│   └── bspwmrc
├── sxhkd/
│   └── sxhkdrc
├── xinit/
│   └── xinitrc
├── templates/
│   └── template.xopp    # default template for new .xopp files (used by xournalpp() in bashrc)
├── slock/
│   └── config.h         # all-black lockscreen build (compiled from source by install.sh)
├── sysctl/
│   ├── 99-swappiness.conf       # vm.swappiness=10 (deployed by install.sh)
│   └── 99-hardening.conf        # kptr_restrict, ptrace_scope, rp_filter, redirects (deployed by optional-scripts/system-hardening.sh)
├── wifi/
│   └── wifi.sh          # interactive nmcli helper
├── lemonbar/            # custom status bar (date | CPU | WiFi | BAT)
│   ├── bar.sh           # feeder piped into lemonbar
│   ├── start.sh         # (re)launch the bar
│   └── watcher.sh       # bspwm event listener, hides bar on fullscreen
├── optional-scripts/    # OPTIONAL: idempotent helpers, not run by install.sh
│   ├── system-hardening.sh      # /boot fmask, sysctl hardening, GRUB hidden menu
│   ├── migrate-to-mnt-data.sh   # offload caches/dev stores to /mnt/data
│   ├── migrate-to-home.sh       # mirror: consolidate back to ~/storage
│   └── README.md
└── nvidia/              # OPTIONAL: idempotent NVIDIA driver installer, not run by install.sh
    ├── install-nvidia.sh
    └── README.md
```

## License

Personal configuration — use, fork, copy, adapt freely. No warranty.
