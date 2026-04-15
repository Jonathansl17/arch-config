#!/bin/bash
# Instala/actualiza lemonbar: copia scripts a /lemonbar, engancha
# autostart en bspwmrc, registra super+minus en sxhkdrc y reinicia
# el watcher de forma limpia.
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST=/lemonbar

# 0) Copiar scripts a /lemonbar (si no estoy ya parado ahí)
if [ "$SRC_DIR" != "$DEST" ]; then
    if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
        sudo mkdir -p "$DEST"
        sudo chown "$USER:$USER" "$DEST"
    fi
    cp "$SRC_DIR"/bar.sh "$SRC_DIR"/start.sh "$SRC_DIR"/toggle.sh \
       "$SRC_DIR"/watcher.sh \
       "$SRC_DIR"/install.sh "$SRC_DIR"/uninstall.sh "$DEST"/
fi

# 1) Paquete (AUR) — cc (clang) rompe con -march=x86-64, forzamos gcc
if ! pacman -Q lemonbar-xft-git >/dev/null 2>&1; then
    CC=gcc yay -S --noconfirm lemonbar-xft-git
fi

# 2) Permisos
chmod +x "$DEST"/bar.sh "$DEST"/start.sh "$DEST"/toggle.sh "$DEST"/watcher.sh

# 3) bspwmrc: autostart
BSPWMRC="$HOME/.config/bspwm/bspwmrc"
if [ -f "$BSPWMRC" ] && ! grep -q "# LEMONBAR-START" "$BSPWMRC"; then
    cat >> "$BSPWMRC" <<'EOF'

# LEMONBAR-START
/lemonbar/watcher.sh &
# LEMONBAR-END
EOF
fi

# 4) sxhkdrc: super + minus -> toggle
SXHKDRC="$HOME/.config/sxhkd/sxhkdrc"
if [ -f "$SXHKDRC" ] && ! grep -q "# LEMONBAR-TOGGLE" "$SXHKDRC"; then
    cat >> "$SXHKDRC" <<'EOF'

# LEMONBAR-TOGGLE
super + minus
    /lemonbar/toggle.sh
EOF
fi

# 5) Recargar sxhkd (SIGUSR1 re-lee el rc sin matarlo)
pkill -USR1 -x sxhkd 2>/dev/null || true

# 6) Reinicio limpio del watcher + barra
pkill -f '/lemonbar/watcher.sh' 2>/dev/null || true
pkill -f '/lemonbar/bar.sh' 2>/dev/null || true
pkill -x lemonbar 2>/dev/null || true
rm -f /tmp/lemonbar-hidden /tmp/lemonbar.lock
sleep 0.3
setsid -f /lemonbar/watcher.sh </dev/null >/dev/null 2>&1

echo "Listo. Toggle con Super + minus."
