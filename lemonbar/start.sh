#!/bin/bash
# Launch bar.sh (kills previous instance). Serializado con flock para que
# toggle+watcher no ejecuten start.sh en paralelo.
LOCK=/tmp/lemonbar-start.lock
exec 9>"$LOCK"
flock 9

# Si ya hay un lemonbar corriendo (otro start.sh nos ganó), salir.
pgrep -x lemonbar >/dev/null && exit 0

pkill -f '/lemonbar/bar.sh' 2>/dev/null
pkill -x lemonbar 2>/dev/null

bspc config top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1

# Micro-espera para que el proceso aparezca en pgrep (sin bloquear).
sleep 0.1
