#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== WiFi Manager ===${NC}"
echo ""

current=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /wireless/ {print $1; exit}')
if [[ -n "$current" ]]; then
  echo -e "  Status: ${GREEN}Connected${NC} → ${GREEN}$current${NC}"
else
  echo -e "  Status: ${YELLOW}Disconnected${NC}"
fi

echo ""
echo "  1) Connect to a new network"
echo "  2) Reconnect to a saved network"
echo "  3) Disconnect current network"
echo "  4) Delete a saved connection"
echo ""
read -rp "Choose an option [1/2/3/4]: " option

case "$option" in
  1)
    echo ""
    echo -e "${YELLOW}Scanning available networks...${NC}"
    mapfile -t networks < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | grep -v '^:' | sort -t: -k2 -rn | awk -F: '!seen[$1]++')

    if [[ ${#networks[@]} -eq 0 ]]; then
      echo -e "${RED}No networks found.${NC}"
      exit 1
    fi

    echo ""
    echo -e "${CYAN}Available networks:${NC}"
    echo ""
    for i in "${!networks[@]}"; do
      IFS=: read -r ssid signal security <<< "${networks[$i]}"
      printf "  %d) %-30s Signal: %s%%  Security: %s\n" $((i+1)) "$ssid" "$signal" "${security:-Open}"
    done

    echo ""
    read -rp "Select a network [1-${#networks[@]}]: " net_choice

    if [[ -z "$net_choice" ]] || [[ "$net_choice" -lt 1 ]] || [[ "$net_choice" -gt ${#networks[@]} ]]; then
      echo -e "${RED}Invalid selection.${NC}"
      exit 1
    fi

    IFS=: read -r ssid signal security <<< "${networks[$((net_choice-1))]}"

    echo ""
    echo -e "Selected: ${GREEN}$ssid${NC} (${security:-Open})"
    echo ""
    echo "  1) Open (no password)"
    echo "  2) WPA/WPA2 Personal (password only)"
    echo "  3) WPA2 Enterprise (user + password)"
    echo ""
    read -rp "Select security type [1/2/3]: " sec_choice

    case "$sec_choice" in
      1)
        if nmcli connection show "$ssid" &>/dev/null; then
          nmcli connection up "$ssid"
        else
          nmcli device wifi connect "$ssid"
        fi
        ;;
      2)
        read -rp "Password: " -s wifi_pass
        echo ""
        if nmcli connection show "$ssid" &>/dev/null; then
          nmcli connection up "$ssid"
        else
          nmcli device wifi connect "$ssid" password "$wifi_pass" ifname wlp4s0
        fi
        ;;
      3)
        read -rp "Identity (user): " identity
        read -rp "Password: " -s wifi_pass
        echo ""
        echo ""
        echo "  1) PEAP + MSCHAPv2 (most common)"
        echo "  2) TTLS + PAP"
        echo "  3) TTLS + MSCHAPv2"
        echo ""
        read -rp "Select EAP method [1/2/3]: " eap_choice

        case "$eap_choice" in
          1) eap="peap"; phase2="mschapv2" ;;
          2) eap="ttls"; phase2="pap" ;;
          3) eap="ttls"; phase2="mschapv2" ;;
          *)
            echo -e "${RED}Invalid selection. Defaulting to PEAP + MSCHAPv2.${NC}"
            eap="peap"; phase2="mschapv2"
            ;;
        esac

        if nmcli connection show "$ssid" &>/dev/null; then
          nmcli connection up "$ssid"
        else
          nmcli connection add type wifi con-name "$ssid" ifname wlp4s0 ssid "$ssid" \
            wifi-sec.key-mgmt wpa-eap \
            802-1x.eap "$eap" \
            802-1x.phase2-auth "$phase2" \
            802-1x.identity "$identity" \
            802-1x.password "$wifi_pass"
          nmcli connection up "$ssid"
        fi
        ;;
      *)
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
        ;;
    esac

    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}Connected to $ssid successfully!${NC}"
    else
      echo -e "${RED}Failed to connect to $ssid.${NC}"
    fi
    ;;

  2)
    echo ""
    echo -e "${YELLOW}Saved WiFi connections:${NC}"
    echo ""
    mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | grep ':.*wireless' | cut -d: -f1)

    if [[ ${#saved[@]} -eq 0 ]]; then
      echo -e "${RED}No saved WiFi connections found.${NC}"
      exit 1
    fi

    for i in "${!saved[@]}"; do
      printf "  %d) %s\n" $((i+1)) "${saved[$i]}"
    done

    echo ""
    read -rp "Select a connection [1-${#saved[@]}]: " re_choice

    if [[ -z "$re_choice" ]] || [[ "$re_choice" -lt 1 ]] || [[ "$re_choice" -gt ${#saved[@]} ]]; then
      echo -e "${RED}Invalid selection.${NC}"
      exit 1
    fi

    chosen="${saved[$((re_choice-1))]}"

    echo -e "${YELLOW}Connecting to $chosen...${NC}"
    if nmcli connection up "$chosen"; then
      echo -e "${GREEN}Connected to $chosen successfully!${NC}"
    else
      echo -e "${RED}Failed to connect to $chosen.${NC}"
    fi
    ;;

  3)
    echo ""
    active=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 ~ /wireless/ {print $1; exit}')
    if [[ -z "$active" ]]; then
      echo -e "${YELLOW}No hay ninguna red WiFi conectada.${NC}"
      exit 0
    fi
    echo -e "${YELLOW}Disconnecting from $active...${NC}"
    if nmcli connection down "$active"; then
      echo -e "${GREEN}Disconnected from $active.${NC}"
    else
      echo -e "${RED}Failed to disconnect from $active.${NC}"
      exit 1
    fi
    ;;

  4)
    echo ""
    echo -e "${YELLOW}Saved WiFi connections:${NC}"
    echo ""
    mapfile -t saved < <(nmcli -t -f NAME,TYPE connection show | grep ':.*wireless' | cut -d: -f1)

    if [[ ${#saved[@]} -eq 0 ]]; then
      echo -e "${RED}No saved WiFi connections found.${NC}"
      exit 1
    fi

    for i in "${!saved[@]}"; do
      printf "  %d) %s\n" $((i+1)) "${saved[$i]}"
    done

    echo ""
    read -rp "Select a connection to delete [1-${#saved[@]}]: " del_choice

    if [[ -z "$del_choice" ]] || [[ "$del_choice" -lt 1 ]] || [[ "$del_choice" -gt ${#saved[@]} ]]; then
      echo -e "${RED}Invalid selection.${NC}"
      exit 1
    fi

    target="${saved[$((del_choice-1))]}"

    echo ""
    read -rp "Are you sure you want to delete '$target'? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo -e "${YELLOW}Cancelled.${NC}"
      exit 0
    fi

    if nmcli connection delete "$target"; then
      echo -e "${GREEN}Connection '$target' deleted.${NC}"
    else
      echo -e "${RED}Failed to delete '$target'.${NC}"
      exit 1
    fi
    ;;

  *)
    echo -e "${RED}Invalid option.${NC}"
    exit 1
    ;;
esac
