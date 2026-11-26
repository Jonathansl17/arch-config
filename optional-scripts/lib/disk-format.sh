# shellcheck shell=bash
# Destructive and system-changing steps for the /mnt/data setup.
# Sourced, never executed. Every function assumes it runs as root and that the
# caller already obtained explicit confirmation from the user.
# Requires lib/disk-detect.sh (DATA_LABEL, DATA_FSTYPE).

readonly DATA_PART_TYPECODE="8300"
readonly FSTAB_FILE="/etc/fstab"
readonly FSTAB_OPTS="rw,relatime,nofail,x-systemd.device-timeout=10,x-gvfs-show"
readonly GRUB_CFG="/boot/grub/grub.cfg"
readonly REQUIRED_TOOLS=(sgdisk:gptfdisk wipefs:util-linux mkfs.ext4:e2fsprogs partprobe:parted)

# require_disk_tools: install missing partitioning tools via pacman.
require_disk_tools() {
    local entry pkgs=()
    for entry in "${REQUIRED_TOOLS[@]}"; do
        command -v "${entry%%:*}" >/dev/null 2>&1 || pkgs+=("${entry#*:}")
    done
    ((${#pkgs[@]} == 0)) && return 0
    echo "  installing required tools: ${pkgs[*]}"
    pacman -S --needed --noconfirm "${pkgs[@]}"
}

# partition_path DISK NUM: /dev/sdb 1 -> /dev/sdb1, /dev/nvme0n1 1 -> /dev/nvme0n1p1
partition_path() {
    local disk="$1" num="$2"
    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# unmount_disk DISK: unmount every mounted filesystem on DISK.
unmount_disk() {
    local mp
    while read -r mp; do
        [[ -z "$mp" ]] && continue
        umount "$mp" || { echo "ERROR: could not unmount $mp" >&2; return 1; }
    done < <(lsblk -lnpo MOUNTPOINT "$1" | sort -r)
}

# format_data_disk DISK: wipe DISK and create one ext4 LABEL=data partition.
# Prints the new partition path.
format_data_disk() {
    local disk="$1" part devices
    unmount_disk "$disk" || return 1
    mapfile -t devices < <(lsblk -lnpo NAME "$disk" | tac)
    wipefs -af "${devices[@]}" >&2 || return 1
    sgdisk --zap-all "$disk" >&2 || return 1
    sgdisk -n 1:0:0 -t "1:$DATA_PART_TYPECODE" -c "1:$DATA_LABEL" "$disk" >&2 || return 1
    partprobe "$disk" || return 1
    udevadm settle
    part=$(partition_path "$disk" 1)
    [[ -b "$part" ]] || { echo "ERROR: $part missing after partprobe" >&2; return 1; }
    mkfs.ext4 -F -L "$DATA_LABEL" "$part" >&2 || return 1
    echo "$part"
}

# ensure_fstab_entry PART MOUNTPOINT: point MOUNTPOINT at PART's UUID,
# replacing a stale entry. Backs fstab up before any change.
ensure_fstab_entry() {
    local part="$1" mp="$2" uuid entry
    uuid=$(blkid -s UUID -o value "$part")
    [[ -n "$uuid" ]] || { echo "ERROR: no UUID on $part" >&2; return 1; }
    entry="UUID=$uuid  $mp  $DATA_FSTYPE  $FSTAB_OPTS  0 2"
    if grep -qF "UUID=$uuid " "$FSTAB_FILE"; then
        echo "  [fstab] entry for $uuid already present"
        return 0
    fi
    cp "$FSTAB_FILE" "$FSTAB_FILE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
    sed -i -E "\\|^[^#]*[[:space:]]${mp}[[:space:]]|d" "$FSTAB_FILE" || return 1
    echo "$entry" >>"$FSTAB_FILE" || return 1
    systemctl daemon-reload
    echo "  [fstab] $mp -> UUID=$uuid"
}

# mount_data MOUNTPOINT: mount through fstab.
mount_data() {
    mkdir -p "$1" || return 1
    mountpoint -q "$1" || mount "$1"
}

# refresh_bootloader: drop boot entries of an erased OS from GRUB.
refresh_bootloader() {
    if ! command -v grub-mkconfig >/dev/null 2>&1 || [[ ! -f "$GRUB_CFG" ]]; then
        echo "  [boot] GRUB not found; remove stale boot entries manually (efibootmgr)."
        return 0
    fi
    grub-mkconfig -o "$GRUB_CFG" || return 1
    echo "  [boot] GRUB menu regenerated."
    echo "  [boot] leftover firmware entry, if any: efibootmgr | grep -i windows"
}
