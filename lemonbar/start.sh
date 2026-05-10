#!/bin/bash
# Launch bar.sh. The watcher guarantees no previous bar is running, so we
# skip pkill/waits here and spawn directly via setsid -f.

# Detect the primary display dynamically — same logic as bspwmrc/watcher.sh.
PRIMARY=$(xrandr --query | awk '/^(eDP|LVDS|DSI)[A-Za-z0-9-]* connected/ {print $1; exit}')
[ -z "$PRIMARY" ] && PRIMARY=$(xrandr --query | awk '/ connected/ {print $1; exit}')

bspc config -m "$PRIMARY" top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
