#!/usr/bin/env python3
"""The logic install.sh and install.ps1 share (docs/guides/site-configuration.md, ADR 0020).

The installers run it in a pinned Python container, so the host needs only Docker. Python 3.9+ and the
standard library only. Every subcommand reads and writes files under the paths it is given and prints
lines the installers parse; run "python riot2site.py --help" for the list.

Exit codes: 0 done, 1 failed, 2 invalid input (a bad rule, a missing file).
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

MANIFEST = "backup-manifest.json"
# The parts of a configuration backup that belong to the Matter bridge's pairing: the restore replaces
# them as a whole and deletes credentials the archive lacks (BackupService.ReplaceCredentials).
MATTER_PREFIXES = ("MatterCredentials/", "StoredObjects/MatterConfiguration/", "StoredObjects/MatterBridgeState/")
RULES = ("once", "managed")
# Owners of the compose volumes, by name prefix (docs/contracts/images.md): the .NET services run as
# UID 1654, the node as root.
DEFAULT_OWNERS = (("orchestrator-", "1654:1654"), ("elsa-", "1654:1654"), ("influxdb-connector-", "1654:1654"),
                  ("node-", "0:0"))
SAFE_NAME = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")
ENV_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
TEMP_SUFFIX = ".riot2-seed.tmp"


class InputError(Exception):
    """Invalid input: exit code 2."""


# ------------------------------------------------------------------------------------------- helpers
def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha256(path.read_bytes())


def site_files(site: Path) -> dict[str, Path]:
    """Every file of a site host folder by its relative POSIX path, without .git."""
    files = {}
    if site.is_dir():
        for p in sorted(site.rglob("*")):
            rel = p.relative_to(site).as_posix()
            if p.is_file() and not rel.startswith(".git/"):
                files[rel] = p
    return files


def parse_env(text: str) -> dict[str, str]:
    """KEY=value lines of a compose .env file; the value as written (quotes included)."""
    values = {}
    for line in text.splitlines():
        m = ENV_LINE.match(line)
        if m and not line.lstrip().startswith("#"):
            values[m.group(1)] = m.group(2).strip()
    return values


def read_json(path: Path | None, default=None):
    if path is None or not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def category(rel: str) -> str:
    if rel in ("deploy.env", "site.conf", "docker-compose.override.yml"):
        return "settings"
    head = rel.split("/", 1)[0]
    return {"volumes": "secret-files", "configuration": "configuration", "workflows": "workflows",
            "grafana-dashboards": "dashboards"}.get(head, "other")


# ------------------------------------------------------------------------------------------- versions
def split_image(image: str) -> tuple[str, str]:
    """Repository and tag of an image reference; the digest is ignored."""
    image = image.split("@", 1)[0]
    slash = image.rfind("/")
    colon = image.rfind(":")
    if colon > slash:
        return image[:colon], image[colon + 1:]
    return image, "latest"


def version_key(tag: str):
    """Numeric parts of a tag (v1.2.3-arm64v8 -> (1, 2, 3)), or None when it isn't a version."""
    core = tag[1:] if tag[:1] in ("v", "V") else tag
    parts = core.split("-", 1)[0].split(".")
    if not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def compare_tags(old: str, new: str) -> str:
    """same, older (the installed one is older: an upgrade), newer (a downgrade) or changed."""
    if old == new:
        return "same"
    a, b = version_key(old), version_key(new)
    if a is None or b is None:
        return "changed"
    width = max(len(a), len(b))
    a, b = a + (0,) * (width - len(a)), b + (0,) * (width - len(b))
    if a == b:
        return "changed"
    return "older" if a < b else "newer"


def expected_images(config: dict) -> dict[str, str]:
    return {name: svc["image"] for name, svc in (config.get("services") or {}).items() if svc.get("image")}


