# slock

Suckless screen locker, all-black, PAM password.

## Files

- `config.h` — slock build config (compiled from source by `install.sh`)

## What install.sh does

1. Clones slock source
2. Drops in this `config.h`
3. `make`
4. `sudo make install` → `/usr/local/bin/slock` (setuid root)

## Binding

`super + l` in sxhkd runs `slock`. Black screen until PAM password
accepted.

## Why slock vs i3lock

slock is ~600 LoC, no images, no fancy effects. Smaller attack surface,
zero config to maintain.
