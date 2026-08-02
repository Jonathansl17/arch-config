# bash

Shell config.

## Files

- `bash_profile` → `~/.bash_profile` (login shell setup)
- `bashrc` → `~/.bashrc` (interactive shell setup)

## What lives where

`bash_profile` (one-time login setup, sets env once):
- `JAVA_HOME`, `ANDROID_HOME`, `NVM_DIR`, `PNPM_HOME`
- Combined `PATH`
- Auto-`startx` on TTY1 (no display manager)

`bashrc` (sourced per interactive shell):
- Aliases, prompt, completions
- Lazy-load functions for `nvm`, `node`, `pnpm`
- `evince` shell function — launches Evince detached (must stay a function:
  it shadows the binary of the same name). The Xournal++ launcher `x` lives
  in [`bin/x`](../bin/README.md) instead, since it needs no shell state.
- Sources `~/.bashrc.local` if present

## Local-only overrides: `~/.bashrc.local`

Machine-specific or sensitive content (API keys, internal hostnames, DB
URLs, per-machine paths) goes in `~/.bashrc.local`, which is **not**
versioned. Final line of `bashrc`:

```sh
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
```

### Fresh machine setup

```sh
touch ~/.bashrc.local
chmod 600 ~/.bashrc.local
```

### Example contents

```sh
export OPENAI_API_KEY="sk-..."
export GITHUB_TOKEN="ghp_..."
alias work-ssh='ssh me@internal.example.com'
export DATABASE_URL='postgres://user:pass@host:5432/db'
```

## Secret leak check before pushing

```sh
grep -nE 'sk-|ghp_|AKIA|password=|token=|@[0-9.]+' bash/bashrc
```

Expected: empty. Anything matching belongs in `~/.bashrc.local`.
