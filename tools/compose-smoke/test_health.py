"""Self-test of health.py: the checks it plans, how it judges answers, and the deadline."""
import json
import subprocess
import unittest

import health


def fake_get(answers):
    def get(url):
        for fragment, answer in answers.items():
            if fragment in url:
                return answer
        return 0, "connection refused"
    return get


def fake_run(stdout, returncode=0):
    def run(cmd, capture_output, text):
        assert cmd[:2] == ["docker", "compose"] and cmd[-4:] == ["ps", "--all", "--format", "json"], cmd
        return subprocess.CompletedProcess(cmd, returncode, stdout, "boom" if returncode else "")
    return run


HEALTHY_PS = "\n".join(json.dumps(s) for s in [
    {"Service": "mosquitto", "State": "running", "Health": "healthy"},
    {"Service": "orchestrator", "State": "running", "Health": "healthy"},
    {"Service": "influxdb-connector", "State": "running", "Health": ""},
])
CONNECTORS = json.dumps([
    {"id": "riot2-influxdb", "health": {"status": "ok", "spool": {"messages": 0}}},
    {"id": "riot2-prometheus-exporter", "health": {"status": "ok", "spool": {"messages": 0}}},
])
ALL_UP = {
    ":8080/api/v2/connectors": (200, CONNECTORS),
    ":8086/health": (200, '{"status":"pass"}'),
    ":9090/api/v1/query": (200, '{"data":{"result":[{"value":[1,"1"]}]}}'),
    "": (200, "ok"),
}
FILES = ["docker-compose.yml", "compose.influx.yml", "compose.observability.yml"]


class HealthTests(unittest.TestCase):
    def test_plan_follows_the_compose_files_and_profiles(self):
        base = [c.name for c in health.plan("h", ["docker-compose.yml"], [], fake_get({}), fake_run(""))]
        self.assertEqual(base, ["containers", "orchestrator /health", "Elsa /health", "UI /", "UI /api proxy"])
        full = [c.name for c in health.plan("h", FILES, ["node"], fake_get({}), fake_run(""))]
        for name in ("node /health", "InfluxDB /health", "InfluxDB connector", "Prometheus /-/ready",
                     "Prometheus exporter", "Prometheus scrapes the exporter", "Grafana /api/health"):
            self.assertIn(name, full)
        self.assertEqual(full.count("Grafana /api/health"), 1, "one Grafana for both files")

    def test_a_healthy_stack_passes(self):
        clock = iter(range(1000))
        checks = health.plan("h", FILES, ["node"], fake_get(ALL_UP), fake_run(HEALTHY_PS))
        self.assertTrue(health.run_checks(checks, 0, 120, clock=lambda: next(clock), sleep=lambda _: None))
        self.assertIn("| containers | pass |", health.table(checks, 120))

    def test_unhealthy_answers_are_reported(self):
        answers = {":8080/api/v2/connectors": (200, json.dumps([
            {"id": "riot2-influxdb", "health": {"status": "degraded", "spool": {"messages": 7}}},
            {"id": "riot2-prometheus-exporter", "health": None, "healthError": "No answer within 8 s"}])),
            ":9090/api/v1/query": (200, '{"data":{"result":[{"value":[1,"0"]}]}}'),
            ":8082/health": (503, "unhealthy")}
        answers.update({k: v for k, v in ALL_UP.items() if k not in answers})
        ps = HEALTHY_PS + "\n" + json.dumps({"Service": "grafana", "State": "running", "Health": "starting"})
        now = [0.0]
        checks = health.plan("h", FILES, [], fake_get(answers), fake_run(ps))

        def sleep(seconds):
            now[0] += seconds
        self.assertFalse(health.run_checks(checks, 0, 10, interval=5, clock=lambda: now[0], sleep=sleep))
        failed = {c.name: c.detail for c in checks if c.passed_after is None}
        self.assertEqual(failed["InfluxDB connector"], "status degraded, spool 7")
        self.assertEqual(failed["Prometheus exporter"], "No answer within 8 s")
        self.assertEqual(failed["Prometheus scrapes the exporter"], "up = 0")
        self.assertEqual(failed["Elsa /health"], "HTTP 503")
        self.assertEqual(failed["containers"], "grafana: running/starting")
        self.assertIn("| Elsa /health | FAIL | > 10 s | HTTP 503 |", health.table(checks, 10))

    def test_a_check_that_passes_late_is_timed_and_not_run_again(self):
        calls = {"n": 0}

        def probe():
            calls["n"] += 1
            return calls["n"] >= 3, "ok" if calls["n"] >= 3 else "starting"
        now = [100.0]
        check = health.Check("late", probe)

        def sleep(seconds):
            now[0] += seconds
        self.assertTrue(health.run_checks([check], 100, 60, interval=4, clock=lambda: now[0], sleep=sleep))
        self.assertEqual((check.passed_after, calls["n"]), (8, 3))

    def test_a_probe_that_raises_is_a_failure_not_a_crash(self):
        def probe():
            raise RuntimeError("boom")
        check = health.Check("raises", probe)
        self.assertFalse(health.run_checks([check], 0, 0, clock=lambda: 1, sleep=lambda _: None))
        self.assertEqual(check.detail, "RuntimeError: boom")

    def test_ps_output_in_both_formats_and_compose_errors(self):
        self.assertEqual(len(health.parse_ps(HEALTHY_PS)), 3)
        self.assertEqual(len(health.parse_ps(json.dumps([{"Service": "a"}]))), 1)
        self.assertEqual(health.parse_ps(""), [])
        self.assertEqual(health.containers(["docker", "compose"], fake_run("", 1))(), (False, "boom"))
        self.assertEqual(health.containers(["docker", "compose"], fake_run(""))(), (False, "no containers"))

    def test_nothing_answering_reads_as_the_reason(self):
        ok, detail = health.http_ok("http://h:1/health", fake_get({}))()
        self.assertEqual((ok, detail), (False, "connection refused"))

    def test_main_requires_extra_urls_and_fails_on_them(self):
        import io
        import contextlib
        import unittest.mock as mock
        with mock.patch.object(health, "plan", return_value=[]), \
                mock.patch.object(health, "fetch", return_value=(404, "")), \
                contextlib.redirect_stdout(io.StringIO()) as out:
            code = health.main(["--host", "h", "--deadline", "0", "--require", "http://h:8080/simulated-failure"])
        self.assertEqual(code, 1)
        self.assertIn("::error::GET http://h:8080/simulated-failure did not pass within 0 s: HTTP 404", out.getvalue())

    def test_fetch_reads_success_errors_and_silence(self):
        import http.server
        import threading

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                code = 200 if self.path == "/ok" else 503
                self.send_response(code)
                self.end_headers()
                self.wfile.write(b'{"status":"x"}')

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            base = f"http://127.0.0.1:{server.server_address[1]}"
            self.assertEqual(health.fetch(base + "/ok"), (200, '{"status":"x"}'))
            self.assertEqual(health.fetch(base + "/down")[0], 503)
        finally:
            server.shutdown()
            server.server_close()
        status, reason = health.fetch(base + "/ok", timeout=2)
        self.assertEqual(status, 0)
        self.assertTrue(reason)


if __name__ == "__main__":
    unittest.main()
