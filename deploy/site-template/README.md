# RIoT2 site

Applies to: this private repository, which holds one RIoT2 installation's settings and secrets for
the installer (`deploy/install.sh` or `deploy/install.ps1`). The guide:
[site-configuration.md](https://github.com/Revolutionized-IoT2/.github/blob/main/docs/guides/site-configuration.md).

Keep this repository private. Secrets are committed only encrypted with
[sops](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age) (`*.sops.*`
files); `.gitignore` keeps the plaintext copies out.

## Layout

| Path | Holds | The installer |
|---|---|---|
| `.sops.yaml` | Which age keys each folder is encrypted for | – |
| `hosts/<host>/deploy.sops.env` | The host's `deploy/.env`, including `COMPOSE_FILE` and `COMPOSE_PROFILES` | Writes `deploy/.env` |
| `hosts/<host>/site.conf` | Plugins, seed rules, the LAN network (not secret) | Reads it |
| `hosts/<host>/docker-compose.override.yml` | Optional own compose changes; list it in `COMPOSE_FILE` | Copies it to `deploy/` |
| `hosts/<host>/volumes/<volume>/<path>` | Files a service reads from its volume, e.g. `node-data/service_account.sops.json` (Firebase), `node-data/netatmoAuth-<clientId>.sops.json`, `orchestrator-matter/attestation/dac.sops.der` | Copies them into the volume (`SEED_RULES`) |
| `hosts/<host>/configuration/riot2-backup.sops.zip` | The orchestrator's configuration backup: nodes, devices, dashboards, variables | Restores it |
| `hosts/<host>/workflows/*.json` | Workflows as the Workflows page exports them (`*.sops.json` if one holds a secret) | Imports them |
| `hosts/<host>/grafana-dashboards/*.json` | Own Grafana dashboards | Shows them in Grafana's "Site" folder |
| `firmware/<device>.sops.env` | What was entered in an ESP32 node's setup portal | Nothing: kept for a factory reset |

A file named `name.sops.ext` is installed as `name.ext`. Never keep both a plaintext and an
encrypted copy of one file in a host folder: the installer stops.

## Start a site

1. Copy this folder into a new private repository.
2. Make an age key for yourself, and keep it in your password manager: `age-keygen -o personal.agekey`
   (the public key is on its second line). Hosts you install from your PC (`install.ps1 -RemoteHost`)
   need no key: delete their keys' lines from `.sops.yaml`. A host that runs the installer itself gets
   its own key, made the same way. Put the public keys into `.sops.yaml`.
3. Fill in `hosts/<host>/deploy.env.template` and `site.conf`, then encrypt the settings:
   `sops encrypt --filename-override hosts/qnap/deploy.sops.env --output hosts/qnap/deploy.sops.env hosts/qnap/deploy.env.template`.
   Clear the secrets from the template again.
4. Add secret files the same way, for example
   `sops encrypt --filename-override hosts/qnap/volumes/node-data/service_account.sops.json --output hosts/qnap/volumes/node-data/service_account.sops.json service_account.json`,
   then delete the plaintext file.
5. Commit, then install: from your PC with
   `deploy/install.ps1 -Site <this folder> -HostName qnap -RemoteHost admin@<NAS> -RemoteDeploy <deploy folder on the NAS>`,
   or on the host with `deploy/install.sh --site <this folder> --host qnap --age-key <host key>`.

Edit an encrypted file with `sops edit <file>` (it needs a key the file is encrypted for).

## Keep it current

After changes in the UI, or when a token the service renews has changed, run
`deploy/install.sh --site <this folder> --host <host> --export`, check `git diff`, and commit. Before
an upgrade the installer exports by itself.
