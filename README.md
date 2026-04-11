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
- **5 systemd services enabled** (`services.txt`): NetworkManager,
  bluetooth, docker, sshd, ufw.
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

Anything machine-specific or sensitive — credentials, tokens, paths to files
that only exist on one laptop — goes into `~/.bashrc.local`, which is
**not** part of this repo. The versioned `bashrc` ends with:

```sh
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
```

If `~/.bashrc.local` doesn't exist, the block is a no-op and everything
still works. This is how secrets stay out of a public dotfiles repo.

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
└── templates/
    └── template.xopp    # default template for new .xopp files (used by xournalpp() in bashrc)
```

## License

Personal configuration — use, fork, copy, adapt freely. No warranty.
