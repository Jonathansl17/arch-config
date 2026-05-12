# services

systemd services to `enable` at boot.

## Files

- `services.txt` — one service per line, `#` comments OK

## Current list

- `NetworkManager.service`

`install.sh` runs `sudo systemctl enable <name>` (without `--now`) for
each line. On a running machine `enable` is idempotent and leaves live
processes alone; on next reboot they start automatically.

## Inline-enabled in install.sh

Not in `services.txt` but enabled by `install.sh` separately:
- `ufw.service` — enabled after applying default deny-inbound /
  allow-outbound rules

## Installed but NOT enabled (start manually when needed)

- `bluetooth.service`
- `sshd.service` (openssh is installed for the client; the daemon stays
  off so the machine never accepts inbound SSH unless you opt in)
- `docker.service`
- `postgresql.service` (needs `initdb` first)
