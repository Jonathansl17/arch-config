# wifi-mac.sh — MAC address mode picker for the `wifi` command.
# Sourced by `wifi`; not meant to be executed directly.

# Values understood by 802-11-wireless.cloned-mac-address.
readonly MAC_MODE_STABLE="stable"
readonly MAC_MODE_RANDOM="random"
readonly MAC_MODE_PERMANENT="permanent"
readonly MAC_MODE_PROPERTY="802-11-wireless.cloned-mac-address"

# choose_mac_mode
# MAC_MODE=selected mode. Enter picks stable. Returns 2 if user typed q.
choose_mac_mode() {
  while true; do
    echo ""
    echo "  1) Stable  (fake, always the same on this network) [default]"
    echo "  2) Random  (fake, new one on every connection)"
    echo "  3) Real    (hardware MAC)"
    echo ""
    read_input "Select MAC address type [1/2/3, Enter=1, q=back]: " || return 2
    case "${REPLY:-1}" in
      1) MAC_MODE="$MAC_MODE_STABLE"; return 0 ;;
      2) MAC_MODE="$MAC_MODE_RANDOM"; return 0 ;;
      3) MAC_MODE="$MAC_MODE_PERMANENT"; return 0 ;;
      *) invalid ;;
    esac
  done
}
