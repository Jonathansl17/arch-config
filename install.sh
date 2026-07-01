#!/usr/bin/env bash
# Installs packages (official repos + AUR) and configs into ~/.config and ~.
# Idempotent: pacman --needed and yay --needed skip anything already installed;
# config files with identical content are left untouched. Existing files that
# differ are overwritten in place — the repo is the source of truth, so any
# local divergence is intentionally clobbered. No backups are kept; commit
# or stash anything you want to preserve before running.
#
# Usage: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    "bin/alacritty-selectall  $HOME/bin/alacritty-selectall"
    "bin/b                    $HOME/bin/b"
    "bin/monitor              $HOME/bin/monitor"
    "bin/s                    $HOME/bin/s"
    "bin/ws                   $HOME/bin/ws"
    "bin/vm                   $HOME/bin/vm"
    "bin/xp                   $HOME/bin/xp"
    "bin/xpc                  $HOME/bin/xpc"
    "bin/wifi                 $HOME/bin/wifi"
    "bin/bt                   $HOME/bin/bt"
    "nvim/init.lua            $HOME/.config/nvim/init.lua"
    "nvim/ideavimrc           $HOME/.ideavimrc"
    "nvim/intellij-keymap.xml         $HOME/.config/JetBrains/IntelliJIdea2026.1/keymaps/XWin copy.xml"
    "nvim/intellij-ide.general.xml    $HOME/.config/JetBrains/IntelliJIdea2026.1/options/ide.general.xml"
    "vscode/keybindings.json  $HOME/.config/Code/User/keybindings.json"
    "vscode/settings.json     $HOME/.config/Code/User/settings.json"
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

    if [[ -e "$dst" || -L "$dst" ]] && cmp -s "$src" "$dst"; then
        say "unchanged: $dst"
        return
    fi

    cp -f "$src" "$dst"
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
say "Installing official packages (pacman/pacman-packages.txt)"
pkgs=$(read_pkglist "$REPO_DIR/pacman/pacman-packages.txt")
if [[ -n "$pkgs" ]]; then
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
else
    warn "pacman/pacman-packages.txt empty or missing, skipping"
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
say "Installing AUR packages (aur/aur-packages.txt)"
aur_pkgs=$(read_pkglist "$REPO_DIR/aur/aur-packages.txt")
if [[ -n "$aur_pkgs" ]]; then
    # shellcheck disable=SC2086
    yay -S --needed --noconfirm $aur_pkgs
else
    warn "aur/aur-packages.txt empty or missing, skipping"
fi

# --- 3c. pipx packages (Python CLI tools in isolated venvs) ---
say "Installing pipx packages (pipx/pipx-packages.txt)"
if command -v pipx >/dev/null 2>&1; then
    pipx_pkgs=$(read_pkglist "$REPO_DIR/pipx/pipx-packages.txt")
    if [[ -n "$pipx_pkgs" ]]; then
        installed=$(pipx list --short 2>/dev/null | awk '{print $1}')
        while read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if grep -qx "$pkg" <<<"$installed"; then
                say "pipx: $pkg already installed"
            else
                pipx install "$pkg"
            fi
        done <<<"$pipx_pkgs"
    else
        warn "pipx/pipx-packages.txt empty or missing, skipping"
    fi
else
    warn "pipx not installed; skipping pipx packages"
fi

# --- 3b. Remove packages that were previously installed by this setup but
#         are no longer part of it. Keep the list short; these are one-off
#         cleanups after decisions are reversed. Safe no-op on fresh installs.
for pkg in xss-lock pnpm-bin; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        say "Removing obsolete package: $pkg"
        sudo pacman -Rns --noconfirm "$pkg"
    fi
done

# --- 4. Configs ---
say "Installing configs from $REPO_DIR"
for entry in "${MAPPINGS[@]}"; do
    read -r src dst <<< "$entry"
    install_file "$src" "$dst"
done

# bspwm scripts and local bin scripts must be executable
chmod +x "$HOME/.config/bspwm/bspwmrc" 2>/dev/null || true
chmod +x "$HOME/bin/r" 2>/dev/null || true
chmod +x "$HOME/bin/monitor" 2>/dev/null || true
for sc in s b ws vm xp xpc wifi bt; do
    chmod +x "$HOME/bin/$sc" 2>/dev/null || true
