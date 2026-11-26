# shellcheck shell=bash
# Guards that keep IDE state valid across a cache migration: refuse to run
# while an IDE holds the caches open, and pin Maven's local repository to the
# stable ~/.m2 path so IDEs never record the symlink's resolved target.
# Sourced, never executed.

# Full-command-line patterns (pgrep -f) of IDEs that cache paths under ~.
readonly IDE_PROCESS_PATTERNS=(
    "/opt/intellij-idea"
    "/opt/visual-studio-code/code"
)
readonly MAVEN_SETTINGS_REL=".m2/settings.xml"
readonly MAVEN_REPO_REL=".m2/repository"

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

# maven_settings_xml REPO: settings.xml body pinning localRepository to REPO.
maven_settings_xml() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0">
  <localRepository>$1</localRepository>
</settings>
EOF
}

# pin_maven_local_repo HOME USER: write ~/.m2/settings.xml with a fixed
# localRepository when none exists. Never edits an existing file; warns when
# that file points somewhere else.
pin_maven_local_repo() {
    local home="$1" user="$2"
    local settings="$home/$MAVEN_SETTINGS_REL" repo="$home/$MAVEN_REPO_REL"
    [[ -d "$home/.m2" ]] || { echo "  [skip]  $home/.m2 missing"; return 0; }
    if [[ ! -e "$settings" ]]; then
        maven_settings_xml "$repo" >"$settings"
        chown "$user:$user" "$settings"
        echo "  [pin]   $settings localRepository = $repo"
        return 0
    fi
    if grep -qF "<localRepository>$repo</localRepository>" "$settings"; then
        echo "  [done]  $settings already pins $repo"
        return 0
    fi
    echo "  [warn]  $settings exists without <localRepository>$repo</localRepository>; edit it by hand"
}
