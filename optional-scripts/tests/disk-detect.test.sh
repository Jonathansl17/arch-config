#!/usr/bin/env bash
# Tests for lib/disk-detect.sh classification. Pure: feeds lsblk fixtures,
# touches no real disk. Run: bash optional-scripts/tests/disk-detect.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/disk-detect.sh
source "$SCRIPT_DIR/../lib/disk-detect.sh"

readonly GIB=$((1024 * 1024 * 1024))
readonly MSR="e3c9e316-0b5c-4db8-817d-f92df00215ae"
readonly WIN_DATA="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
readonly LINUX_FS="0fc63daf-8483-4772-8e79-3d69d8477de4"
failures=0

# row NAME TYPE SIZE FSTYPE LABEL PARTTYPE: one `lsblk -bPpo` line.
row() {
    printf 'NAME="%s" TYPE="%s" SIZE="%s" FSTYPE="%s" LABEL="%s" PARTTYPE="%s"\n' "$@"
}

expect() {
    local name="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: want '$want', got '$got'"
        failures=$((failures + 1))
    fi
}

disk=$(row /dev/sdb disk $((500 * GIB)) "" "" "")

# Regression: Windows MSR carrying a stale 16M ext4 LABEL=data signature.
expect "windows disk with fake data label" windows "$(
    { echo "$disk"; row /dev/sdb1 part $((16 * 1024 * 1024)) ext4 data "$MSR"
      row /dev/sdb2 part $((476 * GIB)) ntfs "" "$WIN_DATA"; } | classify_disk)"

expect "real data partition" "data:/dev/sdb1" "$(
    { echo "$disk"; row /dev/sdb1 part $((500 * GIB)) ext4 data "$LINUX_FS"; } | classify_disk)"

expect "tiny data partition rejected" linux "$(
    { echo "$disk"; row /dev/sdb1 part $((GIB - 1)) ext4 data "$LINUX_FS"; } | classify_disk)"

expect "other linux install" linux "$(
    { echo "$disk"; row /dev/sdb1 part $((100 * GIB)) btrfs "" "$LINUX_FS"; } | classify_disk)"

expect "macos" macos "$(
    { echo "$disk"; row /dev/sdb1 part $((100 * GIB)) apfs "" ""; } | classify_disk)"

expect "unknown filesystem" other "$(
    { echo "$disk"; row /dev/sdb1 part $((8 * GIB)) exfat "" ""; } | classify_disk)"

expect "empty disk" empty "$(echo "$disk" | classify_disk)"

expect "windows wins over linux on dual-boot disk" windows "$(
    { echo "$disk"; row /dev/sdb1 part $((50 * GIB)) ext4 "" "$LINUX_FS"
      row /dev/sdb2 part $((50 * GIB)) ntfs "" "$WIN_DATA"; } | classify_disk)"

expect "lsblk_field skips PKNAME prefix" "/dev/sdb1" "$(
    lsblk_field 'PKNAME="/dev/sdb" NAME="/dev/sdb1"' NAME)"

((failures == 0)) && echo "all passed" || { echo "$failures failed"; exit 1; }
