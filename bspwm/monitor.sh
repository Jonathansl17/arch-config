#!/bin/sh

usage() {
    echo "uso: monitor --left | --right" >&2
    exit 1
}

case "$1" in
    --left)  direction="left-of" ;;
    --right) direction="right-of" ;;
    *) usage ;;
esac

# Reposition any connected HDMI-* relative to eDP and keep the same
# desktop split used during bspwm startup.
hdmi=$(xrandr --query | awk '/^HDMI-[0-9-]+ connected/ {print $1; exit}')
[ -z "$hdmi" ] && exit 0

# Preferred mode + max refresh rate on the external monitor. The first
# mode line in xrandr is the preferred resolution; we pick the highest
# refresh rate available for it. --mode+--rate must be explicit because
# --auto alone keeps the "+" preferred rate and ignores --rate on some
# drivers.
mode_line=$(xrandr | sed -n "/^$hdmi connected/,/^[^ ]/{/^ /p}" | head -1)
hdmi_mode=$(echo "$mode_line" | awk '{print $1}')
hdmi_rate=$(echo "$mode_line" | grep -oP '[0-9]+\.[0-9]+' \
    | sort -t. -k1,1nr -k2,2nr | head -1)

xrandr --output eDP --primary --auto \
       --output "$hdmi" "--$direction" eDP \
       ${hdmi_mode:+--mode "$hdmi_mode"} \
       ${hdmi_rate:+--rate "$hdmi_rate"}

bspc monitor eDP     -d 1 2 3 4 5
bspc monitor "$hdmi" -d 6 7 8 9 10

/lemonbar/start.sh
