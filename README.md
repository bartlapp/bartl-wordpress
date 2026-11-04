# bartl-wordpress

> The home of this project is [codeberg.org/bartlapp/bartl-wordpress](https://codeberg.org/bartlapp/bartl-wordpress). The GitHub repository is a read-only mirror - please open issues and pull requests on Codeberg.

A historical WordPress, MySQL and Docker Compose example of restoring application state through the installation path. It illustrates one mechanism, not full conformance to the current Bartl application contract.

Start with the [Bartl philosophy](https://codeberg.org/bartlapp/bartl-app/src/branch/main/docs/philosophy.md), the [current application contract](https://codeberg.org/bartlapp/bartl-app/src/branch/main/docs/application-contract.md) and [How to bartlize](https://codeberg.org/bartlapp/bartl-app/src/branch/main/docs/how-to-bartlize.md) for new implementations. The procedure below describes this example, not additional Bartl requirements.

## The design point

There is no separate `restore.sh`. This example selects its path from a local version marker and backup availability:

| Observed input | Example behavior |
| --- | --- |
| No version marker, no backup | release WordPress for initial setup |
| No version marker, backup present | restore from archive |
| Version marker equals configured engine version | release existing installation |
| Engine version newer than marker | release WordPress; database upgrade is deferred to admin access |
| Engine version older than marker | abort |

Moving to another host or provider reuses the application-and-state reconstruction procedure. Provisioning, transfer, endpoint reachability and cutover remain surrounding work. This example does not establish complete provider switching.

## Prerequisites

- A Linux host with Docker and Docker Compose.
- Nothing provider-specific inside the Bartl restore path. No managed database, no object-store API, no cloud snapshot. The stack runs identically on any compatible Linux host with Docker and Docker Compose; provisioning and access remain outside that path.

## Quickstart

```
git clone https://codeberg.org/bartlapp/bartl-wordpress.git
cd bartl-wordpress
docker compose up -d
```

The `bartl-init` sidecar sees a vanilla install (no backup available) and sets up WordPress from scratch. Wait for the logs to show `BARTL: Stack is ready`, then open http://localhost:8080 and complete the WordPress setup wizard.

Make some changes - create a post and upload an image.

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
- `uploads.tar` - the `wp-content/uploads` tree, when nonempty
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

Your post and your image - both back. There is no separate restore command and no provider-specific step inside the Bartl restore path.

## Integrity checks and qualification limits

[init.sh](init.sh) checks the archive sidecar and member checksums when present and rejects checksum mismatches. Missing sidecars or `SHA256SUMS` do not stop it. It also tolerates a missing database dump or uploads archive. These checks therefore do not establish complete, verified reconstruction under the current contract.

[backup.sh](backup.sh) writes the archive directly to its final path, then writes the sidecar. Restore selects an archive without requiring that sidecar, so it is not an enforced publication marker. Database capture and uploads capture run sequentially without a shared writer pause; consistency during concurrent changes is not established.

The version marker is not an observation of complete application state. Upgrade completion is not checked before access opens, and plugins/themes in the writable `wp-content` volume are outside the uploads-only backup. Use this example to inspect its mechanism, not as a qualified operating package or a template for the current failure policy.

## What is in this repo

```
compose.yaml              WordPress + MySQL + bartl-init sidecar
init.sh                   restore-or-init: install / restore / upgrade / serve
backup.sh                 snapshot state into a portable, checksummed blob
override-entrypoint.sh    multi-container startup choreography (compose only)
```

Two scripts, not three. The absence of `restore.sh` is the design point.

## Scope

Bartl covers application, infrastructure and responsibility for the complete service. This example covers only a bounded application-state mechanism. It does not supply independently retained backups, infrastructure provisioning, user and dependency access, controlled cutover or a complete recovery-time guarantee.

The Compose marker choreography is specific to this example. Kubernetes initContainers and readiness probes are not a general replacement for application lifecycle coordination: readiness does not stop background writers, and an init container cannot wait for a main process in its own Pod. Select coordination from the application's native procedures under the current contract.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
