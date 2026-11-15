#!/usr/bin/env python3
"""RIoT2 preflight: the checks CI runs, run before a push, for what the push changes.

    python .github/tools/preflight/preflight.py [--repo PATH] [--base REF] [--full | --quick] [--only a,b]

The git pre-push hook (install-hooks.ps1) runs it for every push from a RIoT2 repository, and an agent
runs it by hand before it pushes. Exit code 0: push. 1: fix the FAIL lines first. See README.md.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import io
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
HUB = HERE.parents[1]
WORKSPACE = HUB.parent
ZERO = "0" * 40
MANIFEST = json.loads((HERE / "preflight.json").read_text(encoding="utf-8"))
TOOLS = MANIFEST["tools"]
DOC_ONLY = re.compile(r"(\.md$|^docs/|\.(png|jpe?g|gif|svg|webp)$|(^|/)LICENSE$)", re.IGNORECASE)
RELEASE_TAG = re.compile(r"^\d+\.\d+\.\d+$")
FORBIDDEN = re.compile(r"(^|/)(\.env|local\.configuration\.json|id_rsa|id_ed25519|[^/]+\.pfx|[^/]+\.p12)$")
CORE_PACKAGE = re.compile(r'Include="(RIoT2\.Core(?:\.[\w.]+)?|RIoT2\.Connector\.Sdk)"\s+Version="(\d+\.\d+\.\d+)"')
CHEAP = ["hygiene", "red-main", "tags", "core-sync", "siblings", "secrets", "markdown", "workflows", "docs",
         "python", "pins", "shellcheck"]
HEAVY = ["dotnet", "npm", "firmware", "downstream"]
LOGS = Path(tempfile.gettempdir()) / "riot2-preflight"


# ---------------------------------------------------------------- helpers

def run(cmd: list[str], cwd: Path, timeout: int = 1800, env: dict | None = None) -> tuple[int, str]:
    """Runs a command; returns its exit code and combined output."""
    try:
        result = subprocess.run(cmd, cwd=str(cwd), capture_output=True, timeout=timeout,
                                env={**os.environ, **(env or {})})
    except FileNotFoundError as error:
        return 127, str(error)
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout} s: {' '.join(cmd)}"
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    return result.returncode, output


def git(repo: Path, *args: str) -> str:
    code, out = run(["git", "-C", str(repo), *args], repo, timeout=120)
    if code:
        raise RuntimeError(f"git {' '.join(args)} failed: {out.strip()}")
    return out.strip()


def git_ok(repo: Path, *args: str) -> tuple[int, str]:
    code, out = run(["git", "-C", str(repo), *args], repo, timeout=120)
    return code, out.strip()


def version_key(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", text)[:3])


def tail(text: str, lines: int = 40) -> str:
    return "\n".join(text.rstrip().splitlines()[-lines:])


def save_log(name: str, text: str) -> Path:
    LOGS.mkdir(parents=True, exist_ok=True)
    path = LOGS / f"{name}.log"
    path.write_text(text, encoding="utf-8")
    return path


def is_doc_only(paths: list[str]) -> bool:
    return bool(paths) and all(DOC_ONLY.search(p) for p in paths)


# ---------------------------------------------------------------- what is pushed

@dataclass
class Push:
    local_ref: str
    local_sha: str
    remote_ref: str
    remote_sha: str

    @property
    def is_tag(self) -> bool:
        return self.remote_ref.startswith("refs/tags/")

    @property
    def name(self) -> str:
        return self.remote_ref.split("/", 2)[-1]


def parse_push_lines(text: str) -> list[Push]:
    """The pre-push hook's stdin: '<local ref> <local sha> <remote ref> <remote sha>' per ref. Deletions drop out."""
    pushes = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 4 and parts[1] != ZERO:
            pushes.append(Push(*parts))
    return pushes


@dataclass
class Context:
    repo: Path
    name: str
    config: dict
    pushes: list[Push]
    head: str
    base: str | None
    changed: list[str]
    default_branch: str
    full: bool
    quick: bool
    hook: bool
    only: set[str] = field(default_factory=set)
    skip: set[str] = field(default_factory=set)

    @property
    def to_default_branch(self) -> bool:
        return any(p.remote_ref == f"refs/heads/{self.default_branch}" for p in self.pushes)

    @property
    def tags(self) -> list[Push]:
        return [p for p in self.pushes if p.is_tag and RELEASE_TAG.match(p.name)]

    @property
    def doc_only(self) -> bool:
        return not self.full and not self.tags and is_doc_only(self.changed)

    def touched(self, pattern: str) -> list[str]:
        regex = re.compile(pattern)
        return [p for p in self.changed if regex.search(p)]


