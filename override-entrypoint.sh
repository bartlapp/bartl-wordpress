#!/usr/bin/env bash

# Bartl override-entrypoint.sh for Docker Compose choreography
# Bind-mounted into containers to coordinate multi-container startup.
# Waits for the appropriate marker file before executing the original entrypoint.
#
# In K8s, this entire script is unnecessary - initContainers and readiness
# probes handle the same coordination natively.

set -eu
set -o pipefail

BARTL_SHARED="${BARTL_SHARED:-/bartl}"
BARTL_ROLE="${BARTL_ROLE:-app}"
MARKER_AWAITS_DB="${BARTL_SHARED}/BARTL_AWAITS_DB"
MARKER_READY="${BARTL_SHARED}/BARTL_READY"

log() {
    echo "BARTL-OVERRIDE [$(hostname)]: $*"
}

wait_for_marker() {
    local marker="$1"
    local description="$2"
    log "Waiting for ${description}..."
    while [ ! -e "$marker" ]; do
        sleep 2
    done
    log "${description} - done."
}

wait_for_any_marker() {
    log "Waiting for BARTL_AWAITS_DB or BARTL_READY..."
    while [ ! -e "$MARKER_AWAITS_DB" ] && [ ! -e "$MARKER_READY" ]; do
        sleep 2
    done
    log "Marker found. Proceeding."
}

wait_for_db_port() {
    local host="${WORDPRESS_DB_HOST%%:*}"
    local port="${WORDPRESS_DB_HOST##*:}"
    port="${port:-3306}"

    log "Waiting for database at ${host}:${port}..."
    while ! bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; do
        sleep 2
    done
    log "Database is reachable."
}

case "$BARTL_ROLE" in
    db)
        # DB container: start when init has prepared data (BARTL_AWAITS_DB)
        # or when the stack is fully ready (BARTL_READY, restart case)
        wait_for_any_marker
        ;;
    app)
        # App container: wait for full initialization, then verify DB is up
        wait_for_marker "$MARKER_READY" "stack initialization"
        wait_for_db_port
        ;;
    *)
        log "Unknown BARTL_ROLE: ${BARTL_ROLE}. Waiting for BARTL_READY."
        wait_for_marker "$MARKER_READY" "stack initialization"
        ;;
esac

log "Executing original entrypoint: $*"
exec "$@"
