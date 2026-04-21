#!/bin/bash
# Relaunch bar.sh safely: clear previous instances first so manual runs don't
# stack multiple bars on top of each other.
pkill -f '/lemonbar/bar.sh' 2>/dev/null || true
pkill -x bspwm-desktops 2>/dev/null || true
pkill -x lemonbar 2>/dev/null || true
sleep 0.1
bspc config -m eDP top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
