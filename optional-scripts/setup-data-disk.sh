#!/usr/bin/env bash
# Interactive setup for the /mnt/data disk.
# Reuses an existing ext4 LABEL=data partition when one exists. Otherwise lists
# spare disks, names any Windows/macOS/Linux found on them, and wipes the chosen
# one only after the user types DESTROY. Never touches the disk holding /,
# /home or /boot. Adds a nofail fstab entry and mounts the disk.
#
# Run:
#   sudo bash ~/arch-config/optional-scripts/setup-data-disk.sh

set -euo pipefail

DATA="/mnt/data"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

# shellcheck source=lib/disk-detect.sh
source "$SCRIPT_DIR/lib/disk-detect.sh"
# shellcheck source=lib/disk-format.sh
source "$SCRIPT_DIR/lib/disk-format.sh"
# shellcheck source=lib/data-disk-setup.sh
source "$SCRIPT_DIR/lib/data-disk-setup.sh"

ensure_data_disk || exit 1
echo "$DATA ready."
echo "Next step:"
echo "  sudo bash $SCRIPT_DIR/migrate-to-mnt-data.sh"
