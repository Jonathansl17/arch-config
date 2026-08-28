#!/usr/bin/env bash
# =====================================================
#  termclip - Installation Script
#  Author: Jonathansl17
#  Description:
#    Copies termclip clipboard utilities (`c`, `cc`, `cpwd`, `v`)
#    into ~/bin. Does NOT touch ~/.bashrc or PATH — make sure
#    ~/bin is already on your PATH (most distros do this via
#    ~/.profile / ~/.bash_profile; on Arch, `arch-config/bash/bash_profile`
#    handles it).
# =====================================================

set -euo pipefail

BIN_DIR="$HOME/bin"
TERMCLIP_REF="${TERMCLIP_REF:-master}"
RAW_BASE="https://raw.githubusercontent.com/Jonathansl17/termclip/$TERMCLIP_REF"

# Resolve the script's own directory so vendored .py files are found
# even when invoked with a relative or absolute path from another cwd
# (e.g. `bash termclip/instalation.sh` from a parent directory).
# In curl|bash mode there is no script on disk, so BASH_SOURCE is empty
# and we leave SCRIPT_DIR empty — the standalone fetch path will run.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi

fetch_if_missing() {
  local name="$1"
  if [ ! -f "$name" ]; then
    echo "Downloading $name from $TERMCLIP_REF..."
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$RAW_BASE/$name" -o "$name"
    elif command -v wget >/dev/null 2>&1; then
      wget -q "$RAW_BASE/$name" -O "$name"
    else
      echo "Neither curl nor wget available to download $name." >&2
      exit 1
    fi
  fi
}

# --- Step 1: Ensure dependencies (python3 + PyQt5) ---
need_pyqt5=0
if ! command -v python3 >/dev/null 2>&1; then
  need_pyqt5=1
elif ! python3 -c "import PyQt5" >/dev/null 2>&1; then
  need_pyqt5=1
fi

if [ "$need_pyqt5" -eq 1 ]; then
  echo "Installing python3 + PyQt5 via system package manager..."
  if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm python python-pyqt5
  elif command -v apt >/dev/null 2>&1; then
    sudo apt update -y && sudo apt install -y python3 python3-pyqt5
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 python3-qt5
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y python3 python3-qt5
  else
    echo "ERROR: no supported package manager (pacman/apt/dnf/zypper) found." >&2
    echo "Install python3 + PyQt5 manually, then re-run." >&2
    exit 1
  fi
fi

# --- Step 2: Ensure ~/bin exists ---
mkdir -p "$BIN_DIR"

# --- Step 3: Locate python backends ---
# Prefer .py files sitting next to this script (vendored / cloned repo).
# Fall back to fetching from GitHub only if SCRIPT_DIR is empty (curl|bash
# mode) or one of the .py files is missing.
missing=0
if [ -z "$SCRIPT_DIR" ]; then
  missing=1
else
  for f in c.py v.py cc.py cpwd.py termclip_owner.py; do
    [ -f "$SCRIPT_DIR/$f" ] || { missing=1; break; }
  done
fi

if [ "$missing" -eq 0 ]; then
  SRC_DIR="$SCRIPT_DIR"
else
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  echo "Standalone mode — fetching backends into $WORKDIR"
  cd "$WORKDIR"
  for f in c.py v.py cc.py cpwd.py termclip_owner.py; do
    fetch_if_missing "$f"
  done
  SRC_DIR="$WORKDIR"
fi

# --- Step 4: Copy backends + write wrappers ---
cp -f "$SRC_DIR"/c.py "$SRC_DIR"/cc.py "$SRC_DIR"/cpwd.py "$SRC_DIR"/v.py \
      "$SRC_DIR"/termclip_owner.py "$BIN_DIR/"
chmod u+x "$BIN_DIR/c.py" "$BIN_DIR/cc.py" "$BIN_DIR/cpwd.py" "$BIN_DIR/v.py"

cat > "$BIN_DIR/c" <<'EOF'
#!/usr/bin/env bash
if [ $# -lt 1 ]; then
    echo "Usage: c file1 file2 ..."
    exit 1
fi
"$HOME/bin/c.py" "$@" >/dev/null 2>&1 & disown
echo "Files copied to clipboard:"
for f in "$@"; do
    echo "   $f"
done
EOF

cat > "$BIN_DIR/cc" <<'EOF'
#!/usr/bin/env bash
if [ $# -lt 1 ]; then
    echo "Usage: cc file"
    exit 1
fi
"$HOME/bin/cc.py" "$1" >/dev/null 2>&1 & disown
echo "Content copied to clipboard from:"
echo "   $1"
EOF

cat > "$BIN_DIR/cpwd" <<'EOF'
#!/usr/bin/env bash
target="${1:-$(pwd)}"
"$HOME/bin/cpwd.py" "$target" >/dev/null 2>&1 & disown
echo "Path copied to clipboard:"
echo "   $target"
EOF

cat > "$BIN_DIR/v" <<'EOF'
#!/usr/bin/env bash
output=$("$HOME/bin/v.py" "$@")
if [ $? -ne 0 ]; then
    echo "No files found in clipboard."
    exit 1
fi
echo "Files pasted from clipboard:"
for f in $output; do
    echo "   $f"
done
EOF

chmod u+x "$BIN_DIR/c" "$BIN_DIR/cc" "$BIN_DIR/cpwd" "$BIN_DIR/v"

echo ""
echo "termclip installation complete!"
echo "Installed to: $BIN_DIR"
echo ""
echo "Commands available:"
echo "  c file1 file2 ...   → Copy files or folders to clipboard"
echo "  cc file             → Copy text content of a file to clipboard"
echo "  cpwd [path]         → Copy current (or given) path to clipboard"
echo "  v                   → Paste files from clipboard"
echo ""
echo "Note: $BIN_DIR must be on your PATH (most shells auto-add this)."
echo "      verify with: echo \"\$PATH\" | tr ':' '\\n' | grep \"$BIN_DIR\""
