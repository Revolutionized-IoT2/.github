# Installer check

Applies to: [deploy/install.sh](../../deploy/install.sh), [deploy/install.ps1](../../deploy/install.ps1)
and their shared logic [deploy/installer/riot2site.py](../../deploy/installer/riot2site.py)
([ADR 0020](../../docs/adr/0020-site-configuration-and-installer.md)).

| Check | Command (in `deploy/`) | Needs |
|---|---|---|
| Unit tests of `riot2site.py` | `python installer/test_riot2site.py` | Python 3.9+ |
| Bash 3.2 (QNAP's QTS): syntax, and no "unbound variable" before the first docker call | the "Bash 3.2" step of deploy-check.yml | Docker |
| End to end | `bash ../tools/installer-check/check.sh` | Linux, Docker, `unzip`, `pwsh` |

`check.sh` builds a throwaway site folder and checks, against the real stack:

- a file left encrypted (`*.sops.*`) is refused, and a dry run changes nothing;
- a fresh install writes `.env`, the secret files with their owners, the workflow and the Grafana
  dashboard, and a second run is "up to date";
- `--export` writes the configuration and a renewed token into the site folder;
- a changed site is only reported, then refused without an answer, then applied with
  `--reconfigure --secrets installer`, keeping the renewed token and taking a backup;
- a configuration restore keeps the running Matter pairing and the attestation files;
- an upgrade (an older UI image) asks, keeps or replaces the settings on request, and backs up;
- a downgrade is refused without `--allow-downgrade`;
- `install.ps1` installs the same site, and its second run (with the site from `RIOT2_SITE`) is "up to date";
- `install.ps1 -RemoteHost` installs through an `ssh` stand-in, is "up to date" on a second run, exports
  into the site folder on the "PC", and leaves nothing of the site on the host.

It removes the compose project `riot2` with its volumes, `.env` and `backups/`: never run it next to
an installation you want to keep. [deploy-check.yml](../../.github/workflows/deploy-check.yml) runs
both checks on every change in `deploy/`.
