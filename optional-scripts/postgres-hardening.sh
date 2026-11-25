#!/usr/bin/env bash
# Replaces "trust" authentication in pg_hba.conf: peer for the local socket,
# scram-sha-256 for TCP. Idempotent. Leaves no backup file: the
# original rules are kept in memory and restored if any step fails.
#
# Run:
#   sudo bash ~/arch-config/optional-scripts/postgres-hardening.sh
set -Eeuo pipefail

readonly DB_ROLE=postgres
readonly DB_HOST=localhost
readonly SERVICE=postgresql
readonly WRONG_PASSWORD="wrong-$RANDOM-$RANDOM"
readonly RELOAD_WAIT_SECONDS=2

HBA_FILE=""
ORIGINAL_RULES=""

admin_psql() { runuser -u "$DB_ROLE" -- psql -X -w -v ON_ERROR_STOP=1 -d postgres "$@"; }

fail() { echo "ERROR: $*" >&2; return 1; }

rollback() {
    local status=$?
    trap - EXIT
    if [[ $status -ne 0 && -n $ORIGINAL_RULES ]]; then
        echo "Failed; restoring $HBA_FILE" >&2
        printf '%s\n' "$ORIGINAL_RULES" >"$HBA_FILE"
        systemctl reload "$SERVICE" || echo "Reload failed; run: systemctl reload $SERVICE" >&2
    fi
    exit "$status"
}

harden_rules() {
    sed -i -E \
        -e '/^[[:space:]]*local[[:space:]]/ s/[[:space:]]trust[[:space:]]*$/ peer/' \
        -e '/^[[:space:]]*host[a-z]*[[:space:]]/ s/[[:space:]]trust[[:space:]]*$/ scram-sha-256/' \
        "$1"
}

count_bad_rules() {
    admin_psql -Atc "select count(*) from pg_hba_file_rules where error is not null or auth_method = 'trust'"
}

check_rules() {
    local bad
    bad=$(count_bad_rules)
    [[ $bad == 0 ]] || fail "$bad invalid or trust rules remain"
}

verify_access() {
    admin_psql -Atc 'select 1' >/dev/null || fail "peer login does not work"
    if PGPASSWORD=$WRONG_PASSWORD psql -X -w -h "$DB_HOST" -U "$DB_ROLE" -d postgres -c 'select 1' >/dev/null 2>&1; then
        fail "a wrong password was still accepted"
    fi
    echo "Enter the new password once more to confirm that it works."
    env -u PGPASSWORD psql -X -W -h "$DB_HOST" -U "$DB_ROLE" -d postgres -c 'select 1' >/dev/null ||
        fail "login with the new password failed"
}

main() {
    [[ $EUID -eq 0 ]] || fail "run with sudo"
    cd /
    local bad
    bad=$(count_bad_rules)
    if [[ $bad == 0 ]]; then
        echo "Already hardened. Nothing to do."
        return 0
    fi
    HBA_FILE=$(admin_psql -Atc 'show hba_file')
    echo "Set a new password for role $DB_ROLE (applies immediately)."
    admin_psql -c "\\password $DB_ROLE"
    ORIGINAL_RULES=$(<"$HBA_FILE")
    trap rollback EXIT
    harden_rules "$HBA_FILE"
    check_rules
    systemctl reload "$SERVICE"
    sleep "$RELOAD_WAIT_SECONDS"
    verify_access
    echo "Done."
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
