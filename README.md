# arch-config

My personal Arch Linux setup: packages, configs, and a single `install.sh`
that reproduces the whole system on a fresh install.

Window manager is **bspwm** driven by **sxhkd**, terminal is **alacritty**,
login goes straight from TTY1 into X via `.bash_profile` → `startx` →
`.xinitrc`. No display manager, no desktop environment.

## What it installs

- **~80 official packages** (`packages.txt`): base system, kernel, drivers
  (Intel/AMD/Nouveau + Vulkan), PipeWire audio stack, NetworkManager,
  Bluetooth, bspwm/sxhkd/dmenu/i3lock, alacritty, Thunar, screenshot tools,
  common desktop apps, and a full dev toolchain (git, docker, postgres,
  JDK 21, Android tools, etc.).
- **8 AUR packages** (`aur.txt`): brave-bin, visual-studio-code-bin,
  intellij-idea-ultimate-edition, postman-bin, pgadmin4-desktop-bin, ngrok,
  zoom, android-sdk-cmdline-tools-latest. `yay` is bootstrapped from source
  automatically if it's missing.
- **4 systemd services enabled** (`services.txt`): NetworkManager,
  bluetooth, sshd, ufw. (Docker is installed but not enabled at boot —
  start it manually with `sudo systemctl start docker` when needed.)
- **6 config files** copied into `~` / `~/.config`:
  `bspwm/bspwmrc`, `sxhkd/sxhkdrc`, `alacritty/alacritty.toml`, `bash/bashrc`,
  `bash/bash_profile`, `xinit/xinitrc`.
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
config files. Any config file that exists and differs is backed up to
`<file>.bak-<timestamp>` before being replaced.

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
├── install.sh            # the installer (prereqs → pacman → yay bootstrap → AUR → configs → services)
├── packages.txt          # official packages list
├── aur.txt               # AUR packages list
├── services.txt          # systemd services to enable
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
│   └── 99-swappiness.conf
├── wifi/
│   └── wifi.sh          # interactive nmcli helper
└── nvidia/              # OPTIONAL: idempotent NVIDIA driver installer, not run by install.sh
    ├── install-nvidia.sh
    └── README.md
```

## License

Personal configuration — use, fork, copy, adapt freely. No warranty.
