#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# read_input "prompt" [silent]
# REPLY=text. Returns 2 if user typed q/Q (back).
read_input() {
  local prompt="$1" silent="$2"
  if [[ -n "$silent" ]]; then
    read -rsp "$prompt" REPLY
    echo ""
  else
    read -rp "$prompt" REPLY
  fi
  [[ "$REPLY" == "q" || "$REPLY" == "Q" ]] && return 2
  return 0
}

show_status() {
  local eth_conn wifi_conn
  eth_conn=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /ethernet/ {print $1; exit}')
  wifi_conn=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /wireless/ {print $1; exit}')
  echo -e "${CYAN}=== WiFi Manager ===${NC}"
  echo ""
  if [[ -n "$eth_conn" ]]; then
    echo -e "  LAN:  ${GREEN}Connected${NC} → ${GREEN}$eth_conn${NC}"
  else
    echo -e "  LAN:  ${YELLOW}Disconnected${NC}"
  fi
  if [[ -n "$wifi_conn" ]]; then
    echo -e "  WiFi: ${GREEN}Connected${NC} → ${GREEN}$wifi_conn${NC}"
  else
    echo -e "  WiFi: ${YELLOW}Disconnected${NC}"
  fi
}

invalid() { echo -e "${RED}Invalid selection. Try again (q to go back).${NC}"; }

connect_new() {
  local networks=() ssid signal security net_choice sec_choice
  while true; do
    echo ""
    echo -e "${YELLOW}Scanning available networks...${NC}"
    nmcli device wifi rescan >/dev/null 2>&1
    mapfile -t networks < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | grep -v '^:' | sort -t: -k2 -rn | awk -F: '!seen[$1]++')

    if [[ ${#networks[@]} -eq 0 ]]; then
      echo -e "${RED}No networks found.${NC}"
      return 0
    fi

    echo ""
    echo -e "${CYAN}Available networks:${NC}"
    echo ""
    for i in "${!networks[@]}"; do
      IFS=: read -r ssid signal security <<< "${networks[$i]}"
      printf "  %d) %-30s Signal: %s%%  Security: %s\n" $((i+1)) "$ssid" "$signal" "${security:-Open}"
    done

    echo ""
    while true; do
      read_input "Select a network [1-${#networks[@]}, 0=rescan, q=back]: " || return 2
      net_choice="$REPLY"
      if [[ "$net_choice" == "0" ]]; then
        clear
        break
      fi
      if [[ "$net_choice" =~ ^[0-9]+$ ]] && (( net_choice >= 1 && net_choice <= ${#networks[@]} )); then
        break 2
      fi
      invalid
    done
  done

  IFS=: read -r ssid signal security <<< "${networks[$((net_choice-1))]}"

  echo ""
  echo -e "Selected: ${GREEN}$ssid${NC} (${security:-Open})"

  if nmcli -t -f NAME,TYPE connection show | grep -q "^${ssid}:.*wireless$"; then
    echo -e "${YELLOW}Saved connection found. Connecting...${NC}"
    if nmcli connection up "$ssid"; then
      echo -e "${GREEN}Connected to $ssid successfully!${NC}"
    else
      echo -e "${RED}Failed to connect to $ssid.${NC}"
    fi
    return 0
  fi

  while true; do
    echo ""
    echo "  1) Open (no password)"
    echo "  2) WPA/WPA2 Personal (password only)"
    echo "  3) WPA2 Enterprise (user + password)"
    echo ""
    read_input "Select security type [1/2/3, q=back]: " || return 2
    sec_choice="$REPLY"
    case "$sec_choice" in
      1|2|3) break ;;
      *) invalid ;;
    esac
  done

  case "$sec_choice" in
    1)
      nmcli device wifi connect "$ssid"
      ;;
    2)
      local wifi_pass
      read_input "Password (q=back): " 1 || return 2
      wifi_pass="$REPLY"
      nmcli device wifi connect "$ssid" password "$wifi_pass" ifname wlp4s0
      ;;
    3)
      local identity wifi_pass eap phase2 eap_choice
      read_input "Identity (user, q=back): " || return 2
      identity="$REPLY"
      read_input "Password (q=back): " 1 || return 2
      wifi_pass="$REPLY"
      while true; do
        echo ""
        echo "  1) PEAP + MSCHAPv2 (most common)"
        echo "  2) TTLS + PAP"
        echo "  3) TTLS + MSCHAPv2"
        echo ""
        read_input "Select EAP method [1/2/3, q=back]: " || return 2
        eap_choice="$REPLY"
        case "$eap_choice" in
          1) eap="peap"; phase2="mschapv2"; break ;;
          2) eap="ttls"; phase2="pap"; break ;;
          3) eap="ttls"; phase2="mschapv2"; break ;;
          *) invalid ;;
        esac
      done
      nmcli connection add type wifi con-name "$ssid" ifname wlp4s0 ssid "$ssid" \
        wifi-sec.key-mgmt wpa-eap \
        802-1x.eap "$eap" \
        802-1x.phase2-auth "$phase2" \
        802-1x.identity "$identity" \
        802-1x.password "$wifi_pass"
      nmcli connection up "$ssid"
      ;;
  esac

  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Connected to $ssid successfully!${NC}"
  else
    echo -e "${RED}Failed to connect to $ssid.${NC}"
  fi
}

