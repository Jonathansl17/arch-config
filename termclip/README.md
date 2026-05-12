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
| `instalation.sh`     | Installer: drops `.py` backends + bash wrappers into `~/bin/`, ensures `~/bin` is on PATH inside `~/.bashrc` |
| `UPSTREAM_README.md` | Upstream termclip readme |

## What instalation.sh does

1. Creates `~/bin` if missing.
2. Copies `c.py cc.py cpwd.py v.py` to `~/bin/` (chmod +x).
3. Writes bash wrappers `c cc cpwd v` to `~/bin/` (chmod +x).
4. Prints a summary of installed commands.

Does **not** touch `~/.bashrc`, `~/.profile`, or PATH. Does **not**
install PyQt5. Callers are responsible for both.

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
cp ~/termclip/{c.py,cc.py,cpwd.py,v.py,instalation.sh,README.md} \
   ~/arch-config/termclip/
mv ~/arch-config/termclip/README.md ~/arch-config/termclip/UPSTREAM_README.md
# (keep this local README.md as-is)
```

Commit. Re-run `install.sh` to redeploy.
