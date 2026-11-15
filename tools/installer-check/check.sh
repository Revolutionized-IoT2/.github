#!/usr/bin/env bash
# End-to-end check of deploy/install.sh and deploy/install.ps1 (ADR 0020) on a clean Docker host: it
# builds a throwaway site folder, installs it, and checks a re-run, the export, a reconfiguration, a
# restore that keeps the running Matter pairing, an upgrade, a refused downgrade, a fresh install with
# install.ps1, and a remote install from a "PC" (install.ps1 -RemoteHost, with ssh standing in to this
# machine). Run it in deploy/ on a Linux host with Docker, unzip and pwsh; deploy-check.yml does:
#
#   bash ../tools/installer-check/check.sh
#
# It removes the compose project riot2 with its volumes, .env and backups/ before and after: never run
# it next to an installation you want to keep.
set -euo pipefail

[[ -f install.sh ]] || { echo "Run it in deploy/" >&2; exit 2; }
tmp="${RUNNER_TEMP:-/tmp}/installer-check"
site="$tmp/site"
template_url="https://raw.githubusercontent.com/Revolutionized-IoT2/RIoT2.Elsa/master/templates/forecast-preheat.json"
helper="alpine:3.22"

fail() { echo "::error::$*"; exit 1; }
ok() { echo "ok: $*"; }
step() { echo; echo "######## $*"; }
clean() {
  docker compose --env-file "$tmp/plain.env" down --volumes --remove-orphans > /dev/null 2>&1 || true
  rm -rf .env .env.bak .riot2-install.json docker-compose.override.yml backups .install
  find grafana/site-dashboards -name '*.json' -delete
}
# Runs install.sh without a terminal, expecting exit code $1; its output is in $out.
expect() {
  local code=0
  out="$(./install.sh --site "$site" --host qnap "${@:2}" < /dev/null 2>&1)" || code=$?
  echo "$out"
  [[ "$code" == "$1" ]] || fail "install.sh ${*:2} exited with $code, not $1"
}
# put FILE PATH: FILE becomes hosts/qnap/PATH in the site; site_file PATH prints it.
put() { mkdir -p "$(dirname "$site/hosts/qnap/$2")"; cp "$1" "$site/hosts/qnap/$2"; }
site_file() { cat "$site/hosts/qnap/$1"; }
volume_file() { docker run --rm -v "riot2_$1:/v:ro" "$helper" cat "/v/$2"; }
volume_owner() { docker run --rm -v "riot2_$1:/v:ro" "$helper" stat -c %u "/v/$2"; }
write_volume_file() { docker run --rm -v "riot2_$1:/v" "$helper" sh -c "printf '%s' '$3' > /v/$2 && chown $4 /v/$2"; }
api() { curl -fsS "http://$host:8080/api/$1"; }
variable() {
  curl -fsS -X POST "http://$host:8080/api/nodes/variable/save" -H 'Content-Type: application/json' \
    -d "{\"id\":\"installer-check\",\"name\":\"installer-check\",\"description\":\"\",\"isPersistant\":true,\"type\":1,\"value\":\"$1\"}" > /dev/null
}
variable_is() { [[ "$(api nodes/variables)" == *"\"$1\""* ]]; }
backups() { find backups -maxdepth 1 -name 'riot2-system-*' 2> /dev/null | wc -l; }

step "A throwaway site folder"
rm -rf "$tmp"
mkdir -p "$tmp"
cp -r site-template "$site"
bash ../tools/compose-smoke/env.sh > /dev/null
{
  echo "COMPOSE_PATH_SEPARATOR=:"
  echo "COMPOSE_FILE=docker-compose.yml:compose.influx.yml"
  echo "COMPOSE_PROFILES=node"
  cat .env
} > "$tmp/plain.env"
rm .env
host="$(sed -n 's/^RIOT2_HOST=//p' "$tmp/plain.env")"
grafana_password="$(sed -n 's/^RIOT2_GRAFANA_ADMIN_PASSWORD=//p' "$tmp/plain.env")"
clean

put "$tmp/plain.env" deploy.env
cat > "$site/hosts/qnap/site.conf" << 'EOF'
PUBLISH_WORKFLOWS=auto
SEED_RULES="node-data/netatmoAuth-*.json=once node-data/service_account.json=managed orchestrator-matter/attestation/*=managed"
EOF
printf '{"client_email":"ci@example.invalid","v":1}' > "$tmp/account.json"
put "$tmp/account.json" volumes/node-data/service_account.json
printf '{"token":"from-site"}' > "$tmp/token.json"
put "$tmp/token.json" volumes/node-data/netatmoAuth-ci.json
head -c 64 /dev/urandom > "$tmp/dac.der"
put "$tmp/dac.der" volumes/orchestrator-matter/attestation/dac.der
curl -fsSL "$template_url" -o "$site/hosts/qnap/workflows/forecast-preheat.json"
printf '{"uid":"riot2-installer-check","title":"Installer check","panels":[],"schemaVersion":39}' \
  > "$site/hosts/qnap/grafana-dashboards/installer-check.json"

