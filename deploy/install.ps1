<#
.SYNOPSIS
Installs, upgrades or reconfigures RIoT2 from a site folder (ADR 0020), on this host or, with -RemoteHost,
on another one over SSH. The PowerShell version of install.sh.

.DESCRIPTION
Applies the host's settings (.env), secret files in the volumes, the orchestrator's configuration, the
workflows, Grafana dashboards and the node's plugins from hosts/<HostName>/ of a site folder. Guide:
docs/guides/site-configuration.md. The site's files are plain files: keeping them private is up to you.
On this host it works on the compose files next to it and needs only Docker: the installer's logic
(installer/riot2site.py) runs in a pinned container.

It first compares the running versions with the compose files': the same versions and an unchanged
site end it ("up to date"); the same versions and a changed site list the changes (-Reconfigure
applies them); an upgrade or downgrade exports the running installation into the site, backs it up
with backup.ps1, and asks per category whether to keep the existing configuration or use the
installer's.

Exit codes: 0 done, or already up to date; 1 failed; 2 invalid input, or a question needs an answer
(without a console, give -KeepExisting, -UseInstaller or the category parameters).

.EXAMPLE
./install.ps1 -HostName qnap -RemoteHost admin@192.168.0.13 -RemoteDeploy /share/Container/riot2/.github/deploy -DryRun

Installs on the NAS from this PC, from the site folder ~\riot2-site: install.sh runs on the NAS over SSH
(installer/remote.ps1), and this PC needs no Docker.

.EXAMPLE
./install.ps1 -Site D:\riot2-site -HostName pc -DryRun
#>
param(
    # The site folder; hosts/<HostName>/ in it is this host's folder. Default: $env:RIOT2_SITE, then ~/riot2-site.
    [string] $Site = '',
    # This host's folder name.
    [Parameter(Mandatory = $true)] [Alias('Host')] [string] $HostName,
    # Install on another host over SSH (user@host), whose deploy/ folder is -RemoteDeploy.
    [string] $RemoteHost = '',
    [string] $RemoteDeploy = '',
    # Show what would happen, and change nothing.
    [switch] $DryRun,
    # The same versions are installed: apply what changed in the site.
    [switch] $Reconfigure,
    # Answer "keep" or "use the installer's" for every category.
    [switch] $KeepExisting,
    [switch] $UseInstaller,
    # Per category: the installed .env, the managed secret files, the orchestrator's configuration, the workflows.
    [Alias('Env')] [ValidateSet('', 'Keep', 'Installer')] [string] $Settings = '',
    [ValidateSet('', 'Keep', 'Installer')] [string] $Secrets = '',
    [ValidateSet('', 'Keep', 'Installer')] [string] $Config = '',
    [ValidateSet('', 'Keep', 'Installer')] [string] $Workflows = '',
    # Install older images than the running ones (after a backup).
    [switch] $AllowDowngrade,
    # Replace "once" files too (renewed tokens: the site's copy may be stale).
    [switch] $OverwriteOnce,
    # Restore the site's Matter pairing instead of keeping the running one.
    [switch] $ReplaceMatter,
    # Before an upgrade, don't export the running installation into the site.
    [switch] $NoExport,
    # Only export the running configuration, workflows and tokens into the site; with -ExportManaged
    # also the "managed" secret files.
    [switch] $Export,
    [switch] $ExportManaged
)

$ErrorActionPreference = 'Stop'
$deploy = $PSScriptRoot
if (-not $Site) { $Site = if ($env:RIOT2_SITE) { $env:RIOT2_SITE } else { Join-Path $HOME 'riot2-site' } }
# Relative paths are the caller's.
$caller = (Get-Location).Path
if (-not [IO.Path]::IsPathRooted($Site)) { $Site = Join-Path $caller $Site }
Set-Location $deploy
$installerVersion = 1
# Pinned like the compose images: it runs installer/riot2site.py.
$pythonImage = if ($env:RIOT2_INSTALLER_PYTHON_IMAGE) { $env:RIOT2_INSTALLER_PYTHON_IMAGE } else { 'python:3.14-alpine3.23' }
$configZip = 'configuration/riot2-backup.zip'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Stop-Invalid([string] $Message) { [Console]::Error.WriteLine("ERROR: $Message"); exit 2 }
function Stop-Failed([string] $Message) { [Console]::Error.WriteLine("ERROR: $Message"); exit 1 }
function Write-Note([string] $Message) { Write-Host "  $Message" }
function Write-Step([string] $Message) { Write-Host ''; Write-Host "== $Message" }
function Write-Lines([string] $Path, $Lines) { [IO.File]::WriteAllLines($Path, [string[]] @($Lines), $utf8) }

# Native commands are judged by their exit code alone: with 'Stop', Windows PowerShell 5.1 turns
# a line on stderr (docker's progress output, for example) into a terminating error.
function Invoke-Native([string] $Command, [string[]] $Arguments, [switch] $AllowFailure) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Command @Arguments }
    finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
    return $output
}

# ------------------------------------------------------------------------------------------- options
$answers = @{ env = ''; secrets = ''; config = ''; workflows = '' }
if ($KeepExisting) { foreach ($k in @($answers.Keys)) { $answers[$k] = 'keep' } }
if ($UseInstaller) { foreach ($k in @($answers.Keys)) { $answers[$k] = 'installer' } }
if ($Settings) { $answers.env = $Settings.ToLowerInvariant() }
if ($Secrets) { $answers.secrets = $Secrets.ToLowerInvariant() }
if ($Config) { $answers.config = $Config.ToLowerInvariant() }
if ($Workflows) { $answers.workflows = $Workflows.ToLowerInvariant() }

