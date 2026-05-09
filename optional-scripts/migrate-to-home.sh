#!/usr/bin/env bash
# Mirror of migrate-to-mnt-data.sh — moves caches/heavy data BACK TO /home.
# Use if /mnt/data dies, or you want everything consolidated on the Arch disk.
# Future writes auto-go to /home/<user>/storage because originals are symlinks.
# Idempotent. Safe to re-run.
#
# Strategy:
#   - Whole ~/.cache → /home/<user>/storage/cache (catches ALL XDG-cache apps)
#   - Heavy dev tool stores (~/.gradle, ~/.m2, ~/.npm, ~/.cargo, etc.)
#   - System: /var/cache/pacman/pkg, /var/lib/docker
#
# Run with all desktop apps closed (browsers, IDEs) to avoid open-file races.

set -euo pipefail

USER_NAME="jony"
USER_HOME="/home/$USER_NAME"
DATA="$USER_HOME/storage"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if [[ ! -d "$USER_HOME" ]]; then
  echo "ERROR: $USER_HOME does not exist. Aborting."
  exit 1
fi

mkdir -p "$DATA"
chown "$USER_NAME:$USER_NAME" "$DATA"

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
  .m2               # Maven
  .npm              # npm cache
  .cargo            # Rust toolchain + cache
  .rustup           # Rust toolchains
  .nvm              # Node versions
  .jdks             # JetBrains JDKs
  .javacpp          # JavaCPP cache
  .android          # Android SDK/avd
  .vscode           # VSCode extensions
  .vscode-server    # VSCode remote (if any)
  .codex            # Codex
  .claude           # Claude artifacts
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
