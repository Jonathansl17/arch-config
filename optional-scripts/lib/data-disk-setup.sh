# shellcheck shell=bash
# Interactive flow that guarantees a usable /mnt/data. Reuses an existing data
# partition when one exists; otherwise lists spare disks, names any operating
# system found on them, and wipes the chosen one only after explicit consent.
# Sourced, never executed. Requires lib/disk-detect.sh and lib/disk-format.sh.

readonly DESTROY_WORD="DESTROY"
readonly QUIT_WORD="q"

# os_name KIND: human label for a classify_disk result.
os_name() {
    case "$1" in
        windows) echo "WINDOWS installation" ;;
        macos) echo "macOS installation" ;;
        linux) echo "Linux installation or Linux data" ;;
        other) echo "unrecognised data" ;;
        empty) echo "empty disk" ;;
        *) echo "$1" ;;
    esac
}

# find_existing_data_part: print the first valid data partition on a spare disk.
find_existing_data_part() {
    local disk kind
    while read -r disk; do
        kind=$(disk_lsblk "$disk" | classify_disk)
        [[ "$kind" == data:* ]] && { echo "${kind#data:}"; return 0; }
    done < <(candidate_disks)
    return 1
}

# print_candidates: show every spare disk with what it contains.
print_candidates() {
    local disk kind size
    while read -r disk; do
        kind=$(disk_lsblk "$disk" | classify_disk)
        size=$(lsblk -dno SIZE "$disk")
        printf '\n  %s  (%s)  ->  %s\n' "$disk" "${size// /}" "$(os_name "$kind")"
        lsblk -no NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME "$disk" | tail -n +2 | sed 's/^/      /'
    done < <(candidate_disks)
}

# choose_disk: ask for a spare disk path; prints it, fails on quit or bad input.
choose_disk() {
    local target
    read -rp "Disk to turn into $DATA (device path, '$QUIT_WORD' to quit): " target
    [[ -n "$target" && "$target" != "$QUIT_WORD" ]] || return 1
    if ! candidate_disks | grep -qxF "$target"; then
        echo "ERROR: $target is not a spare disk from the list." >&2
        return 1
    fi
    echo "$target"
}

# confirm_destroy DISK KIND: explicit, OS-aware consent before wiping.
confirm_destroy() {
    local disk="$1" kind="$2" answer
    echo
    echo "!!! $disk contains: $(os_name "$kind")"
    [[ "$kind" == windows || "$kind" == macos || "$kind" == linux ]] &&
        echo "!!! That system will be ERASED PERMANENTLY and will no longer boot."
    echo "!!! Every file on $disk will be lost. Back up anything you need first."
    read -rp "Type '$DESTROY_WORD' to wipe $disk: " answer
    [[ "$answer" == "$DESTROY_WORD" ]]
}

# prepare_new_data_disk: choose, confirm, wipe and register a disk.
prepare_new_data_disk() {
    local disk kind part
    if [[ -z "$(candidate_disks)" ]]; then
        echo "No spare disk besides the system disk: nothing mounted, nothing changed." >&2
        echo "To consolidate caches on the system disk use migrate-to-home.sh instead." >&2
        return 1
    fi
    echo "No data partition found. Spare disks:"
    print_candidates
    echo
    disk=$(choose_disk) || { echo "Aborted."; return 1; }
    kind=$(disk_lsblk "$disk" | classify_disk)
    confirm_destroy "$disk" "$kind" || { echo "Aborted."; return 1; }
    require_disk_tools || return 1
    part=$(format_data_disk "$disk") || return 1
    ensure_fstab_entry "$part" "$DATA" || return 1
    mount_data "$DATA" || return 1
    [[ "$kind" == empty || "$kind" == other ]] || refresh_bootloader "$kind"
}

# ensure_data_disk: leave a valid data partition mounted at $DATA.
ensure_data_disk() {
    local part
    if mountpoint -q "$DATA"; then
        part=$(findmnt -no SOURCE "$DATA")
        is_data_partition "$(lsblk -bPpo "$LSBLK_FIELDS" "$part")" && return 0
        echo "ERROR: $DATA is mounted from $part, which is not a valid data partition." >&2
        return 1
    fi
    if part=$(find_existing_data_part); then
        echo "  found data partition $part"
        ensure_fstab_entry "$part" "$DATA" && mount_data "$DATA"
        return
    fi
    prepare_new_data_disk
}
