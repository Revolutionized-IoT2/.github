# 0020. A site repository and an installer for one-command installs

- Status: Accepted
- Date: 2026-11-14
- Applies to: `.github` (`deploy/`), UI (listen port)

## Context

The compose install ([ADR 0012](0012-operations-first-class.md), [getting-started.md](../guides/getting-started.md))
covers environment variables (`deploy/.env`) and backups, but not the rest of an installation's settings:

- Secret files that services read from their volumes: the Firebase `Data/service_account.json` of the
  Messaging device, Netatmo's `netatmoAuth-<clientId>.json` tokens in the node's `/app/Data`, and Matter
  attestation material in the orchestrator's `/app/MatterCredentials`. They were copied in by hand.
- The orchestrator's configuration (nodes, devices, dashboards, variables), workflows and own Grafana
  dashboards, which only existed inside a running installation or a backup.
- Hosts where the services need their own LAN addresses, such as a QNAP NAS whose web interface uses
  ports 80 and 8080.

Reinstalling or upgrading a host therefore took manual steps, and nothing kept an installation's
settings under version control.

## Decision

- An installation's settings live in a **private site repository**, one folder per host:
  - `hosts/<host>/deploy.sops.env`: the host's `deploy/.env`, including `COMPOSE_FILE` and `COMPOSE_PROFILES`.
  - `hosts/<host>/site.conf`: the installer's own settings; not secret.
  - `hosts/<host>/volumes/<volume>/`: the files to put into a volume.
  - `hosts/<host>/configuration/riot2-backup.sops.zip`: an orchestrator configuration backup.
  - `hosts/<host>/workflows/` and `hosts/<host>/grafana-dashboards/`.
  - `firmware/`: setup records of ESP32 nodes.

  [deploy/site-template/](../../deploy/site-template/README.md) is the starting point.
- **Secrets must be committed only encrypted with sops and age** (`*.sops.*`). A host that decrypts its own
  folder must have its own key, and its folder must be encrypted for that key and the owner's personal key,
  so that one host can't read another's secrets.
- **`deploy/install.sh`** applies a site to the host it runs on; `install.ps1` is its PowerShell version.
  Both must behave the same, and they share their logic in `deploy/installer/riot2site.py`. The host
  must need only Docker and bash: sops and that logic run in pinned containers.
- **`install.ps1 -RemoteHost`** installs on another host from a PC, so that host needs no age key:
  - It decrypts on the PC and runs `install.sh --plain` over SSH, then encrypts the exports on the PC.
  - The decrypted files must exist on the host only while the installer runs, and must be deleted
    afterwards, also on failure.
  - Shell scripts must run on the bash of a QNAP NAS (3.2).
- **The installer must check the installation first:**
  - It compares the running images with the compose files' images and the install marker
    `deploy/.riot2-install.json`.
  - The same versions and an unchanged site change nothing. A changed site is only reported, unless the
    user gives `--reconfigure`.
  - An upgrade or a downgrade must back up with `backup.sh` before changing anything. A downgrade also needs
    confirmation.
  - Before changing anything it must ask per category (settings, secret files, configuration, workflows)
    whether to keep the existing configuration or use the installer's. Without a terminal, the user must
    give an answer as an option.
- **Before an upgrade the installer must export** the running configuration, workflows and renewed tokens
  into the site's working copy. Site files changed since the last install are kept. It must never commit.
- **Secret files are copied into the volumes** before their services start, with the services' owners.
  Each file has a rule:
  - `once` files are copied only where missing, for tokens a service renews itself; a file without a rule
    is `once`.
  - `managed` files are always the site's.
- **A configuration restore must keep the running Matter pairing.** The installer replaces the Matter part of
  the site's backup with the running one, unless `--replace-matter`.
- **Optional static LAN addresses:** `compose.lan.yml` (with `compose.lan.influx.yml` and
  `compose.lan.observability.yml`) gives services their own addresses on an external qnet or macvlan
  network. The UI image's listen port is configurable (`RIOT2_UI_PORT`, UI 1.15.0) for port 80 there.

## Consequences

- A host is installed, reinstalled or upgraded with one command, and its settings are reviewed in git.
- Rotated tokens and UI changes flow back into the site through the export. The owner commits them.
- The age keys become critical: a lost key makes the site's secrets unreadable. Keys must be kept in a password
  manager as well as on the hosts.
- The installer must stay in step with `backup.sh`, the compose files and the backup format;
  [deploy-check.yml](../../.github/workflows/deploy-check.yml) runs [tools/installer-check](../../tools/installer-check/README.md).
- On a qnet or macvlan network the Docker host usually can't reach the services' addresses, so the
  installer calls the orchestrator through the project's default network.

## Alternatives considered

- **A plain private repository without encryption:** anyone with repository access would read every token.
- **Docker secrets or a configurable path for each secret file:** this needs service code changes for every
  file, and doesn't cover tokens that services write.
- **A full-system backup as the installation's source:** a backup is opaque, can't be reviewed, and has no
  per-host or per-key separation.
- **Publishing ports on the NAS:** they clash with QTS, and a node on another host couldn't use the default ports.
