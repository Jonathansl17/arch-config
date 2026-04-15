#!/bin/bash
# Listen to bspwm events and hide the bar whenever a window is fullscreen.
MARKER=/tmp/lemonbar-hidden

sync_bar() {
    if [ -n "$(bspc query -N -n .fullscreen 2>/dev/null)" ]; then
        pkill -f '/lemonbar/bar.sh' 2>/dev/null
        pkill -x lemonbar 2>/dev/null
        bspc config top_padding 0 2>/dev/null
    elif [ ! -f "$MARKER" ]; then
        pgrep -x lemonbar >/dev/null || /lemonbar/start.sh
    fi
}

sync_bar
bspc subscribe node_state node_focus node_remove node_transfer desktop_focus | while read -r _; do
    sync_bar
done
