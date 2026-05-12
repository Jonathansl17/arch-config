# termclip (vendored)

Vendored copy of [termclip](https://github.com/Jonathansl17/termclip) —
terminal clipboard utilities (`c`, `cc`, `cpwd`, `v`). Bundled inside
`arch-config/` so a fresh install gets them without a separate fetch.

Upstream README preserved as [`UPSTREAM_README.md`](UPSTREAM_README.md).

## Files

| File                 | Purpose |
|----------------------|---------|
| `c.py`               | Copy files/folders to clipboard (Nautilus-compatible) |
| `cc.py`              | Copy text content of a file to clipboard |
| `cpwd.py`            | Copy current (or given) path to clipboard |
| `v.py`               | Paste files from clipboard into cwd |
| `instalation.sh`     | Installer: drops `.py` backends + bash wrappers into `~/bin/`, ensures `~/bin` is on PATH inside `~/.bashrc` |
| `UPSTREAM_README.md` | Upstream termclip readme |

## How install.sh wires it in

`arch-config/install.sh` runs:

```sh
( cd termclip && bash instalation.sh )
```

after building the C tools in `bin/`. The installer:

1. Installs `python-pyqt5` if missing (no-op on Arch — already in
   `pacman/pacman-packages.txt`).
2. Copies `c.py cc.py cpwd.py v.py` to `~/bin/`.
3. Writes bash wrappers `c cc cpwd v` to `~/bin/` (chmod +x).
4. Adds a guarded `~/bin` PATH block to `~/.bashrc` between
   `# === termclip configuration ===` markers (idempotent — replaces
   any prior block).

## Why vendored instead of curl|bash

- Reproducible on a fresh PC without network during install of clipboard
  tools.
- Versions pinned to what is committed here, not to upstream master.
- `arch-config/install.sh` stays a single-command bootstrap.

## Updating

When upstream termclip changes, sync manually:

```sh
cd ~/termclip && git pull
cp ~/termclip/{c.py,cc.py,cpwd.py,v.py,instalation.sh,README.md} \
   ~/arch-config/termclip/
mv ~/arch-config/termclip/README.md ~/arch-config/termclip/UPSTREAM_README.md
# (keep this local README.md as-is)
```

Commit. Re-run `install.sh` to redeploy.
