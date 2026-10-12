<#
.SYNOPSIS
    Removes leaked credentials from the git history of a RIoT2 repository (backlog MA1).

.DESCRIPTION
    Works on a fresh mirror clone of the GitHub repository in a temporary folder, never on your
    working copy. Rewrites every branch and tag with git filter-repo using the rule for the
    repository, verifies the result with scan.ps1, and prints the push and re-sync commands.
    Nothing is pushed unless -Push is given.

    Revoke and replace the credential BEFORE you push: the old value stays readable in existing
    clones, forks and GitHub's caches, so the rewrite only hides it.

.EXAMPLE
    powershell -File .github\tools\secret-scan\scrub-history.ps1 -Repository RIoT2.Net.Orchestrator
    powershell -File .github\tools\secret-scan\scrub-history.ps1 -Repository RIoT2.Net.Orchestrator -Push
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('RIoT2.Net.Orchestrator', 'RIoT2.Matter')]
    [string]$Repository,
    # Folder that holds the .github hub and the RIoT2.* repositories. Default: three levels up.
    [string]$Root,
    [string]$WorkDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'riot2-scrub'),
    # Force-push the rewritten branches and tags to origin.
    [switch]$Push
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }

# The mirror clone is bare. Allow bare repositories for this process and its git children only, in
# case the global config sets safe.bareRepository=explicit.
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'safe.bareRepository'
$env:GIT_CONFIG_VALUE_0 = 'all'

# One rule per repository. Paths are removed from every commit; replace-text expressions use
# git filter-repo syntax (regex:PATTERN==>REPLACEMENT, Python backreferences).
$Rules = @{
    'RIoT2.Net.Orchestrator' = @{
        What   = 'Remove the tracked build output bin/, which held StoredObjects with the Netatmo client secret and tokens.'
        Paths  = @('bin/')
    }
    'RIoT2.Matter' = @{
        What    = 'Blank the MatterController:CredentialProtectionSecret GUID committed in Controller/appsettings.json.'
        Replace = @('regex:("CredentialProtectionSecret"\s*:\s*")[0-9A-Fa-f-]{36}"==>\1"')
    }
}
$rule = $Rules[$Repository]

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit code $LASTEXITCODE)." }
}

function Invoke-FilterRepo([string[]]$FilterArgs) {
    # Probing writes to stderr; with 'Stop', Windows PowerShell turns redirected stderr into an error.
    $ErrorActionPreference = 'Continue'
    & git filter-repo --version *> $null
    if ($LASTEXITCODE -eq 0) { & git filter-repo @FilterArgs }
    else {
        & python -m git_filter_repo --version *> $null
        if ($LASTEXITCODE -ne 0) { throw 'git filter-repo is missing. Install it with: pip install --user git-filter-repo' }
        & python -m git_filter_repo @FilterArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "git filter-repo failed (exit code $LASTEXITCODE)." }
}

$local = Join-Path $Root $Repository
$url = (& git -C $local remote get-url origin).Trim()
$branch = (& git -C $local branch --show-current).Trim()
Invoke-Git -C $local fetch origin --quiet
$ahead = [int](& git -C $local rev-list --count "origin/$branch..$branch")
if ($ahead -gt 0) {
    throw "$Repository has $ahead unpushed commit(s) on $branch. Push them first, so they are rewritten too."
}

Write-Output "Rule: $($rule.What)"
New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
$mirror = Join-Path $WorkDirectory "$Repository.git"
if (Test-Path $mirror) { Remove-Item $mirror -Recurse -Force }
Invoke-Git clone --mirror --quiet $url $mirror
$before = [int](& git -C $mirror rev-list --all --count)

$filterArgs = @()
foreach ($p in $rule.Paths) { $filterArgs += @('--invert-paths', '--path', $p) }
$expressions = $null
if ($rule.Replace) {
    $expressions = Join-Path $WorkDirectory "$Repository.expressions.txt"
    [IO.File]::WriteAllLines($expressions, [string[]]$rule.Replace)
    $filterArgs += @('--replace-text', $expressions)
}

Push-Location $mirror
try { Invoke-FilterRepo $filterArgs }
finally {
    Pop-Location
    if ($expressions) { Remove-Item $expressions -Force -ErrorAction SilentlyContinue }
}
$after = [int](& git -C $mirror rev-list --all --count)
Write-Output "Rewritten: $before commit(s) before, $after after, in $mirror"

& (Join-Path $PSScriptRoot 'scan.ps1') -Path $mirror -Config (Join-Path $local '.gitleaks.toml')
if ($LASTEXITCODE -ne 0) { throw 'The rewritten history still has findings. Nothing was pushed.' }

$pushCommands = @(
    "git -C `"$mirror`" remote add origin $url",
    "git -C `"$mirror`" push --force --all origin",
    "git -C `"$mirror`" push --force --tags origin"
)
if ($Push) {
    $ErrorActionPreference = 'Continue'
    & git -C $mirror remote remove origin *> $null
    $ErrorActionPreference = 'Stop'
    Invoke-Git -C $mirror remote add origin $url
    Invoke-Git -C $mirror push --force --all origin
    Invoke-Git -C $mirror push --force --tags origin
    Write-Output 'Pushed the rewritten branches and tags.'
} else {
    Write-Output ''
    Write-Output 'Not pushed. Allow force pushes on the default branch if it is protected, then run:'
    $pushCommands | ForEach-Object { Write-Output "  $_" }
}

Write-Output ''
Write-Output "After the push, re-sync the working copy (commit or stash local work first):"
Write-Output "  git -C `"$local`" fetch origin --tags --force"
Write-Output "  git -C `"$local`" reset --hard origin/$branch"
Write-Output "Delete any other clones and forks of $Repository, or reset them the same way."
