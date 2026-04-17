#!/usr/bin/env bash
# Installs packages (official repos + AUR) and configs into ~/.config and ~.
# Idempotent: pacman --needed and yay --needed skip anything already installed;
# config files with identical content are left untouched. Existing files that
# differ are backed up to <file>.bak-<timestamp> before being replaced.
#
# Usage: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# repo_relative_source  absolute_destination
MAPPINGS=(
    "bspwm/bspwmrc            $HOME/.config/bspwm/bspwmrc"
    "sxhkd/sxhkdrc            $HOME/.config/sxhkd/sxhkdrc"
    "alacritty/alacritty.toml $HOME/.config/alacritty/alacritty.toml"
    "bash/bashrc              $HOME/.bashrc"
    "bash/bash_profile        $HOME/.bash_profile"
    "xinit/xinitrc            $HOME/.xinitrc"
    "templates/template.xopp  $HOME/templates/template.xopp"
    "wifi/wifi.sh             $HOME/wifi/wifi.sh"
    "bin/alacritty-cwd        $HOME/bin/alacritty-cwd"
    "nvim/init.lua            $HOME/.config/nvim/init.lua"
)

read_pkglist() {
    # Reads a pacman-style list: strips comments (#...) and blank lines.
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$file"
}

install_file() {
    local src="$REPO_DIR/$1"
    local dst="$2"

    if [[ ! -f "$src" ]]; then
        warn "source missing: $src (skipping)"
        return
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ -e "$dst" || -L "$dst" ]]; then
        if cmp -s "$src" "$dst"; then
            say "unchanged: $dst"
            return
        fi
        local backup="${dst}.bak-${TIMESTAMP}"
        warn "backup: $dst -> $backup"
        mv "$dst" "$backup"
    fi

    cp "$src" "$dst"
    say "installed: $dst"
}

