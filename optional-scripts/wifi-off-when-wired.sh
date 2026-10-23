#!/usr/bin/env bash
# Turn the WiFi radio off while a cable is connected, and back on when it is
# not. Installs a NetworkManager dispatcher script that re-checks the state on
# every network event, then runs it once so it applies right away.
#
# If already installed, asks: y = reinstall (overwrite with the repo version),
# n = uninstall (remove it and turn WiFi back on), anything else cancels.
#
# Run from anywhere (asks for sudo itself):
#   bash ~/arch-config/optional-scripts/wifi-off-when-wired.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCRIPT_NAME="70-wifi-off-when-wired"
SCRIPT_SRC="$REPO_DIR/networkmanager/dispatcher.d/$SCRIPT_NAME"
SCRIPT_DST="/etc/NetworkManager/dispatcher.d/$SCRIPT_NAME"
LOG_TAG="wifi-off-when-wired"
DISPATCHER_UNIT="NetworkManager-dispatcher.service"

c_ok()   { printf '\033[1;32m[OK]\033[0m  %s\n' "$*"; }
c_skip() { printf '\033[1;33m[--]\033[0m  %s\n' "$*"; }
c_err()  { printf '\033[1;31m[!!]\033[0m  %s\n' "$*"; }
c_hdr()  { printf '\n\033[1;35m=== %s ===\033[0m\n' "$*"; }

# Returns the number of failed steps.
do_install() {
    local failed=0
    c_hdr "1. Dispatcher script"
    if [[ ! -f "$SCRIPT_SRC" ]]; then
        c_err "missing source: $SCRIPT_SRC"
        return 1
    fi
    # Dispatcher scripts must be root-owned and not group/world writable.
    if sudo install -Dm755 "$SCRIPT_SRC" "$SCRIPT_DST"; then
        c_ok "installed: $SCRIPT_DST"
    else
        c_err "could not install $SCRIPT_DST"
        return 1
    fi
    if ! systemctl is-enabled --quiet "$DISPATCHER_UNIT"; then
        c_err "$DISPATCHER_UNIT is not enabled; the script will never run"
        ((failed++))
    fi
    c_hdr "2. Apply now"
    if sudo "$SCRIPT_DST"; then
        c_ok "applied (WiFi radio: $(nmcli radio wifi))"
    else
        c_err "first run failed; see journalctl -t $LOG_TAG"
        ((failed++))
    fi
    return "$failed"
}

# Returns the number of failed steps.
do_uninstall() {
    c_hdr "Uninstall"
    if ! sudo rm -f "$SCRIPT_DST"; then
        c_err "could not remove $SCRIPT_DST"
        return 1
    fi
    c_ok "removed: $SCRIPT_DST"
    # Without the script nothing would ever turn the radio back on.
    if ! nmcli radio wifi on; then
        c_err "could not turn WiFi back on; run: nmcli radio wifi on"
        return 1
    fi
    c_ok "WiFi radio turned back on"
}

# Prints install / uninstall / cancel.
choose_action() {
    if [[ ! -e "$SCRIPT_DST" ]]; then
        echo install
        return
    fi
    local answer
    read -rp "Already installed. Reinstall it? [y = reinstall / n = uninstall] " answer
    case "$answer" in
        y|Y) echo install ;;
        n|N) echo uninstall ;;
        *)   echo cancel ;;
    esac
}

if ! command -v nmcli >/dev/null 2>&1; then
    c_skip "NetworkManager (nmcli) not installed — nothing to do"
    exit 0
fi

action=$(choose_action)
if [[ "$action" == cancel ]]; then
    c_skip "cancelled, nothing changed"
    exit 0
fi
if ! sudo -v; then
    c_err "sudo is required to continue."
    exit 1
fi

"do_$action"
exit $(($? > 0))
