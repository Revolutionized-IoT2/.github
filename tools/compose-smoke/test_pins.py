"""Self-test of pins.py: which pins it finds and how it reports one that isn't published."""
import tempfile
import unittest
from pathlib import Path

import pins

COMPOSE = """
services:
  ui:
    image: ghcr.io/revolutionized-iot2/riot2-ui:1.15.0
  node:
    image: ghcr.io/revolutionized-iot2/riot2-node:${RIOT2_NODE_TAG:-2.4.0}
  grafana:
    image: grafana/grafana:13.2.4
"""


class PinsTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.deploy = Path(folder.name) / "deploy"
        (self.deploy / "sub").mkdir(parents=True)
        (self.deploy / "docker-compose.yml").write_text(COMPOSE, encoding="utf-8")
        (self.deploy / "sub" / "compose.x.yml").write_text(
            "image: ghcr.io/revolutionized-iot2/riot2-ui:1.15.0\n", encoding="utf-8")
        (self.deploy / "notes.md").write_text("ghcr.io/revolutionized-iot2/riot2-ui:9.9.9\n", encoding="utf-8")

    def test_finds_riot2_pins_in_compose_files_only(self):
        found = pins.find_pins(self.deploy)
        self.assertEqual(set(found), {("revolutionized-iot2/riot2-ui", "1.15.0")})
        self.assertEqual(found[("revolutionized-iot2/riot2-ui", "1.15.0")],
                         ["deploy/docker-compose.yml", "deploy/sub/compose.x.yml"])

    def test_reports_an_unpublished_pin_once_with_its_files(self):
        problems = pins.missing_pins(self.deploy, is_published=lambda image, tag: False)
        self.assertEqual(len(problems), 1)
        self.assertIn("deploy/docker-compose.yml, deploy/sub/compose.x.yml", problems[0])
        self.assertIn("riot2-ui:1.15.0 is not published", problems[0])

    def test_published_pins_pass(self):
        self.assertEqual(pins.missing_pins(self.deploy, is_published=lambda image, tag: True), [])


if __name__ == "__main__":
    unittest.main()
