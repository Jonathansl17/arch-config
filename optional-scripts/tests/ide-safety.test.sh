#!/usr/bin/env bash
# Tests for lib/ide-safety.sh Maven pinning. Works in a throwaway home under
# mktemp; never touches the real ~/.m2. Run: bash optional-scripts/tests/ide-safety.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ide-safety.sh
source "$SCRIPT_DIR/../lib/ide-safety.sh"

ME="$(id -un)"
failures=0

expect() {
    local name="$1" want="$2" got="$3"
    if [[ "$got" == *"$want"* ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name: want '$want' in '$got'"
        failures=$((failures + 1))
    fi
}

fresh_home() {
    local h
    h=$(mktemp -d)
    mkdir -p "$h/.m2"
    echo "$h"
}

home=$(fresh_home)
pin_maven_local_repo "$home" "$ME" >/dev/null
expect "creates settings with stable repo" \
    "<localRepository>$home/.m2/repository</localRepository>" \
    "$(cat "$home/.m2/settings.xml")"
expect "second run is idempotent" "[done]" "$(pin_maven_local_repo "$home" "$ME")"
rm -rf "$home"

home=$(fresh_home)
echo "<settings><localRepository>/elsewhere</localRepository></settings>" >"$home/.m2/settings.xml"
expect "foreign settings only warns" "[warn]" "$(pin_maven_local_repo "$home" "$ME")"
expect "foreign settings left untouched" "/elsewhere" "$(cat "$home/.m2/settings.xml")"
rm -rf "$home"

home=$(mktemp -d)
expect "missing .m2 skips" "[skip]" "$(pin_maven_local_repo "$home" "$ME")"
expect "missing .m2 creates nothing" "empty" "$(ls -A "$home" | grep -q . && echo dirty || echo empty)"
rm -rf "$home"

[[ $failures -eq 0 ]] && echo "all passed" || { echo "$failures failed"; exit 1; }
