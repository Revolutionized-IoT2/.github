#!/usr/bin/env bash
# Installs, upgrades or reconfigures RIoT2 on this host from a site folder (ADR 0020): the host's
# settings (.env), secret files in the volumes, the orchestrator's configuration, the workflows,
# Grafana dashboards and the node's plugins. Guide: docs/guides/site-configuration.md. Run it on the
# Docker host itself, from anywhere; it works on the compose files next to it. It needs only Docker and
# bash: the installer's logic (installer/riot2site.py) runs in a pinned container. The site's files are
# plain files; keeping them private (and encrypting them, if you want) is up to you.
#
#   ./install.sh --site DIR --host NAME [options]
#   ./install.sh --plain DIR --host NAME [options]
#
#   --site DIR               The site folder; hosts/NAME/ in it is this host's folder. Exports are written
#                            into that folder.
#   --host NAME              This host's folder name.
#   --plain DIR              Instead of --site: the host's folder itself, as install.ps1 -RemoteHost copies it
#                            from a PC. Exports go to .install-export/ here for the PC to fetch. DIR is deleted
#                            at the end when it is .install-site/ here.
#   --site-commit SHA        With --plain: the site's commit, if it's a git repository, for the install marker.
#   --dry-run                Show what would happen, and change nothing.
#   --reconfigure            The same versions are installed: apply what changed in the site.
#   --keep-existing          Answer "keep" for every category below.
#   --use-installer          Answer "use the installer's" for every category below.
#   --env keep|installer     The installed .env (keep adds only the site's new keys).
#   --secrets keep|installer Secret files in the volumes: the "managed" ones ("once" ones stay).
#   --config keep|installer  The orchestrator's configuration (a restore of the site's backup).
#   --workflows keep|installer  The workflows (installer imports every one, as a new version).
#   --allow-downgrade        Install older images than the running ones (after a backup).
#   --overwrite-once         Replace "once" files too (renewed tokens: the site's copy may be stale).
#   --replace-matter         Restore the site's Matter pairing instead of keeping the running one.
#   --no-export              Before an upgrade, don't export the running installation into the site.
#   --export                 Only export the running configuration, workflows and tokens into the site.
#   --export-managed         With --export, also export "managed" secret files.
#
# Exit codes: 0 done, or already up to date; 1 failed; 2 invalid input, or a question needs an answer
# (without a terminal, give --keep-existing, --use-installer or the category options).
set -euo pipefail

caller="$PWD"
cd "$(dirname "$0")"
deploy="$PWD"

installer_version=1
# Pinned like the compose images: it runs installer/riot2site.py.
python_image="${RIOT2_INSTALLER_PYTHON_IMAGE:-python:3.14-alpine3.23}"
config_zip="configuration/riot2-backup.zip"

die() { echo "ERROR: $*" >&2; exit 1; }
invalid() { echo "ERROR: $*" >&2; exit 2; }
note() { echo "  $*"; }
step() { echo; echo "== $*"; }

# ------------------------------------------------------------------------------------------- options
site=""
host=""
plain=""
site_commit=""
dry_run=""
reconfigure=""
allow_downgrade=""
overwrite_once=""
replace_matter=""
no_export=""
export_only=""
export_managed=""
answer_env=""
answer_secrets=""
answer_config=""
answer_workflows=""

