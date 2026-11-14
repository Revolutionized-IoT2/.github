# Site configuration and the installer

Applies to: installing, reinstalling and upgrading a RIoT2 host from a private site repository with
`deploy/install.sh` or `deploy/install.ps1` ([ADR 0020](../adr/0020-site-configuration-and-installer.md)).
For one host with nothing to keep, [getting-started.md](getting-started.md) is enough.

A site repository holds everything one installation needs: each host's `.env`, the secret files the
services read from their volumes, the orchestrator's configuration, workflows and Grafana dashboards.
Secrets are committed only encrypted with [sops](https://github.com/getsops/sops) and
[age](https://github.com/FiloSottile/age). The installer applies a host's folder with one command; the
host needs only Docker, because sops and the installer's logic run in containers.

## What goes where

| Setting | In the site | The installer |
|---|---|---|
| Variables, compose files and profiles | `hosts/<host>/deploy.sops.env` | Writes `deploy/.env` |
| The installer's settings (not secret) | `hosts/<host>/site.conf` | Reads it |
| Own compose changes | `hosts/<host>/docker-compose.override.yml`, listed in `COMPOSE_FILE` | Copies it to `deploy/` |
| Files a service reads from its volume | `hosts/<host>/volumes/<volume>/<path>` | Copies them into the volume |
| Nodes, devices, dashboards, variables | `hosts/<host>/configuration/riot2-backup.sops.zip` | Restores it ([backup-and-restore.md](backup-and-restore.md)) |
| Workflows | `hosts/<host>/workflows/*.json` | Imports them |
| Own Grafana dashboards | `hosts/<host>/grafana-dashboards/*.json` | Grafana's "Site" folder |
| Device plugins | `PLUGIN_URL` and `PLUGIN_SHA256` in `site.conf` | Downloads, checks and installs them |
| An ESP32 node's setup portal values | `firmware/<device>.sops.env` | Nothing: kept for a factory reset |

Examples of volume files:

| File | Volume path in the site |
|---|---|
| Firebase service account of the Messaging device | `volumes/node-data/service_account.sops.json` |
| Netatmo token of a client id | `volumes/node-data/netatmoAuth-<clientId>.sops.json` |
| Matter attestation (`dac.der`, `pai.der`, `cd.der`, `dac-key.pem`) | `volumes/orchestrator-matter/attestation/` |

`name.sops.ext` is installed as `name.ext`. A host folder must not hold both a plaintext and an
encrypted copy of one file. Workflows can stay plaintext; encrypt one (`*.sops.json`) if it holds a secret.

## Keys

- Make one age key per host and one for yourself: `age-keygen -o qnap.agekey`. The second line of the file is
  the public key.
- Keep every key in your password manager. A lost key makes the files encrypted only for it unreadable.
- `.sops.yaml` encrypts each `hosts/<host>/` for that host's key and yours, and `firmware/` for yours only.
  A host can then decrypt only its own folder.
- On a host, keep its key outside the site repository, readable only by the user that runs the installer, and
  pass it with `--age-key` (`-AgeKey`). The default is `$SOPS_AGE_KEY_FILE`, then `~/.config/sops/age/keys.txt`.
- To add a host, add a rule to `.sops.yaml`. To change who can decrypt files, edit the rule, then run
  `sops updatekeys <file>` on each file it covers. Replace a leaked key that way, and also change the
  secrets the key could read.

## Start a site

1. Copy [deploy/site-template](../../deploy/site-template/README.md) into a new **private** repository,
   and put the public keys into `.sops.yaml`.
2. Fill in `hosts/<host>/deploy.env.template` (every variable is in [env-vars.md](../contracts/env-vars.md))
   and `site.conf`, then encrypt the settings and clear the secrets from the template:

   ```powershell
   sops encrypt --filename-override hosts/qnap/deploy.sops.env --output hosts/qnap/deploy.sops.env hosts/qnap/deploy.env.template
   ```

   `--output` keeps the file intact in every shell (Windows PowerShell's `>` would write UTF-16).
3. Encrypt each secret file to its place, for example
   `sops encrypt --filename-override hosts/qnap/volumes/node-data/service_account.sops.json --output hosts/qnap/volumes/node-data/service_account.sops.json service_account.json`,
   then delete the plaintext file.
4. Commit. `.gitignore` refuses plaintext secrets in the usual places.

Edit an encrypted file later with `sops edit <file>`.

## Install

On the host, with the RIoT2 files (this repository's `deploy/`) and the site checked out:

```bash
deploy/install.sh --site <site> --host qnap --age-key <key> --dry-run   # what it would do
deploy/install.sh --site <site> --host qnap --age-key <key>
```

```powershell
deploy/install.ps1 -Site <site> -HostName qnap -AgeKey <key> -DryRun
```

A fresh install:

1. Decrypts the host's folder into `deploy/.install/`, which only the user can read and which is deleted
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

`--export` (`-Export`) writes the running installation back into the site's working copy, encrypted where
the site has the file encrypted, and always under `configuration/` and `volumes/`:

- the configuration backup, when its content changed;
- every workflow, under its existing file name, or `<definitionId>.json` for a new one;
- `once` files from the volumes: renewed tokens, and new files a rule names (a second Netatmo account).
  `--export-managed` also exports `managed` files.

Before an upgrade or `--reconfigure` the installer exports by itself, but only site files that didn't
change since the last install, so your own edits win. `--no-export` skips it. It never commits: check
`git diff` and commit yourself.

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
- `RIOT2_INSTALLER_PYTHON_IMAGE` and `RIOT2_INSTALLER_SOPS_IMAGE` replace the pinned helper images, for
  example with images from a mirror.
- [tools/installer-check](../../tools/installer-check/README.md) tests the installer on every change in
  `deploy/`.