step "A file left encrypted is refused"
put "$tmp/token.json" volumes/node-data/netatmoAuth-other.sops.json
expect 2 --dry-run
[[ "$out" == *"looks encrypted with sops"* ]] || fail "an encrypted file isn't refused"
rm "$site/hosts/qnap/volumes/node-data/netatmoAuth-other.sops.json"
ok "refused, with the reason"

step "Dry run of a fresh install"
expect 0 --dry-run
[[ "$out" == *"riot2 on this host: fresh"* ]] || fail "no fresh verdict"
[[ ! -f .env && -z "$(docker volume ls -q --filter label=com.docker.compose.project=riot2)" ]] || fail "the dry run changed something"
ok "the dry run changes nothing"

step "Fresh install"
expect 0
cmp -s .env "$tmp/plain.env" || fail ".env isn't the site's deploy.env"
[[ "$(volume_file node-data service_account.json)" == *'"v":1'* ]] || fail "service_account.json isn't in node-data"
[[ "$(volume_file node-data netatmoAuth-ci.json)" == *from-site* ]] || fail "the token isn't in node-data"
[[ "$(volume_owner orchestrator-matter attestation/dac.der)" == 1654 && "$(volume_owner orchestrator-matter .)" == 1654 ]] \
  || fail "the orchestrator doesn't own its Matter files"
[[ "$(api workflows)" == *riot2-template-forecast-preheat* ]] || fail "the workflow wasn't imported"
curl -fsS -u "admin:$grafana_password" "http://$host:3000/api/dashboards/uid/riot2-installer-check" > /dev/null \
  || fail "Grafana has no site dashboard"
[[ -f .riot2-install.json ]] || fail "no install marker"
ok "settings, secret files and their owners, workflow, dashboard and marker"

step "A second run changes nothing"
expect 0
[[ "$out" == *"up to date"* ]] || fail "a second run isn't up to date"
ok "up to date"

step "Export"
variable exported
write_volume_file node-data netatmoAuth-ci.json '{"token":"rotated"}' 0:0
expect 0 --export
[[ -f "$site/hosts/qnap/configuration/riot2-backup.zip" ]] || fail "no configuration exported"
unzip -p "$site/hosts/qnap/configuration/riot2-backup.zip" StoredObjects/Variable/installer-check.json | grep -q exported \
  || fail "the export lacks the variable"
[[ "$(site_file volumes/node-data/netatmoAuth-ci.json)" == *rotated* ]] || fail "the renewed token wasn't exported"
[[ "$(site_file volumes/node-data/service_account.json)" == *'"v":1'* ]] || fail "a managed file was exported"
expect 0
[[ "$out" == *"up to date"* ]] || fail "after an export the site isn't up to date"
ok "configuration and renewed token exported; the site is up to date"

step "A changed site: reported, refused without an answer, then applied"
printf '{"client_email":"ci@example.invalid","v":2}' > "$tmp/account.json"
put "$tmp/account.json" volumes/node-data/service_account.json
expect 0
[[ "$out" == *"volumes/node-data/service_account.json (changed)"* && "$out" == *--reconfigure* ]] || fail "the change isn't reported"
[[ "$(volume_file node-data service_account.json)" == *'"v":1'* ]] || fail "a report changed the volume"
expect 2 --reconfigure
[[ "$out" == *"no terminal to ask about: secrets"* ]] || fail "a missing answer isn't explained"
expect 0 --reconfigure --secrets installer
[[ "$(volume_file node-data service_account.json)" == *'"v":2'* ]] || fail "the managed file wasn't replaced"
[[ "$(volume_file node-data netatmoAuth-ci.json)" == *rotated* ]] || fail "a once file was replaced"
[[ "$(backups)" -ge 1 ]] || fail "no backup before the change"
ok "managed file replaced, renewed token kept, backup taken"

step "A restore keeps the running Matter pairing"
write_volume_file orchestrator-matter fabrics.json 'live fabric' 1654:1654
variable after-export
expect 0 --reconfigure --config installer --workflows keep --no-export
variable_is exported || fail "the site's configuration wasn't restored"
[[ "$(volume_file orchestrator-matter fabrics.json)" == "live fabric" ]] || fail "the restore replaced the running pairing"
[[ "$(volume_owner orchestrator-matter attestation/dac.der)" == 1654 ]] || fail "the attestation file is gone"
ok "configuration restored; pairing and attestation kept"

