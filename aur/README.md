# aur

AUR package list, installed via `yay -S --needed` by `install.sh`.

## Files

- `aur-packages.txt` — one package per line, `#` comments OK

## Bootstrapping yay

If `yay` is missing, `install.sh` clones `https://aur.archlinux.org/yay.git`
and builds it with `makepkg -si --noconfirm`. Requires `git` + `base-devel`
(already in the pacman list).

## Special case: lemonbar-xft-git

Not in `aur-packages.txt`. Its PKGBUILD has `-march=x86-64` which clang
rejects. `install.sh` runs it with `CC=gcc yay -S --needed --noconfirm
lemonbar-xft-git`.
