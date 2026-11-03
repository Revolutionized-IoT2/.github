#!/usr/bin/env python3
"""Health check of a running RIoT2 compose stack (design 7.4 phase 5, I40).

Polls every health endpoint the chosen compose files publish, every container's Docker health, the
connectors' own health through the orchestrator (`GET /api/v2/connectors`) and, with the
observability profile, Prometheus' scrape of the exporter, until all pass or the deadline is reached.
Prints a Markdown table (also to $GITHUB_STEP_SUMMARY) and exits 1 when a check never passed.

    python tools/compose-smoke/health.py --host 10.1.0.4 \
        --files docker-compose.yml,compose.influx.yml,compose.observability.yml --profiles node \
        --since "$started" --deadline 120

Standard library only; run it from deploy/, where `docker compose` finds the files.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Callable

Probe = Callable[[], "tuple[bool, str]"]


@dataclass
class Check:
    name: str
    probe: Probe
    passed_after: float | None = None
    detail: str = "not run"


def fetch(url: str, timeout: float = 5) -> tuple[int, str]:
    """Status and body of a GET; status 0 when nothing answered."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as error:
        return 0, str(getattr(error, "reason", error))


def http_ok(url: str, get=fetch) -> Probe:
    def probe():
        status, body = get(url)
        return status == 200, f"HTTP {status}" if status else body
    return probe