def cmd_versions(args) -> int:
    expected = expected_images(read_json(Path(args.expected), {}) or {})
    running: dict[str, str] = {}
    if args.running:
        for line in Path(args.running).read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) >= 2:
                running.setdefault(parts[0], parts[1])
    volumes = Path(args.volumes).read_text(encoding="utf-8").split() if args.volumes else []
    marker = read_json(Path(args.marker)) if args.marker else None
    source = "the running containers"
    if not running and marker:
        running = dict(marker.get("images") or {})
        source = f"the install marker of {marker.get('installedAt', 'an earlier run')}"

    if not running:
        print(f"verdict {'leftover' if volumes else 'fresh'}")
        if volumes:
            print(f"No RIoT2 containers, but volumes of an earlier installation: {', '.join(volumes)}")
        return 0

    rows, changes = [], set()
    for service in sorted(set(running) | set(expected)):
        old, new = running.get(service), expected.get(service)
        if old is None:
            change = "added"
        elif new is None:
            change = "removed"
        else:
            (repo_old, tag_old), (repo_new, tag_new) = split_image(old), split_image(new)
            change = compare_tags(tag_old, tag_new) if repo_old == repo_new else "changed"
        changes.add(change)
        rows.append((service, split_image(old)[1] if old else "-", split_image(new)[1] if new else "-", change))

    verdict = "downgrade" if "newer" in changes else "upgrade" if changes - {"same"} else "same"
    print(f"verdict {verdict}")
    print(f"Installed versions (from {source}) and the installer's:")
    width = max(len(r[0]) for r in rows)
    for service, old, new, change in rows:
        label = {"older": "upgrade", "newer": "DOWNGRADE", "same": ""}.get(change, change)
        print(f"  {service.ljust(width)}  {old:>14} -> {new:<14} {label}".rstrip())
    return 0


# ------------------------------------------------------------------------------------------- marker and diff
def site_state(site: Path, plugin: str) -> dict:
    files = site_files(site)
    env = parse_env(files["deploy.env"].read_text(encoding="utf-8")) if "deploy.env" in files else {}
    return {
        "env": {k: sha256(v.encode()) for k, v in sorted(env.items())},
        "files": {rel: file_sha(p) for rel, p in files.items() if rel != "deploy.env"},
        "plugin": plugin or "",
    }


def cmd_diff(args) -> int:
    marker = read_json(Path(args.marker)) if args.marker else None
    now = site_state(Path(args.site), args.plugin)
    before = (marker or {}).get("site") or {}
    before_env, before_files = before.get("env") or {}, before.get("files") or {}
    items = []

    def how(a, b):
        return "added" if a is None else "removed" if b is None else "changed"

    for key in sorted(set(now["env"]) | set(before_env)):
        a, b = before_env.get(key), now["env"].get(key)
        if a != b:
            items.append(("settings", f"deploy.env:{key}", how(a, b)))
    for rel in sorted(set(now["files"]) | set(before_files)):
        a, b = before_files.get(rel), now["files"].get(rel)
        if a != b:
            items.append((category(rel), rel, how(a, b)))
    if now["plugin"] != before.get("plugin", ""):
        items.append(("plugins", "site.conf:PLUGIN_URL", "changed"))
    print(f"changed {len(items)}")
    for cat, rel, change in items:
        print(f"item {cat} {rel} {change}")
    return 0


def cmd_marker(args) -> int:
    write_json(Path(args.out), {
        "installer": args.installer_version,
        "installedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "host": args.host,
        "project": args.project,
        "siteCommit": args.commit or None,
        "images": expected_images(read_json(Path(args.expected), {}) or {}),
        "site": site_state(Path(args.site), args.plugin),
    })
    return 0


def cmd_marker_update(args) -> int:
    """After an export: the exported site files are what the installation runs."""
    marker = read_json(Path(args.marker))
    if marker is None:
        return 0
    files = marker.setdefault("site", {}).setdefault("files", {})
    for rel in args.paths:
        p = Path(args.site) / rel
        if p.is_file():
            files[rel] = file_sha(p)
    write_json(Path(args.marker), marker)
    return 0


# ------------------------------------------------------------------------------------------- .env
def cmd_env_diff(args) -> int:
    existing = parse_env(Path(args.existing).read_text(encoding="utf-8"))
    site = parse_env(Path(args.site).read_text(encoding="utf-8"))
    for key in sorted(set(existing) | set(site)):
        if existing.get(key) != site.get(key):
            change = "new" if key not in existing else "only-installed" if key not in site else "different"
            print(f"key {key} {change}")
    return 0


