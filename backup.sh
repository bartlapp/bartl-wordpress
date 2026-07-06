#!/usr/bin/env bash

# Bartl backup script for WordPress
# Dumps the MySQL database, tars wp-content/uploads, combines into a single
# .tar.gz blob with metadata (version, timestamp, FQDN).

set -eu
set -o pipefail

BARTL_BACKUP_DIR="${BARTL_BACKUP_DIR:-./backups}"
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-rootpass}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
WORDPRESS_VERSION="${WORDPRESS_VERSION:-unknown}"
BARTL_FQDN="${BARTL_FQDN:-$(hostname -f 2>/dev/null || echo localhost)}"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
BLOB_NAME="${BARTL_FQDN}_${WORDPRESS_VERSION}_${TIMESTAMP}.tar.gz"

log() {
    echo "BARTL-BACKUP: $*"
}

check_dependencies() {
    local missing=0
    for cmd in mysqldump tar gzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR: Required command not found: ${cmd}"
            missing=1
        fi
    done
    if [ "$missing" -eq 1 ]; then
        log "Installing missing dependencies..."
        apt-get update -qq && apt-get install -y -qq default-mysql-client >/dev/null 2>&1
    fi
}

wait_for_db() {
    local retries=0
    while ! bash -c "echo >/dev/tcp/${MYSQL_HOST}/${MYSQL_PORT}" 2>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -ge 30 ]; then
            log "ERROR: Database not reachable after 30 attempts"
            exit 1
        fi
        sleep 2
    done
}

main() {
    log "Starting backup."

    check_dependencies
    wait_for_db

    work_dir=$(mktemp -d)
    trap 'rm -rf "$work_dir"' EXIT

    # Dump database
    log "Dumping database ${MYSQL_DATABASE}..."
    mysqldump \
        -h "$MYSQL_HOST" \
        -P "$MYSQL_PORT" \
        -u "$MYSQL_USER" \
        -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        "$MYSQL_DATABASE" > "$work_dir/database.sql"
    log "Database dump complete ($(wc -c < "$work_dir/database.sql") bytes)."

    # Tar uploads directory
    local uploads_dir="/var/www/html/wp-content/uploads"
    if [ -d "$uploads_dir" ] && [ "$(ls -A "$uploads_dir" 2>/dev/null)" ]; then
        log "Archiving uploads directory..."
        tar -cf "$work_dir/uploads.tar" -C "$uploads_dir" .
        log "Uploads archive complete ($(wc -c < "$work_dir/uploads.tar") bytes)."
    else
        log "No uploads to archive."
    fi

    # Write metadata
    cat > "$work_dir/metadata.txt" <<EOF
version=${WORDPRESS_VERSION}
timestamp=${TIMESTAMP}
fqdn=${BARTL_FQDN}
database=${MYSQL_DATABASE}
EOF

    # Checksum every member of the blob. SHA256SUMS travels inside the blob and
    # is what the restore path verifies before loading any state. This is the
    # integrity half of the pattern's fetch_backup() - a blob that fails
    # verification is not restored.
    log "Computing checksums..."
    ( cd "$work_dir" && sha256sum -- * > SHA256SUMS )
    log "Checksums:"
    sed 's/^/  /' "$work_dir/SHA256SUMS"

    # Combine into final blob
    mkdir -p "$BARTL_BACKUP_DIR"
    log "Creating backup blob: ${BLOB_NAME}"
    tar -czf "$BARTL_BACKUP_DIR/$BLOB_NAME" -C "$work_dir" .

    # Sidecar checksum of the whole blob, so integrity can be checked before the
    # blob is even opened (e.g. after transfer to another provider).
    ( cd "$BARTL_BACKUP_DIR" && sha256sum -- "$BLOB_NAME" > "${BLOB_NAME}.sha256" )

    local blob_size
    blob_size=$(wc -c < "$BARTL_BACKUP_DIR/$BLOB_NAME")
    log "Backup complete: ${BARTL_BACKUP_DIR}/${BLOB_NAME} (${blob_size} bytes)"
    log "Sidecar checksum: ${BARTL_BACKUP_DIR}/${BLOB_NAME}.sha256"
}

main "$@"
