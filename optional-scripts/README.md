# optional-scripts

Standalone helpers. Not part of `install.sh`. Run only if you want them.

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

Mirror of the above. Moves the same paths to `~/storage/...` instead of
`/mnt/data`. Use if `/mnt/data` is gone or to consolidate everything back
on the Arch disk.

```bash
sudo ./migrate-to-home.sh
```

Both scripts auto-detect current location: symlinks pointing to the *other*
target get followed, contents rsynced to the new target, the old payload
removed, and the symlink retargeted. Safe to switch back and forth in any
order without manual cleanup.

## Revert any single migration

```bash
systemctl stop <service>   # if applicable (e.g. docker)
rm <symlink>
mv <new-location> <original-path>
```
