from __future__ import annotations

import tomllib
from pathlib import Path

from astro_host.version import HOST_SEMVER


def test_package_version_matches_runtime_identity() -> None:
    path = Path(__file__).resolve().parents[1] / "pyproject.toml"
    document = tomllib.loads(path.read_text(encoding="utf-8"))
    assert document["project"]["version"] == HOST_SEMVER == "0.1.0"