def cmd_env_merge(args) -> int:
    """Keeps the installed .env and appends the keys only the site has (a new version may need them)."""
    text = Path(args.existing).read_text(encoding="utf-8")
    existing = parse_env(text)
    added = []
    for line in Path(args.site).read_text(encoding="utf-8").splitlines():
        m = ENV_LINE.match(line)
        if m and not line.lstrip().startswith("#") and m.group(1) not in existing:
            added.append((m.group(1), line))
    if text and not text.endswith("\n"):
        text += "\n"
    if added:
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        text += f"\n# Added by the installer on {stamp}: keys the site's deploy.env has and this file didn't.\n"
        text += "\n".join(line for _, line in added) + "\n"
    Path(args.out).write_text(text, encoding="utf-8")
    for key, _ in added:
        print(f"added {key}")
    return 0


# ------------------------------------------------------------------------------------------- seed rules
def parse_rules(text: str) -> list[tuple[str, str]]:
    rules = []
    for item in (text or "").split():
        pattern, sep, rule = item.partition("=")
        if not sep or not pattern or rule not in RULES:
            raise InputError(f"SEED_RULES: '{item}' must be <volume>/<glob>=once or =managed")
        if "/" not in pattern or pattern.startswith("/") or ".." in pattern.split("/"):
            raise InputError(f"SEED_RULES: '{pattern}' must start with a volume name, as in node-data/*.json")
        rules.append((pattern, rule))
    return rules


def rule_for(path: str, rules: list[tuple[str, str]]) -> str:
    """The first rule whose glob matches <volume>/<path>; once without one."""
    for pattern, rule in rules:
        if fnmatch.fnmatchcase(path, pattern):
            return rule
    return "once"


def parse_owners(text: str) -> dict[str, str]:
    owners = {}
    for item in (text or "").split():
        name, sep, owner = item.partition("=")
        if not sep or not re.fullmatch(r"\d+:\d+", owner) or not SAFE_NAME.match(name):
            raise InputError(f"VOLUME_OWNERS: '{item}' must be <volume>=<uid>:<gid>")
        owners[name] = owner
    return owners


def owner_for(volume: str, owners: dict[str, str]) -> str:
    if volume in owners:
        return owners[volume]
    for prefix, owner in DEFAULT_OWNERS:
        if volume.startswith(prefix):
            return owner
    raise InputError(f"volumes/{volume}: no owner is known for this volume; "
                     f"add {volume}=<uid>:<gid> to VOLUME_OWNERS in site.conf")


def seed_files(seeds: Path) -> dict[str, list[str]]:
    """The relative paths under volumes/<volume>/ of a site host folder, by volume."""
    result: dict[str, list[str]] = {}
    if not seeds.is_dir():
        return result
    loose = [p.name for p in seeds.iterdir() if p.is_file()]
    if loose:
        raise InputError(f"volumes/: files must be in a folder named after their volume: {', '.join(sorted(loose))}")
    for volume_dir in sorted(p for p in seeds.iterdir() if p.is_dir()):
        if not SAFE_NAME.match(volume_dir.name):
            raise InputError(f"volumes/{volume_dir.name}: not a compose volume name")
        files = [p.relative_to(volume_dir).as_posix() for p in sorted(volume_dir.rglob("*")) if p.is_file()]
        if files:
            result[volume_dir.name] = files
    return result


def cmd_rules(args) -> int:
    rules = parse_rules(args.rules)
    owners = parse_owners(args.owners)
    declared = (read_json(Path(args.expected), {}) or {}).get("volumes") or {} if args.expected else {}
    for volume, files in seed_files(Path(args.seeds)).items():
        if args.expected and volume not in declared:
            raise InputError(f"volumes/{volume}: the compose files declare no volume {volume} "
                             f"(they declare {', '.join(sorted(declared)) or 'none'})")
        owner = owner_for(volume, owners)
        print(f"volume {volume} {(declared.get(volume) or {}).get('name') or volume} {owner}")
        for rel in files:
            print(f"seed {volume} {rel} {rule_for(f'{volume}/{rel}', rules)} {owner}")
    listed = set(seed_files(Path(args.seeds)))
    for pattern, _ in rules:
        volume = pattern.split("/", 1)[0]
        if args.expected and not any(fnmatch.fnmatchcase(v, volume) for v in declared):
            print(f"note SEED_RULES names {pattern}, but the compose files declare no volume {volume}")
        elif args.expected and volume in declared and volume not in listed:
            # A volume only a rule names: an export may find new files there (a second account's token).
            listed.add(volume)
            print(f"volume {volume} {(declared.get(volume) or {}).get('name') or volume} {owner_for(volume, owners)} rule-only")
    return 0