def json_check(url: str, test: Callable[[object], "tuple[bool, str]"], get=fetch) -> Probe:
    def probe():
        status, body = get(url)
        if status != 200:
            return False, f"HTTP {status}" if status else body
        try:
            return test(json.loads(body))
        except (ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
            return False, f"unexpected answer: {error}"
    return probe


def workflows_ok(host: str, mode: str, get=fetch) -> Probe:
    """The orchestrator's workflow engine (ADR 0016) runs in the expected mode and answers."""
    def test(answer):
        state = "available" if answer.get("available") is True else "unavailable"
        return answer.get("mode") == mode and state == "available", f"{answer.get('mode')}, {state}"
    return json_check(f"http://{host}:8080/api/workflows/status", test, get)


def connector_ok(host: str, connector_id: str, get=fetch) -> Probe:
    """The connector is listed by the orchestrator, and its own /health says ok."""
    def test(connectors):
        match = next((c for c in connectors if c.get("id") == connector_id), None)
        if match is None:
            return False, "not listed by the orchestrator"
        health = match.get("health")
        if health is None:
            return False, match.get("healthError") or "no health (RIOT2_CONNECTOR_URL unset?)"
        status = health.get("status")
        return status == "ok", f"status {status}, spool {health.get('spool', {}).get('messages')}"
    return json_check(f"http://{host}:8080/api/v2/connectors", test, get)


def scraped(host: str, job: str, get=fetch) -> Probe:
    """Prometheus scrapes `job` successfully (up == 1)."""
    query = urllib.parse.quote(f'up{{job="{job}"}}')

    def test(answer):
        result = answer["data"]["result"]
        if not result:
            return False, "no target yet"
        value = result[0]["value"][1]
        return value == "1", f"up = {value}"
    return json_check(f"http://{host}:9090/api/v1/query?query={query}", test, get)


def containers(compose: list[str], run=subprocess.run) -> Probe:
    """Every service runs, and every service with a health check is healthy."""
    def probe():
        result = run([*compose, "ps", "--all", "--format", "json"], capture_output=True, text=True)
        if result.returncode != 0:
            return False, (result.stderr or "docker compose ps failed").strip()
        services = parse_ps(result.stdout)
        if not services:
            return False, "no containers"
        bad = [f"{s.get('Service')}: {s.get('State')}{'/' + s['Health'] if s.get('Health') else ''}"
               for s in services
               if s.get("State") != "running" or s.get("Health") not in ("", None, "healthy")]
        return not bad, "; ".join(bad) if bad else f"{len(services)} running"
    return probe


def parse_ps(output: str) -> list[dict]:
    """`docker compose ps --format json`: one object per line (Compose 2.21+) or one array."""
    text = output.strip()
    if not text:
        return []
    if text.startswith("["):
        return json.loads(text)
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def plan(host: str, files: list[str], profiles: list[str], get=fetch, run=subprocess.run) -> list[Check]:
    """The checks for these compose files and profiles."""
    compose = ["docker", "compose"] + [a for f in files for a in ("-f", f)] + [a for p in profiles for a in ("--profile", p)]
    remote = "remote-workflows" in profiles
    checks = [
        Check("containers", containers(compose, run)),
        Check("orchestrator /health", http_ok(f"http://{host}:8080/health", get)),
        Check("workflow engine", workflows_ok(host, "remote" if remote else "embedded", get)),
        Check("UI /", http_ok(f"http://{host}:80/", get)),
        Check("UI /api proxy", http_ok(f"http://{host}:80/api/security/info", get)),
    ]
    if remote:
        checks.append(Check("Elsa /health", http_ok(f"http://{host}:8082/health", get)))
    if "node" in profiles:
        checks.append(Check("node /health", http_ok(f"http://{host}:8081/health", get)))
    if "compose.influx.yml" in files:
        checks.append(Check("InfluxDB /health", json_check(
            f"http://{host}:8086/health", lambda a: (a.get("status") == "pass", f"status {a.get('status')}"), get)))
        checks.append(Check("InfluxDB connector", connector_ok(host, "riot2-influxdb", get)))
    if "compose.observability.yml" in files:
        checks.append(Check("Prometheus /-/ready", http_ok(f"http://{host}:9090/-/ready", get)))
        checks.append(Check("Prometheus exporter", connector_ok(host, "riot2-prometheus-exporter", get)))
        checks.append(Check("Prometheus scrapes the exporter", scraped(host, "riot2-values", get)))
    if "compose.homeassistant.yml" in files:
        checks.append(Check("Home Assistant connector", connector_ok(host, "riot2-homeassistant", get)))
    if "compose.influx.yml" in files or "compose.observability.yml" in files:
        checks.append(Check("Grafana /api/health", http_ok(f"http://{host}:3000/api/health", get)))
    return checks


def run_checks(checks: list[Check], since: float, deadline: float, interval: float = 3,
               clock=time.time, sleep=time.sleep) -> bool:
    """Runs the checks that haven't passed until all pass or `deadline` seconds after `since` have gone by."""
    while True:
        for check in checks:
            if check.passed_after is not None:
                continue
            try:
                ok, detail = check.probe()
            except Exception as error:  # a check must never stop the others
                ok, detail = False, f"{type(error).__name__}: {error}"
            check.detail = detail
            if ok:
                check.passed_after = clock() - since
        if all(c.passed_after is not None for c in checks):
            return True
        if clock() - since >= deadline:
            return False
        sleep(interval)


def table(checks: list[Check], deadline: float) -> str:
    lines = ["| Check | Result | After | Detail |", "|---|---|---|---|"]
    for c in checks:
        result = "pass" if c.passed_after is not None else "FAIL"
        after = f"{c.passed_after:.0f} s" if c.passed_after is not None else f"> {deadline:.0f} s"
        lines.append(f"| {c.name} | {result} | {after} | {c.detail.replace('|', '/')} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", required=True, help="the address the stack publishes its ports on (RIOT2_HOST)")
    parser.add_argument("--files", default="docker-compose.yml", help="comma-separated compose files")
    parser.add_argument("--profiles", default="", help="comma-separated compose profiles")
    parser.add_argument("--since", type=float, default=None, help="Unix time the stack was started (default: now)")
    parser.add_argument("--deadline", type=float, default=120, help="seconds after --since by which every check must pass")
    parser.add_argument("--require", action="append", default=[], metavar="URL", help="also require this URL to answer 200 (repeatable)")
    args = parser.parse_args(argv)
    files = [f for f in args.files.split(",") if f]
    profiles = [p for p in args.profiles.split(",") if p]
    since = args.since if args.since is not None else time.time()
    checks = plan(args.host, files, profiles) + [Check(f"GET {url}", http_ok(url, fetch)) for url in args.require]
    ok = run_checks(checks, since, args.deadline)
    report = f"### RIoT2 stack health ({', '.join(files + ['profile ' + p for p in profiles])})\n\n{table(checks, args.deadline)}"
    print(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(report + "\n")
    for c in checks:
        if c.passed_after is None:
            print(f"::error::{c.name} did not pass within {args.deadline:.0f} s: {c.detail}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
