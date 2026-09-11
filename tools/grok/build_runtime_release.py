#!/usr/bin/env python3
"""Build reproducible project wheels for an Astro runtime GitHub Release."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[2]
PACKAGES = (
    REPOSITORY / "packages" / "astro-engine-python",
    REPOSITORY / "packages" / "astro-host-python",
)
EXPECTED = (
    "astro_engine-1.0.0-py3-none-any.whl",
    "astro_host-0.1.0-py3-none-any.whl",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build_runtime_release.py")
    parser.add_argument(
        "--output", type=Path, default=REPOSITORY / "dist" / "grok-runtime"
    )
    parser.add_argument(
        "--no-build-isolation",
        action="store_true",
        help="Use build tools already installed in the selected Python environment.",
    )
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    for filename in EXPECTED:
        path = output / filename
        if path.exists():
            path.unlink()

    environment = {**os.environ, "SOURCE_DATE_EPOCH": "315532800"}
    for package in PACKAGES:
        command = [
            sys.executable, "-m", "pip", "wheel", "--no-deps",
            "--wheel-dir", str(output),
        ]
        if args.no_build_isolation:
            command.append("--no-build-isolation")
        command.append(str(package))
        subprocess.run(command, check=True, env=environment)

    artifacts = []
    for filename in EXPECTED:
        path = output / filename
        if not path.is_file():
            raise RuntimeError(f"build did not produce {filename}")
        artifacts.append({
            "filename": filename,
            "sha256": sha256(path),
            "bytes": path.stat().st_size,
        })
    summary = {"source_date_epoch": 315532800, "artifacts": artifacts}
    (output / "release-artifacts.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
