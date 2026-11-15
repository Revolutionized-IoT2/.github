"""Self-test of preflight.py and hooks/riot2_guard.py; the hub's CI runs it."""
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import preflight  # noqa: E402

spec = importlib.util.spec_from_file_location("riot2_guard", HERE.parents[1] / "hooks" / "riot2_guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

ZERO = "0" * 40


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
                   check=True, capture_output=True)


class TempRepo:
    def __init__(self, test):
        folder = tempfile.TemporaryDirectory()
        test.addCleanup(folder.cleanup)
        self.path = Path(folder.name)
        git(self.path, "init", "-q", "-b", "main")
        self.commit("README.md", "# x\n")
        self.base = self.rev()

    def commit(self, name, text, executable=False):
        path = self.path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode())
        git(self.path, "add", name)
        if name.endswith(".sh"):
            git(self.path, "update-index", f"--chmod={'+' if executable else '-'}x", name)
        git(self.path, "commit", "-q", "-m", name)

    def rev(self):
        return subprocess.run(["git", "-C", str(self.path), "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()

    def context(self, pushes=None, config=None):
        head = self.rev()
        pushes = pushes or [preflight.Push("refs/heads/main", head, "refs/heads/main", self.base)]
        return preflight.Context(self.path, "RIoT2.X", config or {}, pushes, head, self.base,
                                 preflight.changed_files(self.path, self.base, head), "main",
                                 False, False, True)


def run_check(check, ctx):
    report = preflight.Report()
    with redirect_stdout(io.StringIO()) as out:
        check(ctx, report)
    return report, out.getvalue()


class PushTest(unittest.TestCase):
    def test_hook_lines_drop_deletions(self):
        pushes = preflight.parse_push_lines(
            f"refs/heads/main {'a' * 40} refs/heads/main {'b' * 40}\n"
            f"(delete) {ZERO} refs/heads/old {'c' * 40}\n"
            f"refs/tags/1.2.3 {'d' * 40} refs/tags/1.2.3 {ZERO}\n")
        self.assertEqual([p.name for p in pushes], ["main", "1.2.3"])
        self.assertTrue(pushes[1].is_tag)

    def test_documentation_only(self):
        self.assertTrue(preflight.is_doc_only(["README.md", "docs/guides/ci.md", "docs/x.png"]))
        self.assertTrue(preflight.is_doc_only([".github/workflows/ci.yml", "CHANGELOG.md"]))
        self.assertFalse(preflight.is_doc_only(["README.md", "src/Program.cs"]))
        self.assertFalse(preflight.is_doc_only([]))


class RedMainTest(unittest.TestCase):
    def test_latest_push_or_schedule_run_per_workflow_decides(self):
        runs = [
            {"workflow_id": 1, "name": "CI", "event": "push", "status": "completed", "conclusion": "success",
             "created_at": "2026-11-15T12:00:00Z"},
            {"workflow_id": 1, "name": "CI", "event": "push", "status": "completed", "conclusion": "failure",
             "created_at": "2026-11-15T11:00:00Z"},
            {"workflow_id": 2, "name": "Deploy", "event": "push", "status": "completed", "conclusion": "failure",
             "created_at": "2026-11-15T11:30:00Z"},
            {"workflow_id": 2, "name": "Deploy", "event": "push", "status": "in_progress", "conclusion": None,
             "created_at": "2026-11-15T12:30:00Z"},
            {"workflow_id": 3, "name": "Nightly", "event": "workflow_dispatch", "status": "completed",
             "conclusion": "failure", "created_at": "2026-11-15T13:00:00Z"},
        ]
        self.assertEqual([r["name"] for r in preflight.red_workflows(runs)], ["Deploy"])


class CoreSyncTest(unittest.TestCase):
    def test_source_version_behind_the_released_tag(self):
        problems = preflight.core_sync_problems("2.4.1", [], ["2.4.0", "2.4.2", "not-a-version"])
        self.assertEqual(len(problems), 1)
        self.assertIn("set <Version> to 2.4.2", problems[0])

    def test_a_pin_above_the_source_version(self):
        problems = preflight.core_sync_problems("2.4.1", [("RIoT2.Elsa", "RIoT2.Core.Mqtt", "2.4.2"),
                                                          ("RIoT2.Net.Devices", "RIoT2.Core.Devices", "2.4.0")], ["2.4.1"])
        self.assertEqual(len(problems), 1)
        self.assertIn("RIoT2.Elsa pins RIoT2.Core.Mqtt 2.4.2", problems[0])

    def test_in_step(self):
        self.assertEqual(preflight.core_sync_problems("2.4.2", [("A", "RIoT2.Core.Mqtt", "2.4.2")], ["2.4.2"]), [])


class HygieneTest(unittest.TestCase):
    def test_clean_change_passes(self):
        repo = TempRepo(self)
        repo.commit("run.sh", "#!/bin/sh\n", executable=True)
        report, _ = run_check(preflight.check_hygiene, repo.context())
        self.assertEqual(report.failures, [])

    def test_script_mode_conflict_marker_and_local_secrets_fail(self):
        repo = TempRepo(self)
        repo.commit("run.sh", "#!/bin/sh\n")
        repo.commit("doc.md", "a\n<<<<<<< HEAD\nb\n")
        repo.commit("deploy/.env", "X=1\n")
        report, out = run_check(preflight.check_hygiene, repo.context())
        self.assertEqual(report.failures, ["hygiene"])
        self.assertIn("run.sh isn't executable", out)
        self.assertIn("doc.md: merge conflict marker", out)
        self.assertIn("deploy/.env must not be committed", out)


class TagTest(unittest.TestCase):
    def test_version_file_must_match_the_tag(self):
        repo = TempRepo(self)
        repo.commit("Directory.Build.repo.props", "<Project><PropertyGroup><Version>2.4.1</Version></PropertyGroup></Project>")
        head = repo.rev()
        ctx = repo.context([preflight.Push("refs/tags/2.4.2", head, "refs/tags/2.4.2", ZERO)])
        report, out = run_check(preflight.check_tags, ctx)
        self.assertEqual(report.failures, ["tags"])
        self.assertIn("Directory.Build.repo.props says 2.4.1", out)

    def test_matching_version_passes(self):
        repo = TempRepo(self)
        repo.commit("package.json", '{\n  "version": "1.15.0"\n}\n')
        repo.commit("CHANGELOG.md", "## 1.15.0\n")
        head = repo.rev()
        ctx = repo.context([preflight.Push("refs/tags/1.15.0", head, "refs/tags/1.15.0", ZERO)])
        report, _ = run_check(preflight.check_tags, ctx)
        self.assertEqual((report.failures, report.warnings), ([], []))


def shell(command, cwd=None, name="powershell", claude=False):
    if claude:
        return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command},
                "cwd": str(cwd or Path.cwd())}
    return {"toolName": name, "toolArgs": {"command": command}, "cwd": str(cwd or Path.cwd())}