if (-not (Test-Path -PathType Container $Site)) { Stop-Invalid "$Site is not a folder" }
$Site = (Resolve-Path $Site).Path
if ($HostName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { Stop-Invalid "-HostName must be a folder name, not '$HostName'" }
$hostDir = Join-Path $Site "hosts/$HostName"
if (-not (Test-Path -PathType Container $hostDir)) { Stop-Invalid "$hostDir doesn't exist" }

if ($RemoteHost -or $RemoteDeploy) {
    if (-not ($RemoteHost -and $RemoteDeploy)) { Stop-Invalid '-RemoteHost and -RemoteDeploy go together' }
    $installArgs = @()
    foreach ($pair in @(@($DryRun, '--dry-run'), @($Reconfigure, '--reconfigure'), @($KeepExisting, '--keep-existing'),
            @($UseInstaller, '--use-installer'), @($AllowDowngrade, '--allow-downgrade'), @($OverwriteOnce, '--overwrite-once'),
            @($ReplaceMatter, '--replace-matter'), @($NoExport, '--no-export'), @($Export, '--export'), @($ExportManaged, '--export-managed'))) {
        if ($pair[0]) { $installArgs += $pair[1] }
    }
    foreach ($pair in @(@($Settings, '--env'), @($Secrets, '--secrets'), @($Config, '--config'), @($Workflows, '--workflows'))) {
        if ($pair[0]) { $installArgs += "$($pair[1]) $($pair[0].ToLowerInvariant())" }
    }
    & (Join-Path $deploy 'installer/remote.ps1') -Site $Site -HostName $HostName -RemoteHost $RemoteHost -RemoteDeploy $RemoteDeploy `
        -InstallArgs $installArgs
    exit $LASTEXITCODE
}

# Compose must read the site's settings, not the caller's environment.
foreach ($name in 'COMPOSE_FILE', 'COMPOSE_PROFILES', 'COMPOSE_ENV_FILES', 'COMPOSE_PROJECT_NAME') {
    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------------------- preflight
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Stop-Failed 'docker is not installed or not on PATH' }
$composeVersion = (Invoke-Native 'docker' @('compose', 'version', '--short') -AllowFailure | Select-Object -First 1)
$composeVersion = "$composeVersion".Trim().TrimStart('v') -replace '-.*$', ''
$parsed = $null
if (-not [version]::TryParse($composeVersion, [ref] $parsed) -or $parsed -lt [version]'2.24.0') {
    Stop-Failed "Docker Compose 2.24 or later is needed (found: $(if ($composeVersion) { $composeVersion } else { 'none' }))"
}

$work = Join-Path $deploy '.install'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force (Join-Path $work 'site'), (Join-Path $work 'export') | Out-Null
$script:backupDir = ''
# On Linux the helper containers run as the calling user, so the files they write in .install stay
# the user's; only seeding (it sets the services' owners) runs as root.
$userArgs = @()
$chownArgs = @()
if ($IsLinux -or $IsMacOS) {
    $uid = "$(& id -u)".Trim()
    if ($uid -ne '0') {
        $userArgs = @('--user', "${uid}:$("$(& id -g)".Trim())")
        $chownArgs = @('--chown', "${uid}:$("$(& id -g)".Trim())")
    }
}

function Invoke-Py([string[]] $Arguments, [string[]] $Mounts = @(), [string] $Network = '', [switch] $Root) {
    $runArgs = @('run', '--rm')
    if (-not $Root) { $runArgs += $userArgs }
    if ($Network) { $runArgs += @('--network', $Network) }
    $runArgs += @('-v', "${deploy}/installer:/installer:ro", '-v', "${work}:/work", '-w', '/work')
    foreach ($m in $Mounts) { $runArgs += @('-v', $m) }
    return Invoke-Native 'docker' ($runArgs + @($pythonImage, 'python', '/installer/riot2site.py') + $Arguments)
}
function Invoke-PyNet([string[]] $Arguments) { return Invoke-Py $Arguments -Network $script:network }
function Use-Image([string] $Image) {
    Invoke-Native 'docker' @('image', 'inspect', $Image) -AllowFailure | Out-Null
    if ($LASTEXITCODE -ne 0) { Invoke-Native 'docker' @('pull', '-q', $Image) | Out-Null }
}
function Get-SiteFiles {
    $root = (Resolve-Path $hostDir).Path
    Get-ChildItem -Recurse -File -Force $root | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') } |
        Where-Object { $_ -notmatch '^\.git/' } | Sort-Object
}
function Test-SiteFile([string] $Rel) { return Test-Path (Join-Path $work "site/$Rel") }
function Test-WorkflowFiles { return [bool] (Get-ChildItem (Join-Path $work 'site/workflows') -Filter *.json -ErrorAction SilentlyContinue) }
function Read-WorkLines([string] $Name) {
    $path = Join-Path $work $Name
    if (Test-Path $path) { return @(Get-Content $path) }
    return @()
}

try {
    # --------------------------------------------------------------------------------------- read the site
    Write-Step "Reading the site: $hostDir"
    Use-Image $pythonImage
    $siteFiles = @(Get-SiteFiles)
    $names = @()
    foreach ($rel in $siteFiles) {
        # An encrypted file would be installed as it is: the installer takes plain files only.
        if ($rel -match '\.sops(\.[^./]+)?$') { Stop-Invalid "$rel looks encrypted with sops; put the decrypted file in the site instead" }
        $target = Join-Path $work "site/$rel"
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item (Join-Path $hostDir $rel) $target
        $names += $rel
    }
    Write-Lines (Join-Path $work 'names.txt') $names
    if (-not (Test-SiteFile 'deploy.env')) { Stop-Invalid "$hostDir/deploy.env is missing" }
    Write-Note "$($names.Count) files"

    # site.conf: KEY=value lines, the value optionally in quotes.
    $conf = [ordered]@{ PLUGIN_URL = ''; PLUGIN_SHA256 = ''; PUBLISH_WORKFLOWS = 'auto'; SEED_RULES = ''; VOLUME_OWNERS = ''
        LAN_DRIVER = ''; LAN_PARENT = ''; LAN_SUBNET = ''; LAN_GATEWAY = ''; LAN_IP_RANGE = ''; LAN_IPV6_SUBNET = ''; LAN_IPV6_GATEWAY = '' }
    function ConvertFrom-Quoted([string] $Value) { if ($Value -match '^"(.*)"$' -or $Value -match "^'(.*)'$") { return $Matches[1] }; return $Value }
    if (Test-SiteFile 'site.conf') {
        $n = 0
        foreach ($line in Get-Content (Join-Path $work 'site/site.conf')) {
            $n++
            if ($line -match '^\s*(#.*)?$') { continue }
            if ($line -notmatch '^([A-Z0-9_]+)=(.*)$') { Stop-Invalid "site.conf line ${n}: expected KEY=value" }
            $key = $Matches[1]; $value = ConvertFrom-Quoted $Matches[2]
            if (-not $conf.Contains($key)) { Stop-Invalid "site.conf line ${n}: unknown setting $key" }
            $conf[$key] = $value
        }
    }
    if ($conf.PUBLISH_WORKFLOWS -notin 'auto', 'true', 'false') { Stop-Invalid 'site.conf: PUBLISH_WORKFLOWS must be auto, true or false' }
    if ($conf.LAN_DRIVER -notin '', 'qnet', 'macvlan') { Stop-Invalid 'site.conf: LAN_DRIVER must be qnet, macvlan or empty' }
    if ($conf.LAN_DRIVER -eq 'qnet' -and $conf.LAN_IP_RANGE) { Write-Note 'site.conf: qnet hands out no address range, so LAN_IP_RANGE is ignored' }
    $pluginId = ("$($conf.PLUGIN_URL) $($conf.PLUGIN_SHA256)").Trim()

    # A value of an env file (the last one wins, quotes removed).
    function Get-EnvValue([string] $File, [string] $Key, [string] $Default = '') {
        $value = ''
        if (Test-Path $File) {
            $line = Get-Content $File | Where-Object { $_ -match "^\s*$Key=" } | Select-Object -Last 1
            if ($line) { $value = ConvertFrom-Quoted ($line.Substring($line.IndexOf('=') + 1)) }
        }
        if ($value) { return $value }
        return $Default
    }
    $siteEnv = Join-Path $work 'site/deploy.env'
    $deployEnv = Join-Path $deploy '.env'

    # --------------------------------------------------------------------------------------- the installed state
    function Invoke-SiteCompose([string[]] $Arguments) { return Invoke-Native 'docker' (@('compose', '--env-file', $siteEnv) + $Arguments) }
    function Invoke-Compose([string[]] $Arguments) { return Invoke-Native 'docker' (@('compose') + $Arguments) }
    try { $expected = Invoke-SiteCompose @('config', '--format', 'json') }
    catch { Stop-Invalid "the compose files don't accept the site's deploy.env (the message above names the variable)" }
    Write-Lines (Join-Path $work 'expected.json') $expected
    $expectedJson = ($expected -join "`n") | ConvertFrom-Json
    $project = $expectedJson.name
    if (-not $project) { Stop-Failed 'could not read the compose project name' }
    $script:network = "${project}_default"
    $serviceNames = @($expectedJson.services.PSObject.Properties.Name)
    $hasOrchestrator = $serviceNames -contains 'orchestrator'
    try { Invoke-Py @('settings', '--expected', '/work/expected.json') | Out-Null }
    catch { Stop-Invalid "the site's deploy.env has a setting a service refuses: $($_.Exception.Message -replace '(?s)^.*ERROR: ', '')" }

    Write-Lines (Join-Path $work 'rules.txt') @(Invoke-Py @('rules', '--rules', $conf.SEED_RULES, '--owners', $conf.VOLUME_OWNERS,
                '--seeds', '/work/site/volumes', '--expected', '/work/expected.json'))
    Read-WorkLines 'rules.txt' | Where-Object { $_ -like 'note *' } | ForEach-Object { Write-Note ('Note: ' + $_.Substring(5)) }
    # The volumes the site has files for: "volume <name> <docker name> <owner>".
    function Get-SeedVolumes { Read-WorkLines 'rules.txt' | Where-Object { $_ -like 'volume *' -and $_ -notlike '* rule-only' } | ForEach-Object {
            $p = $_ -split ' '; [pscustomobject]@{ Volume = $p[1]; Name = $p[2]; Owner = $p[3] } } }
    function Get-AllVolumes { Read-WorkLines 'rules.txt' | Where-Object { $_ -like 'volume *' } | ForEach-Object {
            $p = $_ -split ' '; [pscustomobject]@{ Volume = $p[1]; Name = $p[2]; Owner = $p[3] } } }
    function Test-Volume([string] $Name) { Invoke-Native 'docker' @('volume', 'inspect', $Name) -AllowFailure | Out-Null; return $LASTEXITCODE -eq 0 }

    $running = @()
    foreach ($id in @(Invoke-Native 'docker' @('ps', '-aq', '--filter', "label=com.docker.compose.project=$project"))) {
        if ($id) { $running += Invoke-Native 'docker' @('inspect', '--format', '{{index .Config.Labels "com.docker.compose.service"}} {{.Config.Image}} {{.State.Status}}', $id) }
    }
    Write-Lines (Join-Path $work 'running.txt') $running
    Write-Lines (Join-Path $work 'volumes.txt') @(Invoke-Native 'docker' @('volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project"))
    $markerArgs = @()
    if (Test-Path (Join-Path $deploy '.riot2-install.json')) {
        Copy-Item (Join-Path $deploy '.riot2-install.json') (Join-Path $work 'marker.json')
        $markerArgs = @('--marker', '/work/marker.json')
    }
    $orchestratorRunning = [bool] ($running | Where-Object { $_ -match '^orchestrator .* running$' })

    $versions = @(Invoke-Py (@('versions', '--running', '/work/running.txt', '--expected', '/work/expected.json', '--volumes', '/work/volumes.txt') + $markerArgs))
    $verdict = ($versions | Where-Object { $_ -like 'verdict *' } | Select-Object -First 1).Substring(8)
    $diff = @(Invoke-Py (@('diff', '--site', '/work/site', '--plugin', $pluginId) + $markerArgs))
    Write-Lines (Join-Path $work 'diff.txt') $diff
    $changed = [int] (($diff | Where-Object { $_ -like 'changed *' } | Select-Object -First 1).Substring(8))
    $items = @($diff | Where-Object { $_ -like 'item *' } | ForEach-Object { $p = $_ -split ' ', 4; [pscustomobject]@{ Category = $p[1]; Path = $p[2]; Change = $p[3] } })

    Write-Step "Compose project $project on this host: $verdict"
    $versions | Where-Object { $_ -notlike 'verdict *' } | ForEach-Object { Write-Host $_ }
    function Show-Changes { foreach ($i in $items) { Write-Note "$($i.Category): $($i.Path) ($($i.Change))" } }
    function Test-CategoryChanged([string] $Category) { return [bool] ($items | Where-Object Category -eq $Category) }

    # ----------------------------------------------------------------------------------- export
    # Exports the running installation into .install/export, then writes each file into the site's host
    # folder and into .install/site. Scope: all, or unchanged (site files that didn't change since the
    # last install, and new files).
    function Export-Site([string] $Scope) {
        $export = Join-Path $work 'export'
        if (Test-Path $export) { Remove-Item -Recurse -Force $export }
        New-Item -ItemType Directory $export | Out-Null
        $allowedArgs = @()
        $allowed = @()
        if ($Scope -eq 'unchanged') {
            $changedPaths = @($items | ForEach-Object Path)
            $allowed = @(Read-WorkLines 'names.txt' | Where-Object { $changedPaths -notcontains $_ })
            Write-Lines (Join-Path $work 'allowed.txt') $allowed
            $allowedArgs = @('--allowed', '/work/allowed.txt')
        }
        if ($hasOrchestrator -and $orchestratorRunning) {
            Invoke-PyNet @('api-wait', '--timeout', '60') | Out-Null
            if (-not (Test-SiteFile $configZip) -or $Scope -eq 'all' -or $allowed -contains $configZip) {
                $siteZip = @(); if (Test-SiteFile $configZip) { $siteZip = @('--site', "/work/site/$configZip") }
                Invoke-PyNet (@('api-export-config', '--out', "/work/export/$configZip") + $siteZip) | Out-Null
            }
            else { Write-Note "skip $configZip changed-in-site" }
            $siteWorkflows = @(); if (Test-Path (Join-Path $work 'site/workflows')) { $siteWorkflows = @('--site-dir', '/work/site/workflows') }
            Invoke-PyNet (@('api-workflows-export', '--out', '/work/export') + $siteWorkflows + $allowedArgs) |
                Where-Object { $_ -like 'skip *' } | ForEach-Object { Write-Note $_ }
        }
        elseif ($hasOrchestrator) { Write-Note "The orchestrator isn't running: its configuration and workflows aren't exported" }
        $managedArgs = @(); if ($ExportManaged) { $managedArgs = @('--managed') }
        foreach ($v in @(Get-AllVolumes)) {
            if (-not (Test-Volume $v.Name)) { continue }
            New-Item -ItemType Directory -Force (Join-Path $work "site/volumes/$($v.Volume)") | Out-Null
            Invoke-Py (@('export-seeds', '--volume', $v.Volume, '--volume-dir', '/v', '--seed-dir', "/work/site/volumes/$($v.Volume)",
                    '--out', '/work/export', '--rules', $conf.SEED_RULES) + $allowedArgs + $managedArgs + $chownArgs) -Mounts @("$($v.Name):/v:ro") -Root |
                Where-Object { $_ -like 'skip *' } | ForEach-Object { Write-Note $_ }
        }

        $exported = @()
        $exportRoot = (Resolve-Path $export).Path
        foreach ($file in @(Get-ChildItem -Recurse -File $exportRoot | Sort-Object FullName)) {
            $rel = $file.FullName.Substring($exportRoot.Length + 1).Replace('\', '/')
            foreach ($destination in (Join-Path $hostDir $rel), (Join-Path $work "site/$rel")) {
                New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
                Copy-Item -Force $file.FullName $destination
            }
            if ((Read-WorkLines 'names.txt') -notcontains $rel) { Add-Content -Path (Join-Path $work 'names.txt') -Value $rel }
            $exported += $rel
            Write-Note "exported $rel"
        }
        if ($exported.Count -eq 0) { Write-Note 'the site already matches the running installation'; return }
        if (Test-Path (Join-Path $work 'marker.json')) {
            Invoke-Py (@('marker-update', '--marker', '/work/marker.json', '--site', '/work/site') + $exported) | Out-Null
            Copy-Item -Force (Join-Path $work 'marker.json') (Join-Path $deploy '.riot2-install.json')
        }
        Write-Note "The site's files changed: $hostDir"
    }

    if ($Export) {
        Write-Step 'Exporting the running installation into the site'
        if ($DryRun) { Write-Host 'Dry run: nothing was exported.'; exit 0 }
        Export-Site 'all'
        exit 0
    }

    # ----------------------------------------------------------------------------------- what to do
    $mode = 'update'
    switch ($verdict) {
        'fresh' { $mode = 'fresh' }
        'same' {
            if (-not $Reconfigure) {
                if ($changed -eq 0) { Write-Host "RIoT2 is installed and up to date; the site hasn't changed since the last install." }
                else {
                    Write-Host 'The same versions are installed, but the site changed since the last install:'
                    Show-Changes
                    Write-Host 'Nothing was changed. To apply them, run again with -Reconfigure (it asks what to keep).'
                }
                exit 0
            }
        }
        'leftover' {
            Write-Host 'These volumes will be used as they are. For a clean installation stop here and remove them with'
            Write-Host 'docker volume rm; otherwise the installer backs them up first and asks what to keep.'
        }
        'downgrade' {
            Write-Host "WARNING: the installer's images are older than the running ones. An older version may not read"
            Write-Host "data that a newer one wrote; the safe way back is restore.ps1 with a backup made by that version."
            if (-not $AllowDowngrade -and -not $DryRun) {
                if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) { Stop-Invalid 'a downgrade needs -AllowDowngrade' }
                if ((Read-Host 'Downgrade anyway? [y/N]') -notin 'y', 'Y') { Write-Host 'Nothing was changed.'; exit 1 }
            }
        }
    }

    $exportBefore = $false
    if ($mode -eq 'fresh') { foreach ($k in @($answers.Keys)) { $answers[$k] = 'installer' } }
    else {
        if ($changed -ne 0) { Write-Host 'The site changed since the last install:'; Show-Changes }
        $exportBefore = -not $NoExport
    }

    # What the seeding would do to each volume, as a dry run.
    function Get-SeedPlan([string] $Mode) {
        $plan = @()
        $onceArgs = @(); if ($OverwriteOnce) { $onceArgs = @('--overwrite-once') }
        foreach ($v in @(Get-SeedVolumes)) {
            if (Test-Volume $v.Name) {
                $plan += Invoke-Py (@('seed', '--volume', $v.Volume, '--volume-dir', '/v', '--seed-dir', "/work/site/volumes/$($v.Volume)",
                        '--owner', $v.Owner, '--rules', $conf.SEED_RULES, '--mode', $Mode, '--dry-run') + $onceArgs) -Mounts @("$($v.Name):/v:ro") -Root
            }
            else {
                $plan += Read-WorkLines 'rules.txt' | Where-Object { $_ -like "seed $($v.Volume) *" } | ForEach-Object {
                    $p = $_ -split ' '; "write $($p[1])/$($p[2]) $($p[3])" }
            }
        }
        return , @($plan)
    }

    $questions = @()
    $envDiff = @()
    $seedPlans = @{}
    if ($mode -eq 'update') {
        if (Test-Path $deployEnv) {
            Copy-Item $deployEnv (Join-Path $work 'installed.env')
            $envDiff = @(Invoke-Py @('env-diff', '--existing', '/work/installed.env', '--site', '/work/site/deploy.env'))
            if ($envDiff.Count -gt 0) { $questions += 'env' }
        }
        $seedPlans.keep = Get-SeedPlan 'keep'
        $seedPlans.installer = Get-SeedPlan 'installer'
        if (($seedPlans.keep -join "`n") -ne ($seedPlans.installer -join "`n")) { $questions += 'secrets' }
        if ($hasOrchestrator -and (Test-SiteFile $configZip) -and (-not $exportBefore -or (Test-CategoryChanged 'configuration'))) { $questions += 'config' }
        if ($hasOrchestrator -and (Test-WorkflowFiles) -and (-not $exportBefore -or (Test-CategoryChanged 'workflows'))) { $questions += 'workflows' }
    }
    function Get-Description([string] $Category) {
        switch ($Category) {
            'env' { "Settings: deploy/.env and the site's deploy.env differ in $(($envDiff | ForEach-Object { ($_ -split ' ')[1] }) -join ', ')." }
            'secrets' { "Secret files: the site's managed files differ from the volumes': $(($seedPlans.installer | Where-Object { $_ -like 'write *' } | ForEach-Object { ($_ -split ' ')[1] }) -join ', ')." }
            'config' { "Orchestrator configuration: the site's backup would replace the running nodes, devices, dashboards and variables." }
            'workflows' { "Workflows: the site's workflows would be imported as new versions of the running ones." }
        }
    }
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    $missing = @()
    foreach ($category in $questions) {
        if ($answers[$category] -or $DryRun) { continue }
        if ($interactive) {
            Write-Host ''
            Write-Host (Get-Description $category)
            $reply = Read-Host 'Do you want to keep existing configurations, or do you want to use configuration from installer? [K]eep/[u]se installer'
            $answers[$category] = if ($reply -in 'u', 'U', 'use', 'installer') { 'installer' } else { 'keep' }
        }
        else { $missing += $category }
    }
    if ($missing.Count -gt 0) {
        foreach ($category in $missing) { [Console]::Error.WriteLine((Get-Description $category)) }
        Stop-Invalid "no console to ask about: $($missing -join ' '). Give -KeepExisting, -UseInstaller, or -Settings/-Secrets/-Config/-Workflows Keep|Installer"
    }
    # A category nobody was asked about is kept.
    foreach ($k in @($answers.Keys)) { if (-not $answers[$k]) { $answers[$k] = 'keep' } }

    # The LAN network: create (missing), remake (a qnet network without QNAP's IPAM driver, on which no
    # container starts: "cannot find IPAM config by mac address") or keep.
    $lanNetwork = ''
    $lanAction = ''
    if ($conf.LAN_DRIVER) {
        $lanNetwork = Get-EnvValue $siteEnv 'RIOT2_LAN_NETWORK' 'riot2-lan'
        $lanAction = 'keep'
        Invoke-Native 'docker' @('network', 'inspect', $lanNetwork) -AllowFailure | Out-Null
        if ($LASTEXITCODE -ne 0) { $lanAction = 'create' }
        else {
            $driver = "$(Invoke-Native 'docker' @('network', 'inspect', '--format', '{{.Driver}}', $lanNetwork))".Trim()
            if ($driver -ne $conf.LAN_DRIVER) { Write-Note "WARNING: the network $lanNetwork uses $driver, not $($conf.LAN_DRIVER)" }
            elseif ($driver -eq 'qnet' -and "$(Invoke-Native 'docker' @('network', 'inspect', '--format', '{{.IPAM.Driver}}', $lanNetwork))".Trim() -ne 'qnet') {
                $lanAction = 'remake'
                if ("$(Invoke-Native 'docker' @('network', 'inspect', '--format', '{{len .Containers}}', $lanNetwork))".Trim() -ne '0') {
                    Stop-Invalid "the qnet network $lanNetwork lacks the qnet IPAM driver, but containers run on it: stop them, run 'docker network rm $lanNetwork' and install again"
                }
                foreach ($id in @(Invoke-Native 'docker' @('ps', '-aq', '--filter', "network=$lanNetwork"))) {
                    if (-not "$id".Trim()) { continue }
                    $owner = "$(Invoke-Native 'docker' @('inspect', '--format', '{{index .Config.Labels "com.docker.compose.project"}}', $id))".Trim()
                    if ($owner -ne $project) {
                        Stop-Invalid "the qnet network $lanNetwork lacks the qnet IPAM driver, and container $id of another project uses it: remove it, run 'docker network rm $lanNetwork' and install again"
                    }
                }
            }
        }
    }

    if ($DryRun) {
        Write-Step 'Dry run: what the installer would do'
        if ($exportBefore) { Write-Note 'export the running configuration, workflows and renewed tokens into the site' }
        if ($mode -eq 'update') { Write-Note "back up the installation with backup.ps1 into $deploy\backups" }
        if ($lanAction -eq 'create') { Write-Note "create the $($conf.LAN_DRIVER) network $lanNetwork" }
        if ($lanAction -eq 'remake') { Write-Note "make the qnet network $lanNetwork again, with the qnet IPAM driver (removing this project's stopped containers on it)" }
        if ($mode -eq 'fresh' -or $answers.env -eq 'installer' -or -not (Test-Path $deployEnv)) { Write-Note "settings: write the site's deploy.env as deploy/.env" }
        else { Write-Note 'settings: keep deploy/.env, adding the keys only the site has' }
        if ($conf.PLUGIN_URL) { Write-Note "plugins: install $(Split-Path -Leaf $conf.PLUGIN_URL) unless it's installed" }
        $plan = $seedPlans[$answers.secrets]
        if ($null -eq $plan) { $plan = Get-SeedPlan $answers.secrets }
        foreach ($line in $plan) { Write-Note "secret file: $line" }
        Write-Note 'docker compose pull, then up -d --wait'
        if ($hasOrchestrator -and (Test-SiteFile $configZip)) {
            if ($answers.config -eq 'installer') { Write-Note "configuration: restore the site's backup$(if (-not $ReplaceMatter) { ', keeping the running Matter pairing' })" }
            else { Write-Note 'configuration: keep the running one' }
        }
        if ($hasOrchestrator -and (Test-WorkflowFiles)) {
            Write-Note "workflows: import $(if ($answers.workflows -eq 'installer' -and $mode -ne 'fresh') { 'every one' } else { 'the missing ones' })"
        }
        Write-Host ''
        Write-Host 'Dry run: nothing was changed. Categories nobody answered are shown as keep.'
        exit 0
    }

    # ----------------------------------------------------------------------------------- export and backup
    if ($exportBefore) {
        Write-Step 'Exporting the running installation into the site first'
        Export-Site 'unchanged'
    }
    if ($mode -eq 'update') {
        Write-Step 'Backing up the installation'
        if (-not (Test-Path $deployEnv)) {
            Copy-Item $siteEnv $deployEnv
            Write-Note "deploy/.env was missing: wrote the site's, which backup.ps1 needs"
        }
        $log = & (Join-Path $deploy 'backup.ps1') -Output (Join-Path $deploy 'backups') 6>&1
        $log | ForEach-Object { Write-Host $_ }
        $done = $log | ForEach-Object { "$_" } | Where-Object { $_ -like 'Done: *' } | Select-Object -Last 1
        if ($done) { $script:backupDir = $done.Substring(6) }
        Set-Location $deploy
    }

    # ----------------------------------------------------------------------------------- apply
    if ($lanAction -eq 'remake') {
        Write-Step "Making the qnet network $lanNetwork again, with the qnet IPAM driver"
        foreach ($id in @(Invoke-Native 'docker' @('ps', '-aq', '--filter', "network=$lanNetwork"))) {
            if (-not "$id".Trim()) { continue }
            Write-Note "removing the stopped container $("$(Invoke-Native 'docker' @('inspect', '--format', '{{.Name}}', $id))".Trim()); compose creates it again"
            Invoke-Native 'docker' @('rm', $id) | Out-Null
        }
        Invoke-Native 'docker' @('network', 'rm', $lanNetwork) | Out-Null
        $lanAction = 'create'
    }
    if ($lanAction -eq 'create') {
        Write-Step "Creating the $($conf.LAN_DRIVER) network $lanNetwork"
        if (-not ($conf.LAN_PARENT -and $conf.LAN_SUBNET -and $conf.LAN_GATEWAY)) { Stop-Invalid 'site.conf: LAN_DRIVER needs LAN_PARENT, LAN_SUBNET and LAN_GATEWAY' }
        $netArgs = @('network', 'create', '-d', $conf.LAN_DRIVER, '--subnet', $conf.LAN_SUBNET, '--gateway', $conf.LAN_GATEWAY)
        if ($conf.LAN_DRIVER -eq 'qnet') {
            # QNAP's driver needs its own IPAM driver too, and has no --ip-range.
            $netArgs += @('--opt', "iface=$($conf.LAN_PARENT)", '--ipam-driver', 'qnet', '--ipam-opt', "iface=$($conf.LAN_PARENT)")
        }
        else {
            $netArgs += @('--opt', "parent=$($conf.LAN_PARENT)")
            if ($conf.LAN_IP_RANGE) { $netArgs += @('--ip-range', $conf.LAN_IP_RANGE) }
        }
        if ($conf.LAN_IPV6_SUBNET) {
            $netArgs += @('--ipv6', '--subnet', $conf.LAN_IPV6_SUBNET)
            if ($conf.LAN_IPV6_GATEWAY) { $netArgs += @('--gateway', $conf.LAN_IPV6_GATEWAY) }
        }
        Invoke-Native 'docker' ($netArgs + $lanNetwork) | Out-Null
        Write-Note "docker $($netArgs -join ' ') $lanNetwork"
    }

    Write-Step 'Settings'
    $sameEnv = (Test-Path $deployEnv) -and ((Get-FileHash $deployEnv).Hash -eq (Get-FileHash $siteEnv).Hash)
    if (-not (Test-Path $deployEnv) -or (($mode -eq 'fresh' -or $answers.env -eq 'installer') -and -not $sameEnv)) {
        if (Test-Path $deployEnv) { Copy-Item -Force $deployEnv (Join-Path $deploy '.env.bak'); Write-Note 'the previous deploy/.env is .env.bak' }
        Copy-Item -Force $siteEnv $deployEnv
        Write-Note "wrote the site's deploy.env as deploy/.env"
    }
    elseif ($answers.env -eq 'keep') {
        Copy-Item -Force $deployEnv (Join-Path $work 'installed.env')
        $added = @(Invoke-Py @('env-merge', '--existing', '/work/installed.env', '--site', '/work/site/deploy.env', '--out', '/work/merged.env'))
        if ($added.Count -gt 0) {
            Copy-Item -Force (Join-Path $work 'merged.env') $deployEnv
            Write-Note "kept deploy/.env and added the site's new keys: $(($added | ForEach-Object { ($_ -split ' ')[1] }) -join ', ')"
        }
        else { Write-Note 'kept deploy/.env' }
    }
    else { Write-Note "deploy/.env is the site's" }
    if (Test-SiteFile 'docker-compose.override.yml') {
        Copy-Item -Force (Join-Path $work 'site/docker-compose.override.yml') (Join-Path $deploy 'docker-compose.override.yml')
        Write-Note 'wrote docker-compose.override.yml'
    }

    if (Test-Path (Join-Path $work 'site/grafana-dashboards')) {
        $dashboards = Join-Path $deploy 'grafana/site-dashboards'
        New-Item -ItemType Directory -Force $dashboards | Out-Null
        Get-ChildItem $dashboards -Filter *.json -File | Remove-Item -Force
        Get-ChildItem (Join-Path $work 'site/grafana-dashboards') -Filter *.json -File | Copy-Item -Destination $dashboards
        Write-Note "Grafana's Site folder: $(@(Get-ChildItem $dashboards -Filter *.json -File).Count) dashboards"
    }

    $pluginsChanged = $false
    if ($conf.PLUGIN_URL) {
        $plugins = Get-EnvValue $deployEnv 'RIOT2_NODE_PLUGINS' './plugins'
        if (-not [IO.Path]::IsPathRooted($plugins)) { $plugins = Join-Path $deploy ($plugins -replace '^\./', '') }
        New-Item -ItemType Directory -Force $plugins | Out-Null
        $result = Invoke-Py @('plugins', '--url', $conf.PLUGIN_URL, '--sha256', $conf.PLUGIN_SHA256, '--dest', '/plugins', '--stage', '/work/plugins') -Mounts @("${plugins}:/plugins:ro")
        if ("$result" -eq 'changed') {
            # The node writes its plugin folder as root, so it's replaced from a container.
            Invoke-Native 'docker' @('run', '--rm', '-v', "${plugins}:/plugins", '-v', "${work}/plugins:/stage:ro", $pythonImage, 'sh', '-c',
                'find /plugins -mindepth 1 -maxdepth 1 -exec rm -rf {} + && cp -R /stage/. /plugins/') | Out-Null
            Write-Note "plugins: installed $(Split-Path -Leaf $conf.PLUGIN_URL)"
            $pluginsChanged = $true
        }
        else { Write-Note "plugins: $(Split-Path -Leaf $conf.PLUGIN_URL) is installed" }
    }

    # Writes the site's files into the volumes; returns the volumes it wrote to.
    function Invoke-Seed([string] $Mode) {
        $written = @()
        $onceArgs = @(); if ($OverwriteOnce) { $onceArgs = @('--overwrite-once') }
        foreach ($v in @(Get-SeedVolumes)) {
            if (-not (Test-Volume $v.Name)) {
                Invoke-Native 'docker' @('volume', 'create', '--label', "com.docker.compose.project=$project", '--label',
                    "com.docker.compose.volume=$($v.Volume)", $v.Name) | Out-Null
            }
            $out = @(Invoke-Py (@('seed', '--volume', $v.Volume, '--volume-dir', '/v', '--seed-dir', "/work/site/volumes/$($v.Volume)",
                        '--owner', $v.Owner, '--rules', $conf.SEED_RULES, '--mode', $Mode) + $onceArgs) -Mounts @("$($v.Name):/v") -Root)
            foreach ($line in $out) { Write-Note $line }
            if ($out | Where-Object { $_ -like 'write *' }) { $written += $v.Volume }
        }
        return , @($written)
    }
    Write-Step 'Secret files'
    if (@(Get-SeedVolumes).Count -eq 0) { Write-Note 'the site has none' }
    else {
        # Services whose volume files change stop first, so they don't write the same files meanwhile.
        $plan = Get-SeedPlan $answers.secrets
        $changing = @($plan | Where-Object { $_ -like 'write *' } | ForEach-Object { (($_ -split ' ')[1] -split '/')[0] } | Sort-Object -Unique)
        if ($changing.Count -gt 0 -and $mode -ne 'fresh') {
            $stop = @(Invoke-Py (@('compose-services', '--expected', '/work/expected.json') + $changing))
            if ($stop.Count -gt 0) { Invoke-Compose (@('stop') + $stop) | Out-Null }
        }
        Invoke-Seed $answers.secrets | Out-Null
    }

    Write-Step 'Starting RIoT2'
    # A container made for a network that's gone (made again, or another RIOT2_LAN_NETWORK) can't start, and
    # compose doesn't make it again by itself: remove it, compose creates it anew. Its volumes stay.
    foreach ($id in @(Invoke-Native 'docker' @('ps', '-aq', '--filter', "label=com.docker.compose.project=$project"))) {
        if (-not "$id".Trim()) { continue }
        $nets = "$(Invoke-Native 'docker' @('inspect', '--format', '{{range $name, $ep := .NetworkSettings.Networks}}{{if $ep.NetworkID}}{{$ep.NetworkID}}{{else}}{{$name}}{{end}} {{end}}', $id))"
        foreach ($net in @($nets -split '\s+' | Where-Object { $_ })) {
            Invoke-Native 'docker' @('network', 'inspect', $net) -AllowFailure | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Note "removing $("$(Invoke-Native 'docker' @('inspect', '--format', '{{.Name}}', $id))".Trim()), made for a network that's gone; compose creates it again"
                Invoke-Native 'docker' @('rm', '-f', $id) | Out-Null
                break
            }
        }
    }
    Invoke-Compose @('pull', '--quiet') | Out-Null
    Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '300', '--remove-orphans') | Out-Null
    if ($pluginsChanged -and $serviceNames -contains 'node') {
        # Plugins load only when the node starts.
        Invoke-Compose @('restart', 'node') | Out-Null
        Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '300') | Out-Null
    }
    Invoke-Compose @('ps') | ForEach-Object { Write-Host $_ }

    if ($hasOrchestrator -and ((Test-SiteFile $configZip) -or (Test-WorkflowFiles))) {
        Write-Step 'Orchestrator configuration and workflows'
        Invoke-PyNet @('api-wait') | Out-Null
        if ((Test-SiteFile $configZip) -and $answers.config -eq 'installer') {
            Invoke-PyNet @('api-backup', '--out', '/work/live.zip') | Out-Null
            $matterArgs = @(); if ($ReplaceMatter) { $matterArgs = @('--replace') }
            $merged = Invoke-Py (@('merge-matter', '--site', "/work/site/$configZip", '--live', '/work/live.zip', '--out', '/work/restore.zip') + $matterArgs)
            if ("$merged" -match '^matter live (.*)') { Write-Note "kept the running Matter pairing ($($Matches[1]) files)" }
            elseif ("$merged" -match '^matter site (.*)') { Write-Note "the Matter pairing is the site's: $($Matches[1]) files" }
            Invoke-PyNet @('api-restore', '--zip', '/work/restore.zip') | ForEach-Object { Write-Note $_ }
            # The restore replaces the Matter credentials folder: the site's files for it go back in.
            if ((Read-WorkLines 'rules.txt') -match '^volume orchestrator-matter ') {
                if ((Invoke-Seed $answers.secrets) -contains 'orchestrator-matter') {
                    Invoke-Compose @('restart', 'orchestrator') | Out-Null
                    Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '300') | Out-Null
                    Invoke-PyNet @('api-wait') | Out-Null
                    Write-Note "wrote the site's Matter files again and restarted the orchestrator"
                }
            }
        }
        elseif (Test-SiteFile $configZip) { Write-Note 'configuration: kept the running one' }
        if (Test-WorkflowFiles) {
            $modeWorkflows = if ($answers.workflows -eq 'installer' -and $mode -ne 'fresh') { 'all' } else { 'missing' }
            Invoke-PyNet @('api-workflows-import', '--dir', '/work/site/workflows', '--mode', $modeWorkflows, '--publish', $conf.PUBLISH_WORKFLOWS) |
                ForEach-Object { Write-Note $_ }
        }
    }

    $commit = ''
    if (Get-Command git -ErrorAction SilentlyContinue) { $commit = "$(Invoke-Native 'git' @('-C', $Site, 'rev-parse', '--short', 'HEAD') -AllowFailure)".Trim() }
    if ($LASTEXITCODE -ne 0) { $commit = '' }
    Invoke-Py @('marker', '--site', '/work/site', '--expected', '/work/expected.json', '--out', '/work/marker.new', '--host', $HostName,
        '--project', $project, '--commit', $commit, '--plugin', $pluginId, '--installer-version', "$installerVersion") | Out-Null
    Copy-Item -Force (Join-Path $work 'marker.new') (Join-Path $deploy '.riot2-install.json')

    Write-Step 'Done'
    $composeFiles = Get-EnvValue $deployEnv 'COMPOSE_FILE' 'docker-compose.yml'
    function Get-Lan([string] $Name) { return Get-EnvValue $deployEnv "RIOT2_LAN_IP_$Name" }
    if ($composeFiles -like '*compose.lan.yml*') {
        Write-Note "UI:            http://$(Get-Lan 'UI')/"
        Write-Note "Orchestrator:  http://$(Get-Lan 'ORCHESTRATOR'):8080/health"
        Write-Note "MQTT broker:   $(Get-Lan 'MQTT'):1883 (WebSocket 9001)"
        if ($composeFiles -like '*compose.lan.influx.yml*') { Write-Note "InfluxDB:      http://$(Get-Lan 'INFLUXDB'):8086/" }
        if ($composeFiles -like '*compose.lan.influx.yml*' -or $composeFiles -like '*compose.lan.observability.yml*') { Write-Note "Grafana:       http://$(Get-Lan 'GRAFANA'):3000/" }
    }
    elseif ($hasOrchestrator) {
        Write-Note "UI:            http://$(Get-EnvValue $deployEnv 'RIOT2_HOST'):$(Get-EnvValue $deployEnv 'RIOT2_UI_HOST_PORT' '80')/"
    }
    if ($script:backupDir) { Write-Note "The installation before the changes: $($script:backupDir)" }
}
catch {
    [Console]::Error.WriteLine("ERROR: the installer stopped: $($_.Exception.Message)")
    if ($script:backupDir) {
        [Console]::Error.WriteLine('The installation was backed up first; to go back to it:')
        [Console]::Error.WriteLine("  $deploy\restore.ps1 -Path $($script:backupDir)")
    }
    exit 1
}
finally {
    Set-Location $deploy
    if (Test-Path $work) { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue }
}
