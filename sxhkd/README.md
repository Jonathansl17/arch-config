# sxhkd

Keybinding daemon for X. Drives bspwm + app launchers + media keys.

## Files

- `sxhkdrc` → `~/.config/sxhkd/sxhkdrc`

## Keybinding summary

| Keys | Action |
|---|---|
| `ctrl + <`                  | Launch alacritty |
| `ctrl + q`                  | Close focused window |
| `ctrl + shift + {a,d,w,s}`  | Split left / right / up / down (new alacritty, inherits cwd) |
| `ctrl + {←↑↓→}`             | Focus neighbor |
| `ctrl + shift + {←↑↓→}`     | Move window within desktop |
| `ctrl + alt + {←→}`         | Move window to prev/next monitor |
| `alt + Tab`                 | Toggle between last two focused windows |
| `ctrl + .`                  | Fullscreen toggle |
| `super + {1..0}`            | Switch to desktop I..X |
| `super + shift + {1..0}`    | Move window to desktop I..X |
| `super + b`                 | Brave |
| `super + e`                 | Thunar |
| `super + l`                 | slock (PAM password lock) |
| `Print`                     | Area screenshot → clipboard |
| `XF86Audio*`                | Volume up / down / mute via `wpctl` |

## Screenshot binding

`Print` runs inline:

```sh
maim -s | xclip -selection clipboard -t image/png
```

`maim -s` uses `slop` for area select. `xclip` forks into background and
holds the X11 selection until another app claims ownership — no clipboard
manager daemon required.

## Reloading

`install.sh` ends with `pkill -USR1 sxhkd` to reload bindings without
restarting the daemon.
