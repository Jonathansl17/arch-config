# optional-scripts

Standalone helpers. Not part of `install.sh`. Run only if you want them.

## setup-data-disk.sh

Interactive bootstrap for a fresh PC: partitions a chosen disk as GPT,
creates ext4 with `LABEL=data`, appends fstab entry with `nofail` +
`x-systemd.device-timeout=10`, and mounts it at `/mnt/data`.

Safety:
- Detects the disk hosting `/`, `/home`, `/boot` and refuses to touch them.
- Lists candidate disks with `[SKIP]` / `[OK]` markers.
- Requires typing the device path AND `DESTROY` to proceed.
- Idempotent: if `/mnt/data` already mounted from a `LABEL=data` partition,
  exits cleanly. If partition exists but unmounted, skips partitioning and
  only adds fstab + mounts.

```bash
bash ~/arch-config/optional-scripts/setup-data-disk.sh
```

Run this **first** on a new PC, then `migrate-to-mnt-data.sh`.

## migrate-to-mnt-data.sh

Move heavy caches and dev tool stores from `/` and `/home` to `/mnt/data`
via symlinks. Future writes auto-redirect because originals become symlinks.

Targets:
- `~/.cache` (whole dir → catches every XDG-cache app)
- `~/.gradle ~/.m2 ~/.npm ~/.cargo ~/.nvm ~/.jdks ~/.javacpp ~/.android`
  `~/.vscode ~/.vscode-server ~/.codex ~/.claude ~/.net ~/.dotnet ~/.pipx`
- `~/.local/share/{pnpm,JetBrains,pipx,Steam,flatpak,containers}`
- `/var/cache/pacman/pkg`
- `/var/lib/docker`

Requires `/mnt/data` mounted. Idempotent. Run as root. Close browsers/IDEs first.

```bash
sudo ./migrate-to-mnt-data.sh
```

## migrate-to-home.sh

Flattens caches/dev stores directly under `$HOME` (no nesting). Targets:
`~/pacman-pkg`, `~/docker`, `~/cache`, `~/<devtool>` (dot stripped from
`~/.gradle`, `~/.m2`, ...), `~/share-<name>` for `~/.local/share/*`.
User dotdirs become symlinks to their flat target. Use to consolidate
everything on the Arch disk; cleans up legacy `~/storage` and `~/system`
nests if present.

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
- `~/.aws` / `~/aws` chmod 700 if either exists
- `/mnt/data` fstab `nofail,x-systemd.device-timeout=10` so a dead data
  disk no longer hangs boot ~90s before dropping to emergency shell

```bash
bash ~/arch-config/optional-scripts/system-hardening.sh
```

Backups of any modified system file are left next to the original as
`<file>.bak-<timestamp>`.

## Revert any single migration

```bash
systemctl stop <service>   # if applicable (e.g. docker)
rm <symlink>
mv <new-location> <original-path>
```
