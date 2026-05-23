#!/usr/bin/env bash
# Flatten caches/heavy data into $HOME with NO nesting.
# Targets (all directly under $HOME):
#   - System stores: ~/pacman-pkg, ~/docker
#   - User cache:    ~/cache       (symlinked from ~/.cache)
#   - Dev tool dirs: ~/<name>      (symlinked from ~/.<name>, dot stripped)
#   - Share entries: ~/share-<name> (symlinked from ~/.local/share/<name>)
#   - Screenshots:   ~/screenshots (REAL dir, no symlink)
#
# Idempotent. Safe to re-run. Handles migration from prior nested layouts
# (~/storage/user/..., ~/system/...) and from /var-based defaults.
#
# Run with all desktop apps closed (browsers, IDEs) to avoid open-file races.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [[ -z "$USER_NAME" || "$USER_NAME" == "root" ]]; then
  echo "ERROR: cannot determine the invoking user. Run via 'sudo $0', not as root directly."
  exit 1
fi
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  echo "ERROR: home directory for $USER_NAME not found."
  exit 1
fi
SCREENSHOTS_DIR="$USER_HOME/screenshots"

# move_existing SRC DEST OWNER
# Move a real directory at SRC into DEST. No-op if SRC missing or equals DEST.
# Used for system stores where the active path is configured elsewhere (pacman
# CacheDir, docker data-root) and may already be outside /var.
move_existing() {
  local src="$1" dest="$2" owner="${3:-root}"
  [[ -z "$src" ]] && return 0
  src="${src%/}"
  dest="${dest%/}"
  [[ "$src" == "$dest" ]] && return 0
  if [[ -L "$src" ]]; then
    local tgt; tgt=$(readlink -f "$src" || true)
    if [[ -n "$tgt" && -d "$tgt" && "$tgt" != "$dest" ]]; then
      mkdir -p "$dest"
      echo "  [pull]  $src → $tgt, moving to $dest"
      rsync -aHAX --info=progress2 "$tgt/" "$dest/"
      rm -rf "$tgt"
    fi
    rm -f "$src"
  elif [[ -d "$src" ]]; then
    mkdir -p "$dest"
    echo "  [move]  $src → $dest"
    rsync -aHAX --info=progress2 "$src/" "$dest/"
    rm -rf "$src"
  else
    return 0
  fi
  if [[ "$owner" == "user" ]]; then
    chown -R "$USER_NAME:$USER_NAME" "$dest"
  else
    chown -R root:root "$dest"
  fi
}

# Repoint pacman cache at $1, removing any other active CacheDir lines. Idempotent.
set_pacman_cachedir() {
  local dir="$1" conf=/etc/pacman.conf
  if grep -qE "^[[:space:]]*CacheDir[[:space:]]*=[[:space:]]*${dir}/?[[:space:]]*$" "$conf"; then
    echo "  [conf]  pacman CacheDir already $dir"
    return 0
  fi
  cp "$conf" "$conf.bak.$(date +%s)"
  sed -i -E '/^[[:space:]]*CacheDir[[:space:]]*=/d' "$conf"
  sed -i -E "0,/^\[options\]/s##[options]\nCacheDir = ${dir}/#" "$conf"
  echo "  [conf]  pacman CacheDir = $dir (backup at $conf.bak.*)"
}

# Read current pacman CacheDir (first active, non-commented). Empty if none.
current_pacman_cachedir() {
  grep -E '^[[:space:]]*CacheDir[[:space:]]*=' /etc/pacman.conf 2>/dev/null \
    | head -1 | sed -E 's|^[[:space:]]*CacheDir[[:space:]]*=[[:space:]]*||; s|[[:space:]]*$||; s|/$||'
}

# Grant the alpm sandbox user access to a pacman CacheDir under $HOME.
grant_alpm_pacman_access() {
  local dir="$1"
  if ! id alpm >/dev/null 2>&1; then
    echo "  [skip]  alpm user not present; nothing to grant"
    return 0
  fi
  if ! command -v setfacl >/dev/null 2>&1; then
    echo "  [warn]  setfacl missing (install 'acl'); pacman will fail to download into $dir"
    return 0
  fi
  chown -R alpm:alpm "$dir"
  local p
  p=$(dirname "$dir")
  while [[ "$p" != "/" && -n "$p" ]]; do
    setfacl -m u:alpm:x "$p"
    p=$(dirname "$p")
  done
  echo "  [acl]   alpm granted traverse on parents of $dir; owns $dir"
}

