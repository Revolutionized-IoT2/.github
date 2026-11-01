<#
.SYNOPSIS
Restores a full-system backup made by backup.ps1 or backup.sh (design 7.4), on the same host or a
clean one. The PowerShell version of restore.sh.

.DESCRIPTION
The stack is taken down, every volume in the backup is emptied and filled from it, plugins/ is
restored, and the stack is started again. .env is copied from the backup only when there is none
here. With InfluxDB in the compose files, its data is then replaced with "influx restore --full".

.EXAMPLE
./restore.ps1 -Path backups/riot2-system-20261101T030000Z -ComposeFile docker-compose.yml, compose.influx.yml
#>
param(
    # A riot2-system-<time> folder written by backup.ps1 or backup.sh.
    [Parameter(Mandatory = $true)] [string] $Path,
    # The same compose files as "docker compose -f"; default: docker compose's own default.
    [string[]] $ComposeFile = @(),
    # The same profiles as "docker compose --profile".
    [string[]] $ComposeProfile = @()
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path $Path).Path
Set-Location $PSScriptRoot

$helperImage = 'alpine:3.22'

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

$volumesFolder = Join-Path $source 'volumes'
if (-not (Test-Path $volumesFolder)) { throw "$source is not a backup folder (no volumes/)" }

if (-not (Test-Path .env) -and (Test-Path (Join-Path $source '.env'))) {
    Write-Host "Using the backup's .env"
    Copy-Item (Join-Path $source '.env') .env
}

$project = (Invoke-Compose @('config') | Where-Object { $_ -match '^name: *(.+)$' } | Select-Object -First 1) -replace '^name: *', ''
if (-not $project) { throw 'Could not read the compose project name' }
Write-Host "Restoring $source into compose project $project"

# Every archive is read through before anything changes, so a damaged backup stops here.
Write-Host 'Checking the archives'
Invoke-Native 'docker' @('run', '--rm', '-v', "${volumesFolder}:/backup:ro", $helperImage, 'sh', '-c',
    'for f in /backup/*.tar.gz; do [ -e $f ] || continue; tar -tzf $f > /dev/null || { echo $f is damaged >&2; exit 1; }; done') | Out-Null
$plugins = Join-Path $source 'plugins.tar.gz'
if (Test-Path $plugins) { Invoke-Native 'tar' @('-tzf', $plugins) | Out-Null }

Invoke-Compose @('down') | Out-Null

# Each archive is unpacked next to the old content first, which is replaced only when that worked.
# The volume's root folder takes the archive's owner and mode, which non-root services need.
$replace = 'rm -rf /data/.riot2-restore && mkdir /data/.riot2-restore && if tar -xzf /backup/$KEY.tar.gz -C /data/.riot2-restore; then find /data -mindepth 1 -maxdepth 1 ! -name .riot2-restore -exec rm -rf {} \; && find /data/.riot2-restore -mindepth 1 -maxdepth 1 -exec mv {} /data/ \; && chown $(stat -c %u:%g /data/.riot2-restore) /data && chmod $(stat -c %a /data/.riot2-restore) /data && rmdir /data/.riot2-restore; else rm -rf /data/.riot2-restore; exit 1; fi'

foreach ($archive in Get-ChildItem -Path $volumesFolder -Filter '*.tar.gz') {
    $key = $archive.Name -replace '\.tar\.gz$', ''
    $volume = "${project}_$key"
    Write-Host "Volume $volume"
    # The labels make the volume compose's own, as if "up" had created it.
    Invoke-Native 'docker' @('volume', 'create', '--label', "com.docker.compose.project=$project",
        '--label', "com.docker.compose.volume=$key", $volume) | Out-Null
    Invoke-Native 'docker' @('run', '--rm', '-v', "${volume}:/data", '-v', "${volumesFolder}:/backup:ro", '-e', "KEY=$key",
        $helperImage, 'sh', '-c', $replace) | Out-Null
}

if (Test-Path $plugins) {
    Write-Host 'plugins/'
    if (Test-Path plugins) { Remove-Item -Recurse -Force plugins }
    Invoke-Native 'tar' @('-xzf', $plugins) | Out-Null
}

Invoke-Compose @('up', '--detach', '--wait', '--wait-timeout', '180') | Out-Null

$influx = Join-Path $source 'influxdb'
if (Test-Path $influx) {
    if (@(Invoke-Compose @('config', '--services')) -contains 'influxdb') {
        Write-Host 'InfluxDB: influx restore --full'
        Invoke-Compose @('cp', $influx, 'influxdb:/tmp/riot2-restore') | Out-Null
        Invoke-Compose @('exec', '-T', 'influxdb', 'sh', '-c',
            'influx restore --full /tmp/riot2-restore -t $DOCKER_INFLUXDB_INIT_ADMIN_TOKEN > /dev/null && rm -rf /tmp/riot2-restore') | Out-Null
        # The connector and Grafana reconnect to the restored server.
        Invoke-Compose @('restart', 'influxdb-connector', 'grafana') | Out-Null
    }
    else {
        Write-Warning "The backup has InfluxDB data, but compose.influx.yml isn't in the compose files; skipped"
    }
}

Write-Host 'Done'
