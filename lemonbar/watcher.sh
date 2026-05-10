#!/bin/bash
# Listen to bspwm events and hide the bar whenever a window is fullscreen.
# Single-instance via flock: bail out if another watcher is already running.
LOCK=/tmp/lemonbar-watcher.lock
exec 9>"$LOCK"
flock -n 9 || exit 0

# Detect the primary display dynamically — see bspwmrc for the same logic.
PRIMARY=$(xrandr --query | awk '/^(eDP|LVDS|DSI)[A-Za-z0-9-]* connected/ {print $1; exit}')
[ -z "$PRIMARY" ] && PRIMARY=$(xrandr --query | awk '/ connected/ {print $1; exit}')

sync_bar() {
    if [ -n "$(bspc query -N -d "$PRIMARY":focused -n .fullscreen 2>/dev/null)" ]; then
        # Fullscreen: hide the bar without killing it to preserve metrics state.
        xdo hide -n lemonbar 2>/dev/null
        bspc config -m "$PRIMARY" top_padding 0 2>/dev/null
    else
        if pgrep -x lemonbar >/dev/null; then
            # Bar is alive but hidden -> show it.
            xdo show -n lemonbar 2>/dev/null
            bspc config -m "$PRIMARY" top_padding 22 2>/dev/null
        else
            # Bar is not running (first launch) -> spawn it.
            /lemonbar/start.sh
        fi
    fi
}

sync_bar
bspc subscribe node_state node_focus node_remove node_transfer desktop_focus | while read -r _; do
    sync_bar
done