# Repoint docker data-root at $1, merging into existing daemon.json. Idempotent.
set_docker_dataroot() {
  local dir="$1" conf=/etc/docker/daemon.json
  mkdir -p /etc/docker
  if [[ -f "$conf" ]]; then
    cp "$conf" "$conf.bak.$(date +%s)"
    if command -v jq >/dev/null 2>&1; then
      local tmp; tmp=$(mktemp)
      jq --arg d "$dir" '. + {"data-root":$d}' "$conf" >"$tmp" && mv "$tmp" "$conf"
    elif command -v python3 >/dev/null 2>&1; then
      python3 - "$conf" "$dir" <<'PY'
import json,sys
p,d=sys.argv[1],sys.argv[2]
try: c=json.load(open(p))
except Exception: c={}
c["data-root"]=d
json.dump(c,open(p,"w"),indent=2)
PY
    else
      echo "  [warn] jq/python3 missing — set data-root manually in $conf"
      return 0
    fi
  else
    printf '{\n  "data-root": "%s"\n}\n' "$dir" >"$conf"
  fi
  echo "  [conf]  docker data-root = $dir"
}

# Read current docker data-root from daemon.json. Empty if none.
current_docker_dataroot() {
  local conf=/etc/docker/daemon.json
  [[ -f "$conf" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '."data-root" // empty' "$conf" 2>/dev/null
  else
    sed -nE 's|.*"data-root"[[:space:]]*:[[:space:]]*"([^"]+)".*|\1|p' "$conf" | head -1
  fi
}

# Detect dead /mnt/data: entry in fstab but device not mountable.
clean_dead_mnt_data() {
  local mp="/mnt/data"
  if ! grep -qE "^[^#].*[[:space:]]${mp}[[:space:]]" /etc/fstab; then
    return 0
  fi
  if mountpoint -q "$mp"; then
    echo "[preflight] $mp mounted, leaving fstab alone."
    return 0
  fi
  if mount "$mp" 2>/dev/null && mountpoint -q "$mp"; then
    echo "[preflight] $mp mounted on demand, leaving fstab alone."
    umount "$mp" 2>/dev/null || true
    return 0
  fi
  echo "[preflight] $mp in fstab but device unavailable. Commenting out entry."
  cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
  sed -i -E "s|^([^#].*[[:space:]]${mp}[[:space:]].*)|# DEAD-DEVICE \1|" /etc/fstab
  systemctl daemon-reload || true
  if [[ -d "$mp" ]] && [[ -z "$(ls -A "$mp" 2>/dev/null)" ]]; then
    rmdir "$mp" 2>/dev/null || true
  fi
  echo "[preflight] fstab backup at /etc/fstab.bak.*"
}
clean_dead_mnt_data

cat <<WARN
=== WARNING ===
Close browsers, IDEs (VSCode/IntelliJ), and any heavy app before continuing.
This script flattens caches/dev stores directly under $USER_HOME.
Open file handles can cause inconsistencies.

WARN
read -rp "Type 'GO' to continue: " confirm
[[ "$confirm" == "GO" ]] || { echo "Aborted."; exit 1; }

# migrate SRC DEST OWNER
# Handles 4 states of SRC:
#   - missing             → skip
#   - symlink → dest      → done
#   - symlink → elsewhere → rsync from elsewhere to dest, retarget symlink
#   - real dir/file       → rsync to dest, replace with symlink
migrate() {
  local src="$1"
  local dest="$2"
  local owner="${3:-user}"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "  [skip]  $src missing"
    return 0
  fi

  if [[ -L "$src" ]]; then
    local cur
    cur=$(readlink -f "$src" || true)
    if [[ "$cur" == "$dest" ]]; then
      echo "  [done]  $src → $dest"
      return 0
    fi
    if [[ -z "$cur" || ! -e "$cur" ]]; then
      echo "  [fix]   $src dangling → $cur, recreating empty at $dest"
      mkdir -p "$dest"
      rm "$src"
      ln -s "$dest" "$src"
    else
      echo "  [redir] $src currently → $cur, migrating contents to $dest"
      mkdir -p "$(dirname "$dest")"
      rsync -aHAX --info=progress2 "$cur/" "$dest/"
      rm -rf "$cur"
      rm "$src"
      ln -s "$dest" "$src"
    fi
  else
    echo "  [move]  $src → $dest"
    mkdir -p "$(dirname "$dest")"
    rsync -aHAX --info=progress2 "$src/" "$dest/"
    rm -rf "$src"
    ln -s "$dest" "$src"
  fi

  if [[ "$owner" == "user" ]]; then
    chown -h "$USER_NAME:$USER_NAME" "$src"
    chown -R "$USER_NAME:$USER_NAME" "$dest"
  else
    chown -h root:root "$src"
  fi
}

echo
echo "=== System (flat in \$HOME, /var stays clean) ==="

echo "[1] pacman cache → $USER_HOME/pacman-pkg"
PACMAN_DEST="$USER_HOME/pacman-pkg"
PACMAN_CUR=$(current_pacman_cachedir)
# Move from currently-configured CacheDir first (e.g. ~/system/pacman-pkg).
move_existing "$PACMAN_CUR" "$PACMAN_DEST" root
# Also handle /var default in case nothing was repointed yet.
move_existing /var/cache/pacman/pkg "$PACMAN_DEST" root
mkdir -p "$PACMAN_DEST"
set_pacman_cachedir "$PACMAN_DEST"
grant_alpm_pacman_access "$PACMAN_DEST"

echo
echo "[2] docker data-root → $USER_HOME/docker"
DOCKER_DEST="$USER_HOME/docker"
DOCKER_WAS_RUNNING=0
if systemctl is-active --quiet docker; then
  systemctl stop docker docker.socket || true
  DOCKER_WAS_RUNNING=1
fi
if command -v docker >/dev/null 2>&1; then
  DOCKER_CUR=$(current_docker_dataroot)
  move_existing "$DOCKER_CUR" "$DOCKER_DEST" root
  move_existing /var/lib/docker "$DOCKER_DEST" root
  mkdir -p "$DOCKER_DEST"
  set_docker_dataroot "$DOCKER_DEST"
else
  echo "  [skip]  docker not installed"
fi
[[ "$DOCKER_WAS_RUNNING" == "1" ]] && systemctl start docker || true

echo
echo "=== User: whole ~/.cache ==="
echo "[3] $USER_HOME/.cache → $USER_HOME/cache"
migrate "$USER_HOME/.cache" "$USER_HOME/cache" user

echo
echo "=== User: dev tool stores (~/.<name> → ~/<name>) ==="
USER_DIRS=(
  .gradle           # Java/Gradle
  .m2               # Maven
  .npm              # npm cache
  .cargo            # Rust toolchain + cache
  .rustup           # Rust toolchains
  .nvm              # Node versions
  .jdks             # JetBrains JDKs
  .javacpp          # JavaCPP cache
  .android          # Android SDK/avd
  .vscode           # VSCode extensions
  .vscode-server    # VSCode remote
  .codex            # Codex
  .net              # .NET
  .dotnet           # .NET SDK
  .pipx             # pipx
  .deno             # Deno
  .bun              # Bun runtime
  .yarn             # Yarn
  .pnpm-store       # pnpm content-addressable store
  .ollama           # Ollama models (huge)
  .lmstudio         # LM Studio
  .pyenv            # pyenv
  .rbenv            # rbenv
  .sdkman           # SDKMAN
  .conda            # Anaconda
  .miniconda3       # Miniconda
  .vagrant.d        # Vagrant
)
for d in "${USER_DIRS[@]}"; do
  # Strip leading dot: .gradle → gradle
  flat="${d#.}"
  migrate "$USER_HOME/$d" "$USER_HOME/$flat" user
done

echo
echo "=== User: screenshots (REAL dir in \$HOME, no symlink) ==="
echo "[*] $SCREENSHOTS_DIR"
if [[ -L "$SCREENSHOTS_DIR" ]]; then
  cur=$(readlink -f "$SCREENSHOTS_DIR" || true)
  echo "  [pull]  $SCREENSHOTS_DIR symlink → $cur, restoring real dir"
  rm "$SCREENSHOTS_DIR"
  mkdir -p "$SCREENSHOTS_DIR"
  if [[ -n "$cur" && -d "$cur" ]]; then
    rsync -aHAX --info=progress2 "$cur/" "$SCREENSHOTS_DIR/"
    rm -rf "$cur"
  fi
else
  mkdir -p "$SCREENSHOTS_DIR"
fi
chown -R "$USER_NAME:$USER_NAME" "$SCREENSHOTS_DIR"

# Update sxhkd Print binding to point at the new screenshots location.
update_sxhkd_screenshots() {
  local new_path="$1"
  local files=(
    "$USER_HOME/.config/sxhkd/sxhkdrc"
    "$USER_HOME/arch-config/sxhkd/sxhkdrc"
  )
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -q 'maim -s' "$f"; then
      sed -i -E "s|d=[^;]+;( *mkdir -p \"\\\$d\" && f=\"\\\$d/)|d=$new_path;\\1|" "$f"
      echo "  [sxhkd] updated $f → d=$new_path"
    fi
  done
  pkill -USR1 sxhkd 2>/dev/null && echo "  [sxhkd] reloaded" || true
}
update_sxhkd_screenshots "$SCREENSHOTS_DIR"

echo
echo "=== User: heavy ~/.local/share entries (→ ~/share-<name>) ==="
SHARE_DIRS=(
  pnpm
  JetBrains
  pipx
  Steam
  flatpak
  containers
)
for d in "${SHARE_DIRS[@]}"; do
  migrate "$USER_HOME/.local/share/$d" "$USER_HOME/share-$d" user
done

echo
echo "=== Cleanup empty legacy nests (~/storage, ~/system) ==="
cleanup_empty_tree() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  # Remove empty dirs depth-first. find -empty + -delete is safe: only removes
  # truly-empty dirs and leaves anything non-empty intact.
  find "$root" -depth -type d -empty -delete 2>/dev/null || true
  if [[ -d "$root" ]]; then
    echo "  [keep]  $root still has files, not removing"
    ls -la "$root" | head -20
  else
    echo "  [gone]  $root removed"
  fi
}
cleanup_empty_tree "$USER_HOME/storage"
cleanup_empty_tree "$USER_HOME/system"

echo
echo "=== Done ==="
df -hT / "$USER_HOME"
echo
echo "System stores (flat in \$HOME):"
{
  echo "  pacman CacheDir : $(grep -E '^[[:space:]]*CacheDir' /etc/pacman.conf 2>/dev/null | tail -1)"
  echo "  docker data-root: $(grep -E 'data-root' /etc/docker/daemon.json 2>/dev/null | tr -d ' ')"
  ls -lad "$PACMAN_DEST" "$DOCKER_DEST" "$SCREENSHOTS_DIR" 2>/dev/null
}
echo
echo "Active symlinks (user dotdirs → flat \$HOME targets):"
{
  find "$USER_HOME" -maxdepth 1 -type l 2>/dev/null
  find "$USER_HOME/.local/share" -maxdepth 1 -type l 2>/dev/null
} | sort -u

cat <<EOF

Everything now lives directly under $USER_HOME. No /var symlinks, no nested
~/storage or ~/system. User dotdirs (~/.cache, ~/.gradle, ...) are symlinks
to flat targets (~/cache, ~/gradle, ...). Share entries point to ~/share-<name>.

Revert system store to /var:
  pacman : remove CacheDir line in /etc/pacman.conf, mv $PACMAN_DEST /var/cache/pacman/pkg
  docker : systemctl stop docker; drop data-root in /etc/docker/daemon.json; mv $DOCKER_DEST /var/lib/docker; systemctl start docker

EOF
