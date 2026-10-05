# pipx

Python CLI tools installed in isolated virtualenvs, via `pipx install`.

## Files

- `pipx-packages.txt` — one package per line

## Current packages

- `sherlock-project` — username OSINT across social networks
- `holehe` — email OSINT (which sites have an account for this email)
- `pdf2docx` — PDF to editable .docx converter used by `bin/ptw`

## When to use pipx vs pacman vs pip

- **pacman** — system-wide tools, native deps, kernel-coupled stuff
- **pipx** — Python CLIs you run from any shell, isolated venv per tool
- **pip (in venv)** — project libraries, never system-wide
