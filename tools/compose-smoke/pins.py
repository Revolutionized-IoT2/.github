"""Checks that every RIoT2 image pinned in deploy/ is published on GHCR.

deploy-check.yml and nightly-smoke.yml run it before they pull anything, and tools/preflight runs
it before a push that changes deploy/. A pin moves only through a release's deploy pull request,
which opens after the image is pushed; a pin edited by hand can name a tag that doesn't exist.

    python3 tools/compose-smoke/pins.py [--deploy deploy]

Exit code 1: an image isn't published. Exit code 2: the registry couldn't be asked.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

PIN = re.compile(r"\bghcr\.io/(revolutionized-iot2/[a-z0-9._-]+):([A-Za-z0-9._-]+)")
ACCEPT = ", ".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


class RegistryError(Exception):
    pass


def find_pins(deploy: Path) -> dict[tuple[str, str], list[str]]:
    """(image, tag) -> files that pin it. Tags taken from a variable aren't pins."""
    pins: dict[tuple[str, str], list[str]] = {}
    for path in sorted(deploy.rglob("*")):
        if path.suffix not in (".yml", ".yaml") or not path.is_file():
            continue
        rel = path.relative_to(deploy.parent).as_posix()
        for match in PIN.finditer(path.read_text(encoding="utf-8", errors="replace")):
            pins.setdefault((match.group(1), match.group(2)), []).append(rel)
    return pins


def published(image: str, tag: str, timeout: float = 15) -> bool:
    """True when ghcr.io has the manifest. Anonymous: the RIoT2 images are public."""
    try:
        url = f"https://ghcr.io/token?scope=repository:{image}:pull&service=ghcr.io"
        with urllib.request.urlopen(url, timeout=timeout) as answer:
            token = json.load(answer)["token"]
        request = urllib.request.Request(f"https://ghcr.io/v2/{image}/manifests/{tag}", method="HEAD",
                                         headers={"Authorization": f"Bearer {token}", "Accept": ACCEPT})
        with urllib.request.urlopen(request, timeout=timeout):
            return True
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return False
        raise RegistryError(f"ghcr.io answered {error.code} for {image}:{tag}") from error
    except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
        raise RegistryError(f"ghcr.io couldn't be asked about {image}:{tag}: {error}") from error


def missing_pins(deploy: Path, is_published=published) -> list[str]:
    """One message per pin that isn't published. Raises RegistryError when the registry fails."""
    problems = []
    for (image, tag), files in find_pins(deploy).items():
        if not is_published(image, tag):
            problems.append(f"{', '.join(sorted(set(files)))}: ghcr.io/{image}:{tag} is not published. "
                            "Pin a released tag; a release's deploy pull request moves the pin.")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--deploy", default=str(Path(__file__).resolve().parents[2] / "deploy"))
    args = parser.parse_args(argv)
    deploy = Path(args.deploy)
    try:
        problems = missing_pins(deploy)
    except RegistryError as error:
        print(f"::error::{error}")
        return 2
    for problem in problems:
        print(f"::error::{problem}")
    if not problems:
        print(f"Every RIoT2 image pinned in {deploy.name}/ is published ({len(find_pins(deploy))} pins).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
