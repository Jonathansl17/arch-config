# alacritty

Terminal emulator config.

## Files

- `alacritty.toml` → `~/.config/alacritty/alacritty.toml`

## Notes

- Font: `monospace:size=12` (matches lemonbar height).
- `alacritty-cwd` (in `bin/`) inherits the cwd from the focused alacritty
  when launching a new one. `sxhkd` uses it for the split bindings
  (`ctrl + shift + {a,d,w,s}`).
- `alacritty-selectall` (in `bin/`) enters vi-mode, selects all, yanks
  to clipboard. Bound in alacritty config.
