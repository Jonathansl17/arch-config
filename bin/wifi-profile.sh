# wifi-profile.sh — builds the security properties of a new WiFi profile and
# saves it in NetworkManager for the `wifi` command.
# Sourced by `wifi`; not meant to be executed directly.

readonly SEC_OPEN=1
readonly SEC_PERSONAL=2
readonly SEC_ENTERPRISE=3
readonly NMCLI_EMPTY_FIELD="--"
declare -rA SEC_LABELS=(
  [$SEC_OPEN]="Open (no password)"
  [$SEC_PERSONAL]="WPA/WPA2 Personal (password only)"
  [$SEC_ENTERPRISE]="WPA2 Enterprise (user + password)"
)

# detect_security_choice <scan-security>
# Prints the security type inferred from nmcli's SECURITY scan field.
# Returns 1 when the value is not recognised (WEP, OWE, ...), so the caller
# can fall back to asking the user.
detect_security_choice() {
  local sec="$1"
  if [[ -z "$sec" || "$sec" == "$NMCLI_EMPTY_FIELD" ]]; then
    echo "$SEC_OPEN"
  elif [[ "$sec" == *802.1X* ]]; then
    echo "$SEC_ENTERPRISE"
  elif [[ "$sec" =~ (^|[[:space:]])WPA[123]($|[[:space:]]) ]]; then
    echo "$SEC_PERSONAL"
  else
    return 1
  fi
}

# choose_security_type <scan-security>
# SEC_CHOICE=detected security type, or the user's pick when detection fails.
# Returns 2 if user typed q.
choose_security_type() {
  local choice
  if SEC_CHOICE=$(detect_security_choice "$1"); then
    echo -e "Detected security: ${GREEN}${SEC_LABELS[$SEC_CHOICE]}${NC}"
    return 0
  fi
  echo -e "${YELLOW}Unrecognised security type '$1'. Choose it manually.${NC}"
  while true; do
    echo ""
    for choice in "$SEC_OPEN" "$SEC_PERSONAL" "$SEC_ENTERPRISE"; do
      echo "  $choice) ${SEC_LABELS[$choice]}"
    done
    echo ""
    read_input "Select security type [1/2/3, q=back]: " || return 2
    if [[ -n "${SEC_LABELS[$REPLY]+set}" ]]; then
      SEC_CHOICE="$REPLY"
      return 0
    fi
    invalid
  done
}

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
    "$SEC_PERSONAL")
      read_input "Password (q=back): " 1 || return 2
      SEC_ARGS=(wifi-sec.key-mgmt "$(personal_key_mgmt "$2")" wifi-sec.psk "$REPLY")
      ;;
    "$SEC_ENTERPRISE")
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
