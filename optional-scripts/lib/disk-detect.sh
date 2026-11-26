# shellcheck shell=bash
# Read-only disk classification for the /mnt/data setup.
# Sourced, never executed. Classification functions read `lsblk -bPpo` lines
# from stdin so they can be tested without real disks.

readonly DATA_LABEL="data"
readonly DATA_FSTYPE="ext4"
readonly MIN_DATA_BYTES=$((1024 * 1024 * 1024))
readonly LSBLK_FIELDS="NAME,TYPE,SIZE,FSTYPE,LABEL,PARTTYPE"
readonly SYSTEM_MOUNTS=(/ /home /boot)
readonly VIRTUAL_DISK_RE='^/dev/(loop|zram|sr|ram)'

# GPT type GUIDs: Microsoft basic data, Microsoft reserved, Windows recovery.
readonly WINDOWS_PARTTYPES=" ebd0a0a2-b9e5-4433-87c0-68b6b72699c7 e3c9e316-0b5c-4db8-817d-f92df00215ae de94bba4-06d1-4d40-a16a-bfd50179d6ac "
readonly WINDOWS_FSTYPES=" ntfs BitLocker "
readonly MACOS_FSTYPES=" apfs hfsplus "
readonly LINUX_FSTYPES=" ext2 ext3 ext4 btrfs xfs f2fs swap crypto_LUKS LVM2_member "

# lsblk_field LINE KEY: print KEY's value from one `lsblk -P` line.
lsblk_field() {
    local line=" $1" key="$2"
    local re=" ${key}=\"([^\"]*)\""
    [[ "$line" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
    return 0
}

# in_list WORD " a b c ": true when WORD is one of the space-padded list.
in_list() {
    [[ -n "$1" && "$2" == *" $1 "* ]]
}

# is_data_partition LINE: a usable ext4 LABEL=data partition. Rejects tiny
# partitions and Microsoft partition types carrying a stale ext4 signature.
is_data_partition() {
    local line="$1"
    [[ "$(lsblk_field "$line" FSTYPE)" == "$DATA_FSTYPE" ]] || return 1
    [[ "$(lsblk_field "$line" LABEL)" == "$DATA_LABEL" ]] || return 1
    in_list "$(lsblk_field "$line" PARTTYPE)" "$WINDOWS_PARTTYPES" && return 1
    (($(lsblk_field "$line" SIZE) >= MIN_DATA_BYTES))
}

# classify_partition LINE: windows | macos | linux | other | none
classify_partition() {
    local line="$1" fstype parttype
    fstype=$(lsblk_field "$line" FSTYPE)
    parttype=$(lsblk_field "$line" PARTTYPE)
    if in_list "$parttype" "$WINDOWS_PARTTYPES" || in_list "$fstype" "$WINDOWS_FSTYPES"; then
        echo windows
    elif in_list "$fstype" "$MACOS_FSTYPES"; then
        echo macos
    elif in_list "$fstype" "$LINUX_FSTYPES"; then
        echo linux
    elif [[ -n "$fstype" ]]; then
        echo other
    else
        echo none
    fi
}

# classify_disk < lsblk lines of one disk (disk row + partitions).
# Prints one of: data:<partition> | windows | macos | linux | other | empty
classify_disk() {
    local line kind found=" " data_part=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ -z "$data_part" ]] && is_data_partition "$line"; then
            data_part=$(lsblk_field "$line" NAME)
        fi
        kind=$(classify_partition "$line")
        found+="$kind "
    done
    if [[ -n "$data_part" ]]; then
        echo "data:$data_part"
        return 0
    fi
    for kind in windows macos linux other; do
        in_list "$kind" "$found" && { echo "$kind"; return 0; }
    done
    echo empty
}

# system_disks: whole disks backing /, /home and /boot.
system_disks() {
    local mp src parent
    for mp in "${SYSTEM_MOUNTS[@]}"; do
        src=$(findmnt -no SOURCE "$mp" 2>/dev/null) || continue
        parent=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
        [[ -n "$parent" ]] && echo "/dev/$parent"
    done | sort -u
}

# candidate_disks: physical disks that hold none of the system mounts.
candidate_disks() {
    local sys disk
    sys=$(system_disks)
    [[ -n "$sys" ]] || { echo "ERROR: cannot detect the system disk." >&2; return 1; }
    while read -r disk; do
        [[ "$disk" =~ $VIRTUAL_DISK_RE ]] && continue
        grep -qxF "$disk" <<<"$sys" && continue
        echo "$disk"
    done < <(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }')
}

# disk_lsblk DISK: `lsblk -bPpo` lines for DISK and its partitions.
disk_lsblk() {
    lsblk -bPpo "$LSBLK_FIELDS" "$1"
}
