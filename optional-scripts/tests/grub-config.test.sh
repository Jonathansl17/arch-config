#!/usr/bin/env bash
# Tests for lib/grub-config.sh and the pure parts of lib/windows-leftovers.sh.
# Works on throwaway files under mktemp; never touches /etc or /boot.
# Run: bash optional-scripts/tests/grub-config.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/grub-config.sh
source "$SCRIPT_DIR/../lib/grub-config.sh"
# shellcheck source=../lib/windows-leftovers.sh
source "$SCRIPT_DIR/../lib/windows-leftovers.sh"

failures=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

expect() {
    local name="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: want '$want', got '$got'"
        failures=$((failures + 1))
    fi
}

count() { grep -c -- "$1" "$2"; }

# set_grub_key
grub="$root/grub"
printf 'GRUB_TIMEOUT=5\n#GRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT_STYLE=menu\n' >"$grub"
set_grub_key "$grub" GRUB_TIMEOUT 0
expect "replaces active key" 1 "$(count '^GRUB_TIMEOUT=0$' "$grub")"
set_grub_key "$grub" GRUB_TIMEOUT_STYLE hidden
expect "leaves commented key alone" 1 "$(count '^#GRUB_TIMEOUT_STYLE=hidden$' "$grub")"
expect "one active style line" 1 "$(count '^GRUB_TIMEOUT_STYLE=' "$grub")"
set_grub_key "$grub" GRUB_DISABLE_OS_PROBER true
expect "appends missing key" 1 "$(count '^GRUB_DISABLE_OS_PROBER=true$' "$grub")"
cp "$grub" "$root/grub.before"
set_grub_key "$grub" GRUB_TIMEOUT 0
expect "no-op when already set" same "$(cmp -s "$grub" "$root/grub.before" && echo same)"

# add_noextract / has_noextract
conf="$root/pacman.conf"
printf '[options]\n#NoExtract   =\nHoldPkg = pacman\n\n[core]\n' >"$conf"
add_noextract "$conf" etc/grub.d/10_linux
expect "inserted under [options]" "NoExtract   = etc/grub.d/10_linux" "$(sed -n 2p "$conf")"
add_noextract "$conf" etc/grub.d/10_linux
expect "idempotent" 1 "$(count 'etc/grub.d/10_linux' "$conf")"
printf '[options]\nNoExtract = usr/share/a etc/grub.d/20_linux_xen\n' >"$conf"
has_noextract "$conf" etc/grub.d/20_linux_xen
expect "finds path in multi-value line" 0 "$?"
has_noextract "$conf" etc/grub.d
expect "no partial-path match" 1 "$?"
printf '[core]\n' >"$conf"
add_noextract "$conf" x 2>/dev/null
expect "fails without [options]" 1 "$?"

# drop_legacy_generators / legacy_generators_left (regression: 2026-11-26
# grub-mkconfig put the initramfs-less 10_linux entry first -> kernel panic)
printf '[options]\n' >"$conf"
mkdir -p "$root/etc/grub.d"
touch "$root/etc/grub.d/10_linux" "$root/etc/grub.d/20_linux_xen" "$root/etc/grub.d/15_uki"
legacy_generators_left "$conf" "$root"
expect "detects generators" 0 "$?"
drop_legacy_generators "$conf" "$root"
expect "10_linux removed" gone "$([[ -e $root/etc/grub.d/10_linux ]] || echo gone)"
expect "15_uki kept" kept "$([[ -e $root/etc/grub.d/15_uki ]] && echo kept)"
legacy_generators_left "$conf" "$root"
expect "nothing left after drop" 1 "$?"

# uki_present
mkdir -p "$root/uki"
uki_present "$root/uki"
expect "empty dir has no UKI" 1 "$?"
touch "$root/uki/arch-linux.efi"
uki_present "$root/uki"
expect "finds UKI" 0 "$?"

# windows_boot_ids
efi_out='BootCurrent: 0005
Boot0000* Windows Boot Manager	HD(1,GPT,445f)/\EFI\MICROSOFT\BOOT\BOOTMGFW.EFI
Boot0005* UEFI OS	HD(1,GPT,445f)/\EFI\BOOT\BOOTX64.EFI
Boot000A  Windows Boot Manager	HD(2,GPT,99aa)'
expect "parses Windows entries" "0000 000A" "$(windows_boot_ids <<<"$efi_out" | xargs)"
expect "no Windows entries" "" "$(windows_boot_ids <<<'Boot0005* UEFI OS	HD()')"

((failures == 0)) && echo "all passed" || { echo "$failures failed"; exit 1; }
