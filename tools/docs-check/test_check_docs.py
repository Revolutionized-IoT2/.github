"""Self-test for check_docs.py: builds a small synthetic workspace and injects one drift at a time.

Run: python .github/tools/docs-check/test_check_docs.py
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import check_docs  # noqa: E402

FILES = {
    ".github/docs/contracts/mqtt-topics.md": """# MQTT
## Topics
| Enum | Template |
|---|---|
| `NodeOnline` (1) | `riot2/node/{id}/online` |
| `Report` (4) | `riot2/node/{id}/report` |
## Payloads
`0` Unknown, `1` Device. `Boolean` (0), `Number` (2).
""",
    ".github/docs/contracts/configuration.md": "# Config\n`Boolean` (0), `Number` (2).\n",
    ".github/docs/contracts/env-vars.md": """# Env
| `RIOT2_NODE_ID` | yes |
## Planned (not implemented)
`RIOT2_SECURITY_MODE`
""",
    ".github/docs/contracts/http-api.md": """# HTTP
| GET | `/api/nodes/{id}/configuration` | config |
| GET | `/health` | health |
""",
    ".github/docs/README.md": "# Index\n\nSee [env](contracts/env-vars.md#env) and ![shot](guides/images/a.png).\n",
    ".github/docs/guides/images/a.png": "png",
    "RIoT2.Core/Constants.cs": 'class C { string a = "riot2/node/{id}/online"; string b = "riot2/node/{id}/report"; }',
    "RIoT2.Core/Enums.cs": """enum MqttTopic { NodeOnline = 1, Report = 4 }
enum NodeType { Unknown = 0, Device = 1 }
enum ValueType { Boolean = 0, Number = 2 }""",
    "RIoT2.Core/Config.cs": 'var id = Environment.GetEnvironmentVariable("RIOT2_NODE_ID");',
    "RIoT2.Core/README.md": "# Core\n",
    "RIoT2.Core/AGENTS.md": "# AGENTS.md\nhttps://github.com/Revolutionized-IoT2/.github/blob/main/AGENTS.md\n"
                            "## What this is\n## Commands\n## Layout\n## Rules\n## Pitfalls\n## Related work\n",
    "RIoT2.Core/CLAUDE.md": "@AGENTS.md\n",
    "RIoT2.Core/CHANGELOG.md": "# Changelog\n## [Unreleased]\n",
    "RIoT2.Net.Orchestrator/Controllers/NodesController.cs": """
