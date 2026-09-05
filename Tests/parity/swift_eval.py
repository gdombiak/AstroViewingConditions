"""Invoke Swift astro-engine-eval against a fixture directory."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
SWIFT_PACKAGE = REPO / "packages" / "astro-engine-swift"


def resolve_eval_binary() -> Path | None:
    env = os.environ.get("ASTRO_ENGINE_EVAL")
    if env:
        path = Path(env)
        return path if path.is_file() else None
    candidates = [
        SWIFT_PACKAGE / ".build" / "debug" / "astro-engine-eval",
        SWIFT_PACKAGE / ".build" / "release" / "astro-engine-eval",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def ensure_eval_binary() -> Path:
    existing = resolve_eval_binary()
    if existing is not None:
        return existing
    if shutil.which("swift") is None:
        raise FileNotFoundError("swift is not available to build astro-engine-eval")
    completed = subprocess.run(
        [
            "swift",
            "build",
            "--package-path",
            str(SWIFT_PACKAGE),
            "--product",
            "astro-engine-eval",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"swift build astro-engine-eval failed:\n{completed.stdout}\n{completed.stderr}"
        )
    built = resolve_eval_binary()
    if built is None:
        raise FileNotFoundError("astro-engine-eval was built but the binary was not found")
    return built


def run_swift_eval(fixture_dir: Path, *, pretty: bool = False) -> tuple[int, dict[str, Any] | None, str]:
    binary = ensure_eval_binary()
    args = [str(binary), "--fixture", str(fixture_dir)]
    if pretty:
        args.append("--pretty")
    completed = subprocess.run(
        args,
        check=False,
        capture_output=True,
        cwd=str(REPO),
    )
    stdout = completed.stdout.decode()
    stderr = completed.stderr.decode()
    payload: dict[str, Any] | None = None
    if stdout.strip():
        payload = json.loads(stdout)
    return completed.returncode, payload, stderr
