"""Astro Engine LP runtime must not import Tools, NumPy, or GDAL."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from subprocess import run

SRC = Path(__file__).resolve().parents[1] / "src"
PROBE = r"""
import json
import sys

import astro_engine.light_pollution as lp

modules = set(sys.modules)
leaks = sorted(
    name
    for name in modules
    if name == "numpy"
    or name.startswith("numpy.")
    or name == "osgeo"
    or name.startswith("osgeo.")
    or name == "light_pollution"
    or name.startswith("light_pollution.")
)
path = lp.__file__ or ""
print(json.dumps({
    "leaks": leaks,
    "module": lp.__name__,
    "path": path,
    "has_from_bytes": hasattr(lp.LightPollutionArtifact, "from_bytes"),
}))
"""


def test_runtime_import_subprocess_has_no_tooling_dependencies(tmp_path: Path) -> None:
    script = tmp_path / "probe.py"
    script.write_text(PROBE, encoding="utf-8")
    env = {
        "PATH": os.environ.get("PATH", ""),
        "PYTHONPATH": str(SRC),
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    completed = run(
        [sys.executable, "-S", str(script)],
        cwd=tmp_path,
        capture_output=True,
        env=env,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr.decode()
    payload = json.loads(completed.stdout.decode())
    assert payload["leaks"] == []
    assert payload["module"] == "astro_engine.light_pollution"
    assert payload["has_from_bytes"] is True
    assert "Tools/LightPollution" not in payload["path"].replace("\\", "/")
    assert "astro_engine" in payload["path"]
