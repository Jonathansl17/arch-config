#!/usr/bin/env bash
# Mirror of migrate-to-mnt-data.sh — moves caches/heavy data BACK TO /home.
# Use if /mnt/data dies, or you want everything consolidated on the Arch disk.
# Future writes auto-go to /home/<user>/storage because originals are symlinks.
# Idempotent. Safe to re-run.
#
# Strategy:
#   - Whole ~/.cache → /home/<user>/storage/cache (catches ALL XDG-cache apps)
#   - Heavy dev tool stores (~/.gradle, ~/.m2, ~/.npm, ~/.cargo, etc.)
#   - System stores → /home/<user>/system/* (NOT under /var, NOT under storage/).
#     pacman.conf CacheDir + docker daemon.json data-root are repointed so /var
#     stays clean (no symlinks). Data lives entirely in $HOME.
#   - screenshots → /home/<user>/screenshots as a REAL dir (no symlink)
#
# Run with all desktop apps closed (browsers, IDEs) to avoid open-file races.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

# Resolve the invoking (non-root) user. SUDO_USER is the canonical source when
# launched via sudo; fall back to logname for sudo -i / su - cases. Refuse to
# run if we still end up with root, since we'd chown user files to root:root.
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
DATA="$USER_HOME/storage"
# Kept directly in $HOME, NOT nested under storage/:
SYSTEM_DATA="$USER_HOME/system"        # pacman cache, docker data-root
SCREENSHOTS_DIR="$USER_HOME/screenshots"

mkdir -p "$DATA"
chown "$USER_NAME:$USER_NAME" "$DATA"

# pull_to_home CURRENT DEST OWNER
# Move a store's data into $HOME and leave NO symlink behind at CURRENT.
# Handles CURRENT being: missing | real dir | symlink → anywhere.
pull_to_home() {
  local cur_path="$1" dest="$2" owner="${3:-root}"
  mkdir -p "$dest"
  if [[ -L "$cur_path" ]]; then
    local tgt; tgt=$(readlink -f "$cur_path" || true)
    if [[ "$tgt" == "$dest" ]]; then
      echo "  [done]  data already at $dest; dropping $cur_path symlink"
      rm "$cur_path"
    else
      if [[ -n "$tgt" && -d "$tgt" ]]; then
        echo "  [pull]  $cur_path → $tgt, moving contents to $dest"
        rsync -aHAX --info=progress2 "$tgt/" "$dest/"
        rm -rf "$tgt"
      fi
      rm "$cur_path"
    fi
  elif [[ -d "$cur_path" ]]; then
    echo "  [move]  $cur_path → $dest"
    rsync -aHAX --info=progress2 "$cur_path/" "$dest/"
    rm -rf "$cur_path"
  else
    echo "  [init]  $dest created (no prior data)"
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

# Grant the alpm sandbox user access to a pacman CacheDir under $HOME. Pacman
# drops privs from root to alpm when downloading (DownloadUser = alpm, default
# since pacman 7.x), so alpm needs:
#   - ownership of the cache dir itself (to create download-XXXX/*.part files)
#   - traverse (+x) on every parent dir up to / — $HOME is 700 by default, so
#     without an ACL alpm cannot even enter it
# ACL is used instead of chmod o+x so other users still cannot traverse $HOME.
# Idempotent: setfacl is a no-op if the entry already exists.
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
  # Walk from $dir's parent up to (but not including) /, granting alpm traverse.
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

# Detect dead /mnt/data: entry in fstab but device not mountable.
# If fstab references /mnt/data and mount fails, comment the entry out and
# remove the empty mountpoint so dangling symlinks can be cleanly fixed.
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
This script moves ~/.cache and dev tool dirs to $DATA.
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
echo "=== System (data → \$HOME, /var stays clean) ==="

echo "[1] pacman cache → $SYSTEM_DATA/pacman-pkg"
pull_to_home /var/cache/pacman/pkg "$SYSTEM_DATA/pacman-pkg" root
set_pacman_cachedir "$SYSTEM_DATA/pacman-pkg"
grant_alpm_pacman_access "$SYSTEM_DATA/pacman-pkg"

echo
echo "[2] docker data-root → $SYSTEM_DATA/docker"
DOCKER_WAS_RUNNING=0
if systemctl is-active --quiet docker; then
  systemctl stop docker docker.socket || true
  DOCKER_WAS_RUNNING=1
fi
if command -v docker >/dev/null 2>&1; then
  pull_to_home /var/lib/docker "$SYSTEM_DATA/docker" root
  set_docker_dataroot "$SYSTEM_DATA/docker"
else
  echo "  [skip]  docker not installed"
fi
[[ "$DOCKER_WAS_RUNNING" == "1" ]] && systemctl start docker || true

echo
echo "=== User: whole ~/.cache ==="
echo "[3] $USER_HOME/.cache (catches ALL XDG-cache apps)"
migrate "$USER_HOME/.cache" "$DATA/user/cache" user

echo
echo "=== User: dev tool stores ==="
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
  .pnpm-store       # pnpm content-addressable store (rare alt location)
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
  migrate "$USER_HOME/$d" "$DATA/user/home-dirs/$d" user
done

echo
echo "=== User: screenshots (REAL dir in \$HOME, no symlink) ==="
echo "[*] $SCREENSHOTS_DIR"
# If a prior run symlinked ~/screenshots → storage, pull the data back and
# restore it as a plain directory living directly in $HOME.
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
echo "=== User: heavy ~/.local/share entries ==="
SHARE_DIRS=(
  pnpm
  JetBrains
  pipx
  Steam
  flatpak
  containers
)
for d in "${SHARE_DIRS[@]}"; do
  migrate "$USER_HOME/.local/share/$d" "$DATA/user/share/$d" user
done

echo
echo "=== Done ==="
df -hT / "$USER_HOME" "$DATA"
echo
echo "System stores (data in \$HOME, /var clean):"
{
  echo "  pacman CacheDir : $(grep -E '^[[:space:]]*CacheDir' /etc/pacman.conf 2>/dev/null | tail -1)"
  echo "  docker data-root: $(grep -E 'data-root' /etc/docker/daemon.json 2>/dev/null | tr -d ' ')"
  ls -lad "$SYSTEM_DATA"/* "$SCREENSHOTS_DIR" 2>/dev/null
}
echo
echo "Active symlinks (user cache/dev stores → storage):"
{
  find "$USER_HOME" -maxdepth 1 -type l 2>/dev/null
  find "$USER_HOME/.local/share" -maxdepth 1 -type l 2>/dev/null
} | sort -u

cat <<EOF

screenshots + system stores live DIRECTLY in $USER_HOME (no /var symlinks).
User caches/dev stores still redirect to $DATA via symlinks; most NEW tools
respect XDG_CACHE_HOME (~/.cache, linked) so they inherit that. If a tool uses
its own dir under ~/, add it to USER_DIRS and re-run this script.

Revert system store to /var:
  pacman : remove CacheDir line in /etc/pacman.conf, mv $SYSTEM_DATA/pacman-pkg /var/cache/pacman/pkg
  docker : systemctl stop docker; drop data-root in /etc/docker/daemon.json; mv $SYSTEM_DATA/docker /var/lib/docker; systemctl start docker

EOF
