# bartl-wordpress

Try Bartl with WordPress in 5 minutes. This is the first showcase registry demonstrating the Bartl pattern: install, restore, upgrade, and disaster recovery are the same operation.

For the full thesis, see [bartl.app](https://github.com/bartl-app/bartl.app).

## Prerequisites

- Docker and Docker Compose
- That's it

## Quickstart

Clone and start:

```
git clone https://github.com/bartl-app/bartl-wordpress.git
cd bartl-wordpress
docker compose up -d
```

The bartl-init sidecar detects a vanilla install (no backup available) and sets up WordPress from scratch. Wait for the logs to show "BARTL: Stack is ready", then open http://localhost:8080 and complete the WordPress setup wizard.

Make some changes - create a post, upload an image, install a plugin.

Back up your state:

```
./backup.sh
```

This produces a timestamped blob in `backups/` containing the database dump, uploaded files, and metadata.

Now tear it down completely:

```
docker compose down -v
```

Bring it back up:

```
docker compose up -d
```

The bartl-init sidecar detects the backup blob and restores from it. Your post, your image, your plugin - all back. That is the thesis at the code level: there is no separate restore command. Init from a backup IS restore.

## What is in this repo

```
compose.yaml              WordPress + MySQL + bartl-init sidecar
init.sh                   Vanilla install / restore from backup / upgrade
backup.sh                 Snapshot state into a portable blob
override-entrypoint.sh    Multi-container startup choreography
```

Two scripts, not three. The absence of `restore.sh` is the design point.

## License

Apache 2.0. See [LICENSE](LICENSE).