def chown(path: Path, owner: str) -> None:
    """Root (the seeding container) gives files to the service's user; elsewhere (tests) nothing to do."""
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        uid, gid = (int(x) for x in owner.split(":"))
        os.chown(path, uid, gid)


def cmd_seed(args) -> int:
    """Writes one volume's seed files: once only where missing, managed also where different (installer mode)."""
    rules = parse_rules(args.rules)
    volume_dir, seed_dir, owner = Path(args.volume_dir), Path(args.seed_dir), args.owner
    if not args.dry_run and volume_dir.is_dir() and volume_dir.stat().st_uid == 0 and owner != "0:0":
        # A volume made before its service first started belongs to root; the service must own it.
        chown(volume_dir, owner)
    for p in sorted(seed_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(seed_dir).as_posix()
        rule = rule_for(f"{args.volume}/{rel}", rules)
        target = volume_dir / rel
        content = p.read_bytes()
        if not target.exists():
            action = "write"
        elif target.read_bytes() == content:
            action = "same"
        elif (rule == "managed" and args.mode == "installer") or (rule == "once" and args.overwrite_once):
            action = "write"
        else:
            action = "keep"
        print(f"{action} {args.volume}/{rel} {rule}")
        if action != "write" or args.dry_run:
            continue
        for parent in reversed(PurePosixPath(rel).parents):
            d = volume_dir / str(parent)
            if str(parent) != "." and not d.exists():
                d.mkdir(mode=0o750)
                chown(d, owner)
        tmp = target.with_name(target.name + TEMP_SUFFIX)
        tmp.write_bytes(content)
        os.chmod(tmp, 0o600)
        chown(tmp, owner)
        os.replace(tmp, target)
    return 0


def cmd_export_seeds(args) -> int:
    """Copies one volume's seed files back for the site: files the site has, and new files a rule names."""
    rules = parse_rules(args.rules)
    volume_dir, seed_dir, out = Path(args.volume_dir), Path(args.seed_dir), Path(args.out)
    allowed = set(Path(args.allowed).read_text(encoding="utf-8").split()) if args.allowed else None
    present = {p.relative_to(seed_dir).as_posix() for p in seed_dir.rglob("*") if p.is_file()} if seed_dir.is_dir() else set()
    exportable = ("once", "managed") if args.managed else ("once",)
    for p in sorted(volume_dir.rglob("*")) if volume_dir.is_dir() else []:
        if not p.is_file() or p.name.endswith((TEMP_SUFFIX, ".tmp")):
            continue
        rel = p.relative_to(volume_dir).as_posix()
        path = f"{args.volume}/{rel}"
        site_rel = f"volumes/{path}"
        named = any(fnmatch.fnmatchcase(path, pattern) for pattern, _ in rules)
        if rule_for(path, rules) not in exportable or (rel not in present and not named):
            continue
        if rel in present and allowed is not None and site_rel not in allowed:
            print(f"skip {site_rel} changed-in-site")
            continue
        content = p.read_bytes()
        if rel in present and (seed_dir / rel).read_bytes() == content:
            continue
        target = out / site_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        if args.chown:
            chown(target, args.chown)
            for parent in PurePosixPath(site_rel).parents:
                if str(parent) != ".":
                    chown(out / str(parent), args.chown)
        print(f"export {site_rel} {'changed' if rel in present else 'new'}")
    return 0


def cmd_compose_services(args) -> int:
    """The services that mount any of the given volumes (stopped while their files change)."""
    config = read_json(Path(args.expected), {}) or {}
    wanted = set(args.volumes)
    for name, svc in sorted((config.get("services") or {}).items()):
        if any(isinstance(m, dict) and m.get("type") == "volume" and m.get("source") in wanted
               for m in svc.get("volumes") or []):
            print(name)
    return 0


# Limits a service enforces only on its first start, when the install has already gone ahead.
SETTING_LIMITS = (
    # service, variable inside it, the .env setting, min and max length in UTF-8 bytes
    ("influxdb", "DOCKER_INFLUXDB_INIT_PASSWORD", "RIOT2_INFLUXDB_ADMIN_PASSWORD", 8, 72),
)


def cmd_settings(args) -> int:
    """Checks the settings the compose files pass on, against the limits of the services that get them."""
    services = (read_json(Path(args.expected), {}) or {}).get("services") or {}
    problems = []
    for service, variable, setting, low, high in SETTING_LIMITS:
        environment = (services.get(service) or {}).get("environment") or {}
        if service in services and variable in environment:
            length = len(str(environment[variable] or "").encode("utf-8"))
            if not low <= length <= high:
                problems.append(f"{setting} must be {low} to {high} characters long ({service} refuses it on its "
                                f"first start); it has {length}")
    if problems:
        raise InputError("; ".join(problems))
    return 0


# ------------------------------------------------------------------------------------------- plugins
def fetch(url: str, timeout: int = 120) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout) as response:  # noqa: S310 - the site names the URL
        return response.read()


