#!/usr/bin/env bash
# Migrate caches and heavy data to /mnt/data via symlinks.
# Future writes auto-go to /mnt/data because original paths are symlinks.
# If /mnt/data is not set up, offers to wipe a spare disk (naming any Windows,
# macOS or Linux found on it) after the user types DESTROY. Never touches the
# disk holding /, /home or /boot, and stops cleanly when no spare disk exists.
# Idempotent. Safe to re-run.
#
# Strategy:
#   - Whole ~/.cache → /mnt/data/user/cache (catches ALL XDG-cache apps)
#   - Heavy dev tool stores (~/.gradle, ~/.npm, ~/.cargo, etc.)
#   - System: /var/cache/pacman/pkg, /var/lib/docker → /mnt/data/system/* (symlink)
#   - ~/screenshots and ~/.m2 stay REAL dirs in $HOME (lib/keep-in-home.sh)
#
# Run with all desktop apps closed (browsers, IDEs) to avoid open-file races.

set -euo pipefail

DATA="/mnt/data"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/disk-detect.sh
source "$SCRIPT_DIR/lib/disk-detect.sh"
# shellcheck source=lib/grub-config.sh
source "$SCRIPT_DIR/lib/grub-config.sh"
# shellcheck source=lib/windows-leftovers.sh
source "$SCRIPT_DIR/lib/windows-leftovers.sh"
# shellcheck source=lib/disk-format.sh
source "$SCRIPT_DIR/lib/disk-format.sh"
# shellcheck source=lib/data-disk-setup.sh
source "$SCRIPT_DIR/lib/data-disk-setup.sh"
# shellcheck source=lib/ide-safety.sh
source "$SCRIPT_DIR/lib/ide-safety.sh"
# shellcheck source=lib/keep-in-home.sh
source "$SCRIPT_DIR/lib/keep-in-home.sh"

ensure_ides_closed "$USER_NAME" || exit 1

ensure_data_disk || exit 1

cat <<'WARN'
=== WARNING ===
Close browsers, IDEs (VSCode/IntelliJ), and any heavy app before continuing.
This script moves ~/.cache and dev tool dirs to /mnt/data.
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
echo "=== System ==="

echo "[1] /var/cache/pacman/pkg"
migrate /var/cache/pacman/pkg "$DATA/system/pacman-pkg" root

echo
echo "[2] /var/lib/docker"
DOCKER_WAS_RUNNING=0
if systemctl is-active --quiet docker; then
  systemctl stop docker docker.socket || true
  DOCKER_WAS_RUNNING=1
fi
if [[ ! -e /var/lib/docker && ! -L /var/lib/docker ]] && command -v docker >/dev/null 2>&1; then
  mkdir -p "$DATA/system/docker"
  ln -s "$DATA/system/docker" /var/lib/docker
  echo "  [init]  $DATA/system/docker created (docker never ran)"
else
  migrate /var/lib/docker "$DATA/system/docker" root
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
  .npm              # npm cache
  .cargo            # Rust toolchain + cache
  .rustup           # Rust toolchains
  .nvm              # Node versions
  .jdks             # JetBrains JDKs
  .javacpp          # JavaCPP cache
  .android          # Android SDK/avd
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
echo "=== User: dirs kept as REAL dirs in \$HOME (never offloaded) ==="
for d in "${KEEP_IN_HOME_DIRS[@]}"; do
  keep_real_dir "$USER_HOME/$d" "$USER_NAME"
done

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
update_sxhkd_screenshots "$USER_HOME/screenshots"

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
echo "Active symlinks:"
{
  ls -la /var/cache/pacman/pkg /var/lib/docker 2>/dev/null
  find "$USER_HOME" -maxdepth 1 -type l 2>/dev/null
  find "$USER_HOME/.local/share" -maxdepth 1 -type l 2>/dev/null
} | sort -u

cat <<EOF

Future caches/data automatically land on $DATA via symlinks.
For NEW tools: most respect XDG_CACHE_HOME (~/.cache, now linked) so they
inherit the redirect. If a tool uses its own dir under ~/, add it to USER_DIRS
and re-run this script.

Revert one item:
  systemctl stop <service>     # if applicable
  rm <symlink>
  mv $DATA/<path> <original>

EOF
