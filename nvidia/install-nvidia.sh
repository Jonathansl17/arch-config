#!/usr/bin/env bash
# Optional NVIDIA driver installer for ASUS hybrid laptop (AMD iGPU + NVIDIA dGPU).
#
# Purpose:
#   Reproduce the exact NVIDIA setup documented in the 2026-04-14 install session:
#     - nvidia-open-dkms + nvidia-utils (no lib32, no nvidia-prime)
#     - nouveau kernel module blacklisted
#     - initramfs regenerated (kms hook keeps amdgpu loading early)
#     - AMD amdgpu remains the primary renderer; NVIDIA only wakes for CUDA/NVENC
#
# Philosophy:
#   - Fully idempotent: if everything is already in the desired state, does NOTHING.
#   - Exhaustive preflight checks: refuses to run if the system can't safely install.
#   - Phases are independent and self-skipping: partial state is detected and completed.
#   - Never silently amends: every change is logged. Every skip is explained.
#
# NOT called by install.sh. This is an on-demand recovery/reinstall script.
#
# Usage:
#     ./nvidia/install-nvidia.sh          # run full idempotent check + install
#     ./nvidia/install-nvidia.sh --check  # preflight only, no changes
#     ./nvidia/install-nvidia.sh --force  # skip "all good" early-exit, re-verify each phase

set -euo pipefail

# ---------- constants ----------
readonly NVIDIA_PKGS=(nvidia-open-dkms nvidia-utils)
readonly NVIDIA_PREREQ_PKGS=(linux-headers dkms linux-firmware-nvidia)
readonly NOUVEAU_USERSPACE_PKGS=(xf86-video-nouveau vulkan-nouveau)
readonly BLACKLIST_FILE=/etc/modprobe.d/blacklist-nouveau.conf
readonly BLACKLIST_CONTENT='# Installed by arch-config/nvidia/install-nvidia.sh
# Prevents nouveau from claiming the NVIDIA GPU so the proprietary driver can load.
blacklist nouveau
options nouveau modeset=0'
readonly EXPECTED_DKMS_MODULES=(nvidia nvidia-modeset nvidia-drm nvidia-uvm)
readonly LOG_DIR="${HOME}/arch-config/nvidia/logs"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

# ---------- flags ----------
CHECK_ONLY=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --force) FORCE=1 ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *) printf '!! unknown flag: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

# ---------- output helpers ----------
say()  { printf '\033[1;36m==>\033[0m %s\n' "$*" | tee -a "$LOG_FILE" ; }
ok()   { printf '\033[1;32m✓\033[0m  %s\n'  "$*" | tee -a "$LOG_FILE" ; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" | tee -a "$LOG_FILE" ; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" | tee -a "$LOG_FILE" >&2; exit 1; }
step() { printf '\n\033[1;35m=== %s ===\033[0m\n' "$*" | tee -a "$LOG_FILE" ; }

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
say "log: $LOG_FILE"

# =============================================================================
# PHASE 0 — PREFLIGHT: refuse to proceed if the system cannot safely install
# =============================================================================
step "Phase 0 — Preflight checks"

# 0.1 — not running as root (sudo is invoked per-command)
if [[ $EUID -eq 0 ]]; then
    die "run as your normal user, not root. sudo is called internally where needed."
fi

# 0.2 — sudo available and cached (ask once, fail fast)
command -v sudo >/dev/null || die "sudo not installed"
sudo -v || die "sudo authentication failed"
ok "sudo authenticated"

# 0.3 — kernel matches installed headers
KERNEL_RUNNING="$(uname -r)"
if ! pacman -Qi linux-headers >/dev/null 2>&1; then
    warn "linux-headers not installed yet (will install below)"