def cmd_plugins(args) -> int:
    """Stages the site's plugin package when the installed one (PluginManifest.json sha256) differs."""
    expected = (args.sha256 or "").strip().lower()
    if not expected:
        try:
            expected = fetch(args.url + ".sha256").decode().split()[0].lower()
        except (urllib.error.URLError, IndexError, UnicodeDecodeError, OSError) as x:
            raise InputError(f"PLUGIN_SHA256 is empty and {args.url}.sha256 can't be read ({x}); "
                             "set PLUGIN_SHA256 in site.conf") from None
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise InputError("PLUGIN_SHA256 must be 64 hexadecimal characters")
    installed = read_json(Path(args.dest) / "PluginManifest.json", {}) or {}
    if str(installed.get("sha256", "")).lower() == expected:
        print("same")
        return 0
    data = fetch(args.url)
    if sha256(data) != expected:
        raise RuntimeError(f"the plugin package {args.url} has SHA-256 {sha256(data)}, not {expected}")
    stage = Path(args.stage)
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            name = PurePosixPath(info.filename)
            if name.is_absolute() or ".." in name.parts or "\\" in info.filename or ":" in info.filename:
                raise InputError(f"the plugin package has an unsafe entry {info.filename}")
        zf.extractall(stage)
    manifest = read_json(stage / "PluginManifest.json", {}) or {}
    # What the node records when it installs a package itself (docs/contracts/configuration.md).
    manifest["installedPackageFilename"] = PurePosixPath(urllib.parse.urlparse(args.url).path).name
    manifest["sha256"] = expected
    write_json(stage / "PluginManifest.json", manifest)
    print("changed")
    return 0


# ------------------------------------------------------------------------------------------- configuration backup
def read_backup(path: Path) -> tuple[dict, dict[str, bytes]]:
    with zipfile.ZipFile(path) as zf:
        entries = {i.filename: zf.read(i) for i in zf.infolist() if not i.is_dir()}
    if MANIFEST not in entries:
        raise InputError(f"{path.name} has no {MANIFEST}, so it is not a RIoT2 configuration backup")
    return json.loads(entries.pop(MANIFEST).decode("utf-8")), entries


def is_matter(name: str) -> bool:
    return name.startswith(MATTER_PREFIXES)


def write_backup(path: Path, manifest: dict, entries: dict[str, bytes]) -> None:
    """A backup the orchestrator accepts: the manifest first, listing every entry's size and SHA-256."""
    manifest = dict(manifest)
    manifest["files"] = [{"path": n, "size": len(c), "sha256": sha256(c)} for n, c in sorted(entries.items())]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(MANIFEST, json.dumps(manifest, indent=2).encode("utf-8"))
        for name, content in sorted(entries.items()):
            zf.writestr(name, content)


def cmd_merge_matter(args) -> int:
    """The site's configuration with the running bridge's Matter pairing, unless --replace or it has none."""
    manifest, site = read_backup(Path(args.site))
    _, live = read_backup(Path(args.live))
    live_matter = {n: c for n, c in live.items() if is_matter(n)}
    if args.replace or not live_matter:
        shutil.copyfile(args.site, args.out)
        reason = "--replace-matter" if args.replace else "the running orchestrator has none"
        print(f"matter site {sum(1 for n in site if is_matter(n))} ({reason})")
        return 0
    merged = {n: c for n, c in site.items() if not is_matter(n)}
    merged.update(live_matter)
    write_backup(Path(args.out), manifest, merged)
    print(f"matter live {len(live_matter)}")
    return 0


def backup_content(path: Path) -> set[tuple[str, str]]:
    return {(n, sha256(c)) for n, c in read_backup(path)[1].items()}


