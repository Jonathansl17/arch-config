# shellcheck shell=bash
# Refuse to migrate caches while an IDE holds them open: IDEs record resolved
# cache paths and keep stale state when those paths move underneath them.
# Sourced, never executed.

# Full-command-line patterns (pgrep -f) of IDEs that cache paths under ~.
readonly IDE_PROCESS_PATTERNS=(
    "/opt/intellij-idea"
    "/opt/visual-studio-code/code"
)

# ensure_ides_closed USER: fail when any listed IDE runs for USER.
ensure_ides_closed() {
    local user="$1" pattern running=()
    for pattern in "${IDE_PROCESS_PATTERNS[@]}"; do
        pgrep -u "$user" -f "$pattern" >/dev/null && running+=("$pattern")
    done
    [[ ${#running[@]} -eq 0 ]] && return 0
    echo "ERROR: close these IDEs first, they hold cache paths open:"
    printf '  %s\n' "${running[@]}"
    return 1
}