def default_branch(repo: Path) -> str:
    code, out = git_ok(repo, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    return out.rsplit("/", 1)[-1] if code == 0 and out else "main"


def commit_of(repo: Path, sha: str) -> str:
    return git(repo, "rev-parse", f"{sha}^{{commit}}")


def base_for(repo: Path, push: Push, branch: str) -> str | None:
    """Where the pushed range starts: the remote's commit, or the fork point from the default branch."""
    if push.remote_sha != ZERO and git_ok(repo, "cat-file", "-e", f"{push.remote_sha}^{{commit}}")[0] == 0:
        return push.remote_sha
    code, out = git_ok(repo, "merge-base", commit_of(repo, push.local_sha), f"refs/remotes/origin/{branch}")
    return out if code == 0 and out else None


def changed_files(repo: Path, base: str | None, head: str) -> list[str]:
    if base is None:
        out = git(repo, "ls-tree", "-r", "--name-only", "--full-tree", head)
    else:
        out = git(repo, "diff", "--name-only", "--no-renames", "--diff-filter=ACMRT", base, head)
    return [line for line in out.splitlines() if line]


def manual_push(repo: Path, branch: str) -> list[Push]:
    """Without the hook: the current branch to its upstream (or the same name on origin)."""
    head = git(repo, "rev-parse", "HEAD")
    code, upstream = git_ok(repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    current = git_ok(repo, "rev-parse", "--abbrev-ref", "HEAD")[1]
    remote_branch = upstream.split("/", 1)[1] if code == 0 and "/" in upstream else (current if current != "HEAD" else branch)
    code, remote_sha = git_ok(repo, "rev-parse", f"refs/remotes/origin/{remote_branch}")
    return [Push(f"refs/heads/{current}", head, f"refs/heads/{remote_branch}", remote_sha if code == 0 else ZERO)]


# ---------------------------------------------------------------- report

class Report:
    def __init__(self):
        self.failures: list[str] = []
        self.warnings: list[str] = []

    @staticmethod
    def _print(tag: str, check: str, message: str = ""):
        lines = message.rstrip().splitlines() or [""]
        print(f"  {tag:<5} {check}" + (f": {lines[0]}" if lines[0] else ""))
        for line in lines[1:]:
            print(f"        {line}")
        sys.stdout.flush()

    def ok(self, check: str, message: str = ""):
        self._print("ok", check, message)

    def skip(self, check: str, message: str):
        self._print("skip", check, message)

    def warn(self, check: str, message: str):
        self.warnings.append(check)
        self._print("warn", check, message)

    def fail(self, check: str, message: str):
        self.failures.append(check)
        self._print("FAIL", check, message)


# ---------------------------------------------------------------- downloaded tools

def _download(url: str, timeout: int = 60) -> bytes:
    with urllib.request.urlopen(url, timeout=timeout) as answer:
        return answer.read()


def _platform_asset() -> tuple[str, str]:
    system = platform.system()
    machine = platform.machine().lower()
    arch = "arm64" if machine in ("arm64", "aarch64") else "amd64"
    return system.lower(), arch


def tool_gitleaks() -> Path:
    found = shutil.which("gitleaks")
    if found:
        return Path(found)
    spec = TOOLS["gitleaks"]
    system, _ = _platform_asset()
    asset = {"windows": "windows_x64.zip", "darwin": "darwin_arm64.tar.gz"}.get(system, "linux_x64.tar.gz")
    exe = "gitleaks.exe" if system == "windows" else "gitleaks"
    folder = Path(tempfile.gettempdir()) / f"gitleaks-{spec['version']}"
    path = folder / exe
    if path.exists():
        return path
    data = _download(f"https://github.com/gitleaks/gitleaks/releases/download/v{spec['version']}/"
                     f"gitleaks_{spec['version']}_{asset}")
    if hashlib.sha256(data).hexdigest() != spec["sha256"][asset]:
        raise RuntimeError(f"gitleaks {asset}: checksum mismatch")
    _extract(data, asset, exe, folder)
    return path


def tool_actionlint() -> Path:
    found = shutil.which("actionlint")
    if found:
        return Path(found)
    version = TOOLS["actionlint"]
    system, arch = _platform_asset()
    ext = "zip" if system == "windows" else "tar.gz"
    exe = "actionlint.exe" if system == "windows" else "actionlint"
    folder = Path(tempfile.gettempdir()) / f"actionlint-{version}"
    path = folder / exe
    if path.exists():
        return path
    asset = f"actionlint_{version}_{system}_{arch}.{ext}"
    base = f"https://github.com/rhysd/actionlint/releases/download/v{version}"
    data = _download(f"{base}/{asset}")
    sums = _download(f"{base}/actionlint_{version}_checksums.txt").decode()
    expected = next((line.split()[0] for line in sums.splitlines() if line.endswith(f" {asset}")), None)
    if expected != hashlib.sha256(data).hexdigest():
        raise RuntimeError(f"actionlint {asset}: checksum mismatch")
    _extract(data, asset, exe, folder)
    return path


def _extract(data: bytes, asset: str, exe: str, folder: Path):
    folder.mkdir(parents=True, exist_ok=True)
    if asset.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            (folder / exe).write_bytes(archive.read(exe))
    else:
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            member = archive.extractfile(exe)
            (folder / exe).write_bytes(member.read())
        (folder / exe).chmod(0o755)


# ---------------------------------------------------------------- GitHub

def github_token() -> str | None:
    """GH_TOKEN, GITHUB_TOKEN, or git's stored credential for github.com. Never printed."""
    for name in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    try:
        result = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                                capture_output=True, text=True, timeout=15,
                                env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never"})
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in result.stdout.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    return None


def github_json(path: str, token: str | None) -> dict:
    headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"https://api.github.com{path}", headers=headers)
    with urllib.request.urlopen(request, timeout=20) as answer:
        return json.load(answer)


def origin_slug(repo: Path) -> str | None:
    code, url = git_ok(repo, "remote", "get-url", "origin")
    match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url) if code == 0 else None
    return match.group(1) if match else None


