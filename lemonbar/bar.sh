#!/bin/bash
# Feeder optimizado: lecturas directas de /proc y /sys, builtins bash.
# Event-driven: solo despierta cuando toca refrescar alguna métrica.

D=""; B="no-bat"; T="--"; W="disconnected"; R="--"
cpu_usage="--"; cpu_ghz="-.-"; DESKTOPS=""

# Parsea una línea de bspc subscribe report → DESKTOPS formateado.
# Formato: WMeDP:O1:f2:o3:... (O/F/U = focused, o/f/u = no focused)
parse_report() {
    local report="$1" out="" IFS=':'
    for token in $report; do
        case $token in
            W*|L*|T*|G*) continue ;;  # skip monitor/layout/state tokens
        esac
        local flag=${token:0:1} name=${token:1}
        case $flag in
            O|F|U) out+="%{F#FF000000}%{B#FFFFFFFF} $name %{B-}%{F-}" ;;
            o|f|u) out+="%{F#88FFFFFF} $name %{F-}" ;;
        esac
    done
    DESKTOPS="$out"
}

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

# GHz real desde cpuinfo_avg_freq (CPPC HW feedback, no la freq "deseada").
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
# Solo establece prev_total/prev_idle; reseteamos cpu_usage para no
# mostrar el promedio-desde-boot como si fuera el uso actual.
read_cpu; cpu_usage="--"
prime_wifi  # cache hit, no bloquea en nmcli

# now = epoch real (builtin bash, sin fork). Evita derivas frente a un contador.
printf -v now '%(%s)T' -1
next_ram=$now; next_temp=$now
next_bat=$now; next_date=$now
# Diferimos los reads caros para que el primer frame salga ya.
next_ghz=$((  now + int_ghz  ))
next_wifi=$(( now + int_wifi ))
# Diferimos el primer %CPU: necesita un delta real de /proc/stat contra el
# prime para no dar un valor basura (p.ej. 100% por 1 jiffy de ruido).
next_cpu=$((  now + int_cpu  ))
first_run=1

render() {
    printf '%%{l} %s %%{c}%s  |  CPU %s%% %sGHz %s  |  RAM %sGB  |  WIFI %s  |  BAT %s\n' \
        "$DESKTOPS" "$D" "$cpu_usage" "$cpu_ghz" "$T" "$R" "$W" "$B"
}

# Dos productores → un pipe (fd 3).
# bspc subscribe report: estado de escritorios en cada evento bspwm.
# Ticker 1s: chequeo de métricas + report de fallback por si subscribe pierde un evento.
exec 3< <(
    bspc subscribe report &
    while :; do sleep 1; bspc subscribe report -c 1; done
)
trap "kill 0" EXIT

# Prime inicial.
parse_report "$(bspc subscribe report -c 1)"
render

if (( first_run )); then
    first_run=0
    read_ghz
    render
fi

while read -r ev <&3; do
    # Si es un report de bspc (empieza con W), parsear escritorios.
    [[ $ev == W* ]] && parse_report "$ev"

    printf -v now '%(%s)T' -1
    (( now >= next_cpu  )) && { read_cpu;  next_cpu=$((  now + int_cpu  )); }
    (( now >= next_ghz  )) && { read_ghz;  next_ghz=$((  now + int_ghz  )); }
    (( now >= next_ram  )) && { read_ram;  next_ram=$((  now + int_ram  )); }
    (( now >= next_temp )) && { read_temp; next_temp=$(( now + int_temp )); }
    (( now >= next_wifi )) && { read_wifi; next_wifi=$(( now + int_wifi )); }
    (( now >= next_bat  )) && { read_bat;  next_bat=$((  now + int_bat  )); }
    (( now >= next_date )) && { read_date; next_date=$(( now + int_date )); }
    render
done | lemonbar -p -d -g x22 -B "#CC000000" -F "#FFFFFFFF" -f "monospace:size=12"
