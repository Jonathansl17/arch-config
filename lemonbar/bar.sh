#!/bin/bash
# Optimized feeder: direct reads from /proc and /sys, bash builtins only.
# Event-driven: wakes up only when a metric is due for refresh.

D=""; T="--"; R="--"
cpu_usage="--"; cpu_ghz="-.-"; DESKTOPS=""

HWMON_TEMP=/sys/class/hwmon/hwmon6/temp1_input   # k10temp Tctl

prev_total=0; prev_idle=0
# /proc/stat -> %CPU. <1 ms. Called every int_cpu seconds.
read_cpu() {
    local _ u n s i io ir sirq st
    read -r _ u n s i io ir sirq st _ < /proc/stat
    local total=$((u + n + s + i + io + ir + sirq + st))
    local dt=$((total - prev_total))
    local di=$((i - prev_idle))
    prev_total=$total; prev_idle=$i
    cpu_usage=0
    (( dt > 0 )) && cpu_usage=$(( (100 * (dt - di)) / dt ))
}

# Real GHz from cpuinfo_avg_freq (CPPC HW feedback, not the "requested" freq).
read_ghz() {
    local sum=0 nc=0 freq
    for f in /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_avg_freq; do
        [[ -r $f ]] || continue
        read -r freq < "$f"
        sum=$((sum + freq))
        ((nc++))
    done
    if (( nc > 0 )); then
        local avg=$(( sum * 10 / nc / 1000000 ))
        cpu_ghz="$((avg / 10)).$((avg % 10))"
    fi
}

read_ram() {
    local line key val t=0 a=0
    while IFS=: read -r key val; do
        val=${val// /}; val=${val%kB}
        case $key in
            MemTotal) t=$val ;;
            MemAvailable) a=$val; break ;;
        esac
    done < /proc/meminfo
    local used=$((t - a))
    # GB with 1 decimal: (kB * 10) / 1048576 -> .1 GB
    local u10=$(( used * 10 / 1048576 ))
    local t10=$(( t    * 10 / 1048576 ))
    R="$((u10/10)).$((u10%10))/$((t10/10)).$((t10%10))"
}

read_temp() {
    local raw
    if [[ -r $HWMON_TEMP ]]; then
        read -r raw < "$HWMON_TEMP"
        T="$((raw / 1000))°C"
    else
        T="--"
    fi
}

read_date() {
    printf -v D '%(%a %d %b %I:%M %p)T' -1
}

# Refresh intervals (s): CPU=2, GHZ=5, RAM=3, TEMP=5, DATE=60
int_cpu=2; int_ghz=5; int_ram=3; int_temp=5; int_date=60

# Prime baseline from /proc/stat (skip the expensive cpuinfo parse).
# Sets prev_total/prev_idle; cpu_usage is reset so we don't render the
# since-boot average as if it were the current usage.
read_cpu; cpu_usage="--"

# now = real epoch (bash builtin, no fork). Avoids drift versus a counter.
printf -v now '%(%s)T' -1
next_ram=$now; next_temp=$now
next_date=$now
# Defer the expensive reads so the first frame renders immediately.
next_ghz=$((  now + int_ghz  ))
# Defer the first %CPU: needs a real /proc/stat delta against the prime,
# otherwise we'd print garbage (e.g. 100% from a 1-jiffy blip).
next_cpu=$((  now + int_cpu  ))

render() {
    printf '%%{l} %s %%{c}%s  |  CPU %s%% %sGHz %s  |  RAM %sGB\n' \
        "$DESKTOPS" "$D" "$cpu_usage" "$cpu_ghz" "$T" "$R"
}

# Confine the bar to the primary monitor, otherwise lemonbar spans the whole
# root window and leaks a 22px strip onto secondary monitors.
# xrandr row 0 is always the primary; field 3 is "W/mm x H/mm+X+Y".
read -r _ _ PRIMARY_GEOM _ < <(xrandr --listmonitors | awk '/^ 0:/')
PRIMARY_W=${PRIMARY_GEOM%%/*}
PRIMARY_OFF=${PRIMARY_GEOM#*+}
PRIMARY_X=${PRIMARY_OFF%+*}
PRIMARY_Y=${PRIMARY_OFF#*+}
BAR_GEOM="${PRIMARY_W}x22+${PRIMARY_X}+${PRIMARY_Y}"

# FIFO: two independent producers, atomic writes (< PIPE_BUF).
BAR_FIFO=/tmp/lemonbar-fifo.$$
mkfifo "$BAR_FIFO"
exec 3<>"$BAR_FIFO"
trap 'kill 0; rm -f "$BAR_FIFO"' EXIT

# Producer 1: bspwm-desktops talks directly to the bspwm socket (no bspc).
# Each line is a preformatted desktops string for lemonbar.
/lemonbar/bspwm-desktops > "$BAR_FIFO" &
# Producer 2: 1s tick for metric refresh.
(while :; do sleep 1; printf 'T\n'; done) > "$BAR_FIFO" &

{
    read_ghz
    render

    while read -r ev <&3; do
        # Lines from the C binary = formatted desktops. "T" = metrics tick.
        [[ $ev != T ]] && DESKTOPS="$ev"

        printf -v now '%(%s)T' -1
        (( now >= next_cpu  )) && { read_cpu;  next_cpu=$((  now + int_cpu  )); }
        (( now >= next_ghz  )) && { read_ghz;  next_ghz=$((  now + int_ghz  )); }
        (( now >= next_ram  )) && { read_ram;  next_ram=$((  now + int_ram  )); }
        (( now >= next_temp )) && { read_temp; next_temp=$(( now + int_temp )); }
        (( now >= next_date )) && { read_date; next_date=$(( now + int_date )); }
        render
    done
} | lemonbar -p -d -g "$BAR_GEOM" -B "#CC000000" -F "#FFFFFFFF" -f "monospace:size=12"