def red_workflows(runs: list[dict]) -> list[dict]:
    """The latest completed push or schedule run of each workflow, where it failed."""
    latest: dict[int, dict] = {}
    for item in sorted(runs, key=lambda r: r.get("created_at", ""), reverse=True):
        if item.get("event") in ("push", "schedule") and item.get("status") == "completed":
            latest.setdefault(item["workflow_id"], item)
    return [r for r in latest.values() if r.get("conclusion") in ("failure", "timed_out", "startup_failure")]


# ---------------------------------------------------------------- checks

def check_hygiene(ctx: Context, report: Report):
    problems = []
    tree = git(ctx.repo, "ls-tree", "-r", "-z", "--full-tree", ctx.head)
    for entry in tree.split("\0"):
        if "\t" in entry:
            meta, path = entry.split("\t", 1)
            if path.endswith(".sh") and meta.split()[0] != "100755":
                problems.append(f"{path} isn't executable: git update-index --chmod=+x {path}")
    for path in ctx.changed:
        if FORBIDDEN.search(path):
            problems.append(f"{path} must not be committed (local secrets or machine settings)")
    if ctx.base is not None and ctx.changed:
        diff = subprocess.run(["git", "-C", str(ctx.repo), "diff", "--no-color", "--no-ext-diff", "-U0",
                               ctx.base, ctx.head, "--", *ctx.changed[:400]], capture_output=True).stdout
        lf_only = _eol_lf_paths(ctx)
        current = ""
        for raw in diff.split(b"\n"):
            if raw.startswith(b"+++ b/"):
                current = raw[6:].decode("utf-8", "replace")
            elif raw.startswith(b"+") and not raw.startswith(b"+++"):
                line = raw[1:]
                if line.startswith((b"<<<<<<< ", b">>>>>>> ")):
                    problems.append(f"{current}: merge conflict marker")
                if current in lf_only and line.endswith(b"\r"):
                    problems.append(f"{current}: CRLF line ending in a file that must stay LF (.gitattributes)")
    sizes = git(ctx.repo, "ls-tree", "-r", "-l", "--full-tree", ctx.head, "--", *ctx.changed[:400]) if ctx.changed else ""
    for line in sizes.splitlines():
        meta, path = line.split("\t", 1)
        size = meta.split()[3]
        if size.isdigit() and int(size) > 5_000_000:
            report.warn("hygiene", f"{path} is {int(size) // 1_000_000} MB; keep binaries out of git")
    unique = sorted(set(problems))
    if unique:
        report.fail("hygiene", "\n".join(unique))
    else:
        report.ok("hygiene", "executable scripts, no conflict markers, no local secret files, line endings")


def _eol_lf_paths(ctx: Context) -> set[str]:
    if not ctx.changed:
        return set()
    out = subprocess.run(["git", "-C", str(ctx.repo), "check-attr", "eol", "--", *ctx.changed[:400]],
                         capture_output=True, text=True).stdout
    return {line.split(": eol: ")[0] for line in out.splitlines() if line.endswith(": eol: lf")}


