# arch-config

My personal Arch Linux setup: packages, configs, and a single `install.sh`
that reproduces the whole system on a fresh install.

Window manager is **bspwm** driven by **sxhkd**, terminal is **alacritty**,
login goes straight from TTY1 into X via `bash_profile` → `startx` →
`xinitrc`. No display manager, no desktop environment.

## Usage

On a fresh Arch base install (you already have a user, sudo, network):

```sh
sudo pacman -S git
git clone https://github.com/Jonathansl17/arch-config.git
cd arch-config
./install.sh
reboot
```

After the reboot, logging into TTY1 auto-starts X and drops you into bspwm
with Wi-Fi, audio, Bluetooth and all the keybindings working.

The script is **idempotent**: re-running on an up-to-date system does
nothing. Config files that differ are overwritten in place — the repo is
the source of truth. Commit or stash anything local before running.

## What it installs (high level)

- **~80 official packages** — see [`pacman/`](pacman/README.md)
- **AUR packages** (yay bootstrapped automatically) — see [`aur/`](aur/README.md)
- **Python CLIs via pipx** — see [`pipx/`](pipx/README.md)
- **systemd services** — see [`services/`](services/README.md)
- **Configs** copied into `~` / `~/.config/` (see per-directory READMEs)
- **Custom C binaries**: clipboard helpers in [`bin/`](bin/README.md),
  status bar in [`lemonbar/`](lemonbar/README.md)
- **slock** built from source — see [`slock/`](slock/README.md)
- **nvm + pnpm** installed via their upstream installers (pinned versions
  in `install.sh`)

## Repository layout

| Path | Purpose |
|------|---------|
| [`install.sh`](install.sh)             | The installer (prereqs → pacman → yay → AUR → pipx → configs → builds → services) |
| [`pacman/`](pacman/README.md)          | Official package list |
| [`aur/`](aur/README.md)                | AUR package list |
| [`pipx/`](pipx/README.md)              | Python CLI tools (sherlock, holehe) |
| [`services/`](services/README.md)      | systemd services to enable at boot |
| [`bash/`](bash/README.md)              | `bashrc`, `bash_profile`, `~/.bashrc.local` convention |
| [`alacritty/`](alacritty/README.md)    | Terminal emulator config |
| [`bspwm/`](bspwm/README.md)            | Window manager config |
| [`sxhkd/`](sxhkd/README.md)            | Keybindings (full table inside) |
| [`xinit/`](xinit/README.md)            | X session startup (`~/.xinitrc`) |
| [`lemonbar/`](lemonbar/README.md)      | Custom C status bar daemon |
| [`bin/`](bin/README.md)                | Personal scripts + compiled C tools copied to `~/bin/` |
| [`termclip/`](termclip/README.md)      | Vendored clipboard utilities (`c`, `cc`, `cpwd`, `v`) |
| [`nvim/`](nvim/README.md)              | Neovim + IdeaVim config |
| [`slock/`](slock/README.md)            | Screen locker (built from source) |
| [`sysctl/`](sysctl/README.md)          | Kernel parameters |
| [`templates/`](templates/README.md)    | xournalpp default template |
| [`nvidia/`](nvidia/README.md)          | **Optional** NVIDIA driver installer (not run by `install.sh`) |
| [`optional-scripts/`](optional-scripts/README.md) | **Optional** helpers: hardening, data-disk setup, cache migration |

## Optional extras

Run manually after `install.sh`. Each is idempotent.

```sh
bash optional-scripts/system-hardening.sh         # /boot fmask, sysctl, GRUB, fstab nofail
bash optional-scripts/setup-data-disk.sh          # partition + mount a second disk as /mnt/data
sudo bash optional-scripts/migrate-to-mnt-data.sh # offload caches and dev tool stores to /mnt/data
./nvidia/install-nvidia.sh                        # NVIDIA dGPU on hybrid laptops
```

Details in each subdirectory's README.

## Assumptions

This config is not portable to arbitrary setups without edits. It assumes:

- **Arch Linux or derivative** with `pacman`.
- **X11**, not Wayland. Screenshot pipeline, `xrandr`, `xsetroot` and
  everything in `xinitrc` are X11-only.
- **PipeWire** audio (volume keybindings use `wpctl`).
- **Monitor names** are detected dynamically in `bspwmrc`, `bin/monitor`
  and `lemonbar/bar.c` — internal display matched against
  `eDP*`/`LVDS*`/`DSI*` with a fallback to the first connected output;
  external monitors picked up by `HDMI-*` scan. Works on any laptop or
  desktop without edits.
- `postgresql` is installed but **not** enabled or initialized
  automatically because it needs a manual `initdb`.

## License

Personal configuration — use, fork, copy, adapt freely. No warranty.
