# networkmanager

NetworkManager drop-ins copied into `/etc/NetworkManager/conf.d/` by `install.sh`.

## Files

| File | Purpose |
|------|---------|
| `mac-random.conf` | Per-network WiFi MAC address instead of the hardware one |

## mac-random.conf

- `wifi.cloned-mac-address=stable` — each network sees a different, generated MAC,
  so the laptop cannot be tracked across networks. The hardware MAC is never sent.
- `connection.stable-id=${NETWORK_SSID}` — the MAC is derived from the SSID instead
  of the profile UUID, so forgetting a network and reconnecting keeps the same MAC
  (same DHCP lease, captive portals still recognize the device).

The generated MAC is a hash of `/var/lib/NetworkManager/secret_key` plus the SSID.
Losing that file (reinstall, wiping `/var/lib`) changes the MAC on every network.
Back it up to keep the same MACs across installs.

To keep the hardware MAC on one network (e.g. one that filters by registered MAC):

```sh
nmcli connection modify "<name>" 802-11-wireless.cloned-mac-address permanent
```

## Activating without dropping the connection

```sh
sudo nmcli general reload conf
```

Only re-reads config. The new MAC applies on the next activation of each network.