# ------------------------------------------------------------------------------------------- orchestrator API
def api(base: str, method: str, path: str, body: bytes | None = None, content_type: str = "application/json",
        timeout: int = 300) -> bytes:
    request = urllib.request.Request(base.rstrip("/") + path, data=body, method=method)
    if body is not None:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - the orchestrator's URL
            return response.read()
    except urllib.error.HTTPError as x:
        detail = x.read().decode("utf-8", "replace")
        try:
            problem = json.loads(detail)
            errors = problem.get("errors") or []
            if isinstance(errors, dict):
                errors = [f"{k}: {'; '.join(map(str, v))}" for k, v in errors.items()]
            detail = "\n  ".join([problem.get("title") or problem.get("detail") or ""] + [str(e) for e in errors])
        except (ValueError, AttributeError):
            pass
        raise RuntimeError(f"{method} {path} answered {x.code}: {detail.strip()}") from None


def cmd_api_wait(args) -> int:
    deadline = time.monotonic() + args.timeout
    last = ""
    while True:
        try:
            api(args.url, "GET", "/health", timeout=5)
            return 0
        except (urllib.error.URLError, RuntimeError, OSError) as x:
            last = str(x)
        if time.monotonic() >= deadline:
            print(f"ERROR: the orchestrator at {args.url} didn't answer within {args.timeout} s: {last}", file=sys.stderr)
            return 1
        time.sleep(2)


def cmd_api_node_count(args) -> int:
    print(len(json.loads(api(args.url, "GET", "/api/nodes"))))
    return 0


def cmd_api_backup(args) -> int:
    Path(args.out).write_bytes(api(args.url, "POST", "/api/v2/backup"))
    return 0


def cmd_api_export_config(args) -> int:
    """A backup of the running configuration, written only when its entries differ from the site's."""
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".new")
    tmp.write_bytes(api(args.url, "POST", "/api/v2/backup"))
    if args.site and Path(args.site).is_file() and backup_content(Path(args.site)) == backup_content(tmp):
        tmp.unlink()
        print("same")
        return 0
    os.replace(tmp, out)
    print("changed")
    return 0


def cmd_api_restore(args) -> int:
    result = json.loads(api(args.url, "POST", "/api/v2/restore", Path(args.zip).read_bytes(), "application/zip") or b"{}")
    print(f"Restored {result.get('nodes', '?')} nodes, {result.get('variables', '?')} variables and "
          f"{result.get('matterCredentials', 0)} Matter files; the replaced configuration is "
          f"{result.get('safetyBackup', '?')} in the orchestrator-backups volume")
    return 0


def workflow_files(folder: Path) -> dict[str, tuple[str, dict]]:
    """Site workflow files by definition id: (file name, model)."""
    result = {}
    for p in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        model = json.loads(p.read_text(encoding="utf-8"))
        if isinstance(model, dict) and isinstance(model.get("model"), dict):
            model = model["model"]  # saved with the export's envelope { fileName, model }
        definition = model.get("definitionId") if isinstance(model, dict) else None
        if not definition:
            raise InputError(f"workflows/{p.name} has no definitionId; save workflows with the Workflows page's Export")
        if definition in result:
            raise InputError(f"workflows/{p.name} and workflows/{result[definition][0]} are the same workflow ({definition})")
        result[definition] = (p.name, model)
    return result


def cmd_api_workflows_import(args) -> int:
    files = workflow_files(Path(args.dir))
    existing = {w.get("definitionId") for w in json.loads(api(args.url, "GET", "/api/workflows"))}
    failed = 0
    for definition, (name, model) in files.items():
        if args.mode == "missing" and definition in existing:
            print(f"keep workflows/{name}")
            continue
        publish = bool(model.get("isPublished")) if args.publish == "auto" else args.publish == "true"
        try:
            api(args.url, "POST", "/api/workflows/import", json.dumps({"model": model, "publish": publish}).encode())
            print(f"import workflows/{name}{' published' if publish else ''}")
        except RuntimeError as x:
            failed += 1
            print(f"ERROR: workflows/{name}: {x}", file=sys.stderr)
    return 1 if failed else 0


