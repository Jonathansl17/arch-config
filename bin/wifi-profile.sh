# wifi-profile.sh — builds the security properties of a new WiFi profile and
# saves it in NetworkManager for the `wifi` command.
# Sourced by `wifi`; not meant to be executed directly.

# personal_key_mgmt <scan-security>
# WPA3-only networks require SAE. Anything still advertising WPA1/WPA2,
# including WPA2/WPA3 transition networks, accepts a PSK.
personal_key_mgmt() {
  if [[ "$1" == *WPA3* && "$1" != *WPA2* && "$1" != *WPA1* ]]; then
    echo "sae"
  else
    echo "wpa-psk"
  fi
}

# choose_eap
# EAP and PHASE2 = selected method. Returns 2 if user typed q.
choose_eap() {
  while true; do
    echo ""
    echo "  1) PEAP + MSCHAPv2 (most common)"
    echo "  2) TTLS + PAP"
    echo "  3) TTLS + MSCHAPv2"
    echo ""
    read_input "Select EAP method [1/2/3, q=back]: " || return 2
    case "$REPLY" in
      1) EAP="peap"; PHASE2="mschapv2"; return 0 ;;
      2) EAP="ttls"; PHASE2="pap"; return 0 ;;
      3) EAP="ttls"; PHASE2="mschapv2"; return 0 ;;
      *) invalid ;;
    esac
  done
}

# prompt_security_args <security-choice> <scan-security>
# SEC_ARGS=nmcli properties for the chosen security type (empty when open).
# Returns 2 if user typed q.
prompt_security_args() {
  local identity password
  SEC_ARGS=()
  case "$1" in
    2)
      read_input "Password (q=back): " 1 || return 2
      SEC_ARGS=(wifi-sec.key-mgmt "$(personal_key_mgmt "$2")" wifi-sec.psk "$REPLY")
      ;;
    3)
      read_input "Identity (user, q=back): " || return 2
      identity="$REPLY"
      read_input "Password (q=back): " 1 || return 2
      password="$REPLY"
      choose_eap || return 2
      # password-flags 0 stores the secret in the system store; without it
      # NetworkManager can fail activation with reason 'no-secrets'.
      SEC_ARGS=(wifi-sec.key-mgmt wpa-eap 802-1x.eap "$EAP" 802-1x.phase2-auth "$PHASE2"
        802-1x.identity "$identity" 802-1x.password "$password" 802-1x.password-flags 0)
      ;;
  esac
  return 0
}

# add_profile <ssid> [nmcli properties...]
add_profile() {
  local ssid="$1"
  shift
  nmcli connection add type wifi con-name "$ssid" ifname "$WIFI_IFACE" ssid "$ssid" "$@"
}
