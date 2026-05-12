#!/usr/bin/env bash
# Interactive setup for the /mnt/data disk.
# Partitions a chosen disk as GPT, creates ext4 with LABEL=data,
# adds an fstab entry with nofail + 10s device-timeout, and mounts it.
#
# Idempotent: if an ext4 LABEL=data partition already exists and is
# mounted at /mnt/data, exits with no changes.
#
# Safety:
#   - Detects the disk holding / and refuses to touch it.
#   - Lists candidate disks; requires the user to type the device path.
#   - Final destructive step requires typing "DESTROY" literally.
#
# Run:
#   bash ~/arch-config/optional-scripts/setup-data-disk.sh

set -uo pipefail

DATA="/mnt/data"
TS="$(date +%Y%m%d-%H%M%S)"

c_ok()   { printf '\033[1;32m[OK]\033[0m  %s\n' "$*"; }
c_skip() { printf '\033[1;33m[--]\033[0m  %s\n' "$*"; }
c_err()  { printf '\033[1;31m[!!]\033[0m  %s\n' "$*"; }
c_hdr()  { printf '\n\033[1;35m=== %s ===\033[0m\n' "$*"; }
c_warn() { printf '\033[1;31m%s\033[0m\n' "$*"; }

if ! sudo -v; then
    c_err "sudo required."
    exit 1
fi

