# wifi-edit.sh — edits the credentials and autoconnect flag of a saved WiFi
# profile for the `wifi` command.
# Sourced by `wifi`; not meant to be executed directly.

readonly KEY_MGMT_PROPERTY="802-11-wireless-security.key-mgmt"
readonly PSK_PROPERTY="wifi-sec.psk"
readonly EAP_IDENTITY_PROPERTY="802-1x.identity"
readonly EAP_PASSWORD_PROPERTY="802-1x.password"
readonly EAP_PASSWORD_FLAGS_PROPERTY="802-1x.password-flags"
readonly AUTOCONNECT_PROPERTY="connection.autoconnect"
readonly KEY_MGMT_EAP="wpa-eap"
# Flag 0 keeps the secret in the system store (see wifi-profile.sh).
readonly EAP_PASSWORD_FLAGS_SYSTEM="0"

# modify_profile <connection> [nmcli properties...]
# Applies the properties and reports the result.
modify_profile() {
  local name="$1"
  shift
  if ! nmcli connection modify "$name" "$@"; then
    echo -e "${RED}Failed to update $name.${NC}"
    return 1
  fi
  echo -e "${GREEN}$name updated.${NC}"
}

# change_password <connection> <key-mgmt>
change_password() {
  read_input "New password (q=back): " 1 || return 2
  if [[ "$2" == "$KEY_MGMT_EAP" ]]; then
    modify_profile "$1" "$EAP_PASSWORD_PROPERTY" "$REPLY" \
      "$EAP_PASSWORD_FLAGS_PROPERTY" "$EAP_PASSWORD_FLAGS_SYSTEM" || return 1
  else
    modify_profile "$1" "$PSK_PROPERTY" "$REPLY" || return 1
  fi
  offer_reconnect "$1"
}

# change_identity <connection>
change_identity() {
  echo -e "Current user: ${GREEN}$(nmcli -g "$EAP_IDENTITY_PROPERTY" connection show "$1")${NC}"
  read_input "New user (q=back): " || return 2
  modify_profile "$1" "$EAP_IDENTITY_PROPERTY" "$REPLY" || return 1
  offer_reconnect "$1"
}

# change_autoconnect <connection>
change_autoconnect() {
  echo -e "Autoconnect now: ${GREEN}$(nmcli -g "$AUTOCONNECT_PROPERTY" connection show "$1")${NC}"
  while true; do
    read_input "Connect automatically to $1? [y/n, q=back]: " || return 2
    case "$REPLY" in
      y|Y) modify_profile "$1" "$AUTOCONNECT_PROPERTY" yes; return ;;
      n|N) modify_profile "$1" "$AUTOCONNECT_PROPERTY" no; return ;;
      *) invalid ;;
    esac
  done
}

# edit_saved
# Offers only the edits that apply to the profile's security type: open
# networks have no password, and only Enterprise (802.1X) has a user.
edit_saved() {
  local key_mgmt
  choose_saved_connection "Select a connection to edit" || return $?
  key_mgmt=$(nmcli -g "$KEY_MGMT_PROPERTY" connection show "$CHOSEN")
  while true; do
    echo ""
    [[ -n "$key_mgmt" ]] && echo "  1) Change password"
    [[ "$key_mgmt" == "$KEY_MGMT_EAP" ]] && echo "  2) Change user"
    echo "  3) Autoconnect on/off"
    echo ""
    read_input "Choose what to edit in $CHOSEN [q=back]: " || return 2
    case "$REPLY" in
      1) [[ -n "$key_mgmt" ]] && { change_password "$CHOSEN" "$key_mgmt"; return; } ;;
      2) [[ "$key_mgmt" == "$KEY_MGMT_EAP" ]] && { change_identity "$CHOSEN"; return; } ;;
      3) change_autoconnect "$CHOSEN"; return ;;
    esac
    invalid
  done
}
