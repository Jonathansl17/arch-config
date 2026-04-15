#!/bin/bash
# Manual toggle. The marker /tmp/lemonbar-hidden tells the watcher
# the user chose to hide the bar (so it will not auto-respawn).
MARKER=/tmp/lemonbar-hidden

if pgrep -x lemonbar >/dev/null; then
    pkill -f '/lemonbar/bar.sh' 2>/dev/null
    pkill -x lemonbar 2>/dev/null
    bspc config top_padding 0 2>/dev/null
    touch "$MARKER"
else
    rm -f "$MARKER"
    /lemonbar/start.sh
fi