# Bootstrap binaries we use during partitioning. mkfs.ext4 ships with
# e2fsprogs (base), but sgdisk/wipefs/partprobe are in gptfdisk/util-linux
# (util-linux is base). Only gptfdisk may be missing on minimal installs.
need_pkgs=()
command -v sgdisk    >/dev/null 2>&1 || need_pkgs+=(gptfdisk)
command -v wipefs    >/dev/null 2>&1 || need_pkgs+=(util-linux)
command -v mkfs.ext4 >/dev/null 2>&1 || need_pkgs+=(e2fsprogs)
if (( ${#need_pkgs[@]} > 0 )); then
    c_skip "Installing required tools: ${need_pkgs[*]}"
    sudo pacman -S --needed --noconfirm "${need_pkgs[@]}" \
        || { c_err "Failed installing ${need_pkgs[*]}"; exit 1; }
fi

#-----------------------------------------------------------------
c_hdr "1. Check if /mnt/data already configured"
#-----------------------------------------------------------------
if mountpoint -q "$DATA"; then
    cur_src=$(findmnt -no SOURCE "$DATA")
    cur_label=$(lsblk -no LABEL "$cur_src" 2>/dev/null)
    if [[ "$cur_label" == "data" ]]; then
        c_skip "$DATA already mounted from $cur_src (LABEL=data). Nothing to do."
        exit 0
    else
        c_err "$DATA mounted from $cur_src but LABEL != 'data' (got '$cur_label')."
        c_err "Refusing to touch unknown mount. Unmount manually if you want to redo setup."
        exit 1
    fi
fi

# Maybe disk exists with LABEL=data but not mounted yet → just mount it
existing_dev=$(lsblk -lnpo NAME,FSTYPE,LABEL | awk '$2=="ext4" && $3=="data" {print $1; exit}')
if [[ -n "$existing_dev" ]]; then
    c_ok "Found existing ext4 LABEL=data on $existing_dev — skipping partitioning."
    SELECTED_PART="$existing_dev"
    SKIP_PARTITION=1
else
    SKIP_PARTITION=0
fi

#-----------------------------------------------------------------
c_hdr "2. Detect system disk (will NOT be touched)"
#-----------------------------------------------------------------
ROOT_SRC=$(findmnt -no SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null)
if [[ -z "$ROOT_DISK" ]]; then
    c_err "Could not determine root disk from $ROOT_SRC. Aborting."
    exit 1
fi
ROOT_DISK="/dev/$ROOT_DISK"
c_ok "System disk: $ROOT_DISK (off-limits)"

# Also exclude /home and /boot disks if separate
EXCLUDE_DISKS=("$ROOT_DISK")
for mp in /home /boot; do
    src=$(findmnt -no SOURCE "$mp" 2>/dev/null || true)
    [[ -z "$src" ]] && continue
    d=$(lsblk -no PKNAME "$src" 2>/dev/null)
    [[ -n "$d" ]] && EXCLUDE_DISKS+=("/dev/$d")
done

is_excluded() {
    local d="$1"
    for x in "${EXCLUDE_DISKS[@]}"; do
        [[ "$d" == "$x" ]] && return 0
    done
    return 1
}

#-----------------------------------------------------------------
if [[ "$SKIP_PARTITION" -eq 0 ]]; then
c_hdr "3. Candidate disks (NOT system/home/boot)"
#-----------------------------------------------------------------
echo "Available block devices:"
lsblk -dpno NAME,SIZE,MODEL,TRAN | while read -r name size model tran; do
    [[ -z "$name" ]] && continue
    # Skip loop/zram/rom
    [[ "$name" == /dev/loop* || "$name" == /dev/zram* || "$name" == /dev/sr* ]] && continue
    if is_excluded "$name"; then
        printf '  \033[1;33m[SKIP]\033[0m %s  %s  %s  (%s) — system\n' "$name" "$size" "$model" "$tran"
    else
        # Show what's on it
        parts=$(lsblk -lnpo NAME,FSTYPE,LABEL,MOUNTPOINT "$name" | tail -n +2 | sed 's/^/      /')
        printf '  \033[1;32m[OK]\033[0m   %s  %s  %s  (%s)\n' "$name" "$size" "$model" "$tran"
        [[ -n "$parts" ]] && echo "$parts"
    fi
done

echo
c_warn "WARNING: the chosen disk will be FULLY WIPED (new GPT, new ext4)."
c_warn "ALL DATA ON IT WILL BE DESTROYED."
echo
read -rp "Type the device path to use (e.g. /dev/nvme1n1, /dev/sdb) or 'q' to quit: " TARGET
[[ "$TARGET" == "q" || -z "$TARGET" ]] && { echo "Aborted."; exit 0; }

if [[ ! -b "$TARGET" ]]; then
    c_err "$TARGET is not a block device."
    exit 1
fi

if is_excluded "$TARGET"; then
    c_err "$TARGET hosts /, /home, or /boot. Refusing."
    exit 1
fi

# Show what we'll destroy
echo
echo "About to wipe:"
lsblk -po NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$TARGET"
echo
read -rp "Type 'DESTROY' (uppercase) to confirm: " CONFIRM
[[ "$CONFIRM" == "DESTROY" ]] || { echo "Aborted."; exit 0; }

# Unmount any mounted partitions on target
for p in $(lsblk -lnpo NAME "$TARGET" | tail -n +2); do
    if mountpoint -q "$(findmnt -no TARGET "$p" 2>/dev/null)" 2>/dev/null; then
        mp=$(findmnt -no TARGET "$p")
        sudo umount "$mp" || { c_err "Could not unmount $mp"; exit 1; }
    fi
done

#-----------------------------------------------------------------
c_hdr "4. Partition + format"
#-----------------------------------------------------------------
sudo wipefs -af "$TARGET"
sudo sgdisk --zap-all "$TARGET"
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:"data" "$TARGET"
sudo partprobe "$TARGET"
sleep 2

# Determine partition name (/dev/sdb → /dev/sdb1, /dev/nvme1n1 → /dev/nvme1n1p1)
if [[ "$TARGET" =~ nvme|mmcblk ]]; then
    SELECTED_PART="${TARGET}p1"
else
    SELECTED_PART="${TARGET}1"
fi

if [[ ! -b "$SELECTED_PART" ]]; then
    c_err "Expected partition $SELECTED_PART not found after partprobe."
    exit 1
fi

sudo mkfs.ext4 -F -L data "$SELECTED_PART"
c_ok "Partition $SELECTED_PART created with LABEL=data"
fi  # end if SKIP_PARTITION == 0

#-----------------------------------------------------------------
c_hdr "5. Add fstab entry (with nofail)"
#-----------------------------------------------------------------
UUID=$(sudo blkid -s UUID -o value "$SELECTED_PART")
if [[ -z "$UUID" ]]; then
    c_err "Could not read UUID of $SELECTED_PART"
    exit 1
fi

if grep -qE "^[^#].*\s${DATA}\s" /etc/fstab; then
    c_skip "fstab already has an entry for $DATA"
else
    sudo cp /etc/fstab "/etc/fstab.bak-$TS"
    echo "UUID=$UUID  $DATA  ext4  rw,relatime,nofail,x-systemd.device-timeout=10,x-gvfs-show  0 2" \
        | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
    c_ok "fstab entry added (UUID=$UUID)"
fi

#-----------------------------------------------------------------
c_hdr "6. Mount"
#-----------------------------------------------------------------
sudo mkdir -p "$DATA"
if mountpoint -q "$DATA"; then
    c_skip "$DATA already mounted"
else
    sudo mount "$DATA" && c_ok "Mounted $DATA"
fi

c_hdr "Done"
echo "Next step:"
echo "  sudo bash ~/arch-config/optional-scripts/migrate-to-mnt-data.sh"
