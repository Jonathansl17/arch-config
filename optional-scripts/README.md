# optional-scripts

Standalone helpers. Not part of `install.sh`. Run only if you want them.

## setup-data-disk.sh

Interactive bootstrap for `/mnt/data`. Reuses an existing ext4 `LABEL=data`
partition (at least 1 GiB, not a Microsoft partition type) when one exists.
Otherwise lists spare disks, names what is on each one (Windows, macOS,
Linux, unknown data, empty), and wipes the chosen disk into a single ext4
`LABEL=data` partition. Adds a `nofail` + `x-systemd.device-timeout=10` fstab
entry and mounts it. After erasing an OS it regenerates the GRUB menu.

Safety:
- Never offers the disk holding `/`, `/home` or `/boot`.
- Wiping requires typing the device path AND `DESTROY`.
- No spare disk: exits without mounting or changing anything.

```bash
sudo bash ~/arch-config/optional-scripts/setup-data-disk.sh
```

`migrate-to-mnt-data.sh` runs the same flow on its own, so calling this first
is optional. Shared logic lives in `lib/`; tests in `tests/`.

## migrate-to-mnt-data.sh

Move heavy caches and dev tool stores from `/` and `/home` to `/mnt/data`
via symlinks. Future writes auto-redirect because originals become symlinks.

Targets:
- `~/.cache` (whole dir → catches every XDG-cache app)
- `~/.gradle ~/.npm ~/.cargo ~/.nvm ~/.jdks ~/.javacpp ~/.android`
  `~/.vscode ~/.vscode-server ~/.codex ~/.claude ~/.net ~/.dotnet ~/.pipx`
- `~/.local/share/{pnpm,JetBrains,pipx,Steam,flatpak,containers}`
- `/var/cache/pacman/pkg`
- `/var/lib/docker`

If `/mnt/data` is not set up, runs the `setup-data-disk.sh` flow first
(detects Windows/other OS on a spare disk and erases it only after `DESTROY`).
`~/screenshots` and `~/.m2` always stay real dirs in `$HOME`; a symlink left
by an earlier run is pulled back (`lib/keep-in-home.sh`). Keeping `~/.m2` put
gives IDEs a Maven repository path that never changes.

Idempotent. Run as root. Refuses to run while IntelliJ or VS Code is open,
since IDEs keep stale state when cache paths move (`lib/ide-safety.sh`).

```bash
sudo ./migrate-to-mnt-data.sh
```

## migrate-to-home.sh

Flattens caches/dev stores directly under `$HOME` (no nesting). Targets:
`~/pacman-pkg`, `~/docker`, `~/cache`, `~/<devtool>` (dot stripped from
`~/.gradle`, `~/.npm`, ...), `~/share-<name>` for `~/.local/share/*`.
User dotdirs become symlinks to their flat target. Use to consolidate
everything on the Arch disk; cleans up legacy `~/storage` and `~/system`
nests if present. Applies the same IDE guard and keeps
`~/screenshots` and `~/.m2` as real dirs, like `migrate-to-mnt-data.sh`.

```bash
sudo ./migrate-to-home.sh
```

Both scripts auto-detect current location: symlinks pointing to the *other*
target get followed, contents rsynced to the new target, the old payload
removed, and the symlink retargeted. Safe to switch back and forth in any
order without manual cleanup.

## system-hardening.sh

Apply optional security defaults. Idempotent — re-run anytime; each section
skips cleanly when already in place.

Sections:
- `/boot` fstab `fmask=0077,dmask=0077` (vfat ESP — fixes the world-readable
  `random-seed` `bootctl` warning)
- sysctl hardening (`sysctl/99-hardening.conf` → `/etc/sysctl.d/`):
  `kernel.kptr_restrict`, `kernel.yama.ptrace_scope`, `rp_filter`,
  `accept_redirects`, `send_redirects`
- GRUB hidden menu (`GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`); regenerates
  `/boot/grub/grub.cfg`. Hold **Shift** at POST to force the menu.
- `/mnt/data` fstab `nofail,x-systemd.device-timeout=10` so a dead data
  disk no longer hangs boot ~90s before dropping to emergency shell

```bash
bash ~/arch-config/optional-scripts/system-hardening.sh
```

Backups of any modified system file are left next to the original as
`<file>.bak-<timestamp>`.

## wifi-suspend-fix.sh

Keeps PCI WiFi cards alive across suspend/resume. Written for the Realtek
RTL8852BE (rtw89), which can stay dead on resume until a full power off:

```
rtw89_8852be: Unable to change power state from D3hot to D0, device inaccessible
rtw89_8852be: mac preinit fail, ret: -110
Hardware became unavailable upon resume
```

`modprobe/rtw89.conf` (power-save options) does not cover this case.

Nothing is tied to one model: cards are detected by PCI class `0x0280xx`
(wireless controller) and their driver is read at runtime. USB dongles are not
covered. With no PCI WiFi card, the script exits without changes.

Sections:
- systemd-sleep hook (`system-sleep/wifi-reload` → `/usr/lib/systemd/system-sleep/`):
  unloads the WiFi driver before suspend and loads it again after resume
- udev rule (`udev/80-wifi-no-d3cold.rules` → `/etc/udev/rules.d/`):
  `d3cold_allowed=0` for WiFi cards, applied right away and on every boot
- removes the older rtw89-only files (`system-sleep/rtw89`,
  `80-rtw89-no-d3cold.rules`) if present

If the fix is already installed, the script asks before touching anything:

- `y` — reinstall: overwrites both files with the repo version
- `n` — uninstall: removes both files (plus the old rtw89 ones) and restores
  `d3cold_allowed=1` right away
- anything else — cancel, nothing changes

Takes effect on the next suspend, no reboot needed. If the card
still hangs, try `wifi-reset` (see `bin/README.md`) before powering off.

```bash
bash ~/arch-config/optional-scripts/wifi-suspend-fix.sh
```

## wifi-off-when-wired.sh

Turns the WiFi radio off while a cable is connected and back on when it is not,
so the card stays idle (no scans, no second connection) on wired days.

Installs `networkmanager/dispatcher.d/70-wifi-off-when-wired` →
`/etc/NetworkManager/dispatcher.d/` and runs it once so it applies right away.
The script re-checks the real state on every NetworkManager event, so it also
works when booting without the cable after a wired shutdown. Details in
`networkmanager/README.md`.

If already installed, the script asks before touching anything:

- `y` — reinstall: overwrites it with the repo version
- `n` — uninstall: removes it and turns the WiFi radio back on
- anything else — cancel, nothing changes

```bash
bash ~/arch-config/optional-scripts/wifi-off-when-wired.sh
```

## Revert any single migration

```bash
systemctl stop <service>   # if applicable (e.g. docker)
rm <symlink>
mv <new-location> <original-path>
```

## postgres-hardening.sh

Stop a local PostgreSQL from accepting any password. Replaces `trust` in
`pg_hba.conf` with `peer` (local socket) and `scram-sha-256` (TCP), after
prompting for a new password for the `postgres` role.

- Idempotent: exits cleanly when no `trust` rule remains.
- Reloads the service, so open connections are kept.
- Checks that a wrong password is rejected and the new one works.
- Leaves no backup file. If a step fails, the original rules are restored from
  memory; the new password is kept.

Affects every database in the cluster: apps connecting as `postgres` over TCP
need the new password afterwards.

```bash
sudo bash ~/arch-config/optional-scripts/postgres-hardening.sh
```
