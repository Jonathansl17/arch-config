# shellcheck shell=bash
# Cleanup of Windows boot files left behind after its disk was erased.
# Sourced, never executed. Writes assume root. Requires lib/disk-detect.sh
# (disk_lsblk, classify_disk) and lib/grub-config.sh (set_grub_key, backup_file).
#
# Windows keeps its boot manager on the ESP it shares with Linux, so erasing
# the Windows disk leaves a dead "Windows Boot Manager" in GRUB (via
# os-prober) and in the firmware boot list.

readonly WINDOWS_ESP_DIR="/boot/EFI/Microsoft"
readonly WINDOWS_EFI_LABEL="Windows Boot Manager"

# windows_installed: true when any physical disk still holds Windows.
windows_installed() {
    local disk
    while read -r disk; do
        [[ "$(disk_lsblk "$disk" | classify_disk)" == windows ]] && return 0
    done < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }')
    return 1
}

# windows_boot_ids < efibootmgr output: print the hex ids of Windows entries.
windows_boot_ids() {
    local re="^Boot([0-9A-Fa-f]{4})\\*?[[:space:]]+$WINDOWS_EFI_LABEL"
    local line
    while IFS= read -r line; do
        [[ "$line" =~ $re ]] && echo "${BASH_REMATCH[1]}"
    done
    return 0
}

# windows_leftovers_present: boot files or firmware entries remain.
windows_leftovers_present() {
    [[ -d "$WINDOWS_ESP_DIR" ]] && return 0
    [[ -n "$(efibootmgr 2>/dev/null | windows_boot_ids)" ]]
}

# remove_windows_leftovers: delete the ESP boot files and firmware entries and
# stop os-prober from scanning. Caller must confirm Windows is gone first.
remove_windows_leftovers() {
    local id
    if [[ -d "$WINDOWS_ESP_DIR" ]]; then
        rm -rf "$WINDOWS_ESP_DIR" || return 1
        echo "  [windows] removed $WINDOWS_ESP_DIR"
    fi
    while read -r id; do
        [[ -z "$id" ]] && continue
        efibootmgr -q -b "$id" -B || return 1
        echo "  [windows] removed firmware entry Boot$id"
    done < <(efibootmgr | windows_boot_ids)
    backup_file "$GRUB_DEFAULTS" || return 1
    set_grub_key "$GRUB_DEFAULTS" GRUB_DISABLE_OS_PROBER true
}
