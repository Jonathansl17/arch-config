#!/bin/bash
# Launch bar.sh (kills previous instance).
pkill -f '/lemonbar/bar.sh' 2>/dev/null
pkill -x lemonbar 2>/dev/null
sleep 0.2
bspc config top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
