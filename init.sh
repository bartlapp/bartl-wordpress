#!/usr/bin/env bash

# Bartl init script for WordPress
# Handles: vanilla install, restore from backup, upgrade detection
# There is no restore.sh - restore IS init with a backup available.

set -eu
set -o pipefail

BARTL_SHARED="${BARTL_SHARED:-/bartl}"
BARTL_BACKUP_DIR="${BARTL_BACKUP_DIR:-/backups}"
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-rootpass}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
WORDPRESS_VERSION="${WORDPRESS_VERSION:-unknown}"

MARKER_AWAITS_DB="${BARTL_SHARED}/BARTL_AWAITS_DB"
MARKER_READY="${BARTL_SHARED}/BARTL_READY"
VERSION_FILE="${BARTL_SHARED}/.bartl_version"

log() {
    echo "BARTL: $*"
}

install_dependencies() {
    if ! command -v mysqldump >/dev/null 2>&1; then
        log "Installing MySQL client..."
        apt-get update -qq && apt-get install -y -qq default-mysql-client >/dev/null 2>&1
    fi
}

wait_for_db() {
    log "Waiting for database on ${MYSQL_HOST}:${MYSQL_PORT}..."
    local retries=0
    while ! bash -c "echo >/dev/tcp/${MYSQL_HOST}/${MYSQL_PORT}" 2>/dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -ge 60 ]; then
            log "ERROR: Database not reachable after 60 attempts"
            exit 1
        fi
        sleep 2
    done
    # Give MySQL a moment to accept connections after port is open
    sleep 3
    log "Database is reachable."
}

find_latest_backup() {
    if [ ! -d "$BARTL_BACKUP_DIR" ]; then
        echo ""
        return
    fi
    # Find the latest .tar.gz backup blob
    local latest
    latest=$(find "$BARTL_BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null | sort | tail -n 1)
    echo "$latest"
}

restore_database() {
    local sql_file="$1"
    log "Restoring database from ${sql_file}..."

    if [[ "$sql_file" == *.gz ]]; then
        gunzip -c "$sql_file" | mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"
    else
        mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$sql_file"
    fi

    log "Database restored."
}

restore_uploads() {
    local tar_file="$1"
    local target="/var/www/html/wp-content/uploads"
    log "Restoring uploads from ${tar_file}..."
    mkdir -p "$target"
    tar -xf "$tar_file" -C "$target"
    log "Uploads restored."
}

restore_from_backup() {
    local backup_blob="$1"
    local work_dir
    work_dir=$(mktemp -d)

    log "Extracting backup blob: ${backup_blob}"
    tar -xzf "$backup_blob" -C "$work_dir"

    # Signal DB to start - we need it for the restore
    touch "$MARKER_AWAITS_DB"
    wait_for_db

    # Restore database
    local sql_file
    sql_file=$(find "$work_dir" -name "database.sql*" -type f | head -n 1)
    if [ -n "$sql_file" ]; then
        restore_database "$sql_file"
    else
        log "WARNING: No database dump found in backup"
    fi

    # Restore uploads
    local uploads_tar
    uploads_tar=$(find "$work_dir" -name "uploads.tar" -type f | head -n 1)
    if [ -n "$uploads_tar" ]; then
        restore_uploads "$uploads_tar"
    fi

    # Read version from backup metadata
    if [ -f "$work_dir/metadata.txt" ]; then
        log "Backup metadata:"
        cat "$work_dir/metadata.txt"
    fi

    rm -rf "$work_dir"
    log "Restore complete."
}

vanilla_install() {
    log "Vanilla install - no backup found."
    log "WordPress will initialize itself on first HTTP request."

    # Signal DB to start
    touch "$MARKER_AWAITS_DB"
    wait_for_db

    log "Vanilla install complete."
}

check_upgrade() {
    if [ ! -f "$VERSION_FILE" ]; then
        return 1
    fi
    local old_version
    old_version=$(cat "$VERSION_FILE")
    if [ "$old_version" != "$WORDPRESS_VERSION" ]; then
        log "Upgrade detected: ${old_version} -> ${WORDPRESS_VERSION}"
        return 0
    fi
    return 1
}

handle_upgrade() {
    log "Running upgrade procedure..."

    # Signal DB to start
    touch "$MARKER_AWAITS_DB"
    wait_for_db

    # WordPress handles its own DB migrations on the next admin page load.
    # We just need to ensure the DB is available and the new container version
    # is running.
    log "WordPress will run database upgrades automatically on next admin access."
    log "Upgrade handling complete."
}

main() {
    log "Bartl init starting."
    log "WordPress version: ${WORDPRESS_VERSION}"

    install_dependencies

    # Clean any stale markers
    rm -f "$MARKER_AWAITS_DB" "$MARKER_READY"

    local backup
    backup=$(find_latest_backup)

    if [ -f "$VERSION_FILE" ] && check_upgrade; then
        handle_upgrade
    elif [ -n "$backup" ]; then
        log "Backup found: ${backup}"
        restore_from_backup "$backup"
    else
        vanilla_install
    fi

    # Record version
    echo "$WORDPRESS_VERSION" > "$VERSION_FILE"

    # Signal all containers: stack is ready
    touch "$MARKER_READY"
    log "Stack is ready."

    # Transition to backup daemon: run backup every 6 hours
    log "Entering backup daemon mode (every 6 hours)."
    while true; do
        sleep 21600
        log "Running scheduled backup..."
        /bin/bash /backup.sh || log "WARNING: Scheduled backup failed"
    done
}

main "$@"
