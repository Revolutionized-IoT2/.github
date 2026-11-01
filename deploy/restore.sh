#!/usr/bin/env bash
# Restores a full-system backup made by backup.sh (design 7.4), on the same host or a clean one.
#
#   ./restore.sh [-f FILE]... [--profile NAME]... FOLDER
#
#   -f, --profile  The same compose files and profiles as "docker compose up".
#   FOLDER         A riot2-system-<time> folder written by backup.sh.
#
# The stack is taken down, every volume in the backup is emptied and filled from it, plugins/ is
# restored, and the stack is started again. .env is copied from the backup only when there is none
# here. With InfluxDB in the compose files, its data is then replaced with "influx restore --full".
set -euo pipefail

helper_image="alpine:3.22"

compose_args=()
source=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f | --file | --profile) compose_args+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
    -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "Unknown option $1; see $0 --help" >&2; exit 2 ;;
    *) source="$1"; shift ;;
  esac
done
[[ -n "$source" ]] || { echo "Which backup? $0 [-f FILE]... [--profile NAME]... FOLDER" >&2; exit 2; }
# Relative to the folder the script was started from.
source="$(cd "$source" && pwd)"
cd "$(dirname "$0")"
[[ -d "$source/volumes" ]] || { echo "$source is not a backup.sh folder (no volumes/)" >&2; exit 1; }

if [[ ! -f .env && -f "$source/.env" ]]; then
  echo "Using the backup's .env"
  cp "$source/.env" .env
  chmod 600 .env
fi

compose() { docker compose "${compose_args[@]}" "$@"; }

project="$(compose config | sed -n 's/^name: *//p' | head -n 1)"
[[ -n "$project" ]] || { echo "Could not read the compose project name" >&2; exit 1; }
echo "Restoring $source into compose project $project"

# Every archive is read through before anything changes, so a damaged backup stops here.
echo "Checking the archives"
# shellcheck disable=SC2016 # expanded in the container
docker run --rm -v "$source/volumes:/backup:ro" "$helper_image" \
  sh -c 'for f in /backup/*.tar.gz; do [ -e $f ] || continue; tar -tzf $f > /dev/null || { echo $f is damaged >&2; exit 1; }; done'
if [[ -f "$source/plugins.tar.gz" ]]; then tar -tzf "$source/plugins.tar.gz" > /dev/null; fi

compose down

# Each archive is unpacked next to the old content first, which is replaced only when that worked.
# The volume's root folder takes the archive's owner and mode, which non-root services need.
# shellcheck disable=SC2016 # expanded in the container
replace='rm -rf /data/.riot2-restore && mkdir /data/.riot2-restore && if tar -xzf /backup/$KEY.tar.gz -C /data/.riot2-restore; then find /data -mindepth 1 -maxdepth 1 ! -name .riot2-restore -exec rm -rf {} \; && find /data/.riot2-restore -mindepth 1 -maxdepth 1 -exec mv {} /data/ \; && chown $(stat -c %u:%g /data/.riot2-restore) /data && chmod $(stat -c %a /data/.riot2-restore) /data && rmdir /data/.riot2-restore; else rm -rf /data/.riot2-restore; exit 1; fi'

for archive in "$source"/volumes/*.tar.gz; do
  [[ -e "$archive" ]] || continue
  key="$(basename "$archive" .tar.gz)"
  volume="${project}_${key}"
  echo "Volume $volume"
  # The labels make the volume compose's own, as if "up" had created it.
  docker volume create --label "com.docker.compose.project=$project" --label "com.docker.compose.volume=$key" "$volume" > /dev/null
  docker run --rm -v "$volume:/data" -v "$source/volumes:/backup:ro" -e KEY="$key" "$helper_image" sh -c "$replace"
done

if [[ -f "$source/plugins.tar.gz" ]]; then
  echo "plugins/"
  rm -rf plugins
  tar -xzf "$source/plugins.tar.gz"
fi

compose up --detach --wait --wait-timeout 180

if [[ -d "$source/influxdb" ]]; then
  if compose config --services | grep -qx influxdb; then
    echo "InfluxDB: influx restore --full"
    compose cp "$source/influxdb" influxdb:/tmp/riot2-restore
    # shellcheck disable=SC2016 # expanded in the container, where the token is set
    compose exec -T influxdb sh -c 'influx restore --full /tmp/riot2-restore -t "$DOCKER_INFLUXDB_INIT_ADMIN_TOKEN" > /dev/null && rm -rf /tmp/riot2-restore'
    # The connector and Grafana reconnect to the restored server.
    compose restart influxdb-connector grafana
  else
    echo "The backup has InfluxDB data, but compose.influx.yml isn't in the compose files; skipped" >&2
  fi
fi

echo "Done"