def check_red_main(ctx: Context, report: Report):
    if not ctx.to_default_branch:
        report.skip("red-main", f"not a push to {ctx.default_branch}")
        return
    slug = origin_slug(ctx.repo)
    if not slug:
        report.skip("red-main", "origin isn't a GitHub repository")
        return
    try:
        runs = github_json(f"/repos/{slug}/actions/runs?branch={ctx.default_branch}&per_page=60"
                           "&exclude_pull_requests=true", github_token())["workflow_runs"]
    except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
        report.warn("red-main", f"couldn't ask GitHub for the CI state of {slug}: {error}")
        return
    red = red_workflows(runs)
    if not red:
        report.ok("red-main", f"{ctx.default_branch} is green on GitHub")
        return
    lines = [f"{r['name']} failed on {ctx.default_branch}: {r['html_url']}" for r in red]
    if os.environ.get("RIOT2_PREFLIGHT_FIXES_RED") == "1":
        report.warn("red-main", "\n".join(lines + ["RIOT2_PREFLIGHT_FIXES_RED=1: this push says it fixes them"]))
    else:
        report.fail("red-main", "\n".join(lines + [
            "Fix the failure first: read the failed job's log, fix it, and push that fix with",
            "RIOT2_PREFLIGHT_FIXES_RED=1 set. Don't stack other changes on a red branch."]))


def check_tags(ctx: Context, report: Report):
    if not ctx.tags:
        report.skip("tags", "no x.y.z tag pushed")
        return
    problems, notes = [], []
    existing = [t for t in git(ctx.repo, "tag", "--list").splitlines() if RELEASE_TAG.match(t)]
    for push in ctx.tags:
        tag, sha = push.name, commit_of(ctx.repo, push.local_sha)
        for file, pattern in (("Directory.Build.repo.props", r"<Version>([^<]+)</Version>"),
                              ("package.json", r'^\s*"version"\s*:\s*"([^"]+)"'),
                              ("VERSION", r"^\s*(\S+)\s*$")):
            code, content = git_ok(ctx.repo, "show", f"{sha}:{file}")
            match = re.search(pattern, content, re.MULTILINE) if code == 0 else None
            if match and match.group(1) != tag:
                problems.append(f"tag {tag}: {file} says {match.group(1)}. Bump it to {tag}, commit, and tag that commit.")
        newer = [t for t in existing if t != tag and version_key(t) > version_key(tag)]
        if newer:
            notes.append(f"tag {tag} is older than {max(newer, key=version_key)}: is this the release you meant?")
        code, changelog = git_ok(ctx.repo, "show", f"{sha}:CHANGELOG.md")
        if code == 0 and tag not in changelog:
            notes.append(f"tag {tag}: CHANGELOG.md doesn't mention {tag}")
    for note in notes:
        report.warn("tags", note)
    if problems:
        report.fail("tags", "\n".join(problems))
    else:
        report.ok("tags", ", ".join(p.name for p in ctx.tags))


def source_version(repo: Path) -> str | None:
    """The literal <Version> in Directory.Build.repo.props (RIoT2.Core, RIoT2.Elsa), if any."""
    props = repo / "Directory.Build.repo.props"
    match = re.search(r"<Version>(\d+\.\d+\.\d+)</Version>", props.read_text(encoding="utf-8")) if props.exists() else None
    return match.group(1) if match else None


def core_versions() -> tuple[str | None, list[tuple[str, str, str]]]:
    """RIoT2.Core's source version, and every (repository, package, version) pin in the workspace."""
    pins = []
    for packages in sorted(WORKSPACE.glob("*/Directory.Packages.props")):
        for package, version in CORE_PACKAGE.findall(packages.read_text(encoding="utf-8")):
            pins.append((packages.parent.name, package, version))
    return source_version(WORKSPACE / "RIoT2.Core"), pins


def released_version_problem(repo_name: str, source: str | None, tags: list[str]) -> str | None:
    released = max((t for t in tags if RELEASE_TAG.match(t)), key=version_key, default=None)
    if source and released and version_key(released) > version_key(source):
        return (f"{repo_name}'s Directory.Build.repo.props says {source}, but {released} is released: "
                f"set <Version> to {released}.")
    return None


def core_sync_problems(source: str | None, pins: list[tuple[str, str, str]], tags: list[str]) -> list[str]:
    problems = []
    if source is None:
        return problems
    behind = released_version_problem("RIoT2.Core", source, tags)
    if behind:
        problems.append(behind)
    for repo, package, version in pins:
        if version_key(version) > version_key(source):
            problems.append(f"{repo} pins {package} {version}, above RIoT2.Core's source version {source}. "
                            "RIoT2.Tests builds both and fails (CS1704): raise RIoT2.Core's <Version>.")
    return problems


