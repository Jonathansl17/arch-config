# shellcheck shell=bash
# Directories that must stay as real directories on the home disk, never
# offloaded behind a symlink. Sourced, never executed.

# Relative to the user's home. ~/.m2 stays put so IDEs keep a stable Maven
# repository path; screenshots stay on the home disk by choice.
readonly KEEP_IN_HOME_DIRS=(
    screenshots
    .m2
)

# keep_real_dir DIR USER: make DIR a real directory owned by USER. A symlink
# left by an earlier migration is replaced by a copy of its target, and the
# target is deleted only after the copy succeeded.
keep_real_dir() {
    local dir="$1" user="$2" target staging
    if [[ ! -L "$dir" ]]; then
        mkdir -p "$dir"
        chown -R "$user:$user" "$dir"
        echo "  [keep]  $dir real dir"
        return 0
    fi
    target=$(readlink -f "$dir" || true)
    staging="$dir.pull-staging"
    mkdir -p "$staging"
    if [[ -n "$target" && -d "$target" ]]; then
        echo "  [pull]  $dir symlink → $target, restoring real dir"
        rsync -aHAX --info=progress2 "$target/" "$staging/" || return 1
    fi
    rm "$dir"
    mv "$staging" "$dir"
    [[ -n "$target" && -d "$target" ]] && rm -rf "$target"
    chown -R "$user:$user" "$dir"
}