while [[ $# -gt 0 ]]; do
  option="$1"
  shift
  value=""
  inline=""
  case "$option" in --*=*) value="${option#*=}"; option="${option%%=*}"; inline=1 ;; esac
  case "$option" in
    --site | --host | --plain | --site-commit | --env | --secrets | --config | --workflows)
      if [[ -z "$inline" ]]; then
        [[ $# -gt 0 ]] || invalid "$option needs a value; see $0 --help"
        value="$1"
        shift
      fi
      ;;
    *) [[ -z "$inline" ]] || invalid "$option takes no value" ;;
  esac
  case "$option" in
    --env | --secrets | --config | --workflows)
      case "$value" in keep | installer) ;; *) invalid "$option needs keep or installer, not '$value'" ;; esac ;;
  esac
  case "$option" in
    --site) [[ "$value" == /* ]] || value="$caller/$value"; site="$value" ;;
    --host) host="$value" ;;
    --plain) [[ "$value" == /* ]] || value="$caller/$value"; plain="$value" ;;
    --site-commit) site_commit="$value" ;;
    --env) answer_env="$value" ;;
    --secrets) answer_secrets="$value" ;;
    --config) answer_config="$value" ;;
    --workflows) answer_workflows="$value" ;;
    --dry-run) dry_run=1 ;;
    --reconfigure) reconfigure=1 ;;
    --keep-existing) answer_env=keep; answer_secrets=keep; answer_config=keep; answer_workflows=keep ;;
    --use-installer) answer_env=installer; answer_secrets=installer; answer_config=installer; answer_workflows=installer ;;
    --allow-downgrade) allow_downgrade=1 ;;
    --overwrite-once) overwrite_once=1 ;;
    --replace-matter) replace_matter=1 ;;
    --no-export) no_export=1 ;;
    --export) export_only=1 ;;
    --export-managed) export_managed=1 ;;
    -h | --help) sed -n '2,35p' "$0"; exit 0 ;;
    *) invalid "unknown option $option; see $0 --help" ;;
  esac
done

re_name='^[A-Za-z0-9][A-Za-z0-9_.-]*$'
[[ -n "$host" && "$host" =~ $re_name ]] || invalid "--host must be a folder name; see $0 --help"
if [[ -n "$plain" ]]; then
  [[ -z "$site" ]] || invalid "give --site or --plain, not both"
  [[ -d "$plain" ]] || invalid "$plain is not a folder"
  host_dir="$(cd "$plain" && pwd)"
  export_dir="$deploy/.install-export"
  # Only the PC's upload folder is deleted afterwards, never a folder given for something else.
  remove_plain=""
  if [[ "$host_dir" == "$deploy/.install-site" ]]; then remove_plain=1; fi
else
  [[ -n "$site" ]] || invalid "--site or --plain is required; see $0 --help"
  [[ -d "$site" ]] || invalid "$site is not a folder"
  site="$(cd "$site" && pwd)"
  host_dir="$site/hosts/$host"
  [[ -d "$host_dir" ]] || invalid "$host_dir doesn't exist"
fi

# Compose must read the site's settings, not the caller's environment.
unset COMPOSE_FILE COMPOSE_PROFILES COMPOSE_ENV_FILES COMPOSE_PROJECT_NAME

# ------------------------------------------------------------------------------------------- preflight
if ! command -v docker > /dev/null; then
  # QNAP Container Station keeps its tools here, outside an SSH session's PATH.
  for dir in /share/*/.qpkg/container-station/bin; do
    if [[ -x "$dir/docker" ]]; then PATH="$dir:$PATH"; break; fi
  done
fi
command -v docker > /dev/null || die "docker is not installed or not on PATH"
version_ge() {
  local IFS=.
  # shellcheck disable=SC2206 # split on the dots
  local -a a=($1) b=($2)
  local i
  for i in 0 1 2; do
    if ((${a[i]:-0} != ${b[i]:-0})); then
      ((${a[i]:-0} > ${b[i]:-0}))
      return
    fi
  done
}
compose_version="$(docker compose version --short 2> /dev/null || true)"
compose_version="${compose_version#v}"
compose_version="${compose_version%%-*}"
if [[ -z "$compose_version" ]] || ! version_ge "$compose_version" 2.24.0; then
  die "Docker Compose 2.24 or later is needed (found: ${compose_version:-none})"
fi

work="$deploy/.install"
rm -rf "$work"
mkdir -p "$work/site" "$work/export"
chmod 700 "$work"
backup_dir=""
cleanup() {
  rm -rf "$work"
  if [[ -n "$plain" && -n "$remove_plain" ]]; then rm -rf "$host_dir"; fi
}
trap cleanup EXIT
# A dropped SSH session must still delete the copied site.
trap 'exit 129' HUP INT TERM
if [[ -n "$plain" ]]; then
  rm -rf "$export_dir"
  mkdir -p "$export_dir"
  chmod 700 "$export_dir"
fi
on_error() {
  echo "ERROR: the installer stopped (line $1)." >&2
  if [[ -n "$backup_dir" ]]; then
    echo "The installation was backed up first; to go back to it:" >&2
    echo "  bash $deploy/restore.sh $backup_dir" >&2
  fi
}
trap 'on_error $LINENO' ERR

user_args=()
if [[ "$(id -u)" != 0 ]]; then user_args=(--user "$(id -u):$(id -g)"); fi

# riot2site.py in the Python image. py: paths under /work; py_net: on the project's network, where the
# orchestrator is http://orchestrator:8080; py_root: as root, with the mounts given before "--".
py() {
  docker run --rm ${user_args[@]+"${user_args[@]}"} -v "$deploy/installer:/installer:ro" -v "$work:/work" -w /work \
    "$python_image" python /installer/riot2site.py "$@"
}
py_net() {
  docker run --rm ${user_args[@]+"${user_args[@]}"} --network "$network" -v "$deploy/installer:/installer:ro" \
    -v "$work:/work" -w /work "$python_image" python /installer/riot2site.py "$@"
}
py_root() {
  local -a mounts=()
  while [[ "$1" != "--" ]]; do
    mounts+=(-v "$1")
    shift
  done
  shift
  docker run --rm -v "$deploy/installer:/installer:ro" "${mounts[@]}" "$python_image" python /installer/riot2site.py "$@"
}
# py_mounts: as the calling user, with /work and the mounts given before "--".
py_mounts() {
  local -a mounts=()
  while [[ "$1" != "--" ]]; do
    mounts+=(-v "$1")
    shift
  done
  shift
  docker run --rm ${user_args[@]+"${user_args[@]}"} -v "$deploy/installer:/installer:ro" -v "$work:/work" -w /work \
    "${mounts[@]}" "$python_image" python /installer/riot2site.py "$@"
}
pull_once() { docker image inspect "$1" > /dev/null 2>&1 || docker pull -q "$1" > /dev/null; }

list_site() { (cd "$host_dir" && find . -type f ! -path './.git/*' | sed 's|^\./||' | sort); }

# ------------------------------------------------------------------------------------------- read the site
step "Reading the site: $host_dir"
pull_once "$python_image"
re_sops='\.sops(\.[^./]+)?$'
: > "$work/names.txt"
while IFS= read -r rel; do
  # An encrypted file would be installed as it is: the installer takes plain files only.
  [[ ! "$rel" =~ $re_sops ]] || invalid "$rel looks encrypted with sops; put the decrypted file in the site instead"
  mkdir -p "$work/site/$(dirname "$rel")"
  cp "$host_dir/$rel" "$work/site/$rel"
  echo "$rel" >> "$work/names.txt"
done < <(list_site)
[[ -f "$work/site/deploy.env" ]] || invalid "$host_dir/deploy.env is missing"
note "$(wc -l < "$work/names.txt" | tr -d ' ') files"

# site.conf: KEY=value lines, the value optionally in quotes.
conf_PLUGIN_URL=""
conf_PLUGIN_SHA256=""
conf_PUBLISH_WORKFLOWS="auto"
conf_SEED_RULES=""
conf_VOLUME_OWNERS=""
conf_LAN_DRIVER=""
conf_LAN_PARENT=""
conf_LAN_SUBNET=""
conf_LAN_GATEWAY=""
conf_LAN_IP_RANGE=""
conf_LAN_IPV6_SUBNET=""
conf_LAN_IPV6_GATEWAY=""
re_blank='^[[:space:]]*(#.*)?$'
re_setting='^([A-Z0-9_]+)=(.*)$'
re_double='^"(.*)"$'
re_single="^'(.*)'$"
unquote() {
  if [[ "$1" =~ $re_double || "$1" =~ $re_single ]]; then echo "${BASH_REMATCH[1]}"; else echo "$1"; fi
}
if [[ -f "$work/site/site.conf" ]]; then
  n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    [[ "$line" =~ $re_blank ]] && continue
    [[ "$line" =~ $re_setting ]] || invalid "site.conf line $n: expected KEY=value"
    key="${BASH_REMATCH[1]}"
    case "$key" in
      PLUGIN_URL | PLUGIN_SHA256 | PUBLISH_WORKFLOWS | SEED_RULES | VOLUME_OWNERS | LAN_DRIVER | LAN_PARENT | LAN_SUBNET | \
        LAN_GATEWAY | LAN_IP_RANGE | LAN_IPV6_SUBNET | LAN_IPV6_GATEWAY)
        printf -v "conf_$key" '%s' "$(unquote "${BASH_REMATCH[2]}")" ;;
      *) invalid "site.conf line $n: unknown setting $key" ;;
    esac
  done < "$work/site/site.conf"