def check_core_sync(ctx: Context, report: Report):
    problems = []
    own = source_version(ctx.repo)
    if own and ctx.name != "RIoT2.Core":
        behind = released_version_problem(ctx.name, own, git(ctx.repo, "tag", "--list").splitlines())
        if behind:
            problems.append(behind)
    relevant = ctx.name in ("RIoT2.Core", "RIoT2.Tests") or ctx.touched(r"(^|/)Directory\.(Packages|Build\.repo)\.props$")
    if relevant or ctx.full:
        source, pins = core_versions()
        core = WORKSPACE / "RIoT2.Core"
        tags = git(core, "tag", "--list").splitlines() if (core / ".git").exists() else []
        problems += core_sync_problems(source, pins, tags)
        detail = f"RIoT2.Core {source}; no repository pins a newer package"
    elif own:
        detail = f"source version {own} isn't behind a released tag"
    else:
        report.skip("core-sync", "no package version changed")
        return
    if problems:
        report.fail("core-sync", "\n".join(problems))
    else:
        report.ok("core-sync", detail)


def check_siblings(ctx: Context, report: Report):
    siblings = ctx.config.get("siblings", [])
    if not siblings or ctx.doc_only:
        report.skip("siblings", "none" if not siblings else "documentation only")
        return
    problems = []
    for name in siblings:
        sibling = WORKSPACE / name
        if not (sibling / ".git").exists():
            report.warn("siblings", f"{name} isn't checked out next to this repository; CI clones it")
            continue
        branch = default_branch(sibling)
        run(["git", "-C", str(sibling), "fetch", "--quiet", "origin", branch], sibling, timeout=30)
        code, counts = git_ok(sibling, "rev-list", "--left-right", "--count", f"refs/remotes/origin/{branch}...HEAD")
        if code:
            continue
        behind, ahead = (int(x) for x in counts.split())
        if ahead:
            problems.append(f"{name} has {ahead} commit(s) not on origin/{branch}. CI builds against {name}'s "
                            f"{branch}: push {name} first (producer before consumer).")
        if behind:
            report.warn("siblings", f"{name} is {behind} commit(s) behind origin/{branch}: pull it, CI uses the newer one")
        if git_ok(sibling, "status", "--porcelain", "--untracked-files=no")[1]:
            report.warn("siblings", f"{name} has uncommitted changes that this run builds against; CI won't have them")
    if problems:
        report.fail("siblings", "\n".join(problems))
    else:
        report.ok("siblings", ", ".join(siblings))


def check_secrets(ctx: Context, report: Report):
    try:
        gitleaks = tool_gitleaks()
    except (OSError, urllib.error.URLError, RuntimeError) as error:
        report.warn("secrets", f"gitleaks unavailable ({error}); CI scans the history")
        return
    commits = f"{ctx.base}..{ctx.head}" if ctx.base else ctx.head
    args = [str(gitleaks), "git", str(ctx.repo), "--log-opts", commits, "--redact", "--no-banner",
            "--exit-code", "1", "--log-level", "warn"]
    if (ctx.repo / ".gitleaks.toml").exists():
        args += ["--config", str(ctx.repo / ".gitleaks.toml")]
    code, out = run(args, ctx.repo, timeout=300)
    if code == 0:
        report.ok("secrets", f"gitleaks, {commits.replace(ctx.head, ctx.head[:8]).replace(str(ctx.base), str(ctx.base)[:8])}")
    else:
        report.fail("secrets", tail(out, 30) + "\nRotate a real credential first; allowlist only reviewed test "
                    "material in .gitleaks.toml (tools/secret-scan).")


def check_markdown(ctx: Context, report: Report):
    files = ctx.touched(r"\.md$") if ctx.config.get("markdownlint") else []
    if not files:
        report.skip("markdown", "no Markdown changed" if ctx.config.get("markdownlint") else "CI doesn't lint Markdown here")
        return
    npx = shutil.which("npx")
    if not npx:
        report.warn("markdown", "npx isn't installed; CI runs markdownlint")
        return
    code, out = run([npx, "--yes", f"markdownlint-cli2@{TOOLS['markdownlint-cli2']}", *files], ctx.repo, timeout=300)
    if code == 0:
        report.ok("markdown", f"{len(files)} file(s)")
    else:
        report.fail("markdown", "\n".join(l for l in out.splitlines() if re.search(r":\d+(:\d+)? MD\d+", l)) or tail(out))


def check_workflows(ctx: Context, report: Report):
    files = ctx.touched(r"^\.github/workflows/[^/]+\.ya?ml$")
    if not files:
        report.skip("workflows", "no workflow changed")
        return
    try:
        actionlint = tool_actionlint()
    except (OSError, urllib.error.URLError, RuntimeError) as error:
        report.warn("workflows", f"actionlint unavailable ({error}); the hub's CI lints its workflows")
        return
    code, out = run([str(actionlint), "-no-color", *files], ctx.repo, timeout=120)
    if code == 0:
        report.ok("workflows", f"actionlint, {len(files)} file(s)")
    else:
        report.fail("workflows", tail(out))


