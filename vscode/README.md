# vscode

User-level VS Code config (keybindings + settings). Deployed to
`~/.config/Code/User/` by the repo `install.sh`.

## Files

| File               | Destination                              |
|--------------------|------------------------------------------|
| `keybindings.json` | `~/.config/Code/User/keybindings.json`   |
| `settings.json`    | `~/.config/Code/User/settings.json`      |

Both are overwritten in place on install (repo is source of truth).
Editor behavior is driven by the `vscode-neovim` extension, so motions /
leader bindings live in `../nvim/init.lua`; this folder only holds the
native VS Code layer underneath it.

## Notable keybindings (`keybindings.json`)

Native overrides on top of vscode-neovim. The Alt-prefixed set is the
primary one (works regardless of editor/nvim focus).

| Keys          | Action                              |
|---------------|-------------------------------------|
| `alt+e`       | Show explorer                       |
| `alt+r`       | Show explorer / toggle sidebar      |
| `alt+f`       | Find in files                       |
| `alt+d` / `alt+s` | Next / previous editor          |
| `alt+q`       | Close active editor                 |
| `alt+m`       | Toggle panel                        |
| `alt+[`       | Toggle auxiliary (right) bar        |
| `alt+l`       | Kill active terminal tab / editor   |
| `ctrl+g`      | Format document                     |
| `ctrl+alt+s`  | Format + save                       |
| `ctrl+7`      | Toggle line comment                 |

Explorer-focus single-key binds: `r` trash, `n` rename, `c` new folder.

## Notable settings (`settings.json`)

| Setting | Value | Effect |
|---------|-------|--------|
| `vscode-neovim.neovimExecutablePaths.linux` | `/usr/bin/nvim` | Backend for the Neovim extension |
| `extensions.experimental.affinity` | `vscode-neovim: 1` | Pins the extension to its own host process (latency) |
| `editor.fontFamily` / `fontLigatures` | JetBrains Mono / true | Editor font |
| `workbench.colorTheme` / `iconTheme` | Dark Modern / material-icon-theme | Look |
| `editor.tabSize` + `insertSpaces` + `detectIndentation` | 4 / true / false | Forced 4-space indent |
| `editor.minimap.enabled` | false | No minimap |
| `editor.cursorSurroundingLines` | 8 | Scrolloff equivalent |
| `telemetry.telemetryLevel` | `off` | Kills all native VS Code telemetry |
| `redhat.telemetry.enabled` / `jdk.telemetry.enabled` | false / false | Extension telemetry off |
| `C_Cpp.intelliSenseEngine` | disabled | C/C++ IntelliSense off (clangd/other used instead) |
| `git.autofetch` / `enableSmartCommit` / `confirmSync` | true / true / false | Git ergonomics |
