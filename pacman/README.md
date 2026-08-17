# pacman

Official Arch package list, installed via `sudo pacman -S --needed` by
`install.sh`.

## Files

- `pacman-packages.txt` — one package per line, `#` comments OK

## Sections (by comment header in the file)

- Base system (`base`, `linux`, `linux-firmware`, microcode, `grub`, etc.)
- Network (`networkmanager`, `wpa_supplicant`, `ufw`, `openssh`)
- Audio (PipeWire stack)
- Xorg (`xorg-server`, `xorg-xinit`, `xrandr`, etc.)
- Graphics drivers (Intel/AMD/Nouveau + Vulkan)
- WM stack (`bspwm`, `sxhkd`, `dmenu`, `alacritty`)
- Fonts (JetBrains Mono, DejaVu, Noto, Liberation)
- Apps (Thunar, screenshot tools, common desktop apps)
- Dev toolchain (`git`, `docker`, `postgresql`, `jdk21-openjdk`,
  `nodejs`, `npm`, `rust`, `android-tools`, etc.)
- Utilities (`htop`, `fzf`, `zoxide`, `nmap`, `wireshark-qt`, etc.)
- Typesetting (TeX Live: `texlive-latexextra`, `texlive-fontsrecommended`,
  `texlive-xetex`, `texlive-langspanish`; plus `typst`)

## Removing packages

Hardcoded in `install.sh` at the end of step 3b — list of packages
previously installed but no longer wanted. Currently: `xss-lock`,
`pnpm-bin` (orphaned/replaced).