def check_docs(ctx: Context, report: Report):
    script = HUB / "tools" / "docs-check" / "check_docs.py"
    if not script.exists():
        report.skip("docs", "docs-check isn't in the workspace")
        return
    code, out = run([sys.executable, str(script), "--workspace", str(WORKSPACE)], WORKSPACE, timeout=300)
    errors = [l for l in out.splitlines() if l.startswith("ERROR")]
    mine = [l for l in errors if f" {ctx.name}/" in l or (ctx.name == ".github" and " .github/" in l)]
    for line in errors:
        if line not in mine:
            report.warn("docs", f"another repository: {line}")
    if mine:
        report.fail("docs", "\n".join(mine))
    elif code and not errors:
        report.fail("docs", tail(out))
    else:
        report.ok("docs", "docs-check")


def check_python(ctx: Context, report: Report):
    tests = sorted({t for prefix, scripts in ctx.config.get("python", {}).items()
                    for t in scripts if ctx.full or ctx.touched("^" + re.escape(prefix))})
    if not tests:
        report.skip("python", "no tested tool changed")
        return
    failed = []
    for test in tests:
        path = ctx.repo / test
        code, out = run([sys.executable, path.name], path.parent, timeout=600)
        if code:
            failed.append(f"{test} (log: {save_log('python-' + path.stem, out)})\n{tail(out, 20)}")
    if failed:
        report.fail("python", "\n".join(failed))
    else:
        report.ok("python", ", ".join(tests))


def check_pins(ctx: Context, report: Report):
    if not ctx.config.get("pins") or not (ctx.full or ctx.touched(r"^deploy/")):
        report.skip("pins", "deploy/ didn't change")
        return
    sys.path.insert(0, str(ctx.repo / "tools" / "compose-smoke"))
    try:
        import pins  # noqa: PLC0415
        problems = pins.missing_pins(ctx.repo / "deploy")
    except Exception as error:  # the registry, or the module itself
        report.warn("pins", f"couldn't check the image pins: {error}")
        return
    finally:
        sys.path.pop(0)
    if problems:
        report.fail("pins", "\n".join(problems))
    else:
        report.ok("pins", "every pinned RIoT2 image is published")


def check_shellcheck(ctx: Context, report: Report):
    files = ctx.touched(r"\.sh$")
    if not files:
        report.skip("shellcheck", "no shell script changed")
        return
    shellcheck = shutil.which("shellcheck")
    if not shellcheck:
        report.skip("shellcheck", "shellcheck isn't installed; CI runs it")
        return
    code, out = run([shellcheck, *files], ctx.repo, timeout=120)
    if code:
        report.fail("shellcheck", tail(out))
    else:
        report.ok("shellcheck", f"{len(files)} file(s)")


def _dotnet(repo: Path, build: list[str], tests: list[str], label: str) -> str | None:
    """Builds and tests like dotnet-validate.yml, with warnings as errors (-p:CI=true). None: passed."""
    for target in build:
        code, out = run(["dotnet", "build", target, "-c", "Release", "-p:CI=true", "-nologo", "-v", "q"], repo)
        if code:
            errors = sorted({l.strip() for l in out.splitlines() if re.search(r"\b(error|warning) [A-Z]+\d+", l)})
            return (f"dotnet build {target} (log: {save_log(label + '-build', out)})\n"
                    + ("\n".join(errors[:25]) or tail(out)))
    for target in tests:
        code, out = run(["dotnet", "test", target, "-c", "Release", "-p:CI=true", "-nologo"], repo)
        if code:
            failed = [l.strip() for l in out.splitlines() if re.match(r"\s*(Failed|error) ", l)]
            return (f"dotnet test {target} (log: {save_log(label + '-test', out)})\n"
                    + ("\n".join(failed[:25]) or tail(out)))
    return None


def check_dotnet(ctx: Context, report: Report):
    spec = ctx.config.get("dotnet")
    if not spec:
        report.skip("dotnet", "not a .NET repository")
        return
    if not shutil.which("dotnet"):
        report.fail("dotnet", "the .NET SDK isn't installed")
        return
    problem = _dotnet(ctx.repo, spec["build"], spec["test"], ctx.name)
    if problem:
        report.fail("dotnet", problem)
    else:
        report.ok("dotnet", f"build {' '.join(spec['build'])}" + (f"; test {' '.join(spec['test'])}" if spec["test"] else ""))


