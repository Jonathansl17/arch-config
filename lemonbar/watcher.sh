#!/bin/bash
# Listen to bspwm events and hide the bar whenever a window is fullscreen.
# Single-instance via flock: si ya hay un watcher corriendo, abortamos.
LOCK=/tmp/lemonbar-watcher.lock
exec 9>"$LOCK"
flock -n 9 || exit 0

sync_bar() {
    if [ -n "$(bspc query -N -n .fullscreen 2>/dev/null)" ]; then
        pkill -f '/lemonbar/bar.sh' 2>/dev/null
        pkill -x lemonbar 2>/dev/null
        bspc config top_padding 0 2>/dev/null
    else
        pgrep -x lemonbar >/dev/null || /lemonbar/start.sh
    fi
}

sync_bar
bspc subscribe node_state node_focus node_remove node_transfer desktop_focus | while read -r _; do
    sync_bar
done