fi
case "$conf_PUBLISH_WORKFLOWS" in auto | true | false) ;; *) invalid "site.conf: PUBLISH_WORKFLOWS must be auto, true or false" ;; esac
case "$conf_LAN_DRIVER" in "" | qnet | macvlan) ;; *) invalid "site.conf: LAN_DRIVER must be qnet, macvlan or empty" ;; esac
if [[ "$conf_LAN_DRIVER" == qnet && -n "$conf_LAN_IP_RANGE" ]]; then
  note "site.conf: qnet hands out no address range, so LAN_IP_RANGE is ignored"
fi
plugin_id="$conf_PLUGIN_URL${conf_PLUGIN_SHA256:+ $conf_PLUGIN_SHA256}"

# A value of an env file (the last one wins, quotes removed): env_value FILE KEY [DEFAULT].
env_value() {
  local line value=""
  line="$(grep -E "^[[:space:]]*$2=" "$1" 2> /dev/null | tail -n 1 || true)"
  [[ -z "$line" ]] || value="$(unquote "${line#*=}")"
  echo "${value:-${3:-}}"
}

# ------------------------------------------------------------------------------------------- the installed state
site_compose() { docker compose --env-file "$work/site/deploy.env" "$@"; }
compose() { docker compose "$@"; }

site_compose config --format json > "$work/expected.json" \
  || invalid "the compose files don't accept the site's deploy.env (the message above names the variable)"
project="$(site_compose config | sed -n 's/^name: *//p' | head -n 1 || true)"
[[ -n "$project" ]] || die "could not read the compose project name"
network="${project}_default"
has_orchestrator=""
if grep -q '"orchestrator": *{' "$work/expected.json"; then has_orchestrator=1; fi

py rules --rules "$conf_SEED_RULES" --owners "$conf_VOLUME_OWNERS" --seeds /work/site/volumes \
  --expected /work/expected.json > "$work/rules.txt" || invalid "the secret files or SEED_RULES are invalid (above)"
sed -n 's/^note /  Note: /p' "$work/rules.txt"
# The volumes the site has files for: "volume <name> <docker name> <owner>".
seed_volume_lines() { grep '^volume ' "$work/rules.txt" | grep -v ' rule-only$' || true; }

: > "$work/running.txt"
while IFS= read -r id; do
  docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}} {{.Config.Image}} {{.State.Status}}' "$id" \
    >> "$work/running.txt"
