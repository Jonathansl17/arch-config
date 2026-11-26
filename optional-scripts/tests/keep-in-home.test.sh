#!/usr/bin/env bash
# Tests for lib/keep-in-home.sh. Works in throwaway dirs under mktemp; never
# touches the real home. Run: bash optional-scripts/tests/keep-in-home.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/keep-in-home.sh
source "$SCRIPT_DIR/../lib/keep-in-home.sh"

ME="$(id -un)"
failures=0

expect() {
    local name="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: want '$want', got '$got'"
        failures=$((failures + 1))
    fi
}

kind() { [[ -L "$1" ]] && echo symlink || { [[ -d "$1" ]] && echo dir || echo none; }; }

root=$(mktemp -d)

# Regression: ~/.m2 offloaded to /mnt/data must come back as a real dir.
mkdir -p "$root/offload/.m2/repository"
echo jar >"$root/offload/.m2/repository/a.jar"
ln -s "$root/offload/.m2" "$root/.m2"
keep_real_dir "$root/.m2" "$ME" >/dev/null
expect "symlink becomes real dir" dir "$(kind "$root/.m2")"
expect "contents pulled back" jar "$(cat "$root/.m2/repository/a.jar")"
expect "offloaded copy removed" none "$(kind "$root/offload/.m2")"
expect "no staging left behind" none "$(kind "$root/.m2.pull-staging")"

echo keep >"$root/.m2/marker"
keep_real_dir "$root/.m2" "$ME" >/dev/null
expect "real dir left untouched" keep "$(cat "$root/.m2/marker")"

ln -s "$root/gone" "$root/dangling"
keep_real_dir "$root/dangling" "$ME" >/dev/null
expect "dangling symlink becomes empty dir" dir "$(kind "$root/dangling")"

keep_real_dir "$root/fresh" "$ME" >/dev/null
expect "missing dir is created" dir "$(kind "$root/fresh")"

expect ".m2 is in the keep list" yes "$(printf '%s\n' "${KEEP_IN_HOME_DIRS[@]}" | grep -qx .m2 && echo yes)"

rm -rf "$root"
[[ $failures -eq 0 ]] && echo "all passed" || { echo "$failures failed"; exit 1; }
