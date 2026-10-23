# networkmanager

NetworkManager drop-ins copied into `/etc/NetworkManager/conf.d/` by `install.sh`.
`dispatcher.d/` is **optional**: installed only by
`optional-scripts/wifi-off-when-wired.sh`.

## Files

| File | Purpose |
|------|---------|
| `mac-random.conf` | Per-network WiFi MAC address instead of the hardware one |
| `dispatcher.d/70-wifi-off-when-wired` | WiFi radio off while a cable is connected, on otherwise |

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

## dispatcher.d/70-wifi-off-when-wired

Runs on every NetworkManager event. If any ethernet device is `connected`, it runs
`nmcli radio wifi off`; otherwise `nmcli radio wifi on`. No-op when the radio is
already in the wanted state. Each change (or failure) is logged:

```sh
journalctl -t wifi-off-when-wired
```

Checking the real state on every event (not only ethernet up/down) covers booting
without the cable after a wired shutdown, where NetworkManager restores the radio
as off and no ethernet event ever fires.

To use WiFi while wired, unplug the cable: a manual `nmcli radio wifi on` lasts
only until the next network event. Install or uninstall with
`bash ~/arch-config/optional-scripts/wifi-off-when-wired.sh`.

## Activating without dropping the connection

```sh
sudo nmcli general reload conf
```

Only re-reads config. The new MAC applies on the next activation of each network.
