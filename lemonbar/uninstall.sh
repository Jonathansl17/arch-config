#!/bin/bash
# Desinstala todo: mata la barra, remueve hook de bspwmrc,
# desinstala el paquete y borra /lemonbar.

# 1) Matar procesos
pkill -f '/lemonbar/watcher.sh' 2>/dev/null
pkill -f '/lemonbar/bar.sh' 2>/dev/null
pkill -x lemonbar 2>/dev/null
rm -f /tmp/lemonbar-watcher.lock /tmp/lemonbar-wifi

# 2) bspwmrc: quitar bloque
BSPWMRC="$HOME/.config/bspwm/bspwmrc"
[ -f "$BSPWMRC" ] && sed -i '/# LEMONBAR-START/,/# LEMONBAR-END/d' "$BSPWMRC"

# 3) Reset padding
bspc config top_padding 0 2>/dev/null || true

# 4) Desinstalar paquete (AUR)
if pacman -Q lemonbar-xft-git >/dev/null 2>&1; then
    yay -Rns --noconfirm lemonbar-xft-git || true
fi

# 5) Borrar /lemonbar
sudo rm -rf /lemonbar

echo "Desinstalado."
