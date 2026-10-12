<#
.SYNOPSIS
    Scans the full git history of every RIoT2 repository for secrets with gitleaks.

.DESCRIPTION
    Downloads a pinned, checksum-verified gitleaks when it is not on PATH, scans every commit
    reachable from any ref of each repository found under -Root, and prints one line per
    finding. Secret values are always redacted. A repository's own .gitleaks.toml (reviewed
    allowlists) is honoured. Exit code 1 means at least one finding.

.EXAMPLE
    powershell -File .github\tools\secret-scan\scan.ps1
    powershell -File .github\tools\secret-scan\scan.ps1 -Repository RIoT2.Matter,RIoT2.Net.Orchestrator
#>
[CmdletBinding()]
param(
    # Folder that holds the .github hub and the RIoT2.* repositories. Default: three levels up.
    [string]$Root,
    # Repository folder names to scan. Default: every git repository under -Root.
    [string[]]$Repository,
    # Scan these repository paths (for example a bare mirror clone) instead of the -Root repositories.
    [string[]]$Path,
    # gitleaks config for -Path scans. Default: the repository's own .gitleaks.toml, if any.
    [string]$Config,
    # Where the redacted JSON reports are written.
    [string]$ReportDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'riot2-secret-scan')
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path }
# powershell -File passes "A,B" as a single string.
$Repository = @($Repository | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Path = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Path.Count -gt 0) {
    # -Path may be a bare mirror clone. Allow it for gitleaks' git children even when the global
    # config sets safe.bareRepository=explicit.
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'safe.bareRepository'
    $env:GIT_CONFIG_VALUE_0 = 'all'
}
$GitleaksVersion = '8.30.1'
$GitleaksSha256 = @{
    'windows_x64.zip'     = 'd29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e'
    'linux_x64.tar.gz'    = '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
    'darwin_arm64.tar.gz' = 'b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5'
}

function Get-Gitleaks {
    $onPath = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    if ([IO.Path]::DirectorySeparatorChar -eq '\') { $asset = 'windows_x64.zip'; $exe = 'gitleaks.exe' }
    elseif ((uname -s) -eq 'Darwin') { $asset = 'darwin_arm64.tar.gz'; $exe = 'gitleaks' }
    else { $asset = 'linux_x64.tar.gz'; $exe = 'gitleaks' }

    $dir = Join-Path ([IO.Path]::GetTempPath()) "gitleaks-$GitleaksVersion"
    $path = Join-Path $dir $exe
    if (Test-Path $path) { return $path }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = "gitleaks_${GitleaksVersion}_$asset"
    $archive = Join-Path $dir $file
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/gitleaks/gitleaks/releases/download/v$GitleaksVersion/$file" -OutFile $archive -UseBasicParsing
    $hash = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $GitleaksSha256[$asset]) {
        Remove-Item $archive -Force
        throw "gitleaks download checksum mismatch for $file."
    }
    if ($asset.EndsWith('.zip')) { Expand-Archive -Path $archive -DestinationPath $dir -Force }
    else { tar -xzf $archive -C $dir $exe }
    return $path
}

$gitleaks = Get-Gitleaks
New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null

$repos = @(if ($Path) {
    $Path | ForEach-Object { Get-Item -Path $_ }
} else {
    Get-ChildItem -Path $Root -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') } |
        Where-Object { $Repository.Count -eq 0 -or $Repository -contains $_.Name }
})
if ($repos.Count -eq 0) { throw "No git repositories found under $Root." }

$total = 0
foreach ($repo in $repos) {
    $report = Join-Path $ReportDirectory "$($repo.Name).json"
    $glArgs = @('git', $repo.FullName, '--redact', '--no-banner', '--log-level', 'error',
        '--exit-code', '0', '--report-format', 'json', '--report-path', $report)
    $repoConfig = if ($Config) { $Config } else { Join-Path $repo.FullName '.gitleaks.toml' }
    if (Test-Path $repoConfig) { $glArgs += @('--config', $repoConfig) }

    & $gitleaks @glArgs
    if ($LASTEXITCODE -ne 0) { throw "gitleaks failed for $($repo.Name) (exit code $LASTEXITCODE)." }

    $parsed = Get-Content -Path $report -Raw | ConvertFrom-Json
    $findings = @($parsed)
    $total += $findings.Count
    $status = if ($findings.Count -eq 0) { 'clean' } else { "$($findings.Count) finding(s)" }
    Write-Output ('{0,-30} {1}' -f $repo.Name, $status)
    foreach ($f in $findings) {
        Write-Output ('    {0} {1}:{2} commit {3} ({4})' -f $f.RuleID, $f.File, $f.StartLine, $f.Commit.Substring(0, 7), $f.Date.Substring(0, 10))
    }
}

Write-Output ''
Write-Output "Redacted reports: $ReportDirectory"
if ($total -gt 0) {
    Write-Output "$total finding(s). Rotate each credential first, then scrub it from history (scrub-history.ps1). Allowlist only reviewed test material, in the repository's .gitleaks.toml."
    exit 1
}
Write-Output 'No findings.'
