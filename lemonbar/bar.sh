#!/bin/bash
# Feeder: date | CPU temp | WiFi SSID | battery, centered, single line.
while :; do
    D=$(date '+%a %d %b %I:%M:%S %p')
    if [ -r /sys/class/power_supply/BAT1/capacity ]; then
        B="$(cat /sys/class/power_supply/BAT1/capacity)% $(cat /sys/class/power_supply/BAT1/status)"
    else
        B="no-bat"
    fi
    T=$(sensors k10temp-pci-00c3 2>/dev/null | awk '/^Tctl:/ {print $2; exit}')
    [ -z "$T" ] && T="--"
    W=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    [ -z "$W" ] && W="disconnected"
    printf '%%{c}%s  |  CPU %s  |  WIFI %s  |  BAT %s\n' "$D" "$T" "$W" "$B"
    sleep 1
done | lemonbar -p -d -g x22 -B "#CC000000" -F "#FFFFFFFF" -f "monospace:size=12"