def _npm(repo: Path, entries: list[dict], label: str, scripts_filter=None) -> str | None:
    npm = shutil.which("npm")
    if not npm:
        return "npm isn't installed"
    for entry in entries:
        folder = repo / entry["dir"]
        if not (folder / "node_modules").exists():
            code, out = run([npm, "ci", "--no-audit", "--no-fund"], folder)
            if code:
                return f"npm ci in {entry['dir']} (log: {save_log(label + '-npm-ci', out)})\n{tail(out)}"
        for script in entry["scripts"]:
            if scripts_filter and script not in scripts_filter:
                continue
            code, out = run([npm, "run", script], folder)
            if code:
                return f"npm run {script} in {entry['dir']} (log: {save_log(label + '-npm-' + script, out)})\n{tail(out)}"
    return None


def check_npm(ctx: Context, report: Report):
    entries = ctx.config.get("npm")
    if not entries:
        report.skip("npm", "no npm project")
        return
    problem = _npm(ctx.repo, entries, ctx.name)
    if problem:
        report.fail("npm", problem)
    else:
        report.ok("npm", "; ".join(f"{e['dir']}: {' '.join(e['scripts'])}" for e in entries))


def check_firmware(ctx: Context, report: Report):
    spec = ctx.config.get("firmware")
    if not spec:
        report.skip("firmware", "not a firmware repository")
        return
    problems, ran = [], []
    shared = WORKSPACE / "RIoT2.Ard.Shared"
    compiler = os.environ.get("CXX") or shutil.which("cl") or shutil.which("c++") or shutil.which("g++")
    if spec.get("hostTests") and compiler and (shared / "tests").exists():
        for test in sorted((shared / "tests").glob("test_*.py")):
            code, out = run([sys.executable, f"tests/{test.name}"], shared, timeout=900)
            ran.append(test.name)
            if code:
                problems.append(f"Ard.Shared {test.name} (log: {save_log('firmware-' + test.stem, out)})\n{tail(out, 20)}")
    elif spec.get("hostTests"):
        report.skip("firmware", "no C++ compiler (CXX, cl or c++): the host tests run in CI")
    pio = shutil.which("pio") or str(Path.home() / ".platformio" / "penv" / ("Scripts/pio.exe" if os.name == "nt" else "bin/pio"))
    if Path(pio).exists() or shutil.which("pio"):
        for project in spec.get("pio", []):
            code, out = run([pio, "run", "-d", str(WORKSPACE / project)], WORKSPACE, timeout=1800)
            ran.append(f"pio {project}")
            if code:
                problems.append(f"pio run {project} (log: {save_log('pio-' + project, out)})\n{tail(out, 20)}")
    else:
        report.skip("firmware", "PlatformIO isn't installed: the firmware builds run in CI")
    if problems:
        report.fail("firmware", "\n".join(problems))
    elif ran:
        report.ok("firmware", ", ".join(ran))


def check_downstream(ctx: Context, report: Report):
    names = ctx.config.get("downstream", [])
    if not names:
        report.skip("downstream", "no other repository builds against this one")
        return
    problems, ran = [], []
    for name in names:
        repo = WORKSPACE / name
        spec = MANIFEST["repositories"].get(name, {})
        if not (repo / ".git").exists():
            report.warn("downstream", f"{name} isn't checked out; its CI runs against your push")
            continue
        if spec.get("dotnet"):
            tests = spec["dotnet"]["test"] or spec["dotnet"]["build"]
            problem = _dotnet(repo, [], tests, f"downstream-{name}") if spec["dotnet"]["test"] else \
                _dotnet(repo, tests, [], f"downstream-{name}")
            if problem:
                problems.append(f"{name}: {problem}")
        if spec.get("npm"):
            problem = _npm(repo, spec["npm"], f"downstream-{name}", scripts_filter={"test"})
            if problem:
                problems.append(f"{name}: {problem}")
        ran.append(name)
    if problems:
        report.fail("downstream", "\n".join(problems + [
            "These repositories build against this one's main: fix them in the same change, and push this "
            "repository first."]))
    elif ran:
        report.ok("downstream", ", ".join(ran))


CHECKS = {
    "hygiene": check_hygiene, "red-main": check_red_main, "tags": check_tags, "core-sync": check_core_sync,
    "siblings": check_siblings, "secrets": check_secrets, "markdown": check_markdown,
    "workflows": check_workflows, "docs": check_docs, "python": check_python, "pins": check_pins,
    "shellcheck": check_shellcheck, "dotnet": check_dotnet, "npm": check_npm, "firmware": check_firmware,
    "downstream": check_downstream,
}


# ---------------------------------------------------------------- stamp

def stamp_path(repo: Path) -> Path:
    git_dir = Path(git(repo, "rev-parse", "--absolute-git-dir"))
    return git_dir / "riot2-preflight.json"


def read_stamp(repo: Path) -> dict:
    try:
        return json.loads(stamp_path(repo).read_text(encoding="utf-8"))
    except (OSError, ValueError, RuntimeError):
        return {}


