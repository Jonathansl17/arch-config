#!/usr/bin/env bash
# Optional system hardening — security defaults to apply on a fresh Arch install.
# Idempotent: safe to re-run; each section guards before acting and skips cleanly
# when already applied.
#
# Sections:
#   1. /boot fstab fmask=0077,dmask=0077 (vfat ESP permission fix)
#   2. sysctl hardening (kptr_restrict, ptrace_scope, rp_filter, redirects)
#   3. GRUB hidden menu (boot directly into Arch; hold Shift at POST for menu)
#   4. ~/.aws and ~/aws permissions to 700 (if either exists)
#   5. /mnt/data fstab nofail + 10s device timeout (boot survives dead disk)
#
# Run from anywhere:
#   bash ~/arch-config/optional-scripts/system-hardening.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

c_ok()   { printf '\033[1;32m[OK]\033[0m  %s\n' "$*"; }
c_skip() { printf '\033[1;33m[--]\033[0m  %s\n' "$*"; }
c_err()  { printf '\033[1;31m[!!]\033[0m  %s\n' "$*"; }
c_hdr()  { printf '\n\033[1;35m=== %s ===\033[0m\n' "$*"; }

# Pre-authorise sudo so prompts don't interrupt mid-run.
if ! sudo -v; then
    c_err "sudo is required to continue."
    exit 1
fi

#-----------------------------------------------------------------
c_hdr "1. /boot fstab umask (vfat ESP, fixes random-seed warning)"
#-----------------------------------------------------------------
boot_line=$(awk '$2=="/boot" && $3=="vfat" {print; exit}' /etc/fstab)
if [[ -z "$boot_line" ]]; then
    c_skip "/boot is not a vfat mount in fstab — skipping"
elif [[ "$boot_line" == *"fmask=0077,dmask=0077"* ]]; then
    c_skip "already applied"
else
    sudo cp /etc/fstab "/etc/fstab.bak-$TS"
    if [[ "$boot_line" == *"fmask=0022"* || "$boot_line" == *"dmask=0022"* ]]; then
        sudo sed -i -E '\#\s/boot\s+vfat#{
            s/fmask=0022/fmask=0077/g
            s/dmask=0022/dmask=0077/g
        }' /etc/fstab
    else
        sudo sed -i -E '\#\s/boot\s+vfat#{
            s#(vfat\s+)([^[:space:]]+)#\1\2,fmask=0077,dmask=0077#
        }' /etc/fstab
    fi
    sudo systemctl daemon-reload
    sudo mount -o remount /boot 2>/dev/null || true
    c_ok "fstab updated; reboot if remount didn't pick it up (vfat quirk)"
fi

#-----------------------------------------------------------------
c_hdr "2. sysctl hardening"
#-----------------------------------------------------------------
SYSCTL_SRC="$REPO_DIR/sysctl/99-hardening.conf"
SYSCTL_DST="/etc/sysctl.d/99-hardening.conf"
if [[ ! -f "$SYSCTL_SRC" ]]; then
    c_err "$SYSCTL_SRC missing — repo incomplete"
elif sudo cmp -s "$SYSCTL_SRC" "$SYSCTL_DST" 2>/dev/null; then
    c_skip "$SYSCTL_DST already in sync"
else
    sudo cp "$SYSCTL_SRC" "$SYSCTL_DST"
    sudo sysctl --system >/dev/null && c_ok "deployed and reloaded"
fi

#-----------------------------------------------------------------
c_hdr "3. GRUB hidden menu (boot directly to Arch)"
#-----------------------------------------------------------------
if [[ ! -f /etc/default/grub ]] || ! command -v grub-mkconfig >/dev/null 2>&1; then
    c_skip "GRUB not installed — skipping"
elif grep -q '^GRUB_TIMEOUT=0$' /etc/default/grub \
  && grep -q '^GRUB_TIMEOUT_STYLE=hidden$' /etc/default/grub; then
    c_skip "already applied"
else
    sudo cp /etc/default/grub "/etc/default/grub.bak-$TS"
    if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT=0' | sudo tee -a /etc/default/grub >/dev/null
    fi
    if grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
    else
        echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a /etc/default/grub >/dev/null
    fi
    sudo grub-mkconfig -o /boot/grub/grub.cfg \
        && c_ok "GRUB regenerated (hold Shift at POST to force the menu)"
fi

#-----------------------------------------------------------------
c_hdr "4. ~/.aws / ~/aws permissions 700"
#-----------------------------------------------------------------
applied_any=0
for d in "$HOME/.aws" "$HOME/aws"; do
    [[ -d "$d" ]] || continue
    if [[ "$(stat -c '%a' "$d")" == "700" ]]; then
        c_skip "$d already 700"
    else
        chmod 700 "$d" && c_ok "chmod 700 $d"
    fi
    applied_any=1
done
[[ $applied_any -eq 0 ]] && c_skip "no aws dir found"

#-----------------------------------------------------------------
c_hdr "5. /mnt/data fstab nofail + device-timeout"
#-----------------------------------------------------------------
# Without nofail, a dead /mnt/data disk hangs boot ~90s then drops to
# emergency shell. With nofail + 10s timeout, boot continues normally
# and symlinks under ~ just dangle until migrate-to-home.sh fixes them.
data_line=$(awk '$2=="/mnt/data" {print; exit}' /etc/fstab)
if [[ -z "$data_line" ]]; then
    c_skip "/mnt/data not in fstab — skipping"
elif [[ "$data_line" == *"nofail"* && "$data_line" == *"x-systemd.device-timeout="* ]]; then
    c_skip "already applied"
else
    sudo cp /etc/fstab "/etc/fstab.bak-$TS"
    # Option-agnostic: rebuild the options field (column 4) merging in
    # nofail + x-systemd.device-timeout=10 without assuming the current
    # set. Preserves whatever other options are already there.
    sudo awk -v OFS='  ' '
        $2=="/mnt/data" && $1 !~ /^#/ {
            n = split($4, opts, ",")
            has_nofail = 0; has_timeout = 0
            for (i = 1; i <= n; i++) {
                if (opts[i] == "nofail") has_nofail = 1
                if (opts[i] ~ /^x-systemd\.device-timeout=/) has_timeout = 1
            }
            if (!has_nofail)  $4 = $4 ",nofail"
            if (!has_timeout) $4 = $4 ",x-systemd.device-timeout=10"
        }
        { print }
    ' /etc/fstab | sudo tee /etc/fstab.new >/dev/null \
        && sudo mv /etc/fstab.new /etc/fstab
    sudo systemctl daemon-reload
    c_ok "fstab updated; reboot to verify boot resilience"
fi

c_hdr "Done"
echo "Hardening applied. Re-run safely whenever you want."
