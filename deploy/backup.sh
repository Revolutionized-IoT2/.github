#!/usr/bin/env bash
# Full-system backup of a RIoT2 compose install (design 7.4): every data volume, the InfluxDB data,
# .env and plugins/. Run it from anywhere; it works on the compose files next to it.
#
#   ./backup.sh [-f FILE]... [--profile NAME]... [-o FOLDER]
#
#   -f, --profile  The same compose files and profiles as "docker compose up", for example
#                  ./backup.sh -f docker-compose.yml -f compose.influx.yml --profile node
#   -o             Where to write the backup folder; default: backups/ next to this script.
#
# The orchestrator, Elsa, the node, Grafana and Prometheus are stopped while their volumes are archived (a few
# seconds), so the SQLite files are consistent, then started again. InfluxDB keeps running: its
# data is copied with "influx backup". Log volumes are skipped. restore.sh restores the folder.
# The backup holds every secret of the install (.env, device credentials, Matter keys): keep it
# private.
set -euo pipefail

# A relative -o is relative to the folder the script was started from.
caller="$PWD"
cd "$(dirname "$0")"

# Pinned like the compose images; only tar and find are used.
helper_image="alpine:3.22"
# Volumes that are written while running and archived with their service stopped.
stopped_services="orchestrator elsa node grafana prometheus"

compose_args=()
output="backups"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --file | --profile) compose_args+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
    -o | --output) output="${2:?$1 needs a folder}"; [[ "$output" == /* ]] || output="$caller/$output"; shift 2 ;;
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option $1; see $0 --help" >&2; exit 2 ;;
  esac
done

compose() { docker compose "${compose_args[@]}" "$@"; }

project="$(compose config | sed -n 's/^name: *//p' | head -n 1)"
[[ -n "$project" ]] || { echo "Could not read the compose project name" >&2; exit 1; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$output"
target="$(cd "$output" && pwd)/riot2-system-$stamp"
mkdir -p "$target/volumes"
echo "Backing up compose project $project to $target"

running="$(compose ps --services --status running)"
stop=()
for service in $stopped_services; do
  if grep -qx "$service" <<< "$running"; then stop+=("$service"); fi
done

if grep -qx influxdb <<< "$running"; then
  echo "InfluxDB: influx backup"
  # shellcheck disable=SC2016 # expanded in the container, where the token is set
  compose exec -T influxdb sh -c 'rm -rf /tmp/riot2-backup && influx backup -t "$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN" /tmp/riot2-backup > /dev/null'
  compose cp influxdb:/tmp/riot2-backup "$target/influxdb"
  compose exec -T influxdb rm -rf /tmp/riot2-backup
fi

restart() {
  if [[ ${#stop[@]} -gt 0 ]]; then
    echo "Starting ${stop[*]}"
    compose start "${stop[@]}"
  fi
}
trap restart EXIT

if [[ ${#stop[@]} -gt 0 ]]; then
  echo "Stopping ${stop[*]}"
  compose stop "${stop[@]}"
fi

volumes=()
for key in $(compose config --volumes); do
  # Logs aren't state, and InfluxDB's data is in influxdb/ (its config is recreated on setup).
  if [[ "$key" == *-logs || "$key" == influxdb-* ]]; then continue; fi
  volume="${project}_${key}"
  if ! docker volume inspect "$volume" > /dev/null 2>&1; then continue; fi
  echo "Volume $volume"
  # As root, to read every file; the archive is then handed to the user running this script.
  # shellcheck disable=SC2016 # expanded in the container
  docker run --rm -v "$volume:/data:ro" -v "$target/volumes:/backup" -e OWNER="$(id -u):$(id -g)" -e KEY="$key" \
    "$helper_image" sh -c 'tar -czf "/backup/$KEY.tar.gz" -C /data . && chown "$OWNER" "/backup/$KEY.tar.gz"'
  volumes+=("$key")
done

trap - EXIT
restart

if [[ -f .env ]]; then cp .env "$target/.env"; chmod 600 "$target/.env"; fi
if [[ -d plugins ]]; then tar -czf "$target/plugins.tar.gz" plugins; fi

{
  echo "created: $stamp"
  echo "project: $project"
  echo "compose: ${compose_args[*]:-}"
  echo "volumes: ${volumes[*]:-}"
  echo "influxdb: $([[ -d "$target/influxdb" ]] && echo yes || echo no)"
  echo "images:"
  compose config --images | sed 's/^/  /'
} > "$target/backup.txt"

echo "Done: $target"