def cmd_api_workflows_export(args) -> int:
    site = workflow_files(Path(args.site_dir)) if args.site_dir else {}
    allowed = set(Path(args.allowed).read_text(encoding="utf-8").split()) if args.allowed else None
    for item in json.loads(api(args.url, "GET", "/api/workflows")):
        definition = item.get("definitionId")
        if not definition:
            continue
        export = json.loads(api(args.url, "GET", f"/api/workflows/{urllib.parse.quote(definition, safe='')}/export"))
        model = export.get("model")
        if definition in site:
            name, current = site[definition]
            if allowed is not None and f"workflows/{name}" not in allowed:
                print(f"skip workflows/{name} changed-in-site")
                continue
            if current == model:
                continue
            change = "changed"
        else:
            name, change = re.sub(r"[^A-Za-z0-9._-]", "-", definition) + ".json", "new"
        write_json(Path(args.out) / "workflows" / name, model)
        print(f"export workflows/{name} {change}")
    return 0


# ------------------------------------------------------------------------------------------- command line
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def add(name, func, help_text, *required, **optional):
        p = sub.add_parser(name, help=help_text)
        p.set_defaults(func=func)
        for option in required:
            p.add_argument(option, required=True)
        for option, default in optional.items():
            p.add_argument("--" + option.replace("_", "-"), default=default)
        return p

    add("versions", cmd_versions, "compare the installed images with the compose files'", "--expected",
        running=None, marker=None, volumes=None)
    add("diff", cmd_diff, "what changed in the site since the last install", "--site", marker=None, plugin="")
    p = add("marker", cmd_marker, "write the install marker", "--site", "--expected", "--out", "--host", "--project",
            commit="", plugin="")
    p.add_argument("--installer-version", type=int, default=1)
    p = add("marker-update", cmd_marker_update, "record exported site files in the marker", "--marker", "--site")
    p.add_argument("paths", nargs="*")
    add("env-diff", cmd_env_diff, "keys that differ between the installed .env and the site's", "--existing", "--site")
    add("env-merge", cmd_env_merge, "keep the installed .env, adding the keys only the site has",
        "--existing", "--site", "--out")
    add("rules", cmd_rules, "check SEED_RULES and VOLUME_OWNERS and list the seed files", "--seeds",
        rules="", owners="", expected=None)
    p = add("seed", cmd_seed, "write one volume's seed files", "--volume", "--volume-dir", "--seed-dir", "--owner",
            rules="")
    p.add_argument("--mode", choices=("keep", "installer"), required=True)
    p.add_argument("--overwrite-once", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p = add("export-seeds", cmd_export_seeds, "copy one volume's seed files back for the site",
            "--volume", "--volume-dir", "--seed-dir", "--out", rules="", allowed=None, chown=None)
    p.add_argument("--managed", action="store_true")
    p = add("compose-services", cmd_compose_services, "services that mount the given volumes", "--expected")
    p.add_argument("volumes", nargs="*")
    add("settings", cmd_settings, "check the settings against the services' limits", "--expected")
    add("plugins", cmd_plugins, "stage the site's plugin package when the installed one differs",
        "--url", "--dest", "--stage", sha256="")
    p = add("merge-matter", cmd_merge_matter, "put the running Matter pairing into the site's backup",
            "--site", "--live", "--out")
    p.add_argument("--replace", action="store_true")

    url = {"url": "http://orchestrator:8080"}
    p = add("api-wait", cmd_api_wait, "wait for the orchestrator's /health", **url)
    p.add_argument("--timeout", type=int, default=180)
    add("api-node-count", cmd_api_node_count, "how many nodes are configured", **url)
    add("api-backup", cmd_api_backup, "a configuration backup", "--out", **url)
    add("api-export-config", cmd_api_export_config, "export the configuration when it changed", "--out",
        site=None, **url)
    add("api-restore", cmd_api_restore, "restore a configuration backup", "--zip", **url)
    p = add("api-workflows-import", cmd_api_workflows_import, "import the site's workflows", "--dir", **url)
    p.add_argument("--mode", choices=("missing", "all"), required=True)
    p.add_argument("--publish", choices=("auto", "true", "false"), default="auto")
    add("api-workflows-export", cmd_api_workflows_export, "export the workflows", "--out",
        site_dir=None, allowed=None, **url)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except InputError as x:
        print(f"ERROR: {x}", file=sys.stderr)
        return 2
    except (RuntimeError, OSError, urllib.error.URLError, zipfile.BadZipFile, ValueError) as x:
        print(f"ERROR: {x}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
