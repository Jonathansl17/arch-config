#!/bin/bash
# Launch bar.sh. El watcher garantiza que no hay una barra previa, así que
# no hacemos pkill ni esperas aquí: spawn directo vía setsid -f.
bspc config -m eDP top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