done < <(docker ps -aq --filter "label=com.docker.compose.project=$project")
docker volume ls -q --filter "label=com.docker.compose.project=$project" > "$work/volumes.txt"
marker_args=()
if [[ -f "$deploy/.riot2-install.json" ]]; then
  cp "$deploy/.riot2-install.json" "$work/marker.json"
  marker_args=(--marker /work/marker.json)
fi
orchestrator_running=""
if grep -q '^orchestrator .* running$' "$work/running.txt"; then orchestrator_running=1; fi

py versions --running /work/running.txt --expected /work/expected.json --volumes /work/volumes.txt \
  ${marker_args[@]+"${marker_args[@]}"} > "$work/versions.txt"
verdict="$(sed -n 's/^verdict //p' "$work/versions.txt")"
py diff --site /work/site --plugin "$plugin_id" ${marker_args[@]+"${marker_args[@]}"} > "$work/diff.txt"
changed="$(sed -n 's/^changed //p' "$work/diff.txt")"

step "Compose project $project on this host: $verdict"
grep -v '^verdict ' "$work/versions.txt" || true

show_changes() { sed -n 's/^item \([^ ]*\) \([^ ]*\) \(.*\)$/  \1: \2 (\3)/p' "$work/diff.txt"; }
category_changed() { grep -q "^item $1 " "$work/diff.txt"; }
has_site() { [[ -e "$work/site/$1" ]]; }
workflow_files_exist() { compgen -G "$work/site/workflows/*.json" > /dev/null; }

# ------------------------------------------------------------------------------------------- export
# Exports the running installation into $work/export, then writes each file into the site's host folder
# (with --plain, into .install-export/ for the PC) and into $work/site.
# $1: all, or unchanged (only site files that didn't change since the last install, and new files).
export_site() {
  local scope="$1" rel destination volume name owner
  local -a exported=() allowed_args=() site_zip=() site_workflows=() managed_args=()
  rm -rf "$work/export"
  mkdir -p "$work/export"
  if [[ "$scope" == unchanged ]]; then
    : > "$work/allowed.txt"
    while IFS= read -r rel; do
      grep -q "^item [^ ]* $rel " "$work/diff.txt" || echo "$rel" >> "$work/allowed.txt"
    done < "$work/names.txt"
    allowed_args=(--allowed /work/allowed.txt)
  fi
  if [[ -n "$has_orchestrator" && -n "$orchestrator_running" ]]; then
    py_net api-wait --timeout 60
    if ! has_site "$config_zip" || [[ "$scope" == all ]] || grep -qx "$config_zip" "$work/allowed.txt"; then
      if has_site "$config_zip"; then site_zip=(--site "/work/site/$config_zip"); fi
      py_net api-export-config --out "/work/export/$config_zip" ${site_zip[@]+"${site_zip[@]}"} > /dev/null
    else
      note "skip $config_zip changed-in-site"
    fi
    if [[ -d "$work/site/workflows" ]]; then site_workflows=(--site-dir /work/site/workflows); fi
    py_net api-workflows-export --out /work/export ${site_workflows[@]+"${site_workflows[@]}"} \
      ${allowed_args[@]+"${allowed_args[@]}"} > "$work/exported.txt"
    sed -n 's/^skip /  skip /p' "$work/exported.txt"
  elif [[ -n "$has_orchestrator" ]]; then
    note "The orchestrator isn't running: its configuration and workflows aren't exported"
  fi
  if [[ -n "$export_managed" ]]; then managed_args=(--managed); fi
  while read -r _ volume name owner _; do
    docker volume inspect "$name" > /dev/null 2>&1 || continue
    mkdir -p "$work/site/volumes/$volume"
    py_root "$work:/work" "$name:/v:ro" -- export-seeds --volume "$volume" --volume-dir /v \
      --seed-dir "/work/site/volumes/$volume" --out /work/export --rules "$conf_SEED_RULES" --chown "$(id -u):$(id -g)" \
      ${allowed_args[@]+"${allowed_args[@]}"} ${managed_args[@]+"${managed_args[@]}"} > "$work/exported.txt"
    sed -n 's/^skip /  skip /p' "$work/exported.txt"
  done < <(grep '^volume ' "$work/rules.txt" || true)

  destination="$host_dir"
  if [[ -n "$plain" ]]; then destination="$export_dir"; fi
  while IFS= read -r rel; do
    mkdir -p "$destination/$(dirname "$rel")" "$work/site/$(dirname "$rel")"
    cp "$work/export/$rel" "$destination/$rel"
    cp "$work/export/$rel" "$work/site/$rel"
    grep -qx "$rel" "$work/names.txt" || echo "$rel" >> "$work/names.txt"
    exported+=("$rel")
    note "exported $rel"
  done < <(cd "$work/export" && find . -type f | sed 's|^\./||' | sort)

  if [[ ${#exported[@]} -eq 0 ]]; then
    note "the site already matches the running installation"
    return 0
  fi
  if [[ -f "$work/marker.json" ]]; then
    py marker-update --marker /work/marker.json --site /work/site "${exported[@]}"
    cp "$work/marker.json" "$deploy/.riot2-install.json"
  fi
  if [[ -z "$plain" ]]; then note "The site's files changed: $host_dir"; fi
}

if [[ -n "$export_only" ]]; then
  step "Exporting the running installation into the site"
  if [[ -n "$dry_run" ]]; then
    echo "Dry run: nothing was exported."
    exit 0
  fi
  export_site all
  exit 0
fi

# ------------------------------------------------------------------------------------------- what to do
mode=update
case "$verdict" in
  fresh) mode=fresh ;;
  same)
    if [[ -z "$reconfigure" ]]; then
      if [[ "$changed" == 0 ]]; then
        echo "RIoT2 is installed and up to date; the site hasn't changed since the last install."
      else
        echo "The same versions are installed, but the site changed since the last install:"
        show_changes
        echo "Nothing was changed. To apply them, run again with --reconfigure (it asks what to keep)."
      fi
      exit 0
    fi
    ;;
  leftover)
    echo "These volumes will be used as they are. For a clean installation stop here and remove them with"
    echo "docker volume rm; otherwise the installer backs them up first and asks what to keep."
    ;;
  downgrade)
    echo "WARNING: the installer's images are older than the running ones. An older version may not read"
    echo "data that a newer one wrote; the safe way back is restore.sh with a backup made by that version."
    if [[ -z "$allow_downgrade" && -z "$dry_run" ]]; then
      [[ -t 0 ]] || invalid "a downgrade needs --allow-downgrade"
      read -r -p "Downgrade anyway? [y/N] " reply < /dev/tty
      [[ "$reply" == y || "$reply" == Y ]] || { echo "Nothing was changed."; exit 1; }
    fi
    ;;
