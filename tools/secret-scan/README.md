# Secret scan and history scrub

Applies to: the git history of every RIoT2 repository. Used by increment
[I01](../../docs/increments/phase-0-1.md#i01-secrets-and-publish-hygiene-s) and maintainer action
[MA1](../../docs/backlog/README.md#ma1-rotate-the-leaked-credentials-and-scrub-them-from-git-history).

| Script | What it does |
|---|---|
| `scan.ps1` | Scans every commit of every repository with [gitleaks](https://github.com/gitleaks/gitleaks). Values are always redacted. Exit code 1 means at least one finding. |
| `scrub-history.ps1` | Rewrites the history of one repository with [git filter-repo](https://github.com/newren/git-filter-repo) to remove a leaked credential, re-scans the result, and pushes only when you pass `-Push`. |

## Scan

From the workspace root (the folder that holds `.github` and the `RIoT2.*` repositories), in
Windows PowerShell 5.1 or PowerShell 7:

```powershell
powershell -File .github\tools\secret-scan\scan.ps1                              # every repository
powershell -File .github\tools\secret-scan\scan.ps1 -Repository RIoT2.Matter      # one repository
```

- When gitleaks isn't on `PATH`, the script downloads the pinned version to the temp folder and
  checks its SHA-256 before running it.
- The redacted JSON reports go to `%TEMP%\riot2-secret-scan`.
- A repository can allowlist reviewed findings in its own `.gitleaks.toml`, for example the public
  CHIP test keys in RIoT2.Matter. Never allowlist a real credential: rotate it and scrub it.

## Scrub a leaked credential from history

1. Revoke and replace the credential first. A rewrite only hides the old value; existing clones,
   forks and GitHub's caches keep it.
2. Commit and push your local work in the repository. The script refuses to run while the branch
   has unpushed commits, because those would be left on the old history.
3. Install git filter-repo once: `pip install --user git-filter-repo`.
4. Rewrite and verify, without pushing:

   ```powershell
   powershell -File .github\tools\secret-scan\scrub-history.ps1 -Repository RIoT2.Net.Orchestrator
   ```

   The script makes a fresh mirror clone in `%TEMP%\riot2-scrub`, rewrites every branch and tag
   there, and runs `scan.ps1` on the result. Your working copy is not touched.
5. If the default branch is protected, allow force pushes for a moment. Then run the script again
   with `-Push`, or run the push commands it printed.
6. Re-sync every working copy with the commands the script prints (`fetch --tags --force`, then
   `reset --hard origin/<branch>`).

The rules are built into the script, one per repository:

| Repository | Rule | Removes |
|---|---|---|
| RIoT2.Net.Orchestrator | Drop the path `bin/` from every commit | The tracked `bin/Debug/net9.0/StoredObjects`, with the Netatmo client secret and tokens |
| RIoT2.Matter | Blank `"CredentialProtectionSecret": "<GUID>"` in every blob | The controller's credential-protection secret from `Controller/appsettings.json` |

Add a rule when a new leak is found, and test it without `-Push` first.
