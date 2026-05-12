# xinit

X session startup.

## Files

- `xinitrc` → `~/.xinitrc`

## What it does

- Sets X11 keyboard layout (latam)
- Loads any user-specific xrandr / xrdb / xset tweaks
- Execs `bspwm`

## How it gets launched

`bash/bash_profile` auto-runs `startx` when logging in on TTY1 (no display
manager). `startx` sources `~/.xinitrc`. End of chain: TTY login → bash
profile → startx → xinitrc → bspwm → bspwmrc → lemonbar.