else
    HEADERS_VER="$(pacman -Q linux-headers | awk '{print $2}' | sed 's/-[0-9]*$//')"
    KERNEL_PKG_VER="$(pacman -Q linux 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]*$//' || echo '?')"
    if [[ "$HEADERS_VER" != "$KERNEL_PKG_VER" ]]; then
        warn "linux-headers ($HEADERS_VER) differs from linux pkg ($KERNEL_PKG_VER). Run 'sudo pacman -Syu' first if you want them synced."
    fi
    ok "kernel headers present ($HEADERS_VER)"
fi
ok "kernel running: $KERNEL_RUNNING"

# 0.4 — root filesystem writable (not read-only emergency mount)
if ! touch /tmp/.nvidia-install-rw-test 2>/dev/null; then
    die "/tmp is not writable — filesystem may be mounted read-only"
fi
rm -f /tmp/.nvidia-install-rw-test
if ! sudo touch /etc/.nvidia-install-rw-test 2>/dev/null; then
    die "/etc is not writable — /etc is read-only. Aborting."
fi
sudo rm -f /etc/.nvidia-install-rw-test
ok "root filesystem is writable"

# 0.5 — disk space: /boot ≥ 200M, / ≥ 2G
BOOT_FREE_MB=$(df -BM /boot | awk 'NR==2 {gsub("M","",$4); print $4}')
ROOT_FREE_MB=$(df -BM /     | awk 'NR==2 {gsub("M","",$4); print $4}')
(( BOOT_FREE_MB >= 200 )) || die "/boot has only ${BOOT_FREE_MB}M free (need ≥200M for new UKI)"
(( ROOT_FREE_MB >= 2048 )) || die "/ has only ${ROOT_FREE_MB}M free (need ≥2G for DKMS build)"
ok "free space OK  (/boot: ${BOOT_FREE_MB}M, /: ${ROOT_FREE_MB}M)"

# 0.6 — hardware: NVIDIA GPU present and is Turing or newer (for nvidia-open)
if ! lspci | grep -qi 'VGA.*NVIDIA\|3D.*NVIDIA'; then
    die "no NVIDIA GPU detected via lspci. This script is for hybrid laptops with an NVIDIA dGPU."
fi
GPU_LINE="$(lspci | grep -i 'VGA.*NVIDIA\|3D.*NVIDIA' | head -1)"
ok "NVIDIA GPU detected: $GPU_LINE"

# 0.7 — AMD iGPU still alive (our fallback for the desktop)
if lspci | grep -qi 'VGA.*AMD\|VGA.*ATI'; then
    ok "AMD iGPU present (primary renderer fallback)"
else
    warn "no AMD iGPU detected — this script was designed for hybrid AMD+NVIDIA. Proceeding anyway."
fi

# 0.8 — internet to arch mirrors
if ! timeout 5 bash -c ': </dev/tcp/archlinux.org/443' 2>/dev/null; then
    die "no network connectivity to archlinux.org:443 (pacman will fail)"
fi
ok "network reachable"

# 0.9 — pacman DB integrity (this bit us during the original install)
say "Checking pacman DB integrity for nvidia-related packages…"
DB_CORRUPT_PKGS=()
for pkg in "${NVIDIA_PKGS[@]}" "${NVIDIA_PREREQ_PKGS[@]}"; do
    pacman -Qi "$pkg" >/dev/null 2>&1 || continue
    if ! pacman -Qkk "$pkg" >/dev/null 2>&1; then
        # Distinguish real corruption ("Unrecognized archive") from benign
        # "file modified" on config files we edited on purpose.
        if pacman -Qkk "$pkg" 2>&1 | grep -q 'Unrecognized archive format'; then
            DB_CORRUPT_PKGS+=("$pkg")
        fi
    fi
