# bartl-wordpress

A stateful WordPress stack made fully portable. Install, restore, upgrade, migration, and disaster recovery are one operation, driven by observed state - not five separate procedures. This is the reference implementation of the Bartl pattern.

For the full thesis, see [bartl.app](https://bartl.app).

## The design point

There is no `restore.sh`. Restore is init with a backup present. The startup mechanism looks at what state exists and what version the engine is, and does the right thing:

| Observed state                    | Action               |
| --------------------------------- | -------------------- |
| No local state, no backup         | fresh install        |
| No local state, backup present    | restore from blob    |
| Local state, engine version equal | serve (reboot)       |
| Local state, engine version newer | upgrade              |
| Local state, engine version older | abort (no downgrade) |

The same restore path serves disaster recovery, migration to another host, and evacuation to another provider. The reason you move and the time you have do not change the operation. That is Wechselfähigkeit.

## Prerequisites

- A Linux host with Docker and Docker Compose.
- Nothing provider-specific. No managed database, no object-store API, no cloud snapshot. The stack runs identically on any Docker host, anywhere.

## Quickstart

```
git clone https://github.com/bartl-app/bartl-wordpress.git
cd bartl-wordpress
docker compose up -d
```

The `bartl-init` sidecar sees a vanilla install (no backup available) and sets up WordPress from scratch. Wait for the logs to show `BARTL: Stack is ready`, then open http://localhost:8080 and complete the WordPress setup wizard.

Make some changes - create a post, upload an image, install a plugin.

## Export (backup)

Backups run automatically inside the sidecar every six hours. To take one on demand:

```
docker compose exec bartl-init /backup.sh
```

This produces a timestamped blob in `backups/`:

```
backups/<host>_<version>_<timestamp>.tar.gz         the portable blob
backups/<host>_<version>_<timestamp>.tar.gz.sha256  its checksum
```

The blob is a single `.tar.gz` containing:

- `database.sql` - a full `mysqldump` of the WordPress database
- `uploads.tar` - the `wp-content/uploads` tree (media, objects)
- `metadata.txt` - version, timestamp, host, database name
- `SHA256SUMS` - a checksum for each of the above

The blob is self-describing and self-verifying. Nothing in it is tied to the host it came from or the provider it ran on.

## Import / Restore / Migrate / Evacuate

All the same operation: place a blob where the stack can find it and bring the stack up. On a fresh host with no local state, init detects the blob and restores from it.

Round-trip on the same host:

```
docker compose down -v      # wipe to empty
docker compose up -d         # init detects the blob in backups/ and restores
```

Move to another host or provider:

```
scp backups/<blob>.tar.gz backups/<blob>.tar.gz.sha256 newhost:.../backups/
# on the new host, from this repo:
docker compose up -d         # same restore path, different machine
```

Your post, your image, your plugin - all back. There is no separate restore command, and no provider-specific step in the path.

## Integrity guarantee

Before restoring, init verifies the blob's sidecar checksum, then verifies each member against `SHA256SUMS`. A blob that fails either check is refused - init aborts rather than load corrupt state. Restore only ever proceeds from a blob whose bytes are exactly what backup wrote.

## What is in this repo

```
compose.yaml              WordPress + MySQL + bartl-init sidecar
init.sh                   restore-or-init: install / restore / upgrade / serve
backup.sh                 snapshot state into a portable, checksummed blob
override-entrypoint.sh    multi-container startup choreography (compose only)
```

Two scripts, not three. The absence of `restore.sh` is the design point.

## Scope

Bartl moves state. It does not handle infrastructure cutover (DNS, firewall, certificates), scaling, provisioning, or runtime monitoring. Those are orchestration concerns around the stack, not part of the restore-or-init mechanism. On Kubernetes the `override-entrypoint.sh` choreography is unnecessary - initContainers and readiness probes cover the same ordering natively.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
