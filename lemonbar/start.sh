#!/bin/bash
# Launch bar.sh. The watcher guarantees no previous bar is running, so we
# skip pkill/waits here and spawn directly via setsid -f.
bspc config -m eDP top_padding 22 2>/dev/null
setsid -f /lemonbar/bar.sh </dev/null >/dev/null 2>&1