# --- 0. Minimum prerequisites (git to clone AUR, base-devel for makepkg) ---
# If you cloned the repo you already have git, but if you downloaded it as a
# zip it might be missing. base-devel is required to bootstrap yay in step 2.
say "Checking prerequisites (git, base-devel)"
prereqs=()
command -v git     >/dev/null 2>&1 || prereqs+=(git)
command -v makepkg >/dev/null 2>&1 || prereqs+=(base-devel)
if (( ${#prereqs[@]} > 0 )); then
    warn "missing: ${prereqs[*]} — installing"
    sudo pacman -S --needed --noconfirm "${prereqs[@]}"
fi

# --- 1. Official packages ---
say "Installing official packages (packages.txt)"
pkgs=$(read_pkglist "$REPO_DIR/packages.txt")
if [[ -n "$pkgs" ]]; then
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
else
    warn "packages.txt empty or missing, skipping"
fi

# --- 2. Bootstrap yay (if missing) ---
if ! command -v yay >/dev/null 2>&1; then
    say "yay not found, bootstrapping from AUR"
    command -v git     >/dev/null || die "git is required to bootstrap yay"
    command -v makepkg >/dev/null || die "base-devel is required to bootstrap yay"

    tmp=$(mktemp -d)
    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
    ( cd "$tmp/yay" && makepkg -si --noconfirm )
    rm -rf "$tmp"
else
    say "yay already installed"
fi

# --- 3. AUR packages ---
say "Installing AUR packages (aur.txt)"
aur_pkgs=$(read_pkglist "$REPO_DIR/aur.txt")
if [[ -n "$aur_pkgs" ]]; then
    # shellcheck disable=SC2086
    yay -S --needed --noconfirm $aur_pkgs
else
    warn "aur.txt empty or missing, skipping"
fi

# --- 3b. Remove packages that were previously installed by this setup but
#         are no longer part of it. Keep the list short; these are one-off
#         cleanups after decisions are reversed. Safe no-op on fresh installs.
for pkg in xss-lock; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        say "Removing obsolete package: $pkg"
        sudo pacman -Rns --noconfirm "$pkg"
    fi
done

# --- 4. Configs ---
say "Installing configs from $REPO_DIR"
for entry in "${MAPPINGS[@]}"; do
    # shellcheck disable=SC2086
    install_file $entry
done

# bspwmrc, wifi.sh and alacritty-cwd must be executable
chmod +x "$HOME/.config/bspwm/bspwmrc" 2>/dev/null || true
chmod +x "$HOME/wifi/wifi.sh" 2>/dev/null || true
chmod +x "$HOME/bin/alacritty-cwd" 2>/dev/null || true

# --- 4b. Build clipcopy (multi-target clipboard for screenshots) ---
say "Building clipcopy"
mkdir -p "$HOME/bin"
gcc -O2 -o "$HOME/bin/clipcopy" "$REPO_DIR/bin/clipcopy.c" \
    $(pkg-config --cflags --libs gtk+-3.0)
say "installed: ~/bin/clipcopy"

# --- 4c. Install lemonbar + /lemonbar scripts (custom status bar) ---
say "Installing lemonbar-xft-git (forces CC=gcc; clang fails with -march)"
if ! pacman -Q lemonbar-xft-git >/dev/null 2>&1; then
    CC=gcc yay -S --needed --noconfirm lemonbar-xft-git
fi

say "Building bspwm-desktops (direct socket, no bspc)"
gcc -O2 -Wall -o "$REPO_DIR/lemonbar/bspwm-desktops" "$REPO_DIR/lemonbar/bspwm-desktops.c"

say "Deploying /lemonbar scripts + binary"
if [[ ! -d /lemonbar ]]; then
    sudo mkdir -p /lemonbar
fi
sudo chown "$USER:$USER" /lemonbar

# Stop the running bar first; otherwise cp on /lemonbar/bspwm-desktops
# fails with "Text file busy" because the binary is in use.
pkill -f '/lemonbar/watcher.sh' 2>/dev/null || true
pkill -f '/lemonbar/bar.sh' 2>/dev/null || true
pkill -x bspwm-desktops 2>/dev/null || true
pkill -x lemonbar 2>/dev/null || true
rm -f /tmp/lemonbar-watcher.lock
sleep 0.3

cp "$REPO_DIR/lemonbar/bar.sh" \
   "$REPO_DIR/lemonbar/start.sh" \
   "$REPO_DIR/lemonbar/watcher.sh" \
   "$REPO_DIR/lemonbar/bspwm-desktops" /lemonbar/
chmod +x /lemonbar/*.sh /lemonbar/bspwm-desktops

say "Restarting lemonbar"
setsid -f /lemonbar/watcher.sh </dev/null >/dev/null 2>&1

# --- 4d. Build slock from source (custom config: all-black lock screen) ---
say "Building slock from source"
SLOCK_BUILD="$HOME/builds/slock"
if [[ ! -d "$SLOCK_BUILD" ]]; then
    mkdir -p "$HOME/builds"
    git clone https://git.suckless.org/slock "$SLOCK_BUILD"
fi
cp "$REPO_DIR/slock/config.h" "$SLOCK_BUILD/config.h"
( cd "$SLOCK_BUILD" && sudo make clean install )

# --- 4e. nvm (Node Version Manager) ---
# Cloned into ~/.nvm; the loader is already in bash/bashrc. We pin a tag so
# the install is reproducible; bump NVM_VERSION when a new release is out.
NVM_VERSION="v0.40.1"
if [[ ! -d "$HOME/.nvm" ]]; then
    say "Cloning nvm $NVM_VERSION into ~/.nvm"
    git clone --depth=1 --branch "$NVM_VERSION" https://github.com/nvm-sh/nvm.git "$HOME/.nvm"
else
    say "nvm already present at ~/.nvm (skipping)"
fi

# --- 4f. sysctl tweaks ---
say "Installing sysctl configs"
sudo cp "$REPO_DIR/sysctl/99-swappiness.conf" /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system >/dev/null 2>&1

# --- 5. systemd services ---
say "Enabling systemd services (services.txt)"
services=$(read_pkglist "$REPO_DIR/services.txt")
if [[ -n "$services" ]]; then
    # shellcheck disable=SC2086
    sudo systemctl enable $services
else
    warn "services.txt empty or missing, skipping"
fi

# --- 6. Keyboard layout (LATAM) ---
say "Setting X11 keyboard layout to latam"
localectl set-x11-keymap latam pc105+inet "" terminate:ctrl_alt_bksp

# --- 7. Reload bspwm + sxhkd if running ---
if pgrep -x bspwm >/dev/null; then
    say "Reloading bspwm and sxhkd"
    bspc wm -r
    pkill -USR1 -x sxhkd 2>/dev/null || true
fi

say "Done. On a fresh machine: reboot so the enabled services start."
