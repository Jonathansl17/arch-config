# wifi-saved.sh — picker for saved WiFi connections, shared by every `wifi`
# menu entry that acts on an existing profile.
# Sourced by `wifi`; not meant to be executed directly.

# choose_saved_connection <prompt>
# CHOSEN=selected connection name. Returns 2 if user typed q or none exist.
choose_saved_connection() {
  local saved=() choice
  echo ""
  echo -e "${YELLOW}Saved WiFi connections:${NC}"
  echo ""
  mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | grep ':.*wireless' | cut -d: -f1)

  if [[ ${#saved[@]} -eq 0 ]]; then
    echo -e "${RED}No saved WiFi connections found.${NC}"
    return 2
  fi

  for i in "${!saved[@]}"; do
    printf "  %d) %s\n" $((i+1)) "${saved[$i]}"
  done
  echo ""

  while true; do
    read_input "$1 [1-${#saved[@]}, q=back]: " || return 2
    choice="$REPLY"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#saved[@]} )); then
      CHOSEN="${saved[$((choice-1))]}"
      return 0
    fi
    invalid
  done
}

# offer_reconnect <connection>
# Profile changes only apply on the next activation, so offer to reconnect
# when the edited profile is the active one.
offer_reconnect() {
  is_active_connection "$1" || return 0
  echo -e "${YELLOW}Reconnecting now drops the network for a few seconds.${NC}"
  read_input "Reconnect now? [y/N, q=back]: " || return 2
  [[ "$REPLY" == "y" || "$REPLY" == "Y" ]] || return 0
  nmcli connection up "$1"
  verify_activation "$1" $?
}
