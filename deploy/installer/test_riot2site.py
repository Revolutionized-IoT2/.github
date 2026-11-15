"""Tests of riot2site.py, the installers' shared logic: python deploy/installer/test_riot2site.py"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import tempfile
import threading
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import riot2site


def run(*argv) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = riot2site.main([str(a) for a in argv])
    return code, out.getvalue(), err.getvalue()


def backup(path: Path, files: dict[str, bytes]) -> Path:
    riot2site.write_backup(path, {"format": "riot2-configuration-backup", "formatVersion": 1,
                                  "createdAt": "2026-11-14T10:00:00+00:00", "kind": "manual"}, files)
    return path


class Case(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, rel: str, content) -> Path:
        p = self.dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, (dict, list)):
            content = json.dumps(content)
        p.write_bytes(content if isinstance(content, bytes) else content.encode())
        return p


class Versions(Case):
    def expected(self, **images):
        return self.write("expected.json", {"services": {s: {"image": i} for s, i in images.items()}})

    def verdict(self, running: str, **kw):
        args = ["versions", "--expected", self.expected(ui="ghcr.io/x/riot2-ui:1.15.0", node="ghcr.io/x/riot2-node:2.4.0")]
        args += ["--running", self.write("running.txt", running)]
        for k, v in kw.items():
            args += [f"--{k}", v]
        code, out, _ = run(*args)
        self.assertEqual(code, 0)
        return out.splitlines()[0], out

    def test_nothing_installed_is_fresh(self):
        self.assertEqual(self.verdict("")[0], "verdict fresh")

    def test_volumes_without_containers_are_leftover(self):
        verdict, out = self.verdict("", volumes=self.write("v.txt", "riot2_node-data\n"))
        self.assertEqual(verdict, "verdict leftover")
        self.assertIn("riot2_node-data", out)

    def test_same_upgrade_and_downgrade(self):
        self.assertEqual(self.verdict("ui ghcr.io/x/riot2-ui:1.15.0\nnode ghcr.io/x/riot2-node:2.4.0")[0], "verdict same")
        verdict, out = self.verdict("ui ghcr.io/x/riot2-ui:1.14.0\nnode ghcr.io/x/riot2-node:2.4.0")
        self.assertEqual(verdict, "verdict upgrade")
        self.assertRegex(out, r"ui\s+1\.14\.0 -> 1\.15\.0\s+upgrade")
        verdict, out = self.verdict("ui ghcr.io/x/riot2-ui:1.16.0\nnode ghcr.io/x/riot2-node:2.3.9")
        self.assertEqual(verdict, "verdict downgrade", "one newer service makes it a downgrade")
        self.assertIn("DOWNGRADE", out)

    def test_versions_compare_numerically_and_a_new_service_is_an_upgrade(self):
        self.assertEqual(riot2site.compare_tags("1.9.0", "1.10.0"), "older")
        self.assertEqual(riot2site.compare_tags("v3.15.1", "v3.9.0"), "newer")
        self.assertEqual(riot2site.compare_tags("2.4.0-arm64v8", "2.4.1-arm64v8"), "older")
        self.assertEqual(riot2site.split_image("registry:5000/a/b:1.2@sha256:00"), ("registry:5000/a/b", "1.2"))
        self.assertEqual(self.verdict("ui ghcr.io/x/riot2-ui:1.15.0")[0], "verdict upgrade")

    def test_the_marker_stands_in_for_stopped_containers(self):
        marker = self.write("marker.json", {"installedAt": "then", "images": {"ui": "ghcr.io/x/riot2-ui:1.15.0",
                                                                               "node": "ghcr.io/x/riot2-node:2.4.0"}})
        self.assertEqual(self.verdict("", marker=marker)[0], "verdict same")


class Diff(Case):
    def site(self):
        self.write("site/deploy.env", "RIOT2_HOST=192.168.0.13\nRIOT2_MQTT_PASSWORD=secret\n")
        self.write("site/volumes/node-data/service_account.json", "{}")
        self.write("site/workflows/heat.json", {"definitionId": "heat"})
        return self.dir / "site"

    def test_reports_what_changed_since_the_marker_without_values(self):
        site = self.site()
        marker = self.dir / "marker.json"
        self.assertEqual(run("marker", "--site", site, "--expected", self.write("e.json", {}), "--out", marker,
                             "--host", "qnap", "--project", "riot2")[0], 0)
        self.assertEqual(run("diff", "--site", site, "--marker", marker)[1], "changed 0\n")

        self.write("site/deploy.env", "RIOT2_HOST=192.168.0.13\nRIOT2_MQTT_PASSWORD=other\nRIOT2_LAN_IP_UI=1\n")
        self.write("site/volumes/node-data/service_account.json", '{"a": 1}')
        out = run("diff", "--site", site, "--marker", marker)[1]
        self.assertIn("item settings deploy.env:RIOT2_MQTT_PASSWORD changed", out)
        self.assertIn("item settings deploy.env:RIOT2_LAN_IP_UI added", out)
        self.assertIn("item secret-files volumes/node-data/service_account.json changed", out)
        self.assertNotIn("other", out, "values never appear")


class Env(Case):
    def test_merge_keeps_the_installed_values_and_adds_new_keys(self):
        existing = self.write(".env", "RIOT2_HOST=a\nRIOT2_MQTT_PASSWORD=installed\n")
        site = self.write("site.env", "RIOT2_HOST=b\nRIOT2_MQTT_PASSWORD=site\nRIOT2_LAN_IP_UI=192.168.0.31\n# X=1\n")
        code, out, _ = run("env-merge", "--existing", existing, "--site", site, "--out", self.dir / "merged")
        self.assertEqual(code, 0)
        self.assertEqual(out, "added RIOT2_LAN_IP_UI\n")
        merged = (self.dir / "merged").read_text()
        self.assertTrue(merged.startswith("RIOT2_HOST=a\nRIOT2_MQTT_PASSWORD=installed\n"))
        self.assertIn("RIOT2_LAN_IP_UI=192.168.0.31", merged)
        self.assertNotIn("X=1", merged)
        out = run("env-diff", "--existing", existing, "--site", site)[1]
        self.assertIn("key RIOT2_HOST different", out)
        self.assertIn("key RIOT2_LAN_IP_UI new", out)

    def test_settings_a_service_refuses_stop_the_install(self):
        def check(password):
            env = {"DOCKER_INFLUXDB_INIT_PASSWORD": password}
            return run("settings", "--expected", self.write("e.json", {"services": {"influxdb": {"environment": env}}}))
        code, _, err = check("short")
        self.assertEqual(code, 2)
        self.assertIn("RIOT2_INFLUXDB_ADMIN_PASSWORD must be 8 to 72", err)
        self.assertNotIn("short", err, "the value never appears")
        self.assertEqual(check("12345678")[0], 0)
        self.assertEqual(check("ä" * 37)[0], 2, "InfluxDB counts bytes: 74")
        self.assertEqual(run("settings", "--expected", self.write("e.json", {"services": {"ui": {}}}))[0], 0)


class Seeds(Case):
    RULES = "node-data/netatmoAuth-*.json=once node-data/service_account.json=managed orchestrator-matter/attestation/*=managed"

    def seed(self, mode, *extra):
        return run("seed", "--volume", "node-data", "--volume-dir", self.dir / "volume", "--seed-dir",
                   self.dir / "site/volumes/node-data", "--owner", "0:0", "--rules", self.RULES, "--mode", mode, *extra)

    def test_rules_name_volumes_owners_and_rules(self):
        self.write("site/volumes/node-data/service_account.json", "{}")
        self.write("site/volumes/orchestrator-matter/attestation/dac.der", b"\x01")
        expected = self.write("e.json", {"volumes": {"node-data": {"name": "riot2_node-data"}, "orchestrator-matter": {}}})
        code, out, _ = run("rules", "--rules", self.RULES, "--seeds", self.dir / "site/volumes", "--expected", expected)
        self.assertEqual(code, 0)
        self.assertIn("volume node-data riot2_node-data 0:0", out, "the volume's Docker name comes from the compose files")
        self.assertIn("seed node-data service_account.json managed 0:0", out)
        self.assertIn("seed orchestrator-matter attestation/dac.der managed 1654:1654", out)

    def test_a_volume_only_a_rule_names_is_listed_for_the_export(self):
        self.write("site/volumes/orchestrator-matter/attestation/dac.der", b"\x01")
        expected = self.write("e.json", {"volumes": {"node-data": {"name": "riot2_node-data"}, "orchestrator-matter": {}}})
        out = run("rules", "--rules", self.RULES, "--seeds", self.dir / "site/volumes", "--expected", expected)[1]
        self.assertIn("volume node-data riot2_node-data 0:0 rule-only", out)
        self.assertEqual(out.count("volume node-data "), 1)

    def test_bad_rules_unknown_volumes_and_owners_are_input_errors(self):
        self.write("site/volumes/grafana-data/x.json", "{}")
        seeds = self.dir / "site/volumes"
        self.assertEqual(run("rules", "--rules", "node-data/*=always", "--seeds", seeds)[0], 2)
        self.assertEqual(run("rules", "--rules", "*.json=once", "--seeds", seeds)[0], 2)
        code, _, err = run("rules", "--seeds", seeds)
        self.assertEqual(code, 2)
        self.assertIn("VOLUME_OWNERS", err)
        self.assertEqual(run("rules", "--seeds", seeds, "--owners", "grafana-data=472:0")[0], 0)
        code, _, err = run("rules", "--seeds", seeds, "--owners", "grafana-data=472:0",
                           "--expected", self.write("e.json", {"volumes": {"node-data": {}}}))
        self.assertEqual(code, 2)
        self.assertIn("declare no volume grafana-data", err)

    def test_once_files_survive_use_installer_and_managed_files_are_replaced(self):
        self.write("site/volumes/node-data/netatmoAuth-abc.json", "site token")
        self.write("site/volumes/node-data/service_account.json", "site account")
        self.write("site/volumes/node-data/new/deep.json", "new")
        self.write("volume/netatmoAuth-abc.json", "rotated token")
        self.write("volume/service_account.json", "old account")

        code, out, _ = self.seed("keep")
        self.assertEqual(code, 0)
        self.assertIn("keep node-data/service_account.json managed", out)
        self.assertIn("write node-data/new/deep.json once", out)
        self.assertEqual((self.dir / "volume/service_account.json").read_text(), "old account")
        self.assertEqual((self.dir / "volume/new/deep.json").read_text(), "new")

        out = self.seed("installer")[1]
        self.assertIn("keep node-data/netatmoAuth-abc.json once", out)
        self.assertIn("same node-data/new/deep.json once", out)
        self.assertEqual((self.dir / "volume/netatmoAuth-abc.json").read_text(), "rotated token")
        self.assertEqual((self.dir / "volume/service_account.json").read_text(), "site account")

        self.seed("installer", "--overwrite-once")
        self.assertEqual((self.dir / "volume/netatmoAuth-abc.json").read_text(), "site token")
        self.assertEqual(list((self.dir / "volume").rglob("*.tmp")), [])

    def test_dry_run_writes_nothing(self):
        self.write("site/volumes/node-data/service_account.json", "site account")
        (self.dir / "volume").mkdir()
        self.assertIn("write node-data/service_account.json managed", self.seed("installer", "--dry-run")[1])
        self.assertFalse((self.dir / "volume/service_account.json").exists())

    def test_export_returns_rotated_once_files_and_new_named_ones(self):
        self.write("site/volumes/node-data/netatmoAuth-abc.json", "site token")
        self.write("site/volumes/node-data/service_account.json", "site account")
        self.write("volume/netatmoAuth-abc.json", "rotated token")
        self.write("volume/netatmoAuth-new.json", "second account")
        self.write("volume/service_account.json", "changed by hand")
        self.write("volume/configuration.applied.json", "{}")

        def export(*extra):
            return run("export-seeds", "--volume", "node-data", "--volume-dir", self.dir / "volume", "--seed-dir",
                       self.dir / "site/volumes/node-data", "--out", self.dir / "out", "--rules", self.RULES, *extra)[1]

        out = export()
        self.assertIn("export volumes/node-data/netatmoAuth-abc.json changed", out)
        self.assertIn("export volumes/node-data/netatmoAuth-new.json new", out)
        self.assertNotIn("service_account", out, "managed files come from the site")
        self.assertNotIn("configuration.applied", out, "only files the site has or a rule names")
        self.assertEqual((self.dir / "out/volumes/node-data/netatmoAuth-abc.json").read_text(), "rotated token")
        self.assertIn("service_account.json changed", export("--managed"))
        allowed = self.write("allowed.txt", "volumes/node-data/service_account.json\n")
        self.assertIn("skip volumes/node-data/netatmoAuth-abc.json changed-in-site", export("--allowed", allowed))


class Matter(Case):
    SITE = {"StoredObjects/Variable/a.json": b"{\"id\":\"a\"}",
            "StoredObjects/MatterConfiguration/default.json": b"{\"enabled\":true,\"vendorId\":1}",
            "MatterCredentials/fabrics.json": b"site fabrics"}
    LIVE = {"StoredObjects/Variable/a.json": b"{\"id\":\"live\"}",
            "StoredObjects/MatterBridgeState/default.json": b"{}",
            "MatterCredentials/fabrics.json": b"live fabrics",
            "MatterCredentials/attestation/dac.der": b"\x30\x82"}

    def test_the_running_pairing_replaces_the_sites_and_the_manifest_stays_valid(self):
        site, live = backup(self.dir / "site.zip", self.SITE), backup(self.dir / "live.zip", self.LIVE)
        code, out, _ = run("merge-matter", "--site", site, "--live", live, "--out", self.dir / "out.zip")
        self.assertEqual((code, out), (0, "matter live 3\n"))
        with zipfile.ZipFile(self.dir / "out.zip") as zf:
            self.assertEqual(zf.namelist()[0], riot2site.MANIFEST, "the manifest is the first entry")
            manifest = json.loads(zf.read(riot2site.MANIFEST))
            entries = {i.filename: zf.read(i) for i in zf.infolist() if i.filename != riot2site.MANIFEST}
        self.assertEqual(manifest["kind"], "manual", "the site's manifest fields are kept")
        self.assertEqual(entries["StoredObjects/Variable/a.json"], self.SITE["StoredObjects/Variable/a.json"])
        self.assertEqual(entries["MatterCredentials/fabrics.json"], b"live fabrics")
        self.assertNotIn("StoredObjects/MatterConfiguration/default.json", entries)
        self.assertIn("MatterCredentials/attestation/dac.der", entries)
        # What BackupArchive.Read checks: every entry listed once, with its size and SHA-256.
        listed = {f["path"]: f for f in manifest["files"]}
        self.assertEqual(set(listed), set(entries))
        for name, content in entries.items():
            self.assertEqual(listed[name]["size"], len(content))
            self.assertEqual(listed[name]["sha256"], hashlib.sha256(content).hexdigest())

    def test_without_a_running_pairing_or_with_replace_the_site_is_restored_as_it_is(self):
        site = backup(self.dir / "site.zip", self.SITE)
        no_matter = backup(self.dir / "live.zip", {"StoredObjects/Variable/a.json": b"{}"})
        self.assertIn("matter site 2", run("merge-matter", "--site", site, "--live", no_matter, "--out", self.dir / "a.zip")[1])
        self.assertEqual((self.dir / "a.zip").read_bytes(), site.read_bytes())
        live = backup(self.dir / "live2.zip", self.LIVE)
        self.assertIn("--replace-matter", run("merge-matter", "--site", site, "--live", live, "--out", self.dir / "b.zip",
                                              "--replace")[1])
        self.assertEqual((self.dir / "b.zip").read_bytes(), site.read_bytes())


class Plugins(Case):
    def package(self, entries: dict[str, bytes]) -> tuple[str, str]:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as zf:
            for name, content in entries.items():
                zf.writestr(name, content)
        path = self.write("RIoT2.Net.Devices_3.0.0.zip", buffer.getvalue())
        return path.resolve().as_uri(), hashlib.sha256(buffer.getvalue()).hexdigest()

    def test_stages_a_verified_package_once(self):
        url, digest = self.package({"RIoT2.Net.Devices.dll": b"MZ", "PluginManifest.json": b'{"version":"3.0.0"}'})
        self.write("RIoT2.Net.Devices_3.0.0.zip.sha256", f"{digest}  RIoT2.Net.Devices_3.0.0.zip\n")
        (self.dir / "plugins").mkdir()
        code, out, _ = run("plugins", "--url", url, "--dest", self.dir / "plugins", "--stage", self.dir / "stage")
        self.assertEqual((code, out), (0, "changed\n"), "the sidecar supplies the hash")
        manifest = json.loads((self.dir / "stage/PluginManifest.json").read_text())
        self.assertEqual((manifest["version"], manifest["sha256"], manifest["installedPackageFilename"]),
                         ("3.0.0", digest, "RIoT2.Net.Devices_3.0.0.zip"))
        (self.dir / "stage").rename(self.dir / "plugins2")
        self.assertEqual(run("plugins", "--url", url, "--sha256", digest, "--dest", self.dir / "plugins2",
                             "--stage", self.dir / "stage")[1], "same\n")

    def test_a_wrong_hash_or_an_unsafe_entry_is_refused(self):
        url, digest = self.package({"../evil.dll": b"MZ"})
        code, _, err = run("plugins", "--url", url, "--sha256", "0" * 64, "--dest", self.dir, "--stage", self.dir / "s")
        self.assertEqual(code, 1)
        self.assertIn("not " + "0" * 64, err)
        self.assertEqual(run("plugins", "--url", url, "--sha256", digest, "--dest", self.dir, "--stage", self.dir / "s")[0], 2)
        self.assertFalse((self.dir / "evil.dll").exists())


class FakeOrchestrator(BaseHTTPRequestHandler):
    workflows: dict[str, dict] = {}
    imported: list = []
    backups: list[bytes] = []

    def log_message(self, *args):
        pass

    def reply(self, code: int, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/workflows":
            return self.reply(200, [{"definitionId": d} for d in self.workflows])
        if self.path.startswith("/api/workflows/") and self.path.endswith("/export"):
            definition = self.path.split("/")[3]
            return self.reply(200, {"fileName": f"{definition}.json", "model": self.workflows[definition]})
        self.reply(404, {})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.path == "/api/workflows/import":
            self.imported.append(json.loads(body))
            return self.reply(200, {})
        if self.path == "/api/v2/backup":
            return self.reply(200, self.backups.pop(0), "application/zip")
        if self.path == "/api/v2/restore":
            return self.reply(400, {"title": "The backup can't be restored", "errors": ["StoredObjects/x.json is empty."]})
        self.reply(404, {})


class Api(Case):
    def setUp(self):
        super().setUp()
        FakeOrchestrator.workflows = {"heat": {"definitionId": "heat", "isPublished": True},
                                      "live-only": {"definitionId": "live-only"}}
        FakeOrchestrator.imported, FakeOrchestrator.backups = [], []
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeOrchestrator)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        super().tearDown()

    def test_import_adds_only_missing_workflows_unless_all(self):
        self.write("site/workflows/heat.json", {"definitionId": "heat"})
        self.write("site/workflows/lights.json", {"fileName": "x", "model": {"definitionId": "lights", "isPublished": True}})
        code, out, _ = run("api-workflows-import", "--url", self.url, "--dir", self.dir / "site/workflows", "--mode", "missing")
        self.assertEqual(code, 0)
        self.assertIn("keep workflows/heat.json", out)
        self.assertIn("import workflows/lights.json published", out, "auto publishes what was published")
        self.assertEqual([i["model"]["definitionId"] for i in FakeOrchestrator.imported], ["lights"])
        run("api-workflows-import", "--url", self.url, "--dir", self.dir / "site/workflows", "--mode", "all", "--publish", "false")
        self.assertEqual(len(FakeOrchestrator.imported), 3)
        self.assertFalse(FakeOrchestrator.imported[-1]["publish"])

    def test_export_writes_changed_and_new_workflows_but_not_ones_changed_in_the_site(self):
        self.write("site/workflows/heating.json", {"definitionId": "heat"})
        out = run("api-workflows-export", "--url", self.url, "--out", self.dir / "out", "--site-dir",
                  self.dir / "site/workflows")[1]
        self.assertIn("export workflows/heating.json changed", out, "the site's file name is kept")
        self.assertIn("export workflows/live-only.json new", out)
        allowed = self.write("allowed.txt", "")
        out = run("api-workflows-export", "--url", self.url, "--out", self.dir / "out2", "--site-dir",
                  self.dir / "site/workflows", "--allowed", allowed)[1]
        self.assertIn("skip workflows/heating.json changed-in-site", out)

    def test_export_config_writes_only_a_changed_configuration(self):
        site = backup(self.dir / "site.zip", {"StoredObjects/Variable/a.json": b"{}"})
        FakeOrchestrator.backups = [backup(self.dir / "1.zip", {"StoredObjects/Variable/a.json": b"{}"}).read_bytes(),
                                    backup(self.dir / "2.zip", {"StoredObjects/Variable/a.json": b"{\"v\":1}"}).read_bytes()]
        out = self.dir / "export/configuration/riot2-backup.zip"
        self.assertEqual(run("api-export-config", "--url", self.url, "--out", out, "--site", site)[1], "same\n")
        self.assertFalse(out.exists())
        self.assertEqual(run("api-export-config", "--url", self.url, "--out", out, "--site", site)[1], "changed\n")
        self.assertTrue(out.exists())

    def test_a_refused_restore_shows_the_orchestrators_reasons(self):
        code, _, err = run("api-restore", "--url", self.url, "--zip", backup(self.dir / "b.zip", {}))
        self.assertEqual(code, 1)
        self.assertIn("answered 400", err)
        self.assertIn("StoredObjects/x.json is empty.", err)


if __name__ == "__main__":
    unittest.main()
