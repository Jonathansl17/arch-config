#!/usr/bin/env bash
# Instala paquetes (repos + AUR) y configs en ~/.config y ~.
# Idempotente: pacman --needed y yay --needed saltan lo ya instalado;
# los archivos con contenido identico se dejan en paz.
# Archivos existentes que difieren se respaldan a <archivo>.bak-<timestamp>.
#
# Uso: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# origen_relativo_al_repo  destino_absoluto
MAPPINGS=(
    "bspwm/bspwmrc            $HOME/.config/bspwm/bspwmrc"
    "sxhkd/sxhkdrc            $HOME/.config/sxhkd/sxhkdrc"
    "alacritty/alacritty.toml $HOME/.config/alacritty/alacritty.toml"
    "bash/bashrc              $HOME/.bashrc"
)

read_pkglist() {
    # Lee un archivo tipo pacman list: ignora comentarios (#...) y lineas vacias.
    local file="$1"
    [[ -f "$file" ]] || return 0
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$file"
}

install_file() {
    local src="$REPO_DIR/$1"
    local dst="$2"

    if [[ ! -f "$src" ]]; then
        warn "fuente no existe: $src (saltando)"
        return
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ -e "$dst" || -L "$dst" ]]; then
        if cmp -s "$src" "$dst"; then
            say "sin cambios: $dst"
            return
        fi
        local backup="${dst}.bak-${TIMESTAMP}"
        warn "backup: $dst -> $backup"
        mv "$dst" "$backup"
    fi

    cp "$src" "$dst"
    say "instalado: $dst"
}

# --- 0. Prerequisitos minimos (git para clonar AUR, base-devel para makepkg) ---
# Si clonaste el repo ya tenes git, pero si lo descargaste como zip puede faltar.
# base-devel hace falta para bootstrapear yay en el paso 2.
say "Verificando prerequisitos (git, base-devel)"
prereqs=()
command -v git     >/dev/null 2>&1 || prereqs+=(git)
command -v makepkg >/dev/null 2>&1 || prereqs+=(base-devel)
if (( ${#prereqs[@]} > 0 )); then
    warn "faltan: ${prereqs[*]} — instalando"
    sudo pacman -S --needed --noconfirm "${prereqs[@]}"
fi

# --- 1. Paquetes oficiales ---
say "Instalando paquetes oficiales (packages.txt)"
pkgs=$(read_pkglist "$REPO_DIR/packages.txt")
if [[ -n "$pkgs" ]]; then
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
else
    warn "packages.txt vacio o ausente, saltando"
fi

# --- 2. Bootstrap yay (si no esta) ---
if ! command -v yay >/dev/null 2>&1; then
    say "yay no encontrado, bootstrapeando desde AUR"
    command -v git     >/dev/null || die "git es requerido para bootstrapear yay"
    command -v makepkg >/dev/null || die "base-devel es requerido para bootstrapear yay"

    tmp=$(mktemp -d)
    git clone --depth=1 https://aur.archlinux.org/yay.git "$tmp/yay"
    ( cd "$tmp/yay" && makepkg -si --noconfirm )
    rm -rf "$tmp"
else
    say "yay ya instalado"
fi

# --- 3. Paquetes AUR ---
say "Instalando paquetes AUR (aur.txt)"
aur_pkgs=$(read_pkglist "$REPO_DIR/aur.txt")
if [[ -n "$aur_pkgs" ]]; then
    # shellcheck disable=SC2086
    yay -S --needed --noconfirm $aur_pkgs
else
    warn "aur.txt vacio o ausente, saltando"
fi

# --- 4. Configs ---
say "Instalando configs desde $REPO_DIR"
for entry in "${MAPPINGS[@]}"; do
    # shellcheck disable=SC2086
    install_file $entry
done

# bspwmrc debe ser ejecutable
chmod +x "$HOME/.config/bspwm/bspwmrc" 2>/dev/null || true

say "Listo. Si bspwm/sxhkd estan corriendo, recarga con:"
printf '    bspc wm -r && pkill -USR1 -x sxhkd\n'
