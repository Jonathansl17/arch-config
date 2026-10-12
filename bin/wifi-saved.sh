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
