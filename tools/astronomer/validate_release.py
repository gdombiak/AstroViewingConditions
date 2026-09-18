#!/usr/bin/env python3
"""Validate a built Astronomer release directory against astronomer-release.json."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_manifest import MANIFEST_NAME, ReleaseManifestError, load_manifest
from wheel_immutability import (
    check_product_version_monotonicity,
    check_wheel_immutability,
    fetch_published_manifests,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_directory(root: Path) -> dict[str, object]:
    manifest_path = root / MANIFEST_NAME
    manifest = load_manifest(manifest_path)
    artifacts = manifest["artifacts"]
    if not isinstance(artifacts, dict):
        raise ReleaseManifestError("artifacts must be an object")
    expected = {
        "instructions": artifacts["instructions"],
        "engine": artifacts["engine"],
        "host": artifacts["host"],
    }
    for role, artifact in expected.items():
        if not isinstance(artifact, dict):
            raise ReleaseManifestError(f"artifacts.{role} must be an object")
        filename = artifact["filename"]
        if not isinstance(filename, str):
            raise ReleaseManifestError(f"artifacts.{role}.filename must be a string")
        path = root / filename
        if not path.is_file():
            raise ReleaseManifestError(f"missing artifact: {filename}")
        actual = sha256(path)
        if actual != artifact["sha256"]:
            raise ReleaseManifestError(f"checksum mismatch for {filename}")
        if "bytes" in artifact and path.stat().st_size != artifact["bytes"]:
            raise ReleaseManifestError(f"byte size mismatch for {filename}")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="validate_release.py")
    parser.add_argument("directory", type=Path)
    parser.add_argument(
        "--against-published",
        action="store_true",
        help=(
            "Also fetch prior qualifying astronomer-vX.Y.Z GitHub Releases, "
            "reject wheel filenames that would change SHA-256 or byte size, "
            "and require the candidate product version to be strictly newer "
            "than every published Astronomer release."
        ),
    )
    args = parser.parse_args(argv)
    try:
        manifest = validate_directory(args.directory)
        if args.against_published:
            priors = fetch_published_manifests()
            check_wheel_immutability(manifest, priors)
            check_product_version_monotonicity(manifest, priors)
    except (ReleaseManifestError, OSError) as exc:
        print(f"invalid Astronomer release: {exc}", file=sys.stderr)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
