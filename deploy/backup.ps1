<#
.SYNOPSIS
Full-system backup of a RIoT2 compose install (design 7.4): every data volume, the InfluxDB data,
.env and plugins/. The PowerShell version of backup.sh.

.DESCRIPTION
The orchestrator, Elsa, the node and Grafana are stopped while their volumes are archived (a few
seconds), so the SQLite files are consistent, then started again. InfluxDB keeps running: its data
is copied with "influx backup". Log volumes are skipped. restore.ps1 restores the folder. The backup
holds every secret of the install (.env, device credentials, Matter keys): keep it private.

.EXAMPLE
./backup.ps1 -ComposeFile docker-compose.yml, compose.influx.yml -ComposeProfile node
#>
param(
    # The same compose files as "docker compose -f"; default: docker compose's own default.
    [string[]] $ComposeFile = @(),
    # The same profiles as "docker compose --profile".
    [string[]] $ComposeProfile = @(),
    # Where to write the backup folder, relative to the current folder; default: backups/ next to this script.
    [string] $Output = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Output) { $Output = Join-Path $PSScriptRoot 'backups' }
elseif (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path (Get-Location).Path $Output }
Set-Location $PSScriptRoot

# Pinned like the compose images; only tar is used.
$helperImage = 'alpine:3.22'
# Volumes that are written while running and archived with their service stopped.
$stoppedServices = @('orchestrator', 'elsa', 'node', 'grafana')

$composeArgs = @()
foreach ($file in $ComposeFile) { $composeArgs += @('-f', $file) }
foreach ($name in $ComposeProfile) { $composeArgs += @('--profile', $name) }

# Native commands are judged by their exit code alone: with 'Stop', Windows PowerShell 5.1 turns
# a line on stderr (docker's progress output, for example) into a terminating error.
function Invoke-Native([string] $Command, [string[]] $Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $Command @Arguments }
    finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0) { throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
    return $output
}

function Invoke-Compose([string[]] $Arguments) {
    return Invoke-Native 'docker' (@('compose') + $composeArgs + $Arguments)
}

$project = (Invoke-Compose @('config') | Where-Object { $_ -match '^name: *(.+)$' } | Select-Object -First 1) -replace '^name: *', ''
if (-not $project) { throw 'Could not read the compose project name' }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$target = Join-Path (Resolve-Path $Output).Path "riot2-system-$stamp"
New-Item -ItemType Directory -Force -Path (Join-Path $target 'volumes') | Out-Null
Write-Host "Backing up compose project $project to $target"

$running = @(Invoke-Compose @('ps', '--services', '--status', 'running'))
$stop = @($stoppedServices | Where-Object { $running -contains $_ })

if ($running -contains 'influxdb') {
    Write-Host 'InfluxDB: influx backup'
    Invoke-Compose @('exec', '-T', 'influxdb', 'sh', '-c', 'rm -rf /tmp/riot2-backup && influx backup /tmp/riot2-backup -t $DOCKER_INFLUXDB_INIT_ADMIN_TOKEN > /dev/null') | Out-Null
    Invoke-Compose @('cp', 'influxdb:/tmp/riot2-backup', (Join-Path $target 'influxdb')) | Out-Null
    Invoke-Compose @('exec', '-T', 'influxdb', 'rm', '-rf', '/tmp/riot2-backup') | Out-Null
}

$volumes = @()
if ($stop.Count -gt 0) {
    Write-Host "Stopping $($stop -join ' ')"
    Invoke-Compose (@('stop') + $stop) | Out-Null
}
try {
    foreach ($key in @(Invoke-Compose @('config', '--volumes'))) {
        # Logs aren't state, and InfluxDB's data is in influxdb/ (its config is recreated on setup).
        if ($key -like '*-logs' -or $key -like 'influxdb-*') { continue }
        $volume = "${project}_$key"
        # Listed rather than inspected: a missing volume isn't an error here.
        if (@(Invoke-Native 'docker' @('volume', 'ls', '-q', '--filter', "name=^${volume}`$")) -notcontains $volume) { continue }
        Write-Host "Volume $volume"
        Invoke-Native 'docker' @('run', '--rm', '-v', "${volume}:/data:ro", '-v', "$(Join-Path $target 'volumes'):/backup",
            '-e', "KEY=$key", $helperImage, 'sh', '-c', 'tar -czf /backup/$KEY.tar.gz -C /data .') | Out-Null
        $volumes += $key
    }
}
finally {
    if ($stop.Count -gt 0) {
        Write-Host "Starting $($stop -join ' ')"
        Invoke-Compose (@('start') + $stop) | Out-Null
    }
}

if (Test-Path .env) { Copy-Item .env (Join-Path $target '.env') }
if (Test-Path plugins) { Invoke-Native 'tar' @('-czf', (Join-Path $target 'plugins.tar.gz'), 'plugins') | Out-Null }

$images = @(Invoke-Compose @('config', '--images') | ForEach-Object { "  $_" })
@(
    "created: $stamp",
    "project: $project",
    "compose: $($composeArgs -join ' ')",
    "volumes: $($volumes -join ' ')",
    "influxdb: $(if (Test-Path (Join-Path $target 'influxdb')) { 'yes' } else { 'no' })",
    'images:'
) + $images | Set-Content -Path (Join-Path $target 'backup.txt') -Encoding ascii

Write-Host "Done: $target"