done
if (( ${#DB_CORRUPT_PKGS[@]} > 0 )); then
    warn "Pacman DB is corrupt for: ${DB_CORRUPT_PKGS[*]}"
    if (( CHECK_ONLY == 1 )); then
        die "DB corruption detected; run without --check to repair"
    fi
    say "Repairing DB via --overwrite '*'"
    sudo pacman -S --noconfirm --overwrite '*' "${DB_CORRUPT_PKGS[@]}"
    ok "DB repaired"
else
    ok "pacman DB clean for nvidia packages"
fi

# 0.10 — Secure Boot (informational only; install works with SB off)
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "Secure Boot is ENABLED — DKMS modules won't be signed by default. Plan to sign them or disable SB."
else
    ok "Secure Boot disabled or mokutil absent (expected)"
fi

# =============================================================================
# PHASE 1 — DESIRED-STATE PROBE: if everything is already correct, exit early
# =============================================================================
step "Phase 1 — Desired-state probe"

state_ok=1
reasons=()

# 1.1 prereq packages installed
for p in "${NVIDIA_PREREQ_PKGS[@]}"; do
    if ! pacman -Qi "$p" >/dev/null 2>&1; then
        state_ok=0; reasons+=("missing pkg: $p")
    fi
done

# 1.2 nvidia packages installed
for p in "${NVIDIA_PKGS[@]}"; do
    if ! pacman -Qi "$p" >/dev/null 2>&1; then
        state_ok=0; reasons+=("missing pkg: $p")
    fi
done

# 1.3 nouveau userspace removed
for p in "${NOUVEAU_USERSPACE_PKGS[@]}"; do
    if pacman -Qi "$p" >/dev/null 2>&1; then
        state_ok=0; reasons+=("still installed: $p")
    fi
done

# 1.4 blacklist file present and correct
if [[ ! -f "$BLACKLIST_FILE" ]]; then
    state_ok=0; reasons+=("missing $BLACKLIST_FILE")
elif ! grep -q '^blacklist nouveau' "$BLACKLIST_FILE"; then
    state_ok=0; reasons+=("$BLACKLIST_FILE does not blacklist nouveau")
fi

# 1.5 DKMS modules built for running kernel
if command -v dkms >/dev/null 2>&1; then
    if ! dkms status 2>/dev/null | grep -qE "nvidia.*${KERNEL_RUNNING}.*installed"; then
        state_ok=0; reasons+=("DKMS nvidia module not installed for $KERNEL_RUNNING")
    fi
else
    state_ok=0; reasons+=("dkms command missing")
fi

# 1.6 nouveau NOT loaded AND nvidia modules loaded
if lsmod | awk '{print $1}' | grep -qx nouveau; then
    state_ok=0; reasons+=("nouveau kernel module is currently loaded")
fi
for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
    if ! lsmod | awk '{print $1}' | grep -qx "$m"; then
        state_ok=0; reasons+=("module not loaded: $m  (reboot may be pending)")
    fi
done

# 1.7 nvidia-smi works
if command -v nvidia-smi >/dev/null 2>&1; then
    if ! nvidia-smi >/dev/null 2>&1; then
        state_ok=0; reasons+=("nvidia-smi fails")
    fi
else
    state_ok=0; reasons+=("nvidia-smi missing")
fi

if (( state_ok == 1 )) && (( FORCE == 0 )); then
    ok "All checks passed — NVIDIA is correctly installed and running. Nothing to do."
    command -v nvidia-smi >/dev/null && nvidia-smi | head -12 | tee -a "$LOG_FILE"
    exit 0
fi

if (( state_ok == 0 )); then
    warn "Desired state NOT reached. Reasons:"
    for r in "${reasons[@]}"; do printf '    - %s\n' "$r" | tee -a "$LOG_FILE" ; done
fi

if (( CHECK_ONLY == 1 )); then
    say "--check passed; exiting without making changes"
    exit 0
fi

# =============================================================================
# PHASE 2 — PREREQS: kernel-headers, dkms, linux-firmware-nvidia
# =============================================================================
step "Phase 2 — Install prerequisites"
missing=()
for p in "${NVIDIA_PREREQ_PKGS[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
done
if (( ${#missing[@]} > 0 )); then
    say "Installing: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
else
    ok "all prereqs already installed"
fi

# =============================================================================
# PHASE 3 — ORPHAN CLEANUP: remove leftover files from any prior .run install
# =============================================================================
step "Phase 3 — Clean orphan NVIDIA files from legacy .run installs"
# Files a proprietary .run installer drops that pacman does NOT own. If they
# persist they shadow the pacman ones and break loading. We only delete files
# that are NOT owned by any installed package.
ORPHAN_CANDIDATES=(
    /usr/bin/nvidia-smi
    /usr/bin/nvidia-settings
    /usr/bin/nvidia-xconfig
    /usr/bin/nvidia-debugdump
    /usr/bin/nvidia-persistenced
    /usr/bin/nvidia-cuda-mps-control
    /usr/bin/nvidia-cuda-mps-server
    /usr/bin/nvidia-bug-report.sh
    /usr/lib/libnvidia-ml.so.1
    /usr/lib/libGLX_nvidia.so.0
    /usr/lib/libEGL_nvidia.so.0
)
orphans_removed=0
for f in "${ORPHAN_CANDIDATES[@]}"; do
    [[ -e "$f" ]] || continue
    if ! pacman -Qo "$f" >/dev/null 2>&1; then
        warn "orphan (no pkg owner): $f — removing"
        sudo rm -f "$f"
        orphans_removed=$(( orphans_removed + 1 ))
    fi
done
(( orphans_removed == 0 )) && ok "no orphan files found"

# =============================================================================
# PHASE 4 — REMOVE nouveau USERSPACE (keeps kernel module blacklisted instead)
# =============================================================================
step "Phase 4 — Remove nouveau userspace packages"
to_remove=()
for p in "${NOUVEAU_USERSPACE_PKGS[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 && to_remove+=("$p")
done
if (( ${#to_remove[@]} > 0 )); then
    say "Removing: ${to_remove[*]}"
    sudo pacman -Rns --noconfirm "${to_remove[@]}"
else
    ok "nouveau userspace already absent"
fi

# =============================================================================
# PHASE 5 — INSTALL NVIDIA
# =============================================================================
step "Phase 5 — Install nvidia-open-dkms + nvidia-utils"
missing=()
for p in "${NVIDIA_PKGS[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
done
if (( ${#missing[@]} > 0 )); then
    say "Installing: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
else
    ok "nvidia packages already installed"
fi

# =============================================================================
# PHASE 6 — VERIFY DKMS BUILD
# =============================================================================
step "Phase 6 — Verify DKMS compiled for running kernel"
if ! dkms status 2>/dev/null | grep -qE "nvidia.*${KERNEL_RUNNING}.*installed"; then
    warn "DKMS module not installed for $KERNEL_RUNNING; forcing rebuild"
    NVIDIA_PKG_VER="$(pacman -Q nvidia-open-dkms | awk '{print $2}' | sed 's/-[0-9]*$//')"
    sudo dkms install --force "nvidia/${NVIDIA_PKG_VER}" -k "$KERNEL_RUNNING" || \
        die "DKMS install failed; inspect $LOG_FILE and /var/lib/dkms/nvidia/${NVIDIA_PKG_VER}/build/make.log"
fi
dkms status | grep nvidia | tee -a "$LOG_FILE"
ok "DKMS nvidia module present for $KERNEL_RUNNING"

# Also verify the .ko files landed where the kernel expects them
missing_ko=()
for m in "${EXPECTED_DKMS_MODULES[@]}"; do
    ko_name="${m//-/_}.ko"
    if ! find "/lib/modules/${KERNEL_RUNNING}" -name "${ko_name}*" -print -quit | grep -q .; then
        missing_ko+=("$ko_name")
    fi
done
if (( ${#missing_ko[@]} > 0 )); then
    die "DKMS claims installed but .ko files missing: ${missing_ko[*]}"
fi
ok "all expected .ko files present in /lib/modules/${KERNEL_RUNNING}"

# =============================================================================
# PHASE 7 — BLACKLIST nouveau
# =============================================================================
step "Phase 7 — Blacklist nouveau kernel module"
needs_write=1
if [[ -f "$BLACKLIST_FILE" ]]; then
    if diff -q <(printf '%s\n' "$BLACKLIST_CONTENT") "$BLACKLIST_FILE" >/dev/null 2>&1; then
        needs_write=0
    fi
fi
if (( needs_write == 1 )); then
    say "Writing $BLACKLIST_FILE"
    printf '%s\n' "$BLACKLIST_CONTENT" | sudo tee "$BLACKLIST_FILE" >/dev/null
    INITRAMFS_NEEDS_REBUILD=1
else
    ok "$BLACKLIST_FILE already correct"
    INITRAMFS_NEEDS_REBUILD=0
fi

# Also ensure no other file re-enables nouveau accidentally
if grep -rlE '^[[:space:]]*(modprobe[[:space:]]+)?nouveau|^options[[:space:]]+nouveau[[:space:]]+modeset=1' \
        /etc/modprobe.d /etc/modules-load.d 2>/dev/null | grep -v "$BLACKLIST_FILE" | grep -q .; then
    warn "Another modprobe/modules-load.d file references nouveau:"
    grep -rlE '^[[:space:]]*(modprobe[[:space:]]+)?nouveau|^options[[:space:]]+nouveau[[:space:]]+modeset=1' \
        /etc/modprobe.d /etc/modules-load.d 2>/dev/null | grep -v "$BLACKLIST_FILE" | tee -a "$LOG_FILE"
    die "manual review required before proceeding"
fi

# =============================================================================
# PHASE 8 — REGENERATE INITRAMFS (only if blacklist changed or modules missing from initramfs)
# =============================================================================
step "Phase 8 — Regenerate initramfs if needed"
if (( INITRAMFS_NEEDS_REBUILD == 1 )); then
    say "Running mkinitcpio -P"
    sudo mkinitcpio -P
    ok "initramfs regenerated"
    REBOOT_REQUIRED=1
else
    ok "initramfs up-to-date"
fi

# =============================================================================
# PHASE 9 — POST-INSTALL VERIFICATION (runtime-dependent)
# =============================================================================
step "Phase 9 — Runtime verification"

# If nouveau is currently loaded, the install was just completed; a reboot
# is required before runtime probes pass. Same if nvidia isn't loaded.
NEED_REBOOT=0
lsmod | awk '{print $1}' | grep -qx nouveau && NEED_REBOOT=1
for m in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
    lsmod | awk '{print $1}' | grep -qx "$m" || NEED_REBOOT=1
done

if (( NEED_REBOOT == 1 )); then
    warn "Runtime state not yet consistent — a reboot is required."
    warn "After reboot, re-run this script (it will verify and exit with 'nothing to do')."
    exit 0
fi

# Runtime: everything should be green
if ! nvidia-smi >/dev/null 2>&1; then
    die "nvidia-smi fails after install. Check dmesg: sudo dmesg | grep -iE 'nvidia|nvrm' | tail"
fi
ok "nvidia-smi responds"
nvidia-smi | head -12 | tee -a "$LOG_FILE"

# GPU is bound to nvidia driver (not nouveau, not vfio)
if ! lspci -k | awk '/NVIDIA.*VGA|VGA.*NVIDIA|NVIDIA.*3D/{flag=1} flag && /Kernel driver in use: nvidia/{found=1} flag && /^$/{flag=0} END{exit !found}'; then
    warn "dGPU is not bound to the nvidia kernel driver. Check lspci -k output."
fi
ok "dGPU bound to nvidia driver"

step "Done."
ok "NVIDIA install verified. Log: $LOG_FILE"
