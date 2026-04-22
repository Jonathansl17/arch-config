#!/bin/bash
# Relaunch bar.sh safely: clear previous instances first so manual runs don't
# stack multiple bars on top of each other.
primary_monitor() {
    xrandr --query | awk '
        / connected primary / { print $1; exit }
        /^eDP(-[0-9]+)? connected/ { fallback=$1 }
        END { if (fallback != "") print fallback }
    '
}

pkill -f '/lemonbar/bar.sh' 2>/dev/null || true
pkill -x bspwm-desktops 2>/dev/null || true
pkill -x lemonbar 2>/dev/null || true
sleep 0.1
monitor=$(primary_monitor)
[ -n "$monitor" ] && bspc config -m "$monitor" top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
