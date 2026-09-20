#!/usr/bin/env python3
"""Build a self-contained Astronomer product release directory.

Writes wheels, ASTRONOMER.md, and astronomer-release.json under --output.
Unchanged Engine/Host versions reuse the exact published wheel bytes from
qualifying astronomer-vX.Y.Z GitHub Releases; new versions are built from
this tree. Inspecting published lineage requires network access; NO_NETWORK=1
fails instead of rebuilding an immutable filename. Does not create git tags
or publish GitHub Releases.
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
    ReleaseManifestError,
    build_manifest,
    product_version,
    runtime_dependencies,
)
from wheel_immutability import (
    check_product_version_monotonicity,
    fetch_published_asset,
    fetch_published_manifests,
    select_published_wheel,
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


def wheel_filename(dist_name: str, version: str) -> str:
    return f"{dist_name}-{version}-py3-none-any.whl"


def _build_wheel(
    *,
    package: Path,
    output: Path,
    filename: str,
    no_build_isolation: bool,
) -> None:
    environment = {**os.environ, "SOURCE_DATE_EPOCH": "315532800"}
    command = [
        sys.executable, "-m", "pip", "wheel", "--no-deps",
        "--wheel-dir", str(output),
    ]
    if no_build_isolation:
        command.append("--no-build-isolation")
    command.append(str(package))
    print(f"building {filename}", file=sys.stderr)
    subprocess.run(command, check=True, env=environment)


def _reuse_wheel(
    *,
    dest: Path,
    role: str,
    version: str,
    filename: str,
    published: dict[str, object],
) -> None:
    published_role = published.get("role")
    published_version = published.get("version")
    published_filename = published.get("filename")
    published_tag = published.get("tag")
    published_digest = published.get("sha256")
    published_size = published.get("bytes")
    if (
        published_role != role
        or published_version != version
        or published_filename != filename
        or not isinstance(published_tag, str)
        or not isinstance(published_digest, str)
        or not isinstance(published_size, int)
        or isinstance(published_size, bool)
    ):
        raise ReleaseManifestError(
            f"reused wheel {filename} filename/version mismatch"
        )
    print(f"reusing {filename} from {published_tag}", file=sys.stderr)
    blob = fetch_published_asset(published_tag, filename)
    if len(blob) != published_size:
        raise ReleaseManifestError(
            f"reused wheel {filename} byte size mismatch"
        )
    digest = hashlib.sha256(blob).hexdigest()
    if digest != published_digest:
        raise ReleaseManifestError(
            f"reused wheel {filename} SHA-256 mismatch"
        )
    dest.write_bytes(blob)


def materialize_wheel(
    *,
    role: str,
    package: Path,
    dist_name: str,
    output: Path,
    priors: list[dict[str, object]],
    no_build_isolation: bool,
) -> dict[str, object]:
    pkg_version = package_version(package / "pyproject.toml")
    filename = wheel_filename(dist_name, pkg_version)
    dest = output / filename
    if dest.exists():
        dest.unlink()
    published = select_published_wheel(
        role=role,
        version=pkg_version,
        filename=filename,
        priors=priors,
    )
    if published is None:
        _build_wheel(
            package=package,
            output=output,
            filename=filename,
            no_build_isolation=no_build_isolation,
        )
    else:
        _reuse_wheel(
            dest=dest,
            role=role,
            version=pkg_version,
            filename=filename,
            published=published,
        )
    if not dest.is_file():
        raise RuntimeError(f"build did not produce {filename}")
    return {
        "version": pkg_version,
        "filename": filename,
        "sha256": sha256(dest),
        "bytes": dest.stat().st_size,
    }


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
    priors = fetch_published_manifests()
    check_product_version_monotonicity({"version": version}, priors)

    if not INSTRUCTIONS_PATH.is_file():
        raise RuntimeError(f"missing {INSTRUCTIONS_PATH}")
    instructions_dest = output / INSTRUCTIONS_NAME
    instructions_dest.write_bytes(INSTRUCTIONS_PATH.read_bytes())

    wheel_meta: dict[str, dict[str, object]] = {}
    for role, package, dist_name in PACKAGES:
        wheel_meta[role] = materialize_wheel(
            role=role,
            package=package,
            dist_name=dist_name,
            output=output,
            priors=priors,
            no_build_isolation=args.no_build_isolation,
        )

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
