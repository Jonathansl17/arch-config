# termclip (vendored, **optional**)

Vendored copy of [termclip](https://github.com/Jonathansl17/termclip) —
terminal clipboard utilities (`c`, `cc`, `cpwd`, `v`). Not run by
`install.sh`. Run manually after the main install if you want these
commands.

```sh
bash termclip/instalation.sh
```

Upstream README preserved as [`UPSTREAM_README.md`](UPSTREAM_README.md).

## Files

| File                 | Purpose |
|----------------------|---------|
| `c.py`               | Copy files/folders to clipboard (Nautilus-compatible) |
| `cc.py`              | Copy text content of a file to clipboard |
| `cpwd.py`            | Copy current (or given) path to clipboard |
| `v.py`               | Paste files from clipboard into cwd |
| `termclip_owner.py`  | Shared helper: keeps only one clipboard backend alive |
| `instalation.sh`     | Installer: ensures python3 + PyQt5, drops `.py` backends + bash wrappers into `~/bin/` |
| `UPSTREAM_README.md` | Upstream termclip readme |

## What instalation.sh does

1. Installs `python3` + PyQt5 if missing, via the system package
   manager (pacman/apt/dnf/zypper).
2. Creates `~/bin` if missing.
3. Copies `c.py cc.py cpwd.py v.py termclip_owner.py` to `~/bin/`
   (the four entry points get chmod +x).
4. Writes bash wrappers `c cc cpwd v` to `~/bin/` (chmod +x).
5. Prints a summary of installed commands.

Does **not** touch `~/.bashrc`, `~/.profile`, or PATH — the caller is
responsible for having `~/bin` on it.

## Requirements

- `python3` + `PyQt5` (already in `pacman/pacman-packages.txt` as
  `python-pyqt5`, so `install.sh` brings it in).
- `~/bin` on `PATH` (handled by `bash/bash_profile` line 17).

## Why vendored instead of curl|bash

- Reproducible on a fresh PC without network during install of clipboard
  tools.
- Versions pinned to what is committed here, not to upstream master.
- Lives alongside the rest of the dotfiles instead of in a separate clone.

## Updating

When upstream termclip changes, sync manually:

```sh
cd ~/termclip && git pull
cp ~/termclip/{c.py,cc.py,cpwd.py,v.py,termclip_owner.py,instalation.sh,README.md} \
   ~/arch-config/termclip/
mv ~/arch-config/termclip/README.md ~/arch-config/termclip/UPSTREAM_README.md
# (keep this local README.md as-is)
```

Commit. Re-run `install.sh` to redeploy.