def write_stamp(ctx: Context, checks: list[str], clean: bool):
    data = {"head": ctx.head, "base": ctx.base, "clean": clean, "full": ctx.full, "checks": checks,
            "time": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
    stamp_path(ctx.repo).write_text(json.dumps(data, indent=2), encoding="utf-8")


# ---------------------------------------------------------------- main

def plan(ctx: Context) -> list[str]:
    names = list(CHECKS)
    if ctx.only:
        names = [n for n in names if n in ctx.only]
    if ctx.quick or ctx.doc_only:
        names = [n for n in names if n not in HEAVY]
    return [n for n in names if n not in ctx.skip]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="RIoT2 preflight: CI's checks, before a push.")
    parser.add_argument("--repo", default=".", help="repository to check (default: the current one)")
    parser.add_argument("--base", help="check BASE..HEAD instead of what a push to the upstream would send")
    parser.add_argument("--full", action="store_true", help="every check, whatever changed")
    parser.add_argument("--quick", action="store_true", help="no builds or tests")
    parser.add_argument("--only", default="", help="comma-separated checks: " + ", ".join(CHECKS))
    parser.add_argument("--hook", nargs="*", metavar="REMOTE", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    code, top = git_ok(Path(args.repo).resolve(), "rev-parse", "--show-toplevel")
    if code:
        print(f"preflight: {args.repo} isn't a git repository", file=sys.stderr)
        return 2
    repo = Path(top).resolve()
    name = repo.name
    config = MANIFEST["repositories"].get(name)
    if config is None:
        print(f"preflight: {name} isn't a RIoT2 repository in preflight.json; nothing to check")
        return 0
    branch = default_branch(repo)
    hook = args.hook is not None
    pushes = parse_push_lines(sys.stdin.read()) if hook else manual_push(repo, branch)
    if hook and not pushes:
        return 0
    head = commit_of(repo, pushes[0].local_sha)
    if args.base:
        base = git(repo, "rev-parse", args.base)
    else:
        bases = [base_for(repo, p, branch) for p in pushes if not p.is_tag] or [base_for(repo, pushes[0], branch)]
        base = bases[0]
    changed = changed_files(repo, base, head)
    skip = {s for s in os.environ.get("RIOT2_PREFLIGHT_SKIP", "").split(",") if s}
    ctx = Context(repo, name, config, pushes, head, base, changed, branch, args.full or any(p.is_tag for p in pushes),
                  args.quick, hook, {s for s in args.only.split(",") if s}, skip)

    working_head = git(repo, "rev-parse", "HEAD")
    clean = not git_ok(repo, "status", "--porcelain", "--untracked-files=no")[1]
    stamp = read_stamp(repo)
    reuse = hook and stamp.get("head") == head and stamp.get("clean") and not ctx.only
    names = plan(ctx)
    if reuse:
        names = [n for n in names if n in ("red-main", "tags") or n not in stamp.get("checks", [])]

    refs = ", ".join(p.name for p in pushes)
    print(f"preflight {name} -> {refs}: {len(changed)} changed file(s) since "
          f"{base[:8] if base else 'the first commit'}" + (" (documentation only)" if ctx.doc_only else ""))
    if reuse:
        print(f"  (passed by hand for {head[:8]} at {stamp.get('time')}; only the push-specific checks run again)")
    if head != working_head or not clean:
        print("  note: builds and tests use the working tree, which " +
              ("isn't the pushed commit" if head != working_head else "has uncommitted changes"))
    if ctx.skip:
        print(f"  note: RIOT2_PREFLIGHT_SKIP skips {', '.join(sorted(ctx.skip))}")

    report = Report()
    for check in [n for n in names if n in CHEAP]:
        _guarded(check, ctx, report)
    heavy = [n for n in names if n in HEAVY]
    if heavy and report.failures:
        report.skip("builds", f"{', '.join(heavy)} not run: fix the failures above first")
        heavy = []
    for check in heavy:
        _guarded(check, ctx, report)

    if report.failures:
        print(f"preflight FAILED: {', '.join(report.failures)}. Fix them, commit, and run preflight again.")
        print("  CI would fail the same way. Don't push with --no-verify.")
        return 1
    ran = [n for n in names if n not in report.failures]
    if head == working_head and not ctx.only:
        write_stamp(ctx, sorted(set(ran) | (set(stamp.get("checks", [])) if reuse else set())), clean)
    print(f"preflight passed ({len(report.warnings)} warning(s)). After pushing, watch the CI run until it's green.")
    return 0


def _guarded(check: str, ctx: Context, report: Report):
    try:
        CHECKS[check](ctx, report)
    except Exception as error:  # a broken check must not pass silently
        report.fail(check, f"the check itself failed: {type(error).__name__}: {error}")


if __name__ == "__main__":
    sys.exit(main())