esac

export_before=""
if [[ "$mode" == fresh ]]; then
  answer_env=installer
  answer_secrets=installer
  answer_config=installer
  answer_workflows=installer
else
  if [[ "$changed" != 0 ]]; then
    echo "The site changed since the last install:"
    show_changes
  fi
  if [[ -z "$no_export" ]]; then export_before=1; fi
fi

# What the seeding would do to each volume, as a dry run: seed_plan keep|installer.
seed_plan() {
  local volume name owner
  local -a once_args=()
  if [[ -n "$overwrite_once" ]]; then once_args=(--overwrite-once); fi
  : > "$work/seed-$1.txt"
  while read -r _ volume name owner; do
    if docker volume inspect "$name" > /dev/null 2>&1; then
      py_root "$work/site/volumes/$volume:/seed:ro" "$name:/v:ro" -- seed --volume "$volume" --volume-dir /v \
        --seed-dir /seed --owner "$owner" --rules "$conf_SEED_RULES" --mode "$1" --dry-run \
        ${once_args[@]+"${once_args[@]}"} >> "$work/seed-$1.txt"
    else
      sed -n "s|^seed $volume \([^ ]*\) \([^ ]*\) .*|write $volume/\1 \2|p" "$work/rules.txt" >> "$work/seed-$1.txt"
    fi
  done < <(seed_volume_lines)
}
words() { tr '\n' ' ' | sed 's/ *$//; s/ /, /g'; }

questions=()
if [[ "$mode" == update ]]; then
  if [[ -f "$deploy/.env" ]]; then
    cp "$deploy/.env" "$work/installed.env"
    py env-diff --existing /work/installed.env --site /work/site/deploy.env > "$work/env-diff.txt"
    if [[ -s "$work/env-diff.txt" ]]; then questions+=(env); fi
  fi
  seed_plan keep
  seed_plan installer
  cmp -s "$work/seed-keep.txt" "$work/seed-installer.txt" || questions+=(secrets)
  if [[ -n "$has_orchestrator" ]] && has_site "$config_zip" && { [[ -z "$export_before" ]] || category_changed configuration; }; then
    questions+=(config)
  fi
  if [[ -n "$has_orchestrator" ]] && workflow_files_exist && { [[ -z "$export_before" ]] || category_changed workflows; }; then
    questions+=(workflows)
  fi
fi

describe() {
  case "$1" in
    env) echo "Settings: deploy/.env and the site's deploy.env differ in $(awk '{print $2}' "$work/env-diff.txt" | words)." ;;
    secrets) echo "Secret files: the site's managed files differ from the volumes': $(grep '^write ' "$work/seed-installer.txt" | awk '{print $2}' | words)." ;;
    config) echo "Orchestrator configuration: the site's backup would replace the running nodes, devices, dashboards and variables." ;;
    workflows) echo "Workflows: the site's workflows would be imported as new versions of the running ones." ;;
  esac
}
missing=()
for category in ${questions[@]+"${questions[@]}"}; do
  var="answer_$category"
  [[ -z "${!var}" ]] || continue
  if [[ -n "$dry_run" ]]; then
    continue
  elif [[ -t 0 ]]; then
    echo
    describe "$category"
    read -r -p "Do you want to keep existing configurations, or do you want to use configuration from installer? [K]eep/[u]se installer: " reply < /dev/tty
    case "$reply" in u | U | use | installer) printf -v "$var" installer ;; *) printf -v "$var" keep ;; esac
  else
    missing+=("$category")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  for category in "${missing[@]}"; do describe "$category" >&2; done
  invalid "no terminal to ask about: ${missing[*]}. Give --keep-existing, --use-installer, or --env/--secrets/--config/--workflows keep|installer"
