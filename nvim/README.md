# nvim

Neovim + IdeaVim config. Single-file each, no plugin manager.

## Files

| File        | Destination               | Used by |
|-------------|---------------------------|---------|
| `init.lua`  | `~/.config/nvim/init.lua` | neovim, vscode-neovim extension |
| `ideavimrc` | `~/.ideavimrc`            | JetBrains IDEs (IntelliJ, PyCharm, etc.) via IdeaVim plugin |

Both configs are kept intentionally parallel so behavior matches across
editors.

## Settings (init.lua)

| Setting | Value | Effect |
|---------|-------|--------|
| `mapleader` / `maplocalleader` | `" "` (space) | Leader key for all `<leader>...` bindings |
| `number`              | true  | Show line numbers |
| `smartindent`         | true  | Auto-indent on newline based on previous line |
| `ignorecase` + `smartcase` | true / true | Case-insensitive search unless query has uppercase |
| `scrolloff`           | 8     | Keep 8 lines of context above/below cursor |
| `wrap`                | false | No soft-wrap |
| `virtualedit`         | `"onemore"` | Cursor can go one past end of line |
| `clipboard`           | `unnamedplus` | Yank/paste use system clipboard (`+` register) |
| `expandtab`           | true  | Tab key inserts spaces |
| `shiftwidth` / `tabstop` / `softtabstop` | 4 / 4 / 4 | 4-space indent everywhere |

## VS Code-specific keymaps (`vim.g.vscode` block)

Active only inside vscode-neovim. Mirrored 1:1 in `ideavimrc` for
JetBrains IDEs.

| Keys             | Action                          |
|------------------|---------------------------------|
| `<leader>o`      | Focus explorer                  |
| `<leader>f`      | Quick open file (fuzzy)         |
| `<leader>F`      | Reveal current file in explorer |
| `<leader>n`      | Rename symbol                   |
| `<leader>ca`     | Code action / quick fix         |
| `gd`             | Go to definition                |
| `gr`             | Go to references                |
| `gi`             | Go to implementation            |
| `K`              | Show hover (docs)               |
| `[d` / `]d`      | Prev / next diagnostic          |

Explorer toggle / sidebar in VS Code is handled by native keybindings
(`alt+e`, `alt+r`), not this block — see `../vscode/README.md`.

## IdeaVim extras (`ideavimrc`)

Loaded plugins (no manager, IdeaVim bundles them):

- `surround`       — `ys`/`cs`/`ds` for surround edits
- `commentary`     — `gc`/`gcc` to comment lines/motions
- `highlightedyank` — flash yanked region after `y`

IdeaVim-only extras (no equivalent in nvim):

| Keys              | Action               |
|-------------------|----------------------|
| `<Tab>` / `<S-Tab>` | Next / previous IDE tab |
| `<leader>/`       | Find in path         |

## Why no plugin manager

- Init time stays under 50 ms on cold start.
- Behavior is identical across nvim, vscode-neovim and IdeaVim.
- The keymap surface is intentionally small (file tree, fuzzy open,
  rename, LSP-like navigation). Anything beyond that lives in the host
  editor's native UI.
