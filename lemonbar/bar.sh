#!/bin/bash
# Feeder optimizado: lecturas directas de /proc y /sys, builtins bash.
# Event-driven: solo despierta cuando toca refrescar alguna métrica.

D=""; B="no-bat"; T="--"; W="disconnected"; R="--"; C="--"

HWMON_TEMP=/sys/class/hwmon/hwmon6/temp1_input   # k10temp Tctl
BAT_CAP=/sys/class/power_supply/BAT1/capacity
BAT_STAT=/sys/class/power_supply/BAT1/status

prev_total=0; prev_idle=0
read_cpu() {
    local _ u n s i io ir sirq st
    read -r _ u n s i io ir sirq st _ < /proc/stat
    local total=$((u + n + s + i + io + ir + sirq + st))
    local dt=$((total - prev_total))
    local di=$((i - prev_idle))
    prev_total=$total; prev_idle=$i
    local usage=0
    (( dt > 0 )) && usage=$(( (100 * (dt - di)) / dt ))

    # GHz promedio (pure bash: sum cpu MHz lines / n / 1000)
    local sum=0 nc=0 mhz line
    while IFS= read -r line; do
        if [[ $line == "cpu MHz"* ]]; then
            mhz=${line##*: }
            mhz=${mhz%.*}
            sum=$((sum + mhz))
            ((nc++))
        fi
    done < /proc/cpuinfo
    local ghz_int=0 ghz_dec=0
    if (( nc > 0 )); then
        local avg=$((sum * 10 / nc / 1000))
        ghz_int=$((avg / 10)); ghz_dec=$((avg % 10))
    fi
    C="${usage}% ${ghz_int}.${ghz_dec}GHz"
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
    # GB con 1 decimal: (kB * 10) / 1048576 → .1 GB
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

read_wifi() {
    local active
    active=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    W=${active:-disconnected}
}

read_bat() {
    if [[ -r $BAT_CAP ]]; then
        local cap st
        read -r cap < "$BAT_CAP"
        read -r st  < "$BAT_STAT"
        B="${cap}% ${st}"
    else
        B="no-bat"
    fi
}

read_date() {
    printf -v D '%(%a %d %b %I:%M %p)T' -1
}

# Intervalos (s): CPU=2, RAM=3, TEMP=5, WIFI=15, BAT=30, DATE=60
int_cpu=2; int_ram=3; int_temp=5; int_wifi=15; int_bat=30; int_date=60
next_cpu=0; next_ram=0; next_temp=0; next_wifi=0; next_bat=0; next_date=0

read_cpu  # prime counters (primera llamada basura, se sobrescribe enseguida)

# now = epoch real (builtin bash, sin fork). Evita derivas frente a un contador.
printf -v now '%(%s)T' -1
next_cpu=$now; next_ram=$now; next_temp=$now
next_wifi=$now; next_bat=$now; next_date=$now

while :; do
    (( now >= next_cpu  )) && { read_cpu;  next_cpu=$((  now + int_cpu  )); }
    (( now >= next_ram  )) && { read_ram;  next_ram=$((  now + int_ram  )); }
    (( now >= next_temp )) && { read_temp; next_temp=$(( now + int_temp )); }
    (( now >= next_wifi )) && { read_wifi; next_wifi=$(( now + int_wifi )); }
    (( now >= next_bat  )) && { read_bat;  next_bat=$((  now + int_bat  )); }
    (( now >= next_date )) && { read_date; next_date=$(( now + int_date )); }

    printf '%%{c}%s  |  CPU %s %s  |  RAM %sGB  |  WIFI %s  |  BAT %s\n' \
        "$D" "$C" "$T" "$R" "$W" "$B"

    nxt=$next_cpu
    (( next_ram  < nxt )) && nxt=$next_ram
    (( next_temp < nxt )) && nxt=$next_temp
    (( next_wifi < nxt )) && nxt=$next_wifi
    (( next_bat  < nxt )) && nxt=$next_bat
    (( next_date < nxt )) && nxt=$next_date

    printf -v now '%(%s)T' -1
    delay=$(( nxt - now ))
    (( delay > 0 )) && sleep "$delay"
    printf -v now '%(%s)T' -1
done | lemonbar -p -d -g x22 -B "#CC000000" -F "#FFFFFFFF" -f "monospace:size=12"