reconnect_saved() {
  local saved=() re_choice chosen
  echo ""
  echo -e "${YELLOW}Saved WiFi connections:${NC}"
  echo ""
  mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | grep ':.*wireless' | cut -d: -f1)

  if [[ ${#saved[@]} -eq 0 ]]; then
    echo -e "${RED}No saved WiFi connections found.${NC}"
    return 0
  fi

  for i in "${!saved[@]}"; do
    printf "  %d) %s\n" $((i+1)) "${saved[$i]}"
  done
  echo ""

  while true; do
    read_input "Select a connection [1-${#saved[@]}, q=back]: " || return 2
    re_choice="$REPLY"
    if [[ "$re_choice" =~ ^[0-9]+$ ]] && (( re_choice >= 1 && re_choice <= ${#saved[@]} )); then
      break
    fi
    invalid
  done

  chosen="${saved[$((re_choice-1))]}"
  echo -e "${YELLOW}Connecting to $chosen...${NC}"
  if nmcli connection up "$chosen"; then
    echo -e "${GREEN}Connected to $chosen successfully!${NC}"
  else
    echo -e "${RED}Failed to connect to $chosen.${NC}"
  fi
}

disconnect_current() {
  local active
  echo ""
  active=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /wireless/ {print $1; exit}')
  if [[ -z "$active" ]]; then
    echo -e "${YELLOW}No hay ninguna red WiFi conectada.${NC}"
    return 0
  fi
  echo -e "${YELLOW}Disconnecting from $active...${NC}"
  if nmcli connection down "$active"; then
    echo -e "${GREEN}Disconnected from $active.${NC}"
  else
    echo -e "${RED}Failed to disconnect from $active.${NC}"
  fi
}

delete_saved() {
  local saved=() del_choice target confirm
  echo ""
  echo -e "${YELLOW}Saved WiFi connections:${NC}"
  echo ""
  mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | grep ':.*wireless' | cut -d: -f1)

  if [[ ${#saved[@]} -eq 0 ]]; then
    echo -e "${RED}No saved WiFi connections found.${NC}"
    return 0
  fi

  for i in "${!saved[@]}"; do
    printf "  %d) %s\n" $((i+1)) "${saved[$i]}"
  done
  echo ""

  while true; do
    read_input "Select a connection to delete [1-${#saved[@]}, q=back]: " || return 2
    del_choice="$REPLY"
    if [[ "$del_choice" =~ ^[0-9]+$ ]] && (( del_choice >= 1 && del_choice <= ${#saved[@]} )); then
      break
    fi
    invalid
  done

  target="${saved[$((del_choice-1))]}"
  echo ""
  read_input "Are you sure you want to delete '$target'? [y/N, q=back]: " || return 2
  confirm="$REPLY"
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    return 0
  fi

  if nmcli connection delete "$target"; then
    echo -e "${GREEN}Connection '$target' deleted.${NC}"
  else
    echo -e "${RED}Failed to delete '$target'.${NC}"
  fi
}

show_status

while true; do
  echo ""
  echo "  1) Connect to a new network"
  echo "  2) Reconnect to a saved network"
  echo "  3) Disconnect current network"
  echo "  4) Delete a saved connection"
  echo ""
  read_input "Choose an option [1/2/3/4, q=quit]: " || exit 0
  case "$REPLY" in
    1) connect_new ;;
    2) reconnect_saved ;;
    3) disconnect_current ;;
    4) delete_saved ;;
    *) invalid; continue ;;
  esac
  rc=$?
  if [[ $rc -eq 2 ]]; then
    echo ""
    show_status
    continue
  fi
  exit 0
done
