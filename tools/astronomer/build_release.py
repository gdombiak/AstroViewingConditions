#!/usr/bin/env python3
"""Build a self-contained Astronomer product release directory.

Writes wheels, ASTRONOMER.md, and astronomer-release.json under --output.
Does not create git tags or publish GitHub Releases.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_manifest import (
    INSTRUCTIONS_NAME,
    INSTRUCTIONS_PATH,
    MANIFEST_NAME,
    REPOSITORY,
    build_manifest,
    product_version,
    runtime_dependencies,
)


PACKAGES = (
    ("engine", REPOSITORY / "packages" / "astro-engine-python", "astro_engine"),
    ("host", REPOSITORY / "packages" / "astro-host-python", "astro_host"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_version(pyproject: Path) -> str:
    data = tomllib.loads(pyproject.read_text(encoding="utf-8"))
    version = data["project"]["version"]
    if not isinstance(version, str) or not version:
        raise RuntimeError(f"missing project.version in {pyproject}")
    return version


def source_commit(*, cwd: Path = REPOSITORY) -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return completed.stdout.strip()


def worktree_is_dirty(*, cwd: Path = REPOSITORY) -> bool:
    completed = subprocess.run(
        ["git", "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return bool(completed.stdout.strip())


def require_clean_source_commit(*, cwd: Path = REPOSITORY) -> str:
    if worktree_is_dirty(cwd=cwd):
        raise RuntimeError(
            "refusing to record source_commit from a dirty Git worktree"
        )
    return source_commit(cwd=cwd)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build_release.py")
    parser.add_argument(
        "--output",
        type=Path,
        default=REPOSITORY / "dist" / "astronomer",
    )
    parser.add_argument(
        "--no-build-isolation",
        action="store_true",
        help="Use build tools already installed in the selected Python environment.",
    )
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    version = product_version()
    commit = require_clean_source_commit()
    dependencies = runtime_dependencies()

    if not INSTRUCTIONS_PATH.is_file():
        raise RuntimeError(f"missing {INSTRUCTIONS_PATH}")
    instructions_dest = output / INSTRUCTIONS_NAME
    instructions_dest.write_bytes(INSTRUCTIONS_PATH.read_bytes())

    wheel_meta: dict[str, dict[str, object]] = {}
    environment = {**os.environ, "SOURCE_DATE_EPOCH": "315532800"}
    for role, package, dist_name in PACKAGES:
        pkg_version = package_version(package / "pyproject.toml")
        filename = f"{dist_name}-{pkg_version}-py3-none-any.whl"
        path = output / filename
        if path.exists():
            path.unlink()
        command = [
            sys.executable, "-m", "pip", "wheel", "--no-deps",
            "--wheel-dir", str(output),
        ]
        if args.no_build_isolation:
            command.append("--no-build-isolation")
        command.append(str(package))
        subprocess.run(command, check=True, env=environment)
        if not path.is_file():
            raise RuntimeError(f"build did not produce {filename}")
        wheel_meta[role] = {
            "version": pkg_version,
            "filename": filename,
            "sha256": sha256(path),
            "bytes": path.stat().st_size,
        }

    manifest = build_manifest(
        version=version,
        source_commit=commit,
        instructions_sha256=sha256(instructions_dest),
        engine_version=str(wheel_meta["engine"]["version"]),
        engine_filename=str(wheel_meta["engine"]["filename"]),
        engine_sha256=str(wheel_meta["engine"]["sha256"]),
        engine_bytes=int(wheel_meta["engine"]["bytes"]),
        host_version=str(wheel_meta["host"]["version"]),
        host_filename=str(wheel_meta["host"]["filename"]),
        host_sha256=str(wheel_meta["host"]["sha256"]),
        host_bytes=int(wheel_meta["host"]["bytes"]),
        dependencies=dependencies,
    )
    (output / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
