#!/usr/bin/env bash
# Keep PCI WiFi cards alive across suspend/resume. Cards are detected by PCI
# class (0x0280xx, wireless controller); nothing is tied to one model.
# Installs a systemd-sleep hook (unload the WiFi driver before suspend, reload
# after) and a udev rule (d3cold_allowed=0 for WiFi cards, applied right away).
#
# If already installed, asks: y = reinstall (overwrite with the repo version),
# n = uninstall (remove both, restore d3cold_allowed=1), anything else cancels.
#
# Run from anywhere (asks for sudo itself):
#   bash ~/arch-config/optional-scripts/wifi-suspend-fix.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOOK_SRC="$REPO_DIR/system-sleep/wifi-reload"
HOOK_DST="/usr/lib/systemd/system-sleep/wifi-reload"
RULE_SRC="$REPO_DIR/udev/80-wifi-no-d3cold.rules"
RULE_DST="/etc/udev/rules.d/80-wifi-no-d3cold.rules"
HOOK_STATE="/run/wifi-reload.modules"
# Earlier rtw89-only versions of the same files.
LEGACY_FILES=(
    /usr/lib/systemd/system-sleep/rtw89
    /etc/udev/rules.d/80-rtw89-no-d3cold.rules
)
WIFI_CLASS_PREFIX="0x0280"
D3COLD_DEFAULT=1

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

# remove_file PATH — delete if present. Returns 1 on failure.
remove_file() {
    [[ -e "$1" ]] || return 0
    if ! sudo rm -f "$1"; then
        c_err "could not remove $1"
        return 1
    fi
    c_ok "removed: $1"
}

# install_file SRC DST MODE — overwrite DST with SRC. Returns 1 on failure.
install_file() {
    local src="$1" dst="$2" mode="$3"
    if [[ ! -f "$src" ]]; then
        c_err "missing source: $src"
        return 1
    fi
    if ! sudo install -Dm"$mode" "$src" "$dst"; then
        c_err "could not install $dst"
        return 1
    fi
    c_ok "installed: $dst"
}

# apply_udev CARD... — reload rules and re-run them on the given cards.
apply_udev() {
    if ! sudo udevadm control --reload || ! sudo udevadm trigger --action=add "$@"; then
        c_err "udev reload/trigger failed; takes effect on next boot"
        return 1
    fi
    c_ok "udev rules reloaded and applied"
}

# do_install CARD... — returns the number of failed steps.
do_install() {
    local failed=0 legacy
    for legacy in "${LEGACY_FILES[@]}"; do
        remove_file "$legacy" || ((failed++))
    done
    c_hdr "1. systemd-sleep hook (unload WiFi driver across suspend)"
    install_file "$HOOK_SRC" "$HOOK_DST" 755 || ((failed++))
    c_hdr "2. udev rule (no D3cold for WiFi cards)"
    install_file "$RULE_SRC" "$RULE_DST" 644 || ((failed++))
    apply_udev "$@" || ((failed++))
    return "$failed"
}

# do_uninstall CARD... — returns the number of failed steps.
do_uninstall() {
    local failed=0 file dev
    c_hdr "Uninstall"
    for file in "$HOOK_DST" "$RULE_DST" "$HOOK_STATE" "${LEGACY_FILES[@]}"; do
        remove_file "$file" || ((failed++))
    done
    apply_udev "$@" || ((failed++))
    # Removing the rule does not reset the live value; boot would.
    for dev in "$@"; do
        if echo "$D3COLD_DEFAULT" | sudo tee "$dev/d3cold_allowed" >/dev/null; then
            c_ok "${dev##*/} d3cold_allowed restored to $D3COLD_DEFAULT"
        else
            c_err "could not reset ${dev##*/} d3cold_allowed"
            ((failed++))
        fi
    done
    return "$failed"
}

# Prints install / uninstall / cancel.
choose_action() {
    if [[ ! -e "$HOOK_DST" && ! -e "$RULE_DST" ]]; then
        echo install
        return
    fi
    local answer
    read -rp "Fix already installed. Reinstall it? [y = reinstall / n = uninstall] " answer
    case "$answer" in
        y|Y) echo install ;;
        n|N) echo uninstall ;;
        *)   echo cancel ;;
    esac
}

c_hdr "0. Detect PCI WiFi cards"
mapfile -t cards < <(find_wifi_cards)
if [[ ${#cards[@]} -eq 0 ]]; then
    c_skip "no PCI WiFi card found (USB dongles are not covered) — nothing to do"
    exit 0
fi
for dev in "${cards[@]}"; do
    printf '      %s\n' "$(lspci -s "${dev##*/}")"
done

action=$(choose_action)
if [[ "$action" == cancel ]]; then
    c_skip "cancelled, nothing changed"
    exit 0
fi
if ! sudo -v; then
    c_err "sudo is required to continue."
    exit 1
fi

"do_$action" "${cards[@]}"
failed=$?
for dev in "${cards[@]}"; do
    printf '      %s d3cold_allowed=%s\n' "${dev##*/}" "$(cat "$dev/d3cold_allowed")"
done
exit $((failed > 0))
