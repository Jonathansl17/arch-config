# termclip

**Terminal Clipboard Utilities for Linux**

`termclip` is a lightweight set of Bash + Python utilities that bring desktop
clipboard integration directly to your terminal. It lets you **copy and paste
files or folders** from the command line — just like you would in your file
manager.

---

## Features

- Copy files or folders to the system clipboard (`c`)
- Copy the text content of a file to the clipboard (`cc`)
- Copy the current working directory path to the clipboard (`cpwd`)
- Paste files from the clipboard into the current directory (`v`)
- Compatible with GNOME / Nautilus and other Linux desktops that honor the
  `x-special/gnome-copied-files` clipboard format
- Works entirely from the terminal (no GUI required)
- Built with Bash + PyQt5

---

## Installation

### One-liner (recommended, pinned to latest stable tag)

```bash
curl -fsSL https://raw.githubusercontent.com/Jonathansl17/termclip/v1.3.2/instalation.sh | TERMCLIP_REF=v1.3.2 bash
```

Tags are immutable, so this URL is not affected by the GitHub raw CDN
cache that can briefly stall a fresh `master`.

### Track the latest

```bash
curl -fsSL https://raw.githubusercontent.com/Jonathansl17/termclip/master/instalation.sh | bash
```

### Or clone the repository

```bash
git clone https://github.com/Jonathansl17/termclip
cd termclip
bash instalation.sh
```

## What the installer does

1. Installs `python3` + `PyQt5` if missing (`pacman`, `apt`, `dnf`, or
   `zypper` — auto-detected; no-op if both are already present).
2. Creates `~/bin` if missing.
3. Copies `c.py`, `cc.py`, `cpwd.py`, `v.py` to `~/bin/`.
4. Writes bash wrappers `c`, `cc`, `cpwd`, `v` to `~/bin/` (`chmod +x`).
5. Prints a summary.

It does **not** touch `~/.bashrc`, `~/.profile`, or `PATH`. Make sure
`$HOME/bin` is on your `PATH` — most shells handle this via
`~/.profile` or `~/.bash_profile`.

## Updating

Re-run the installer. It overwrites `~/bin/{c,cc,cpwd,v,c.py,cc.py,cpwd.py,v.py}`
in place. No accumulated state to clean.

---

## Usage

### `c` — copy files/folders to the clipboard

Copies one or more files/folders to the system clipboard **as files**,
just like hitting *Copy* in Nautilus.

```bash
c hello.txt
c file1.txt file2.png some-folder/
```

Paste them with `v` in another directory, or with `Ctrl+V` inside Nautilus.

### `cc` — copy the text content of a file to the clipboard

Reads a file as UTF-8 text and puts its **content** in the clipboard.
Trailing whitespace and newlines are stripped, so pasting into a shell
does not auto-execute the command.

```bash
cc comando.txt
```

Paste it with **`Ctrl+V`** in any editor, browser or text field, or with
**`Ctrl+Shift+V`** inside a terminal.

> `cc` is different from `c`: `c` copies the *file itself*, `cc` copies
> the *text inside the file*.

### `cpwd` — copy the current path to the clipboard

Copies the current working directory (or a given path) to the clipboard
as plain text. Useful for quickly sharing a path or pasting it in another
terminal / editor.

```bash
cpwd              # copies $(pwd)
cpwd /etc/nginx   # copies the given path
```

### `v` — paste files from the clipboard

Pastes files previously copied with `c` (or from Nautilus) into the
current directory. If a file with the same name already exists, a unique
name is generated (`file_copy.txt`, `file_copy2.txt`, ...).

```bash
v
```

`v` only works with files in the clipboard — it will not paste plain
text copied with `cc`.
