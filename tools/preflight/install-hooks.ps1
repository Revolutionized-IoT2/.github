<#
.SYNOPSIS
    Turns on the RIoT2 pre-push gate in every repository of the workspace, and the agent guardrails.

.DESCRIPTION
    - Points core.hooksPath of each RIoT2 repository (preflight.json) at tools/preflight/git-hooks, so
      every push runs preflight.py first.
    - Copies the hub's AGENTS.md to the workspace root (C:\Src\RIoT2 isn't a repository) and adds a
      CLAUDE.md that imports it.
    - Writes the Claude Code hook settings (.claude/settings.json at the workspace root) that run
      hooks/riot2_guard.py. Copilot reads the hub's hooks/riot2-guardrails.json, which is the
      workspace's .github/hooks/, without installing anything.
    Safe to run again after a pull. -Uninstall removes core.hooksPath where it points here.

.EXAMPLE
    powershell -File .github\tools\preflight\install-hooks.ps1
    powershell -File .github\tools\preflight\install-hooks.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    # Folder that holds .github and the RIoT2.* repositories. Default: three levels up.
    [string]$Root,
    [switch]$Uninstall,
    # Replace a core.hooksPath that points somewhere else.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$hub = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Root) { $Root = (Resolve-Path (Join-Path $hub '..')).Path }
$hooks = (Join-Path $PSScriptRoot 'git-hooks') -replace '\\', '/'
$manifest = Get-Content -Raw (Join-Path $PSScriptRoot 'preflight.json') | ConvertFrom-Json
$names = @($manifest.repositories.PSObject.Properties.Name)

function Invoke-Git([string]$Repo, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & git -C $Repo @Arguments 2>$null } finally { $ErrorActionPreference = $previous }
    return "$out".Trim()
}

if (-not $Uninstall) {
    $python = $null
    foreach ($candidate in 'python', 'python3', 'py') {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            & $candidate -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>$null
            if ($LASTEXITCODE -eq 0) { $python = $candidate; break }
        }
    }
    if (-not $python) { throw 'Python 3.9 or later must be on PATH: the pre-push gate runs preflight.py.' }
}

foreach ($name in $names) {
    $repo = Join-Path $Root $name
    if (-not (Test-Path (Join-Path $repo '.git'))) { Write-Output ('{0,-32} not checked out' -f $name); continue }
    $current = Invoke-Git $repo @('config', '--local', '--get', 'core.hooksPath')
    if ($Uninstall) {
        if ($current -eq $hooks) {
            Invoke-Git $repo @('config', '--local', '--unset', 'core.hooksPath') | Out-Null
            Write-Output ('{0,-32} gate removed' -f $name)
        }
        continue
    }
    if ($current -and $current -ne $hooks -and -not $Force) {
        Write-Warning "$name already uses core.hooksPath=$current; skipped (use -Force to replace it)"
        continue
    }
    $own = @(Get-ChildItem (Join-Path $repo '.git\hooks') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -ne '.sample' })
    if ($own.Count -gt 0) {
        Write-Warning "$name has its own hooks in .git/hooks ($($own.Name -join ', ')); they stop running."
    }
    Invoke-Git $repo @('config', '--local', 'core.hooksPath', $hooks) | Out-Null
    Write-Output ('{0,-32} pre-push gate on' -f $name)
}

if ($Uninstall) { return }

# The workspace root isn't a repository: agents opened there read these copies.
$agents = Join-Path $Root 'AGENTS.md'
Copy-Item -Force (Join-Path $hub 'AGENTS.md') $agents
$claudeMd = Join-Path $Root 'CLAUDE.md'
if (-not (Test-Path $claudeMd)) { Set-Content -Path $claudeMd -Value '@AGENTS.md' -Encoding ascii }
Write-Output "Workspace AGENTS.md updated from the hub"

$claudeDir = Join-Path $Root '.claude'
$claudeSettings = Join-Path $claudeDir 'settings.json'
$guard = 'python .github/hooks/riot2_guard.py'
$settings = [ordered]@{
    hooks = [ordered]@{
        PreToolUse  = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = "$guard pre"; timeout = 20 }) })
        PostToolUse = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = "$guard post"; timeout = 20 }) })
    }
}
if (-not (Test-Path $claudeSettings)) {
    New-Item -ItemType Directory -Force $claudeDir | Out-Null
    [IO.File]::WriteAllText($claudeSettings, ($settings | ConvertTo-Json -Depth 8))
    Write-Output "Claude Code hooks written to $claudeSettings"
}
elseif ((Get-Content -Raw $claudeSettings) -notmatch 'riot2_guard\.py') {
    Write-Warning "$claudeSettings exists: add these hooks to it by hand:`n$($settings | ConvertTo-Json -Depth 8)"
}
else {
    Write-Output "Claude Code hooks already in $claudeSettings"
}
Write-Output "Done. Every push now runs tools/preflight/preflight.py first."
