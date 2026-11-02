# Backup and restore

Applies to: a compose install ([deploy/](../../deploy/)), Orchestrator 1.7.0 and UI 1.3.0 or
later. Design: [7.4](../design/operations-as-built.md#as-built-phase-3-i21).

RIoT2 has two kinds of backup:

| | Configuration backup | Full-system backup |
|---|---|---|
| Made by | The orchestrator: UI, API or schedule | `deploy/backup.sh` or `deploy/backup.ps1` on the Docker host |
| Holds | Node configurations, dashboards, variables, Matter configuration, pairing and credentials | Every data volume (the configuration above, the outbox, Elsa's workflows, node tokens, broker data, Grafana, Prometheus), InfluxDB data, `.env`, `plugins/` |
| Downtime | None | The orchestrator, Elsa, the node, Grafana and Prometheus stop for a few seconds |
| Restore | UI or API, on a running stack | `deploy/restore.sh` or `deploy/restore.ps1`, also on a clean host |

> Both kinds hold secrets: device parameters such as passwords and tokens, the Matter keys and,
> in a full-system backup, `.env`. Store them like passwords. Encryption comes with the optional
> security mode ([I53](../increments/optional-security.md#i53-signing-and-secrets-at-rest-m)).

## Configuration backup

### Make one

- **UI:** *Backup*, then *Download backup*.
- **API:** `curl -X POST http://<host>:8080/api/v2/backup -o riot2-backup.zip`
- **Schedule:** the orchestrator writes `riot2-backup-<UTC time>.zip` to `/app/Backups` (the
  `orchestrator-backups` volume) at every `RIOT2_BACKUP_SCHEDULE` time. Compose sets 03:00 every
  day (`0 0 3 * * ?`, a Quartz cron expression with seconds, in `TZ`); an empty value in `.env`
  turns it off. The newest `RIOT2_BACKUP_RETENTION` files (default 7) are kept. The *Backup* page
  lists them with the schedule, the next run and the last result, and downloads or restores
  each one.

### Restore one

- **UI:** *Backup*, then *Restore from file*, or the restore button of a saved backup.
- **API:** `curl -X POST http://<host>:8080/api/v2/restore -H "Content-Type: application/zip" --data-binary @riot2-backup.zip`

A restore:

1. Checks the whole archive first. A damaged, changed or foreign zip, a file that doesn't load, or
   a Matter credentials folder outside its own folder is rejected with every reason (`400`), and
   nothing changes.
2. Saves the current configuration as `riot2-pre-restore-<UTC time>.zip` in `/app/Backups`. To
   undo the restore, restore that file.
3. Stops the Matter bridge, replaces the stored objects and the Matter credentials while saves
   wait, reloads every cache, and starts the bridge again.
4. Sends every node a configuration command. Nodes fetch the restored configuration; the *Configure*
   view shows each one in sync when it has applied it. Nodes that aren't in the backup lose their
   retained status.

The configuration may come from another install, for example on a new host. Nodes connect to the
broker of the new install, and the configuration's plugin package URLs must be reachable from it.

### The zip

| Entry | Content |
|---|---|
| `backup-manifest.json` | `format` (`riot2-configuration-backup`), `formatVersion` (1), `createdAt`, `kind` (`manual`, `scheduled` or `pre-restore`), `orchestratorId`, `versions` (`orchestrator`, `core`), and `files`: each entry's `path`, `size` and `sha256` |
| `StoredObjects/<Type>/<Id>.json` | The stored objects, byte for byte: `NodeDeviceConfiguration`, `DashboardConfiguration`, `Variable`, `MatterConfiguration`, `MatterBridgeState` and any other type found (a restored `Rule/` is moved to `StoredObjects/.archive/`, Orchestrator 1.11.0) |
| `MatterCredentials/…` | The Matter bridge's folder (`fabrics.json` and any attestation files placed there) |

The outbox (`StoredObjects/outbox.db`) is runtime state and is never included. A restore accepts
at most 64 MB, 256 MB unpacked and 10,000 files, and a format version up to its own.

## Full-system backup

Run the scripts from any folder; they work on the compose files next to them. Pass the same
compose files and profiles as `docker compose up` (file paths relative to `deploy/`; the backup
folder relative to the current folder):

```bash
cd deploy
./backup.sh -f docker-compose.yml -f compose.influx.yml --profile node     # -o FOLDER, default backups/
./restore.sh -f docker-compose.yml -f compose.influx.yml --profile node backups/riot2-system-20261101T030000Z
```

```powershell
./backup.ps1 -ComposeFile docker-compose.yml, compose.influx.yml -ComposeProfile node   # -Output FOLDER
./restore.ps1 -Path backups/riot2-system-20261101T030000Z -ComposeFile docker-compose.yml, compose.influx.yml -ComposeProfile node
```

`backup.sh` writes `riot2-system-<UTC time>/`:

- `volumes/<volume>.tar.gz`: every volume of the compose project that exists, except the log
  volumes and the `influxdb-*` ones (InfluxDB's, and the connector's spool, which only holds
  messages waiting for InfluxDB). The orchestrator, Elsa, the node, Grafana and Prometheus are stopped while the
  volumes are archived, so the SQLite files (`outbox.db`, `elsa.sqlite.db`, `grafana.db`) are
  consistent, and started again afterwards.
- `influxdb/`: `influx backup` of the running InfluxDB, when it runs.
- `.env` and `plugins.tar.gz`, when they exist.
- `backup.txt`: the time, project, compose options, volumes and images.

`restore.sh` first reads every archive through and stops, changing nothing, if one is damaged.
Then it takes the stack down and replaces the content of every volume in the backup (creating it
on a clean host; each archive is unpacked next to the old content, which is deleted only when that
worked), restores `plugins/`, starts the stack and waits until it is healthy. With
`compose.influx.yml`, it then runs `influx restore --full` and restarts the connector and Grafana.
It copies the backup's `.env` only when `deploy/` has none, so on a clean host clone this
repository, then run `restore.sh`.

Restore with the same image versions as the backup (`backup.txt` lists them), then upgrade as
[upgrading.md](upgrading.md) describes.

A nightly host backup with cron, for example:

```bash
30 3 * * * /opt/riot2/deploy/backup.sh -f docker-compose.yml --profile node -o /mnt/backup/riot2 >> /var/log/riot2-backup.log 2>&1
```

The scripts don't delete old backups. On Linux the archives belong to the user who ran the script.
[deploy-check.yml](../../.github/workflows/deploy-check.yml) runs both scripts and both
PowerShell versions against wiped volumes on every change in `deploy/`.