fi
# A category nobody was asked about is kept.
for category in env secrets config workflows; do
  var="answer_$category"
  [[ -n "${!var}" ]] || printf -v "$var" keep
done

# The LAN network: create (missing), remake (a qnet network without QNAP's IPAM driver, on which no
# container starts: "cannot find IPAM config by mac address") or keep.
lan_network=""
lan_action=""
if [[ -n "$conf_LAN_DRIVER" ]]; then
  lan_network="$(env_value "$work/site/deploy.env" RIOT2_LAN_NETWORK riot2-lan)"
  lan_action=keep
  if ! docker network inspect "$lan_network" > /dev/null 2>&1; then
    lan_action=create
  else
    driver="$(docker network inspect --format '{{.Driver}}' "$lan_network")"
    if [[ "$driver" != "$conf_LAN_DRIVER" ]]; then
      note "WARNING: the network $lan_network uses $driver, not $conf_LAN_DRIVER"
    elif [[ "$driver" == qnet && "$(docker network inspect --format '{{.IPAM.Driver}}' "$lan_network")" != qnet ]]; then
      lan_action=remake
      [[ "$(docker network inspect --format '{{len .Containers}}' "$lan_network")" == 0 ]] \
        || invalid "the qnet network $lan_network lacks the qnet IPAM driver, but containers run on it: stop them, run 'docker network rm $lan_network' and install again"
      while read -r id; do
        [[ -n "$id" ]] || continue
        [[ "$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$id")" == "$project" ]] \
          || invalid "the qnet network $lan_network lacks the qnet IPAM driver, and container $(docker inspect --format '{{.Name}}' "$id") of another project uses it: remove it, run 'docker network rm $lan_network' and install again"
      done < <(docker ps -aq --filter "network=$lan_network")
    fi
  fi
fi

if [[ -n "$dry_run" ]]; then
  step "Dry run: what the installer would do"
  if [[ -n "$export_before" ]]; then note "export the running configuration, workflows and renewed tokens into the site"; fi
  if [[ "$mode" == update ]]; then note "back up the installation with backup.sh into $deploy/backups"; fi
  case "$lan_action" in
    create) note "create the $conf_LAN_DRIVER network $lan_network" ;;
    remake) note "make the qnet network $lan_network again, with the qnet IPAM driver (removing this project's stopped containers on it)" ;;
  esac
  if [[ "$mode" == fresh || "$answer_env" == installer || ! -f "$deploy/.env" ]]; then
    note "settings: write the site's deploy.env as deploy/.env"
  else
    note "settings: keep deploy/.env, adding the keys only the site has"
  fi
  if [[ -n "$conf_PLUGIN_URL" ]]; then note "plugins: install ${conf_PLUGIN_URL##*/} unless it's installed"; fi
  if [[ ! -s "$work/seed-$answer_secrets.txt" ]]; then seed_plan "$answer_secrets"; fi
  sed 's/^/  secret file: /' "$work/seed-$answer_secrets.txt"
  note "docker compose pull, then up -d --wait"
  if [[ -n "$has_orchestrator" ]] && has_site "$config_zip"; then
    if [[ "$answer_config" == installer ]]; then
      note "configuration: restore the site's backup$([[ -n "$replace_matter" ]] || echo ", keeping the running Matter pairing")"
    else
      note "configuration: keep the running one"
    fi
  fi
  if [[ -n "$has_orchestrator" ]] && workflow_files_exist; then
    note "workflows: import $([[ "$answer_workflows" == installer && "$mode" != fresh ]] && echo "every one" || echo "the missing ones")"
  fi
  echo
  echo "Dry run: nothing was changed. Categories nobody answered are shown as keep."
  exit 0
fi

# ------------------------------------------------------------------------------------------- export and backup
if [[ -n "$export_before" ]]; then
  step "Exporting the running installation into the site first"
  export_site unchanged
fi

if [[ "$mode" == update ]]; then
  step "Backing up the installation"
  if [[ ! -f "$deploy/.env" ]]; then
    cp "$work/site/deploy.env" "$deploy/.env"
    chmod 600 "$deploy/.env"
    note "deploy/.env was missing: wrote the site's, which backup.sh needs"
  fi
  # Through bash: a checkout on an SMB share (a NAS) has no executable bits.
  bash "$deploy/backup.sh" -o "$deploy/backups" | tee "$work/backup.log"
  backup_dir="$(sed -n 's/^Done: //p' "$work/backup.log")"
fi

# ------------------------------------------------------------------------------------------- apply
if [[ "$lan_action" == remake ]]; then
  step "Making the qnet network $lan_network again, with the qnet IPAM driver"
  while read -r id; do
    [[ -n "$id" ]] || continue
    note "removing the stopped container $(docker inspect --format '{{.Name}}' "$id"); compose creates it again"
    docker rm "$id" > /dev/null
  done < <(docker ps -aq --filter "network=$lan_network")
  docker network rm "$lan_network" > /dev/null
  lan_action=create
