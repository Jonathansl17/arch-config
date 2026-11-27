#!/usr/bin/env bash
# Fix the GRUB menu on Arch systems that boot a Unified Kernel Image (UKI).
# mkinitcpio builds only the UKI, so the "vmlinuz-linux + initramfs" entry that
# GRUB's 10_linux adds (first, and default) kernel-panics. This blocks that
# generator in pacman.conf (NoExtract), deletes it, and rebuilds grub.cfg so
# the UKI entry boots by default.
#
# Also offers to remove Windows boot leftovers (ESP files, firmware entries,
# os-prober scan) when no disk holds a Windows installation anymore.
#
# Idempotent. Run:
#   sudo bash ~/arch-config/optional-scripts/grub-uki-fix.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIRM_WORD="y"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

# shellcheck source=lib/disk-detect.sh
source "$SCRIPT_DIR/lib/disk-detect.sh"
# shellcheck source=lib/grub-config.sh
source "$SCRIPT_DIR/lib/grub-config.sh"
# shellcheck source=lib/windows-leftovers.sh
source "$SCRIPT_DIR/lib/windows-leftovers.sh"

# offer_windows_cleanup: ask before removing leftovers of an erased Windows.
offer_windows_cleanup() {
    local answer
    windows_leftovers_present || return 0
    if windows_installed; then
        echo "  [windows] Windows still installed on a disk; boot entries kept"
        return 0
    fi
    echo "  [windows] no disk holds Windows, but its boot files remain:"
    echo "            $WINDOWS_ESP_DIR and the firmware '$WINDOWS_EFI_LABEL' entry"
    read -rp "  Remove them? [$CONFIRM_WORD/N] " answer
    [[ "$answer" == "$CONFIRM_WORD" ]] || { echo "  [windows] kept"; return 0; }
    remove_windows_leftovers
}

if ! grub_available; then
    echo "GRUB not installed or $GRUB_CFG missing: nothing to do."
    exit 0
fi
if ! uki_present "$UKI_DIR"; then
    echo "No UKI in $UKI_DIR: 10_linux is your only Linux entry, nothing changed."
    exit 1
fi

offer_windows_cleanup || exit 1
regenerate_grub || exit 1
echo "Done. The UKI entry is now the default; reboot to check."
