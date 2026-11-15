#!/usr/bin/env python3
"""RIoT2 agent guardrail for Copilot and Claude tool hooks (tools/preflight/README.md).

    python .github/hooks/riot2_guard.py pre    # preToolUse: deny bypasses and unchecked pushes
    python .github/hooks/riot2_guard.py post   # postToolUse: after a push, ask for the CI result

Reads the hook event (JSON) on stdin and always prints one JSON object and exits 0: a command hook
that crashes would deny every tool call.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

HUB = Path(__file__).resolve().parents[1]
PREFLIGHT = HUB / "tools" / "preflight" / "preflight.py"
SHELL_TOOLS = {"bash", "powershell", "pwsh", "shell", "run_in_terminal", "runinterminal", "terminal"}
SEPARATORS = re.compile(r"\s*(?:;|&&|\|\||\||\r?\n)\s*")
CD = re.compile(r"^(?:cd|chdir|pushd|push-location|set-location|sl)\s+(?:/d\s+)?(?:-(?:literal)?path\s+)?(.+)$",
                re.IGNORECASE)

BYPASSES = [
    (re.compile(r"\bgit\b[^;\n|&]*\bpush\b[^;\n|&]*--no-verify", re.IGNORECASE),
     "`git push --no-verify` skips the RIoT2 preflight, and CI would fail the same way. Run the preflight, "
     "fix what it reports, and push normally."),
    (re.compile(r"-c\s*core\.hookspath\s*=|\bconfig\b(?![^;\n]*--(?:get|list))[^;\n]*core\.hookspath", re.IGNORECASE),
     "Changing core.hooksPath turns off the RIoT2 pre-push gate. Only tools/preflight/install-hooks.ps1 sets it."),
    (re.compile(r"RIOT2_PREFLIGHT_SKIP", re.IGNORECASE),
     "RIOT2_PREFLIGHT_SKIP is for a person who has decided to skip a check, not for an agent. Fix the failing "
     "check instead, or ask the user."),
    (re.compile(r"(?:remove-item|\brm\b|\bdel\b|\bri\b|set-content|out-file|add-content|new-item|copy-item|move-item|>)"
                r"[^;\n]*(?:git-hooks|pre-push|riot2-preflight\.json)", re.IGNORECASE),
     "That changes the RIoT2 pre-push gate or its record of a passed preflight. Run the preflight instead."),
]


def command_of(event: dict) -> str | None:
    name = str(event.get("toolName") or event.get("tool_name") or "").lower()
    if name not in SHELL_TOOLS:
        return None
    args = event.get("toolArgs", event.get("tool_input"))
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except ValueError:
            return args
    if isinstance(args, dict):
        command = args.get("command") or args.get("cmd") or args.get("script")
        return command if isinstance(command, str) else None
    return None


def _unquote(text: str) -> str:
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        return text[1:-1]
    return text


def pushes_in(command: str, cwd: Path) -> list[tuple[Path, bool]]:
    """(directory git runs in, whether a commit precedes it in the same command) per `git push`."""
    found, committed = [], False
    for segment in SEPARATORS.split(command):
        move = CD.match(segment)
        if move:
            target = Path(os.path.expanduser(_unquote(move.group(1))))
            cwd = target if target.is_absolute() else (cwd / target)
            continue
        try:
            words = shlex.split(segment, posix=False)
        except ValueError:
            words = segment.split()
        words = [_unquote(w) for w in words]
        if not words or Path(words[0]).stem.lower() != "git":
            continue
        where, i = cwd, 1
        while i < len(words) and words[i].startswith("-"):
            if words[i] == "-C" and i + 1 < len(words):
                where = Path(words[i + 1]) if Path(words[i + 1]).is_absolute() else cwd / words[i + 1]
                i += 1
            elif words[i] == "-c":
                i += 1
            i += 1
        verb = words[i].lower() if i < len(words) else ""
        if verb == "commit":
            committed = True
        if verb == "push" and not any(w in ("--dry-run", "-n") for w in words[i + 1:]):
            found.append((where, committed))
    return found


def _git(where: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(["git", "-C", str(where), *args], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def is_riot2(top: Path) -> bool:
    try:
        manifest = json.loads((HUB / "tools" / "preflight" / "preflight.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return top.name in manifest.get("repositories", {}) and top.parent == HUB.parent


def unchecked_push(where: Path, committed: bool) -> str | None:
    top = _git(where, "rev-parse", "--show-toplevel")
    if not top or not is_riot2(Path(top)):
        return None
    top_path = Path(top)
    git_dir = _git(top_path, "rev-parse", "--absolute-git-dir")
    head = _git(top_path, "rev-parse", "HEAD")
    try:
        stamp = json.loads((Path(git_dir) / "riot2-preflight.json").read_text(encoding="utf-8")) if git_dir else {}
    except (OSError, ValueError):
        stamp = {}
    run = f'python "{PREFLIGHT}" --repo "{top_path}"'
    if committed:
        return (f"Commit in its own command, then run the RIoT2 preflight ({run}), fix what it reports, and push "
                "in a separate command.")
    if stamp.get("head") == head and stamp.get("clean"):
        return None
    if stamp.get("head") == head:
        return f"The preflight for {top_path.name} ran with uncommitted changes. Commit or stash them and run it again: {run}"
    return (f"Run the RIoT2 preflight for {top_path.name} before pushing, and fix every FAIL it reports: {run}. "
            "It mirrors the CI checks, so the push won't turn the branch red.")


def decide_pre(event: dict) -> str | None:
    command = command_of(event)
    if not command:
        return None
    for pattern, reason in BYPASSES:
        if pattern.search(command) and "install-hooks.ps1" not in command:
            return reason
    cwd = Path(event.get("cwd") or os.getcwd())
    for where, committed in pushes_in(command, cwd):
        reason = unchecked_push(where, committed)
        if reason:
            return reason
    return None


def decide_post(event: dict) -> str | None:
    command = command_of(event)
    if not command:
        return None
    cwd = Path(event.get("cwd") or os.getcwd())
    names = sorted({Path(_git(w, "rev-parse", "--show-toplevel") or w).name for w, _ in pushes_in(command, cwd)})
    if not names:
        return None
    return (f"You pushed {', '.join(names)}. Its GitHub Actions runs start now. Before you finish or start other "
            "work, wait for them to complete. If one fails, read the failed job's log, fix the cause, run the "
            "preflight, and push the fix (skill: ci-preflight). Report the CI result to the user.")


def output(mode: str, event: dict, message: str | None) -> dict:
    if not message:
        return {}
    claude = "hook_event_name" in event
    if mode == "pre":
        result = {"permissionDecision": "deny", "permissionDecisionReason": message}
        if claude:
            result["hookSpecificOutput"] = {"hookEventName": "PreToolUse", **result}
        return result
    result = {"additionalContext": message}
    if claude:
        result["hookSpecificOutput"] = {"hookEventName": "PostToolUse", "additionalContext": message}
    return result


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "pre"
    try:
        event = json.loads(sys.stdin.read() or "{}")
        message = decide_pre(event) if mode == "pre" else decide_post(event)
        print(json.dumps(output(mode, event, message)))
    except Exception:  # never deny every tool because of a bug here
        print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