fi
if [[ "$lan_action" == create ]]; then
  step "Creating the $conf_LAN_DRIVER network $lan_network"
  [[ -n "$conf_LAN_PARENT" && -n "$conf_LAN_SUBNET" && -n "$conf_LAN_GATEWAY" ]] \
    || invalid "site.conf: LAN_DRIVER needs LAN_PARENT, LAN_SUBNET and LAN_GATEWAY"
  net_args=(network create -d "$conf_LAN_DRIVER" --subnet "$conf_LAN_SUBNET" --gateway "$conf_LAN_GATEWAY")
  if [[ "$conf_LAN_DRIVER" == qnet ]]; then
    # QNAP's driver needs its own IPAM driver too, and has no --ip-range.
    net_args+=(--opt "iface=$conf_LAN_PARENT" --ipam-driver qnet --ipam-opt "iface=$conf_LAN_PARENT")
  else
    net_args+=(--opt "parent=$conf_LAN_PARENT")
    if [[ -n "$conf_LAN_IP_RANGE" ]]; then net_args+=(--ip-range "$conf_LAN_IP_RANGE"); fi
  fi
  if [[ -n "$conf_LAN_IPV6_SUBNET" ]]; then
    net_args+=(--ipv6 --subnet "$conf_LAN_IPV6_SUBNET")
    if [[ -n "$conf_LAN_IPV6_GATEWAY" ]]; then net_args+=(--gateway "$conf_LAN_IPV6_GATEWAY"); fi
  fi
  docker "${net_args[@]}" "$lan_network" > /dev/null
  note "docker ${net_args[*]} $lan_network"
fi

step "Settings"
if [[ ! -f "$deploy/.env" ]] || [[ "$mode" == fresh || "$answer_env" == installer ]] && ! cmp -s "$deploy/.env" "$work/site/deploy.env"; then
  if [[ -f "$deploy/.env" ]]; then
    cp -p "$deploy/.env" "$deploy/.env.bak"
    note "the previous deploy/.env is .env.bak"
  fi
  cp "$work/site/deploy.env" "$deploy/.env"
  chmod 600 "$deploy/.env"
  note "wrote the site's deploy.env as deploy/.env"
elif [[ "$answer_env" == keep ]]; then
  cp "$deploy/.env" "$work/installed.env"
  py env-merge --existing /work/installed.env --site /work/site/deploy.env --out /work/merged.env > "$work/added.txt"
  if [[ -s "$work/added.txt" ]]; then
    cp "$work/merged.env" "$deploy/.env"
    chmod 600 "$deploy/.env"
    note "kept deploy/.env and added the site's new keys: $(awk '{print $2}' "$work/added.txt" | words)"
  else
    note "kept deploy/.env"
  fi
else
  note "deploy/.env is the site's"
fi
if has_site docker-compose.override.yml; then
  cp "$work/site/docker-compose.override.yml" "$deploy/docker-compose.override.yml"
  note "wrote docker-compose.override.yml"
fi

if [[ -d "$work/site/grafana-dashboards" ]]; then
  dashboards="$deploy/grafana/site-dashboards"
  mkdir -p "$dashboards"
  find "$dashboards" -maxdepth 1 -type f -name '*.json' -exec rm -f {} \;
  if compgen -G "$work/site/grafana-dashboards/*.json" > /dev/null; then
    cp "$work/site/grafana-dashboards/"*.json "$dashboards/"
  fi
  note "Grafana's Site folder: $(find "$dashboards" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ') dashboards"
fi