done

# --- 4b. Build native binaries ---
# Verify build deps before any gcc invocation. Otherwise a missing
# package (gcc/pkg-config/gtk3/libx11) explodes mid-flow with a cryptic
# error. Install whatever is missing via pacman --needed.
say "Verifying build deps (gcc, pkg-config, gtk3, libx11)"
build_deps=()
command -v gcc        >/dev/null 2>&1 || build_deps+=(gcc)
command -v pkg-config >/dev/null 2>&1 || build_deps+=(pkgconf)
pacman -Q gtk3   >/dev/null 2>&1 || build_deps+=(gtk3)
pacman -Q libx11 >/dev/null 2>&1 || build_deps+=(libx11)
pacman -Q libxrandr >/dev/null 2>&1 || build_deps+=(libxrandr)
if (( ${#build_deps[@]} > 0 )); then
    warn "missing build deps: ${build_deps[*]} — installing"
    sudo pacman -S --needed --noconfirm "${build_deps[@]}"
fi
pkg-config --exists gtk+-3.0 || die "gtk+-3.0 pkg-config still missing after install"

say "Building clipcopy"
mkdir -p "$HOME/bin"
gcc -O2 -o "$HOME/bin/clipcopy" "$REPO_DIR/bin/clipcopy.c" \
    $(pkg-config --cflags --libs gtk+-3.0)
say "installed: ~/bin/clipcopy"

# --- 4b-ter. Build alacritty-cwd (Xlib + /proc, replaces the bash script) ---
say "Building alacritty-cwd"
gcc -O2 -Wall -o "$HOME/bin/alacritty-cwd" "$REPO_DIR/bin/alacritty-cwd.c" -lX11
say "installed: ~/bin/alacritty-cwd"

# --- 4b-quater. Build r (pure /proc top-N, replaces the bash+awk script) ---
say "Building r"
gcc -O2 -Wall -o "$HOME/bin/r" "$REPO_DIR/bin/r.c"
say "installed: ~/bin/r"

# --- 4c. Install lemonbar + /lemonbar scripts (custom status bar) ---
say "Installing lemonbar-xft-git (forces CC=gcc; clang fails with -march)"
if ! pacman -Q lemonbar-xft-git >/dev/null 2>&1; then
    CC=gcc yay -S --needed --noconfirm lemonbar-xft-git
fi

say "Deploying /lemonbar binaries"
if [[ ! -d /lemonbar ]]; then
    sudo mkdir -p /lemonbar
fi
sudo chown "$USER:$USER" /lemonbar

# Stop the running daemons; otherwise gcc on busy binaries fails with
# "Text file busy".
pkill -x bar 2>/dev/null || true
pkill -x bspwm-desktops 2>/dev/null || true
pkill -x lemonbar 2>/dev/null || true
rm -f /tmp/lemonbar-bar.lock
sleep 0.3

# Build both binaries straight into /lemonbar/ — no intermediate artifacts in
# the repo. bar.c is the unified daemon (metrics + fullscreen watcher);
# bspwm-desktops talks the bspwm IPC and feeds the desktops string.
gcc -O2 -Wall -o /lemonbar/bar             "$REPO_DIR/lemonbar/bar.c"             -lX11 -lXrandr
gcc -O2 -Wall -o /lemonbar/bspwm-desktops  "$REPO_DIR/lemonbar/bspwm-desktops.c"

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

# --- 4e-bis. pnpm (via official install script) ---
# pnpm-bin in AUR is orphaned, so we install via get.pnpm.io straight into
# ~/.local/share/pnpm. The PATH export for $PNPM_HOME is already in
# bash/bashrc, so the binary is on $PATH after the next shell.
PNPM_HOME="$HOME/.local/share/pnpm"
if [[ ! -x "$PNPM_HOME/pnpm" ]]; then
    say "Installing pnpm via get.pnpm.io"
    curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="$PNPM_HOME" SHELL="$(command -v bash)" sh -
else
    say "pnpm already present at $PNPM_HOME/pnpm (skipping)"
fi

# --- 4e-ter. Claude Code (via official install script) ---
# Native installer drops the binary at ~/.local/bin/claude (symlink into
# ~/.local/share/claude/versions/). NOT installed via npm. Self-updates with
# `claude update`, so we only run the installer when the binary is missing.
if [[ ! -x "$HOME/.local/bin/claude" ]]; then
    say "Installing Claude Code via claude.ai/install.sh"
    curl -fsSL https://claude.ai/install.sh | bash
else
    say "Claude Code already present at ~/.local/bin/claude (skipping)"
fi

# --- 4e-quater. Go-installed CLI tools ---
# Binaries fetched with `go install`; they land in ~/go/bin (GOPATH/bin), which
# bash/bash_profile puts on $PATH. Not in the official repos or AUR, so go is
# the only install path. Idempotent: skip when the binary is already present.
if command -v go >/dev/null 2>&1; then
    declare -A GO_TOOLS=(
        [countdown]="github.com/antonmedv/countdown@latest"
    )
    GOBIN_DIR="$(go env GOPATH)/bin"
    for tool in "${!GO_TOOLS[@]}"; do
        if [[ -x "$GOBIN_DIR/$tool" ]]; then
            say "go tool already present: $tool (skipping)"
        else
            say "go install ${GO_TOOLS[$tool]}"
            go install "${GO_TOOLS[$tool]}"
        fi
    done
else
    warn "go not installed; skipping go install tools"
fi

# --- 4f. sysctl tweaks ---
say "Installing sysctl configs"
sudo cp "$REPO_DIR/sysctl/99-swappiness.conf" /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system >/dev/null 2>&1

# --- 4g. ufw firewall (default deny inbound, allow outbound) ---
say "Configuring ufw"
if command -v ufw >/dev/null 2>&1; then
    sudo ufw default deny incoming  >/dev/null
    sudo ufw default allow outgoing >/dev/null
    if ! sudo ufw status | grep -q '^Status: active'; then
        sudo ufw --force enable >/dev/null
    fi
    sudo systemctl enable ufw.service >/dev/null 2>&1 || true
else
    warn "ufw not installed; skipping firewall config"
fi

# --- 5. Mask services we never want active ---
# Done BEFORE enabling, so when `systemctl enable NetworkManager.service`
# evaluates its `[Install] Also=` directive, wait-online is already masked
# and gets skipped instead of being re-enabled. Mask blocks Also=, dependency
# starts, and manual `systemctl start` (symlink to /dev/null).
# Idempotent: mask on an already-masked service is a no-op.
for svc in NetworkManager-wait-online.service; do
    if [[ "$(systemctl is-enabled "$svc" 2>/dev/null)" != "masked" ]]; then
        say "Masking $svc"
        sudo systemctl mask "$svc" >/dev/null
    fi
done

# --- 5b. Enable systemd services ---
say "Enabling systemd services (services/services.txt)"
services=$(read_pkglist "$REPO_DIR/services/services.txt")
if [[ -n "$services" ]]; then
    # shellcheck disable=SC2086
    sudo systemctl enable $services
else
    warn "services/services.txt empty or missing, skipping"
fi

# --- 6. Keyboard layout (LATAM) ---
say "Setting X11 keyboard layout to latam"
localectl set-x11-keymap latam pc105+inet "" terminate:ctrl_alt_bksp

# --- 7. Reload bspwm + sxhkd if running ---
if pgrep -x bspwm >/dev/null; then
    say "Reloading bspwm and sxhkd"
    bspc wm -r
    pkill -USR1 -x sxhkd 2>/dev/null || true

    say "Restarting lemonbar"
    pkill -x bar 2>/dev/null || true
    pkill -x bspwm-desktops 2>/dev/null || true
    pkill -x lemonbar 2>/dev/null || true
    rm -f /tmp/lemonbar-bar.lock
    setsid -f /lemonbar/bar </dev/null >/dev/null 2>&1
else
    warn "bspwm is not running; lemonbar will start on the next X session"
fi

say "Done. On a fresh machine: reboot so the enabled services start."
