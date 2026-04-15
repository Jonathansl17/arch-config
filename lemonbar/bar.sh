#!/bin/bash
# Feeder optimizado: lecturas directas de /proc y /sys, builtins bash.
# Event-driven: solo despierta cuando toca refrescar alguna métrica.

D=""; B="no-bat"; T="--"; W="disconnected"; R="--"
cpu_usage="--"; cpu_ghz="-.-"

HWMON_TEMP=/sys/class/hwmon/hwmon6/temp1_input   # k10temp Tctl
BAT_CAP=/sys/class/power_supply/BAT1/capacity
BAT_STAT=/sys/class/power_supply/BAT1/status

# Primera interfaz wl* (resuelto una vez al arrancar).
WIFI_IFACE=""
for _d in /sys/class/net/wl*; do
    [[ -d $_d ]] && WIFI_IFACE=${_d##*/} && break
done
WIFI_OPERSTATE="/sys/class/net/$WIFI_IFACE/operstate"
WIFI_CACHE=/tmp/lemonbar-wifi

prev_total=0; prev_idle=0
# Solo /proc/stat → %CPU. <1 ms. Se llama cada int_cpu.
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

# GHz promedio desde /proc/cpuinfo. ~50 ms en 12 cores. Se llama cada int_ghz.
read_ghz() {
    local sum=0 nc=0 mhz line
    while IFS= read -r line; do
        if [[ $line == "cpu MHz"* ]]; then
            mhz=${line##*: }
            mhz=${mhz%.*}
            sum=$((sum + mhz))
            ((nc++))
        fi
    done < /proc/cpuinfo
    if (( nc > 0 )); then
        local avg=$((sum * 10 / nc / 1000))
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
    # Link check instantáneo por /sys. Si no está "up", no se consulta nmcli.
    local state=""
    [[ -r $WIFI_OPERSTATE ]] && read -r state < "$WIFI_OPERSTATE"
    if [[ $state != up ]]; then
        W="disconnected"
        return
    fi
    local active
    active=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    W=${active:-disconnected}
    [[ $W != disconnected ]] && printf '%s\n' "$W" > "$WIFI_CACHE"
}

# Primer render: sin bloquear en nmcli. Si el link está up y hay cache, la uso;
# si no, "disconnected". La próxima iteración (int_wifi) ya refresca real.
prime_wifi() {
    local state=""
    [[ -r $WIFI_OPERSTATE ]] && read -r state < "$WIFI_OPERSTATE"
    if [[ $state == up && -r $WIFI_CACHE ]]; then
        read -r W < "$WIFI_CACHE"
    else
        W="disconnected"
    fi
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

# Intervalos (s): CPU=2, GHZ=5, RAM=3, TEMP=5, WIFI=15, BAT=30, DATE=60
int_cpu=2; int_ghz=5; int_ram=3; int_temp=5; int_wifi=15; int_bat=30; int_date=60

# Prime baseline de /proc/stat (sin el parse caro de cpuinfo).
read_cpu
prime_wifi  # cache hit, no bloquea en nmcli

# now = epoch real (builtin bash, sin fork). Evita derivas frente a un contador.
printf -v now '%(%s)T' -1
next_cpu=$now; next_ram=$now; next_temp=$now
next_bat=$now; next_date=$now
# Diferimos los reads caros para que el primer frame salga ya.
next_ghz=$((  now + int_ghz  ))
next_wifi=$(( now + int_wifi ))

while :; do
    (( now >= next_cpu  )) && { read_cpu;  next_cpu=$((  now + int_cpu  )); }
    (( now >= next_ghz  )) && { read_ghz;  next_ghz=$((  now + int_ghz  )); }
    (( now >= next_ram  )) && { read_ram;  next_ram=$((  now + int_ram  )); }
    (( now >= next_temp )) && { read_temp; next_temp=$(( now + int_temp )); }
    (( now >= next_wifi )) && { read_wifi; next_wifi=$(( now + int_wifi )); }
    (( now >= next_bat  )) && { read_bat;  next_bat=$((  now + int_bat  )); }
    (( now >= next_date )) && { read_date; next_date=$(( now + int_date )); }

    printf '%%{c}%s  |  CPU %s%% %sGHz %s  |  RAM %sGB  |  WIFI %s  |  BAT %s\n' \
        "$D" "$cpu_usage" "$cpu_ghz" "$T" "$R" "$W" "$B"

    nxt=$next_cpu
    (( next_ghz  < nxt )) && nxt=$next_ghz
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
