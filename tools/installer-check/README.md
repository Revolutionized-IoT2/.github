# Installer check

Applies to: [deploy/install.sh](../../deploy/install.sh), [deploy/install.ps1](../../deploy/install.ps1)
and their shared logic [deploy/installer/riot2site.py](../../deploy/installer/riot2site.py)
([ADR 0020](../../docs/adr/0020-site-configuration-and-installer.md)).

| Check | Command (in `deploy/`) | Needs |
|---|---|---|
| Unit tests of `riot2site.py` | `python installer/test_riot2site.py` | Python 3.9+ |
| End to end | `bash ../tools/installer-check/check.sh` | Linux, Docker, `age-keygen`, `unzip`, `pwsh` |

`check.sh` builds a throwaway site with its own age keys and checks, against the real stack:

- a key the site isn't encrypted for is refused, and a dry run changes nothing;
- a fresh install writes `.env`, the secret files with their owners, the workflow and the Grafana
  dashboard, and a second run is "up to date";
- `--export` writes the configuration and a renewed token into the site, encrypted;
- a changed site is only reported, then refused without an answer, then applied with
  `--reconfigure --secrets installer`, keeping the renewed token and taking a backup;
- a configuration restore keeps the running Matter pairing and the attestation files;
- an upgrade (an older UI image) asks, keeps or replaces the settings on request, and backs up;
- a downgrade is refused without `--allow-downgrade`;
- `install.ps1` installs the same site, and its second run is "up to date".

It removes the compose project `riot2` with its volumes, `.env` and `backups/`: never run it next to
an installation you want to keep. [deploy-check.yml](../../.github/workflows/deploy-check.yml) runs
both checks on every change in `deploy/`.
