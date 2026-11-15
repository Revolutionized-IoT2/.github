#!/usr/bin/env bash
# Creates deploy/.env from .env.example for a test run on a clean runner (deploy-check.yml and
# nightly-smoke.yml, design 7.4): the runner's address as RIOT2_HOST, random secrets for the
# required values, and with --observability the OTLP endpoint (exported every 5 s). Everything else
# keeps the documented default. Run it in deploy/:
#
#   bash ../tools/compose-smoke/env.sh [--observability]
#
# Prints RIOT2_HOST, and appends it to $GITHUB_ENV in GitHub Actions.
set -euo pipefail

host="$(hostname -I | awk '{print $1}')"
cp .env.example .env
set_var() { sed -i "s|^$1=.*|$1=$2|" .env; }
set_var RIOT2_HOST "$host"
set_var RIOT2_MQTT_PASSWORD "$(openssl rand -hex 16)"
set_var RIOT2_INFLUXDB_TOKEN "$(openssl rand -hex 32)"
set_var RIOT2_INFLUXDB_ADMIN_PASSWORD "$(openssl rand -hex 16)"
set_var RIOT2_GRAFANA_ADMIN_PASSWORD "$(openssl rand -hex 16)"
if [[ "${1:-}" == "--observability" ]]; then
  set_var OTEL_EXPORTER_OTLP_ENDPOINT http://otel-collector:4317
  set_var OTEL_METRIC_EXPORT_INTERVAL 5000
fi
mkdir -p plugins
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "RIOT2_HOST=$host" >> "$GITHUB_ENV"
fi
echo "RIOT2_HOST=$host"
