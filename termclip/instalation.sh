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

# --- Step 1: Ensure ~/bin exists ---
mkdir -p "$BIN_DIR"

# --- Step 2: Fetch python backends if running standalone (curl|bash mode) ---
missing=0
for f in c.py v.py cc.py cpwd.py; do
  [ -f "$f" ] || { missing=1; break; }
done

if [ "$missing" -eq 1 ]; then
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "$WORKDIR"' EXIT
  echo "Standalone mode — fetching backends into $WORKDIR"
  cd "$WORKDIR"
  for f in c.py v.py cc.py cpwd.py; do
    fetch_if_missing "$f"
  done
fi

# --- Step 3: Copy backends + write wrappers ---
cp -f c.py cc.py cpwd.py v.py "$BIN_DIR/"
chmod u+x "$BIN_DIR/c.py" "$BIN_DIR/cc.py" "$BIN_DIR/cpwd.py" "$BIN_DIR/v.py"

cat > "$BIN_DIR/c" <<'EOF'
#!/usr/bin/env bash
if [ $# -lt 1 ]; then
    echo "Usage: c file1 file2 ..."
    exit 1
fi
pkill -f "$HOME/bin/c.py" 2>/dev/null
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
pkill -f "$HOME/bin/cc.py" 2>/dev/null
"$HOME/bin/cc.py" "$1" >/dev/null 2>&1 & disown
echo "Content copied to clipboard from:"
echo "   $1"
EOF

cat > "$BIN_DIR/cpwd" <<'EOF'
#!/usr/bin/env bash
target="${1:-$(pwd)}"
pkill -f "$HOME/bin/cpwd.py" 2>/dev/null
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
echo "Requirements:"
echo "  - python3 + PyQt5 (install via your package manager if missing)"
echo "  - $BIN_DIR on your PATH (most shells auto-add this; verify with:"
echo "    echo \"\$PATH\" | tr ':' '\\n' | grep \"$BIN_DIR\")"