plugins_changed=""
if [[ -n "$conf_PLUGIN_URL" ]]; then
  plugins="$(env_value "$deploy/.env" RIOT2_NODE_PLUGINS ./plugins)"
  [[ "$plugins" == /* ]] || plugins="$deploy/${plugins#./}"
  mkdir -p "$plugins"
  result="$(py_mounts "$plugins:/plugins:ro" -- plugins --url "$conf_PLUGIN_URL" \
    --sha256 "$conf_PLUGIN_SHA256" --dest /plugins --stage /work/plugins)"
  if [[ "$result" == changed ]]; then
    # The node writes its plugin folder as root, so it's replaced from a container.
    docker run --rm -v "$plugins:/plugins" -v "$work/plugins:/stage:ro" "$python_image" \
      sh -c 'find /plugins -mindepth 1 -maxdepth 1 -exec rm -rf {} + && cp -R /stage/. /plugins/'
    note "plugins: installed ${conf_PLUGIN_URL##*/}"
    plugins_changed=1
  else
    note "plugins: ${conf_PLUGIN_URL##*/} is installed"
  fi
fi

# Writes the site's files into the volumes; prints the volumes it wrote to. seed_volumes keep|installer.
seed_volumes() {
  local volume name owner
  local -a once_args=()
  if [[ -n "$overwrite_once" ]]; then once_args=(--overwrite-once); fi
  while read -r _ volume name owner; do
    if ! docker volume inspect "$name" > /dev/null 2>&1; then
      docker volume create --label "com.docker.compose.project=$project" --label "com.docker.compose.volume=$volume" \
        "$name" > /dev/null
    fi
    py_root "$work/site/volumes/$volume:/seed:ro" "$name:/v" -- seed --volume "$volume" --volume-dir /v --seed-dir /seed \
      --owner "$owner" --rules "$conf_SEED_RULES" --mode "$1" ${once_args[@]+"${once_args[@]}"} > "$work/seeded.txt"
    sed 's/^/  /' "$work/seeded.txt" >&2
    if grep -q '^write ' "$work/seeded.txt"; then echo "$volume"; fi
  done < <(seed_volume_lines)
}
step "Secret files"
if [[ -z "$(seed_volume_lines)" ]]; then
  note "the site has none"
else
  # Services whose volume files change stop first, so they don't write the same files meanwhile.
  seed_plan "$answer_secrets"
  changing="$(grep '^write ' "$work/seed-$answer_secrets.txt" | awk '{print $2}' | cut -d/ -f1 | sort -u || true)"
  if [[ -n "$changing" && "$mode" != fresh ]]; then
    # shellcheck disable=SC2086 # one volume per word
    stop="$(py compose-services --expected /work/expected.json $changing | tr '\n' ' ')"
    # shellcheck disable=SC2086 # one service per word
    if [[ -n "${stop// /}" ]]; then compose stop $stop; fi
  fi
  seed_volumes "$answer_secrets" > /dev/null
fi

step "Starting RIoT2"
compose pull --quiet
compose up -d --wait --wait-timeout 300 --remove-orphans
if [[ -n "$plugins_changed" ]] && grep -q '"node": *{' "$work/expected.json"; then
  # Plugins load only when the node starts.
  compose restart node > /dev/null
  compose up -d --wait --wait-timeout 300 > /dev/null
fi
compose ps

if [[ -n "$has_orchestrator" ]] && { has_site "$config_zip" || workflow_files_exist; }; then
  step "Orchestrator configuration and workflows"
  py_net api-wait
  if has_site "$config_zip" && [[ "$answer_config" == installer ]]; then
    py_net api-backup --out /work/live.zip
    matter_args=()
    if [[ -n "$replace_matter" ]]; then matter_args=(--replace); fi
    py merge-matter --site "/work/site/$config_zip" --live /work/live.zip --out /work/restore.zip \
      ${matter_args[@]+"${matter_args[@]}"} \
      | sed 's/^matter live \(.*\)/  kept the running Matter pairing (\1 files)/; s/^matter site \(.*\)/  the Matter pairing is the site'"'"'s: \1 files/'
    py_net api-restore --zip /work/restore.zip | sed 's/^/  /'
    # The restore replaces the Matter credentials folder: the site's files for it go back in.
    if grep -q '^volume orchestrator-matter ' "$work/rules.txt" \
      && seed_volumes "$answer_secrets" 2> /dev/null | grep -qx orchestrator-matter; then
      compose restart orchestrator > /dev/null
      compose up -d --wait --wait-timeout 300 > /dev/null
      py_net api-wait
      note "wrote the site's Matter files again and restarted the orchestrator"
    fi
  elif has_site "$config_zip"; then
    note "configuration: kept the running one"
  fi
  if workflow_files_exist; then
    mode_workflows=missing
    if [[ "$answer_workflows" == installer && "$mode" != fresh ]]; then mode_workflows=all; fi
    py_net api-workflows-import --dir /work/site/workflows --mode "$mode_workflows" --publish "$conf_PUBLISH_WORKFLOWS" \
      | sed 's/^/  /'
  fi
fi

commit="$site_commit"
if [[ -z "$plain" ]]; then commit="$(git -C "$site" rev-parse --short HEAD 2> /dev/null || true)"; fi
py marker --site /work/site --expected /work/expected.json --out /work/marker.new --host "$host" --project "$project" \
  --commit "$commit" --plugin "$plugin_id" --installer-version "$installer_version"
cp "$work/marker.new" "$deploy/.riot2-install.json"

step "Done"
compose_files="$(env_value "$deploy/.env" COMPOSE_FILE docker-compose.yml)"
lan() { env_value "$deploy/.env" "RIOT2_LAN_IP_$1"; }
if [[ "$compose_files" == *compose.lan.yml* ]]; then
  note "UI:            http://$(lan UI)/"
  note "Orchestrator:  http://$(lan ORCHESTRATOR):8080/health"
  note "MQTT broker:   $(lan MQTT):1883 (WebSocket 9001)"
  if [[ "$compose_files" == *compose.lan.influx.yml* ]]; then note "InfluxDB:      http://$(lan INFLUXDB):8086/"; fi
  if [[ "$compose_files" == *compose.lan.influx.yml* || "$compose_files" == *compose.lan.observability.yml* ]]; then
    note "Grafana:       http://$(lan GRAFANA):3000/"
  fi
elif [[ -n "$has_orchestrator" ]]; then
  note "UI:            http://$(env_value "$deploy/.env" RIOT2_HOST):$(env_value "$deploy/.env" RIOT2_UI_HOST_PORT 80)/"
fi
if [[ -n "$backup_dir" ]]; then note "The installation before the changes: $backup_dir"; fi
