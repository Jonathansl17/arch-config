# shellcheck shell=bash
# GRUB menu configuration for systems that boot a Unified Kernel Image (UKI).
# Sourced, never executed. Every function that writes assumes it runs as root.
#
# mkinitcpio builds only the UKI, so no initramfs-linux.img exists. GRUB's
# 10_linux generator still emits a "vmlinuz-linux + initramfs" entry, puts it
# first, and that entry kernel-panics. Every regeneration here removes those
# generators first so the UKI entry (15_uki) becomes the default.

readonly GRUB_DEFAULTS="/etc/default/grub"
readonly GRUB_CFG="/boot/grub/grub.cfg"
readonly GRUB_D_PARENT="/"
readonly PACMAN_CONF="/etc/pacman.conf"
readonly UKI_DIR="/boot/EFI/Linux"
# Relative to /, as pacman's NoExtract expects.
readonly LEGACY_GENERATORS=(etc/grub.d/10_linux etc/grub.d/20_linux_xen)
readonly PACMAN_OPTIONS_SECTION="[options]"

# backup_file FILE: copy FILE next to itself with a timestamp suffix.
backup_file() {
    cp -p "$1" "$1.bak-$(date +%Y%m%d-%H%M%S)"
}

# set_grub_key FILE KEY VALUE: make FILE contain exactly one active KEY=VALUE.
# Returns 0 without touching FILE when it is already set.
set_grub_key() {
    local file="$1" key="$2" value="$3"
    grep -qxF "$key=$value" "$file" && return 0
    if grep -q "^$key=" "$file"; then
        sed -i "s|^$key=.*|$key=$value|" "$file"
    else
        echo "$key=$value" >>"$file"
    fi
}

# has_noextract CONF PATH: true when an active NoExtract line lists PATH.
has_noextract() {
    grep -E '^[[:space:]]*NoExtract[[:space:]]*=' "$1" |
        tr ' \t=' '\n\n\n' | grep -qxF "$2"
}

# add_noextract CONF PATH: add "NoExtract = PATH" under [options] if missing.
add_noextract() {
    local conf="$1" path="$2"
    has_noextract "$conf" "$path" && return 0
    if ! grep -qxF "$PACMAN_OPTIONS_SECTION" "$conf"; then
        echo "ERROR: no $PACMAN_OPTIONS_SECTION section in $conf" >&2
        return 1
    fi
    sed -i "/^\[options\]\$/a NoExtract   = $path" "$conf"
}

# uki_present DIR: true when DIR holds at least one .efi image.
uki_present() {
    compgen -G "$1/*.efi" >/dev/null
}

# drop_legacy_generators CONF ROOT: block and delete the vmlinuz+initramfs
# generators under ROOT so pacman never reinstalls them.
drop_legacy_generators() {
    local conf="$1" root="$2" path
    for path in "${LEGACY_GENERATORS[@]}"; do
        add_noextract "$conf" "$path" || return 1
        rm -f "${root%/}/$path" || return 1
    done
}

# legacy_generators_left CONF ROOT: true when a generator file or a missing
# NoExtract line remains.
legacy_generators_left() {
    local conf="$1" root="$2" path
    for path in "${LEGACY_GENERATORS[@]}"; do
        [[ -e "${root%/}/$path" ]] && return 0
        has_noextract "$conf" "$path" || return 0
    done
    return 1
}

# ensure_uki_only_menu: on UKI systems, remove the panicking menu entries.
# Leaves non-UKI systems alone, since 10_linux is their only Linux entry.
ensure_uki_only_menu() {
    uki_present "$UKI_DIR" || return 0
    legacy_generators_left "$PACMAN_CONF" "$GRUB_D_PARENT" || return 0
    backup_file "$PACMAN_CONF" || return 1
    drop_legacy_generators "$PACMAN_CONF" "$GRUB_D_PARENT" || return 1
    echo "  [boot] removed vmlinuz+initramfs GRUB entries (UKI boots instead)"
}

# grub_available: GRUB is installed and has a generated menu.
grub_available() {
    command -v grub-mkconfig >/dev/null 2>&1 && [[ -f "$GRUB_CFG" ]]
}

# regenerate_grub: rebuild grub.cfg, never leaving a panicking default entry.
regenerate_grub() {
    ensure_uki_only_menu || return 1
    grub-mkconfig -o "$GRUB_CFG"
}

# set_grub_menu TIMEOUT STYLE: set the menu timeout and style, then rebuild.
set_grub_menu() {
    local timeout="$1" style="$2"
    if grep -qxF "GRUB_TIMEOUT=$timeout" "$GRUB_DEFAULTS" &&
        grep -qxF "GRUB_TIMEOUT_STYLE=$style" "$GRUB_DEFAULTS"; then
        echo "  [boot] already GRUB_TIMEOUT=$timeout, GRUB_TIMEOUT_STYLE=$style"
        return 0
    fi
    backup_file "$GRUB_DEFAULTS" || return 1
    set_grub_key "$GRUB_DEFAULTS" GRUB_TIMEOUT "$timeout" || return 1
    set_grub_key "$GRUB_DEFAULTS" GRUB_TIMEOUT_STYLE "$style" || return 1
    regenerate_grub
}
