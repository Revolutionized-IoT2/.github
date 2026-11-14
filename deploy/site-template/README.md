# RIoT2 site

Applies to: this folder, which holds one RIoT2 installation's settings and secrets for the installer
(`deploy/install.ps1` or `deploy/install.sh`). The guide:
[site-configuration.md](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/site-configuration.md).

The files are plain files with passwords and tokens in them. Keep the folder private: on an encrypted
disk, backed up, and never in a public repository. Encrypting it is up to you; the installer takes
plain files only.

## Layout

| Path | Holds | The installer |
|---|---|---|
| `hosts/<host>/deploy.env` | The host's `deploy/.env`, including `COMPOSE_FILE` and `COMPOSE_PROFILES` | Writes `deploy/.env` |
| `hosts/<host>/site.conf` | Plugins, seed rules, the LAN network | Reads it |
| `hosts/<host>/docker-compose.override.yml` | Optional own compose changes; list it in `COMPOSE_FILE` | Copies it to `deploy/` |
| `hosts/<host>/volumes/<volume>/<path>` | Files a service reads from its volume, e.g. `node-data/service_account.json` (Firebase), `node-data/netatmoAuth-<clientId>.json`, `orchestrator-matter/attestation/dac.der` | Copies them into the volume (`SEED_RULES`) |
| `hosts/<host>/configuration/riot2-backup.zip` | The orchestrator's configuration backup: nodes, devices, dashboards, variables | Restores it |
| `hosts/<host>/workflows/*.json` | Workflows as the Workflows page exports them | Imports them |
| `hosts/<host>/grafana-dashboards/*.json` | Own Grafana dashboards | Shows them in Grafana's "Site" folder |
| `firmware/<device>.env` | What was entered in an ESP32 node's setup portal | Nothing: kept for a factory reset |

## Start a site

1. Copy this folder to your PC, by default as `~\riot2-site` (or set `RIOT2_SITE` to where it is).
2. Fill in `hosts/<host>/deploy.env` and `site.conf`, and put the secret files under `volumes/`.
3. Install from the PC:
   `deploy/install.ps1 -HostName qnap -RemoteHost admin@<NAS> -RemoteDeploy <deploy folder on the NAS> -DryRun`,
   then without `-DryRun`.

## Keep it current

The installer writes what it exports (the configuration after changes in the UI, renewed tokens, new
workflows) back into `hosts/<host>/`: with `-Export`, and by itself before an upgrade.
