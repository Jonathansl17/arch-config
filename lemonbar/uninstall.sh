#!/bin/bash
# Desinstala todo: mata la barra, remueve hooks de bspwmrc/sxhkdrc,
# desinstala el paquete y borra /barra.

# 1) Matar procesos
pkill -f '/barra/watcher.sh' 2>/dev/null
pkill -f '/barra/bar.sh' 2>/dev/null
pkill -x lemonbar 2>/dev/null
rm -f /tmp/barra-hidden

# 2) bspwmrc: quitar bloque
BSPWMRC="$HOME/.config/bspwm/bspwmrc"
[ -f "$BSPWMRC" ] && sed -i '/# BARRA-START/,/# BARRA-END/d' "$BSPWMRC"

# 3) sxhkdrc: quitar keybind (bloque de 3 lineas: comentario, binding, accion)
SXHKDRC="$HOME/.config/sxhkd/sxhkdrc"
if [ -f "$SXHKDRC" ]; then
    sed -i '/# BARRA-TOGGLE/,/\/barra\/toggle\.sh/d' "$SXHKDRC"
    pkill -USR1 -x sxhkd 2>/dev/null || true
fi

# 4) Reset padding
bspc config top_padding 0 2>/dev/null || true

# 5) Desinstalar paquete (AUR)
if pacman -Q lemonbar-xft-git >/dev/null 2>&1; then
    yay -Rns --noconfirm lemonbar-xft-git || true
fi

# 6) Borrar /barra
sudo rm -rf /barra

echo "Desinstalado."