step "An upgrade asks, keeps the settings and backs up"
printf 'services:\n  ui:\n    image: ghcr.io/revolutionized-iot2/riot2-ui:1.13.0\n' > "$tmp/older-ui.yml"
docker compose -f docker-compose.yml -f compose.influx.yml -f "$tmp/older-ui.yml" --profile node up -d --wait ui
sed 's/^RIOT2_LOG_LEVEL=.*/RIOT2_LOG_LEVEL=Debug/' "$tmp/plain.env" > "$tmp/debug.env"
put "$tmp/debug.env" deploy.env
before="$(backups)"
expect 2
[[ "$out" == *"1.13.0"*"upgrade"* && "$out" == *"no terminal to ask about: env"* ]] || fail "the upgrade isn't shown or asked"
expect 0 --keep-existing
grep -qx 'RIOT2_LOG_LEVEL=Information' .env || fail "--keep-existing replaced the settings"
[[ "$(backups)" -gt "$before" ]] || fail "no backup before the upgrade"
[[ "$(docker compose ps --format '{{.Image}}' ui)" != *:1.13.0 ]] || fail "the UI wasn't upgraded"
expect 0 --reconfigure --use-installer
grep -qx 'RIOT2_LOG_LEVEL=Debug' .env && [[ -f .env.bak ]] || fail "--use-installer didn't replace the settings"
ok "upgrade shown, settings kept, then replaced on request"

step "A downgrade needs --allow-downgrade"
current="$(docker compose ps --format '{{.Image}}' ui)"
docker tag "$current" ghcr.io/revolutionized-iot2/riot2-ui:999.0.0
printf 'services:\n  ui:\n    image: ghcr.io/revolutionized-iot2/riot2-ui:999.0.0\n' > "$tmp/newer-ui.yml"
docker compose -f docker-compose.yml -f compose.influx.yml -f "$tmp/newer-ui.yml" --profile node up -d --wait ui
expect 2
[[ "$out" == *DOWNGRADE* && "$out" == *--allow-downgrade* ]] || fail "the downgrade isn't refused"
ok "downgrade refused"

step "Fresh install with install.ps1"
clean
code=0
out="$(pwsh -NoProfile -NonInteractive -File install.ps1 -Site "$site" -HostName qnap 2>&1)" || code=$?
echo "$out"
[[ "$code" == 0 ]] || fail "install.ps1 exited with $code"
variable_is exported || fail "install.ps1 didn't restore the site's configuration"
[[ "$(volume_file node-data service_account.json)" == *'"v":2'* ]] || fail "install.ps1 didn't write the secret files"
[[ "$(volume_owner orchestrator-matter attestation/dac.der)" == 1654 ]] || fail "install.ps1 left the Matter files to root"
[[ "$(api workflows)" == *riot2-template-forecast-preheat* ]] || fail "install.ps1 didn't import the workflow"
out="$(RIOT2_SITE="$site" pwsh -NoProfile -NonInteractive -File install.ps1 -HostName qnap 2>&1)"
[[ "$out" == *"up to date"* ]] || { echo "$out"; fail "install.ps1 isn't up to date on a second run (site from RIOT2_SITE)"; }
ok "install.ps1 installs the same site, and a second run is up to date"

step "Remote install from a PC: install.ps1 -RemoteHost"
clean
# Stands in for ssh: runs the remote command on this machine, as the NAS would.
mkdir -p "$tmp/bin"
# shellcheck disable=SC2016 # the stand-in's own code
printf '%s\n' '#!/usr/bin/env bash' 'while [[ "${1:-}" == -* ]]; do if [[ "$1" == -o ]]; then shift; fi; shift; done' 'shift' 'exec bash -c "$*"' > "$tmp/bin/ssh"
chmod +x "$tmp/bin/ssh"
remote() {
  local code=0
  out="$(PATH="$tmp/bin:$PATH" pwsh -NoProfile -NonInteractive -File install.ps1 -Site "$site" -HostName qnap \
    -RemoteHost nas -RemoteDeploy "$PWD" "$@" 2>&1)" || code=$?
  echo "$out"
  [[ "$code" == 0 ]] || fail "install.ps1 -RemoteHost $* exited with $code"
  [[ ! -e .install-site && ! -e .install-export ]] || fail "the site's files were left on the host"
}
remote
variable_is exported || fail "the remote install didn't restore the site's configuration"
[[ "$(volume_file node-data service_account.json)" == *'"v":2'* ]] || fail "the remote install didn't write the secret files"
remote
[[ "$out" == *"up to date"* ]] || fail "a second remote run isn't up to date"
write_volume_file node-data netatmoAuth-ci.json '{"token":"rotated-again"}' 0:0
remote -Export
[[ "$out" == *"wrote hosts/qnap/volumes/node-data/netatmoAuth-ci.json"* ]] || fail "the remote export wasn't written on the PC"
[[ "$(site_file volumes/node-data/netatmoAuth-ci.json)" == *rotated-again* ]] || fail "the remote export lacks the token"
ok "installed, up to date and exported from a PC; nothing left on the host"

clean
echo
echo "The installer check passed."
