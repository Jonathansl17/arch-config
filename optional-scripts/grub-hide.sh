#!/usr/bin/env bash
# Hide the GRUB menu and boot the default entry right away.
# Hold Shift or press Esc while GRUB starts to get the menu once; undo with
# grub-show.sh. Rebuilds grub.cfg (never leaving the panicking vmlinuz entry
# first on UKI systems, see grub-uki-fix.sh).
#
# Idempotent. Run:
#   sudo bash ~/arch-config/optional-scripts/grub-hide.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HIDDEN_TIMEOUT=0
readonly HIDDEN_STYLE="hidden"

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
set_grub_menu "$HIDDEN_TIMEOUT" "$HIDDEN_STYLE" || exit 1
echo "GRUB menu hidden. Hold Shift or press Esc at boot to show it once."