class GuardTest(unittest.TestCase):
    def test_bypasses_are_denied(self):
        for command in ["git push --no-verify origin main", "git -c core.hooksPath=/dev/null push",
                        "git config core.hooksPath x", "$env:RIOT2_PREFLIGHT_SKIP='dotnet'; git push",
                        "Remove-Item .git\\riot2-preflight.json"]:
            self.assertIsNotNone(guard.decide_pre(shell(command)), command)

    def test_harmless_commands_pass(self):
        for command in ["git config --get core.hooksPath", "git status", "git push --dry-run origin main",
                        "Get-Content .git/riot2-preflight.json"]:
            self.assertIsNone(guard.decide_pre(shell(command)), command)
        self.assertIsNone(guard.decide_pre({"toolName": "view", "toolArgs": {"path": "x"}}))

    def test_push_targets(self):
        base = Path(tempfile.gettempdir())
        found = guard.pushes_in('cd "repo a"; git add .; git commit -m x; git -C sub push origin main', base)
        self.assertEqual(found, [(base / "repo a" / "sub", True)])
        self.assertEqual(guard.pushes_in("git push", base), [(base, False)])

    def test_a_push_outside_the_riot2_workspace_is_not_checked(self):
        repo = TempRepo(self)
        self.assertIsNone(guard.decide_pre(shell("git push origin main", repo.path)))

    def test_output_formats(self):
        copilot = guard.output("pre", shell("x"), "no")
        self.assertEqual(copilot, {"permissionDecision": "deny", "permissionDecisionReason": "no"})
        claude = guard.output("pre", shell("x", claude=True), "no")
        self.assertEqual(claude["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertEqual(guard.output("pre", shell("x"), None), {})

    def test_post_push_asks_for_the_ci_result(self):
        repo = TempRepo(self)
        message = guard.decide_post(shell("git push origin main", repo.path))
        self.assertIn("wait for them to complete", message)
        self.assertIsNone(guard.decide_post(shell("git status", repo.path)))

    def test_bad_input_never_crashes(self):
        result = subprocess.run([sys.executable, str(HERE.parents[1] / "hooks" / "riot2_guard.py"), "pre"],
                                input="not json", capture_output=True, text=True)
        self.assertEqual((result.returncode, json.loads(result.stdout)), (0, {}))


if __name__ == "__main__":
    unittest.main()
