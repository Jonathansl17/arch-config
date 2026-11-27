#!/usr/bin/env bash
# Show the GRUB menu at every boot, with a countdown before the default entry.
# Undoes grub-hide.sh. Rebuilds grub.cfg (never leaving the panicking vmlinuz
# entry first on UKI systems, see grub-uki-fix.sh).
#
# Idempotent. Run:
#   sudo bash ~/arch-config/optional-scripts/grub-show.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MENU_TIMEOUT=5
readonly MENU_STYLE="menu"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

# shellcheck source=lib/grub-config.sh
source "$SCRIPT_DIR/lib/grub-config.sh"

if ! grub_available; then
    echo "GRUB not installed or $GRUB_CFG missing: nothing to do."
    exit 0
fi
set_grub_menu "$MENU_TIMEOUT" "$MENU_STYLE" || exit 1
echo "GRUB menu shown for $MENU_TIMEOUT seconds at every boot."
