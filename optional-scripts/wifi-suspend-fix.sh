#!/usr/bin/env bash
# Keep PCI WiFi cards alive across suspend/resume. Detects the cards on this
# machine by PCI class (0x0280xx, wireless controller); nothing is tied to one
# model. Idempotent: each file is only copied when it differs.
#
# Sections:
#   0. Detect PCI WiFi cards (exits cleanly if there are none)
#   1. systemd-sleep hook: unload the WiFi driver before suspend, reload after
#   2. udev rule: d3cold_allowed=0 for WiFi cards (also applied right away)
#
# Run from anywhere:
#   bash ~/arch-config/optional-scripts/wifi-suspend-fix.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOOK_SRC="$REPO_DIR/system-sleep/wifi-reload"
HOOK_DST="/usr/lib/systemd/system-sleep/wifi-reload"
RULE_SRC="$REPO_DIR/udev/80-wifi-no-d3cold.rules"
RULE_DST="/etc/udev/rules.d/80-wifi-no-d3cold.rules"
# Earlier rtw89-only versions of the same files.
LEGACY_FILES=(
    /usr/lib/systemd/system-sleep/rtw89
    /etc/udev/rules.d/80-rtw89-no-d3cold.rules
)
WIFI_CLASS_PREFIX="0x0280"

c_ok()   { printf '\033[1;32m[OK]\033[0m  %s\n' "$*"; }
c_skip() { printf '\033[1;33m[--]\033[0m  %s\n' "$*"; }
c_err()  { printf '\033[1;31m[!!]\033[0m  %s\n' "$*"; }
c_hdr()  { printf '\n\033[1;35m=== %s ===\033[0m\n' "$*"; }

# Prints the sysfs path of every PCI WiFi card, one per line.
find_wifi_cards() {
    local dev
    for dev in /sys/bus/pci/devices/*; do
        [[ "$(cat "$dev/class")" == "$WIFI_CLASS_PREFIX"* ]] && echo "$dev"
    done
}

# install_file SRC DST MODE — copy only when missing or different.
# Returns 0 when it copied, 1 when already up to date, 2 on failure.
install_file() {
    local src="$1" dst="$2" mode="$3"
    if [[ ! -f "$src" ]]; then
        c_err "missing source: $src"
        return 2
    fi
    if sudo cmp -s "$src" "$dst"; then
        c_skip "already installed: $dst"
        return 1
    fi
    if ! sudo install -Dm"$mode" "$src" "$dst"; then
        c_err "could not install $dst"
        return 2
    fi
    c_ok "installed: $dst"
    return 0
}

#-----------------------------------------------------------------
c_hdr "0. Detect PCI WiFi cards"
#-----------------------------------------------------------------
mapfile -t cards < <(find_wifi_cards)
if [[ ${#cards[@]} -eq 0 ]]; then
    c_skip "no PCI WiFi card found (USB dongles are not covered) — nothing to do"
    exit 0
fi
for dev in "${cards[@]}"; do
    printf '      %s\n' "$(lspci -s "${dev##*/}")"
done

# Pre-authorise sudo so prompts don't interrupt mid-run.
if ! sudo -v; then
    c_err "sudo is required to continue."
    exit 1
fi

failed=0

for legacy in "${LEGACY_FILES[@]}"; do
    [[ -e "$legacy" ]] || continue
    if sudo rm -f "$legacy"; then
        c_ok "removed old file: $legacy"
    else
        c_err "could not remove old file: $legacy"
        failed=1
    fi
done

#-----------------------------------------------------------------
c_hdr "1. systemd-sleep hook (unload WiFi driver across suspend)"
#-----------------------------------------------------------------
install_file "$HOOK_SRC" "$HOOK_DST" 755
[[ $? -eq 2 ]] && failed=1

#-----------------------------------------------------------------
c_hdr "2. udev rule (no D3cold for WiFi cards)"
#-----------------------------------------------------------------
install_file "$RULE_SRC" "$RULE_DST" 644
[[ $? -eq 2 ]] && failed=1
if sudo udevadm control --reload && sudo udevadm trigger --action=add "${cards[@]}"; then
    c_ok "udev rules reloaded and applied"
else
    c_err "udev reload/trigger failed; the rule applies on next boot"
    failed=1
fi
for dev in "${cards[@]}"; do
    printf '      %s d3cold_allowed=%s\n' "${dev##*/}" "$(cat "$dev/d3cold_allowed")"
done

exit "$failed"