[ApiController]
[Route("api/[controller]")]
public class NodesController : ControllerBase
{
    [HttpGet("{id}/configuration")]
    public IActionResult Get(string id) => Ok();
}""",
    "RIoT2.Net.Orchestrator/Program.cs": 'app.MapHealthChecks("/health");',
    "RIoT2.Net.Orchestrator/Protos/riot_trigger.proto": 'option csharp_namespace = "A";\npackage riot;\nmessage T { string id = 1; }\n',
    "RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Protos/riot.proto": 'option csharp_namespace = "B";\npackage riot;\nmessage T { string id = 1; }\n',
}
LAYOUT_REPOS = ("RIoT2.Net.Orchestrator", "RIoT2.Elsa", "RIoT2.Net.Node", "RIoT2.Net.Devices",
                "RIoT2.Connector.InfluxDB", "RIoT2.UI")  # every repository the env/route checks require


class DriftTests(unittest.TestCase):
    def setUp(self):
        self.ws = Path(tempfile.mkdtemp())
        for rel, content in FILES.items():
            p = self.ws / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")
        for repo in LAYOUT_REPOS:
            (self.ws / repo).mkdir(parents=True, exist_ok=True)
            for rel, content in FILES.items():
                if rel.startswith("RIoT2.Core/") and rel.endswith(".md"):
                    (self.ws / repo / Path(rel).name).write_text(content, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.ws, ignore_errors=True)

    def run_checks(self, only=None):
        repos = {".github": self.ws / ".github"}
        repos.update({p.name: p for p in self.ws.iterdir() if p.name.startswith("RIoT2.")})
        ctx = check_docs.Context(self.ws.resolve(), repos)
        for name in (only or check_docs.CHECKS):
            check_docs.CHECKS[name](ctx)
        return [f for f in ctx.findings if f.level == "ERROR"]

    def edit(self, rel, old, new):
        p = self.ws / rel
        text = p.read_text(encoding="utf-8")
        self.assertIn(old, text)
        p.write_text(text.replace(old, new), encoding="utf-8")

    def assertCaught(self, check, fragment):
        errors = self.run_checks([check])
        self.assertTrue(any(fragment in e.message for e in errors), f"{check} did not report '{fragment}': {errors}")

    def test_baseline_is_clean(self):
        self.assertEqual(self.run_checks(), [])

    def test_undocumented_topic(self):
        self.edit("RIoT2.Core/Constants.cs", "}", 'string c = "riot2/node/{id}/status"; }')
        self.assertCaught("mqtt", "riot2/node/{id}/status")

    def test_enum_value_changed(self):
        self.edit("RIoT2.Core/Enums.cs", "Number = 2", "Number = 3")
        self.assertCaught("enums", "ValueType.Number = 3")

    def test_undocumented_env_var(self):
        self.edit("RIoT2.Core/Config.cs", ";", '; var u = Environment.GetEnvironmentVariable("RIOT2_NODE_URL");')
        self.assertCaught("env", "RIOT2_NODE_URL is read by")

    def test_documented_env_var_without_code(self):
        self.edit(".github/docs/contracts/env-vars.md", "| `RIOT2_NODE_ID` | yes |", "| `RIOT2_NODE_ID` | yes |\n| `RIOT2_GONE` | yes |")
        self.assertCaught("env", "RIOT2_GONE is documented as current")

    def test_undocumented_route(self):
        self.edit("RIoT2.Net.Orchestrator/Controllers/NodesController.cs", "public IActionResult Get(string id) => Ok();",
                  'public IActionResult Get(string id) => Ok();\n    [HttpGet("online")]\n    public IActionResult Online() => Ok();')
        self.assertCaught("routes", "/api/nodes/online")

    def test_second_route_on_same_method(self):
        self.edit("RIoT2.Net.Orchestrator/Controllers/NodesController.cs", '[HttpGet("{id}/configuration")]',
                  '[HttpGet("{id}/configuration")]\n    [HttpGet("{id}/config")]')
        self.assertCaught("routes", "/api/nodes/{}/config ")

    def test_proto_drift(self):
        self.edit("RIoT2.Elsa/RIoT2.Elsa.Server/RIoT/Protos/riot.proto", "id = 1", "id = 2")
        self.assertCaught("proto", "gRPC contract differs")

    def test_broken_link_and_anchor(self):
        self.edit(".github/docs/README.md", "contracts/env-vars.md#env", "contracts/missing.md")
        self.assertCaught("links", "broken link")

    def test_missing_anchor(self):
        self.edit(".github/docs/README.md", "#env", "#nope")
        self.assertCaught("links", "missing anchor")

    def test_wrong_default_branch(self):
        subprocess.run(["git", "init", "-q", "-b", "master", str(self.ws / "RIoT2.Elsa")], check=True)
        self.edit(".github/docs/README.md", "# Index", "# Index\n[x](https://github.com/Revolutionized-IoT2/RIoT2.Elsa/blob/main/AGENTS.md)")
        self.assertCaught("links", "uses 'master'")

    def test_orphan_image(self):
        (self.ws / ".github/docs/guides/images/old.jpg").write_text("x")
        self.assertCaught("images", "not referenced")

    def test_claude_md_with_content(self):
        (self.ws / "RIoT2.Core/CLAUDE.md").write_text("# Claude\nlots of instructions\n")
        self.assertCaught("layout", "CLAUDE.md must contain only")

    def test_secret_from_launch_settings(self):
        settings = self.ws / "RIoT2.Core/Properties/launchSettings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"profiles":{"p":{"environmentVariables":{"RIOT2_NODE_ID":"5546B84F-E91C-423F-A80F-FF935EEBF299"}}}}')
        self.edit("RIoT2.Core/README.md", "# Core", "# Core\nRun with RIOT2_NODE_ID=5546B84F-E91C-423F-A80F-FF935EEBF299")
        self.assertCaught("secrets", "RIOT2_NODE_ID")

    def test_dead_code_reference(self):
        self.edit(".github/docs/contracts/mqtt-topics.md", "# MQTT", "# MQTT\nSource: `RIoT2.Core/Gone.cs`.")
        self.assertCaught("coderefs", "RIoT2.Core/Gone.cs")

    def test_hub_only_workspace_has_no_errors(self):
        for p in list(self.ws.iterdir()):
            if p.name.startswith("RIoT2."):
                shutil.rmtree(p)
        self.assertEqual(self.run_checks(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
