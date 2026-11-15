# Site configuration and the installer

Applies to: installing, reinstalling and upgrading a RIoT2 host from a site folder with
`deploy/install.ps1` or `deploy/install.sh` ([ADR 0020](../adr/0020-site-configuration-and-installer.md)).
For one host with nothing to keep, [getting-started.md](getting-started.md) is enough.

A site folder holds everything one installation needs: each host's `.env`, the secret files the
services read from their volumes, the orchestrator's configuration, workflows and Grafana dashboards.
It lives on your PC as plain files. The installer applies a host's folder with one command, from your PC
over SSH ([Install from a PC](#install-from-a-pc)) or on the host itself. On the host it needs only
Docker and bash, because its logic runs in a container.

The folder holds passwords and tokens in plain text. Keeping it private is up to you:
- keep it on an encrypted disk (BitLocker, for example);
- back it up;
- never put it in a public repository;
- if you encrypt it with a tool of your own, decrypt it before installing. The installer refuses
  files named `*.sops.*`, so an encrypted file isn't installed by mistake.

## What goes where

| Setting | In the site | The installer |
|---|---|---|
| Variables, compose files and profiles | `hosts/<host>/deploy.env` | Writes `deploy/.env` |
| The installer's settings | `hosts/<host>/site.conf` | Reads it |
| Own compose changes | `hosts/<host>/docker-compose.override.yml`, listed in `COMPOSE_FILE` | Copies it to `deploy/` |
| Files a service reads from its volume | `hosts/<host>/volumes/<volume>/<path>` | Copies them into the volume |
| Nodes, devices, dashboards, variables | `hosts/<host>/configuration/riot2-backup.zip` | Restores it ([backup-and-restore.md](backup-and-restore.md)) |
| Workflows | `hosts/<host>/workflows/*.json` | Imports them |
| Own Grafana dashboards | `hosts/<host>/grafana-dashboards/*.json` | Grafana's "Site" folder |
| Device plugins | `PLUGIN_URL` and `PLUGIN_SHA256` in `site.conf` | Downloads, checks and installs them |
| An ESP32 node's setup portal values | `firmware/<device>.env` | Nothing: kept for a factory reset |

Examples of volume files:

| File | Volume path in the site |
|---|---|
| Firebase service account of the Messaging device | `volumes/node-data/service_account.json` |
| Netatmo token of a client id | `volumes/node-data/netatmoAuth-<clientId>.json` |
| Matter attestation (`dac.der`, `pai.der`, `cd.der`, `dac-key.pem`) | `volumes/orchestrator-matter/attestation/` |

## Start a site

1. Copy [deploy/site-template](../../deploy/site-template/README.md) to your PC. `install.ps1` looks for
   it in `$env:RIOT2_SITE`, then in `~\riot2-site`; `-Site` gives another folder.
2. Fill in `hosts/<host>/deploy.env` (every variable is in [env-vars.md](../contracts/env-vars.md)) and
   `site.conf`. Put the secret files under `volumes/`.
3. If you don't have a configuration backup or workflows yet, leave those folders empty: after the
   first install, `-Export` fills them from the running installation.

## Install from a PC

`install.ps1 -RemoteHost` installs on a NAS or another Docker host from the site folder on your PC. Your PC
needs ssh and tar (Windows 10 and later have both). The host needs the RIoT2 files (this repository's
`deploy/`), Docker, bash and SSH access.

```powershell
./install.ps1 -HostName qnap -RemoteHost admin@192.168.1.13 -RemoteDeploy /share/Container/riot2/.github/deploy -DryRun
```

With an SSH key, nothing is asked. Otherwise the password is asked once; the installer's later SSH connections
get it from a temporary `SSH_ASKPASS` helper, which answers password prompts only (never a new host key).

1. The PC copies `hosts/<host>/` over SSH to `deploy/.install-site/` on the host.
2. `install.sh --plain` runs there with a terminal, so it asks its questions as usual. The other parameters
   (`-DryRun`, `-KeepExisting`, `-Config Installer`, `-Export`, â€¦) pass through as its options.
3. What it exports goes to `deploy/.install-export/`. The PC fetches it into `hosts/<host>/`, also when
   the installation failed after the export.
4. Both folders are deleted, also on failure.
   - A dropped SSH connection makes `install.sh` delete `.install-site/` itself.
   - If the PC loses the connection while fetching the export, delete `.install-export/` by hand; the
     next run replaces it anyway.

The site's files exist on the host only while the installer runs, and under `deploy/`. Keep that folder
on a share that only administrators can open.

## Install on the host

With the RIoT2 files and the site folder on the host itself:

```bash
deploy/install.sh --site <site> --host qnap --dry-run   # what it would do
deploy/install.sh --site <site> --host qnap
```

`install.ps1 -Site <site> -HostName <host>` does the same on a Windows Docker host.

## What an install does

1. Copies the host's folder into `deploy/.install/`, which only the user can read and which is deleted
   when the installer ends.
2. Checks `site.conf`, the seed rules and that the compose files accept the settings.
3. Creates the LAN network ([static-lan-addresses.md](static-lan-addresses.md)) and writes `deploy/.env`.
4. Installs the Grafana dashboards and the plugins, and writes the secret files into their volumes,
   owned by the services' users (UID 1654 for the orchestrator, root for the node).
5. Pulls the images and runs `docker compose up -d --wait`.
6. Restores the configuration backup and imports the workflows.
7. Writes `deploy/.riot2-install.json`: the installed images and a hash of every site file. It holds no
   secret values.

`backup.sh`, `restore.sh` and plain `docker compose` commands use the same files afterwards, because
`COMPOSE_FILE` and `COMPOSE_PROFILES` are in `.env`.

## When RIoT2 is already installed

The installer compares the images of the running containers with the compose files' images. Without
containers, it uses the install marker.

| Found | What happens |
|---|---|
| The same versions, an unchanged site | "Up to date"; nothing changes. |
| The same versions, a changed site | The changes are listed (setting names, never values); nothing changes. `--reconfigure` applies them. |
| Older versions: an upgrade | Shows each service's versions, exports, backs up with `backup.sh`, asks, then upgrades. Read [upgrading.md](upgrading.md) first. |
| Newer versions: a downgrade | Warns and asks; without a terminal it needs `--allow-downgrade`. Then like an upgrade. |
| Volumes, but no containers | Uses them as they are, after a backup, like an upgrade. Remove them first for a clean install. |

For each category with something to apply it asks: "Do you want to keep existing configurations, or do
you want to use configuration from installer?" Keep is the default.

| Category | Keep | Use the installer's |
|---|---|---|
| Settings | `deploy/.env` stays; keys only the site has are added | The site's replaces it; the old one is `.env.bak` |
| Secret files | Only missing files are written | `managed` files are replaced too |
| Configuration | The running one stays | The site's backup is restored (see [The Matter pairing](#the-matter-pairing)) |
| Workflows | Only missing ones are imported | Every one is imported, as a new version |

- Without a terminal (cron, CI), a question that needs an answer stops the installer with exit code 2.
  Answer in advance with `--keep-existing`, `--use-installer` or per category: `--env`, `--secrets`,
  `--config` and `--workflows` with `keep` or `installer`. In PowerShell: `-KeepExisting`, `-UseInstaller`,
  `-Settings`, `-Secrets`, `-Config` and `-Workflows` with `Keep` or `Installer`.
- Grafana dashboards and plugins always come from the site.
- When a step fails after the backup, the installer prints the `restore.sh` command for it.

## Export

`--export` (`-Export`) writes the running installation back into the site's host folder:

- the configuration backup, when its content changed;
- every workflow, under its existing file name, or `<definitionId>.json` for a new one;
- `once` files from the volumes: renewed tokens, and new files a rule names (a second Netatmo account).
  `--export-managed` also exports `managed` files.

Before an upgrade or `--reconfigure` the installer exports by itself, but only site files that didn't
change since the last install, so your own edits win. `--no-export` skips it. If the site folder is a git
repository, the installer doesn't commit: check `git diff` and commit yourself.

## Secret files and their rules

`SEED_RULES` in `site.conf` gives each file under `volumes/` a rule. The first matching glob wins, and a
file without a rule is `once`.

```text
SEED_RULES="node-data/netatmoAuth-*.json=once node-data/service_account.json=managed orchestrator-matter/attestation/*=managed"
```

- **`once`:** the file is copied only where the volume lacks it. Use it for tokens a service renews itself:
  the site's copy goes stale, and writing it back would break the login. `--overwrite-once` forces it.
- **`managed`:** the site's copy is written whenever it differs, and while the services that use the volume
  are stopped. Use it for files only you change.
- The installer knows the owners of the `orchestrator-*`, `elsa-*`, `influxdb-connector-*` and `node-*`
  volumes. Give others in `VOLUME_OWNERS="<volume>=<uid>:<gid>"`.

For real Matter attestation, set the bridge's `AttestationPath` to `MatterCredentials/attestation` on the UI's
Matter page.

## The Matter pairing

A configuration restore replaces the whole Matter part: the bridge's configuration, its state and the
credentials folder with the commissioned fabrics. Restoring an older backup would therefore unpair the
bridge from Apple Home, Google Home or Alexa. The installer prevents that:

1. It takes a backup of the running orchestrator before it restores.
2. If that backup has a Matter part, it puts that part into the site's backup in place of the site's.
3. It restores the result, and writes the site's `orchestrator-matter` files again afterwards.

`--replace-matter` restores the site's pairing instead; the bridge then has to be commissioned again.

## Notes

- The site's plugin package must match the node image. Leave `PLUGIN_URL` empty when the node gets its
  plugins from the plugin package URL in the UI.
- Language model API keys don't survive a restore on another installation
  ([backup-and-restore.md](backup-and-restore.md)); enter them again on the AI models page.
- The installer's full-system backups contain `deploy/.env` in plaintext, so keep `backups/` private.
- `RIOT2_INSTALLER_PYTHON_IMAGE` replaces the pinned helper image, for example with one from a mirror.
- [tools/installer-check](../../tools/installer-check/README.md) tests the installer on every change in
  `deploy/`.
