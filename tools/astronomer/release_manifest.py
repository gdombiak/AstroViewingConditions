#!/usr/bin/env python3
"""Astronomer product release-manifest schema (v1) and validation."""

from __future__ import annotations

from pathlib import Path
import json
import re


SCHEMA_VERSION = 1
PRODUCT_NAME = "astronomer"
TAG_PREFIX = "astronomer-v"
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
WHEEL_NAME_RE = re.compile(
    r"^(astro_engine|astro_host)-(.+)-py3-none-any\.whl$"
)

REPOSITORY = Path(__file__).resolve().parents[2]
ASTRONOMER_ROOT = REPOSITORY / "astronomer"
INSTRUCTIONS_NAME = "ASTRONOMER.md"
MANIFEST_NAME = "astronomer-release.json"
VERSION_PATH = ASTRONOMER_ROOT / "VERSION"
DEPENDENCIES_PATH = ASTRONOMER_ROOT / "runtime-dependencies.txt"
INSTRUCTIONS_PATH = ASTRONOMER_ROOT / INSTRUCTIONS_NAME

PYTHON_REQUIRES = {"minimum": [3, 11]}


class ReleaseManifestError(ValueError):
    pass


def product_version() -> str:
    version = VERSION_PATH.read_text(encoding="utf-8").strip()
    if not SEMVER_RE.fullmatch(version):
        raise ReleaseManifestError(f"invalid product version: {version!r}")
    return version


def runtime_dependencies() -> list[str]:
    pins: list[str] = []
    for raw in DEPENDENCIES_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "==" not in line:
            raise ReleaseManifestError(f"dependency must be an exact pin: {line!r}")
        pins.append(line)
    if not pins:
        raise ReleaseManifestError("runtime-dependencies.txt has no pins")
    return pins


def product_tag(version: str) -> str:
    if not SEMVER_RE.fullmatch(version):
        raise ReleaseManifestError(f"invalid product version: {version!r}")
    return f"{TAG_PREFIX}{version}"


def _require_dict(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ReleaseManifestError(f"{label} must be an object")
    return value


def _require_str(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ReleaseManifestError(f"{label} must be a non-empty string")
    return value


def _require_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ReleaseManifestError(f"{label} must be a positive integer")
    return value


def _require_sha256(value: object, label: str) -> str:
    digest = _require_str(value, label)
    if not SHA256_RE.fullmatch(digest):
        raise ReleaseManifestError(f"{label} must be a lowercase SHA-256 hex digest")
    return digest


def _require_filename(value: object, label: str) -> str:
    filename = _require_str(value, label)
    if Path(filename).name != filename or "/" in filename or "\\" in filename:
        raise ReleaseManifestError(f"{label} must be a basename, not a path")
    return filename


def _validate_python_requires(value: object) -> dict[str, object]:
    requirement = _require_dict(value, "python_requires")
    minimum = requirement.get("minimum")
    if (
        not isinstance(minimum, list)
        or len(minimum) != 2
        or any(not isinstance(item, int) or isinstance(item, bool) for item in minimum)
    ):
        raise ReleaseManifestError("python_requires.minimum must be [major, minor]")
    if tuple(minimum) < (3, 11):
        raise ReleaseManifestError("python_requires.minimum must be at least [3, 11]")
    unexpected = set(requirement) - {"minimum"}
    if unexpected:
        raise ReleaseManifestError(
            f"python_requires has unsupported fields: {sorted(unexpected)}"
        )
    return {"minimum": list(minimum)}


def _validate_dependencies(value: object) -> list[str]:
    if not isinstance(value, list) or not value:
        raise ReleaseManifestError("dependencies must be a non-empty array of pins")
    pins: list[str] = []
    for item in value:
        if not isinstance(item, str) or "==" not in item or not item.strip():
            raise ReleaseManifestError("each dependency must be an exact 'name==version' pin")
        pins.append(item)
    return pins


def _validate_instructions(value: object) -> dict[str, object]:
    artifact = _require_dict(value, "artifacts.instructions")
    filename = _require_filename(artifact.get("filename"), "artifacts.instructions.filename")
    if filename != INSTRUCTIONS_NAME:
        raise ReleaseManifestError(
            f"artifacts.instructions.filename must be {INSTRUCTIONS_NAME}"
        )
    unexpected = set(artifact) - {"filename", "sha256"}
    if unexpected:
        raise ReleaseManifestError(
            f"artifacts.instructions has unsupported fields: {sorted(unexpected)}"
        )
    return {
        "filename": filename,
        "sha256": _require_sha256(artifact.get("sha256"), "artifacts.instructions.sha256"),
    }


def _validate_wheel(value: object, *, role: str, dist_name: str) -> dict[str, object]:
    artifact = _require_dict(value, f"artifacts.{role}")
    version = _require_str(artifact.get("version"), f"artifacts.{role}.version")
    if not SEMVER_RE.fullmatch(version):
        raise ReleaseManifestError(f"artifacts.{role}.version must be a semantic version")
    filename = _require_filename(artifact.get("filename"), f"artifacts.{role}.filename")
    match = WHEEL_NAME_RE.fullmatch(filename)
    if match is None or match.group(1) != dist_name:
        raise ReleaseManifestError(
            f"artifacts.{role}.filename must be {dist_name}-<version>-py3-none-any.whl"
        )
    if match.group(2) != version:
        raise ReleaseManifestError(
            f"artifacts.{role}.filename version must match artifacts.{role}.version"
        )
    unexpected = set(artifact) - {"version", "filename", "sha256", "bytes"}
    if unexpected:
        raise ReleaseManifestError(
            f"artifacts.{role} has unsupported fields: {sorted(unexpected)}"
        )
    return {
        "version": version,
        "filename": filename,
        "sha256": _require_sha256(artifact.get("sha256"), f"artifacts.{role}.sha256"),
        "bytes": _require_int(artifact.get("bytes"), f"artifacts.{role}.bytes"),
    }


def validate_manifest(document: object) -> dict[str, object]:
    payload = _require_dict(document, "manifest")
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise ReleaseManifestError("unsupported schema_version")
    version = _require_str(payload.get("version"), "version")
    if not SEMVER_RE.fullmatch(version):
        raise ReleaseManifestError("version must be a semantic version")
    tag = _require_str(payload.get("tag"), "tag")
    if tag != product_tag(version):
        raise ReleaseManifestError(f"tag must be {product_tag(version)}")
    source_commit = _require_str(payload.get("source_commit"), "source_commit")
    if not re.fullmatch(r"^[0-9a-f]{40}$", source_commit):
        raise ReleaseManifestError("source_commit must be a 40-character git SHA")
    artifacts = _require_dict(payload.get("artifacts"), "artifacts")
    unexpected_artifacts = set(artifacts) - {"instructions", "engine", "host"}
    if unexpected_artifacts:
        raise ReleaseManifestError(
            f"artifacts has unsupported fields: {sorted(unexpected_artifacts)}"
        )
    required = {
        "schema_version",
        "version",
        "tag",
        "source_commit",
        "python_requires",
        "dependencies",
        "artifacts",
    }
    missing = required - set(payload)
    if missing:
        raise ReleaseManifestError(f"manifest is missing required fields: {sorted(missing)}")
    unexpected = set(payload) - required
    if unexpected:
        raise ReleaseManifestError(f"manifest has unsupported fields: {sorted(unexpected)}")
    return {
        "schema_version": SCHEMA_VERSION,
        "version": version,
        "tag": tag,
        "source_commit": source_commit,
        "python_requires": _validate_python_requires(payload.get("python_requires")),
        "dependencies": _validate_dependencies(payload.get("dependencies")),
        "artifacts": {
            "instructions": _validate_instructions(artifacts.get("instructions")),
            "engine": _validate_wheel(
                artifacts.get("engine"), role="engine", dist_name="astro_engine"
            ),
            "host": _validate_wheel(
                artifacts.get("host"), role="host", dist_name="astro_host"
            ),
        },
    }


def load_manifest(path: Path) -> dict[str, object]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReleaseManifestError(f"cannot read release manifest: {exc}") from exc
    return validate_manifest(document)


def build_manifest(
    *,
    version: str,
    source_commit: str,
    instructions_sha256: str,
    engine_version: str,
    engine_filename: str,
    engine_sha256: str,
    engine_bytes: int,
    host_version: str,
    host_filename: str,
    host_sha256: str,
    host_bytes: int,
    dependencies: list[str] | None = None,
) -> dict[str, object]:
    return validate_manifest({
        "schema_version": SCHEMA_VERSION,
        "version": version,
        "tag": product_tag(version),
        "source_commit": source_commit,
        "python_requires": dict(PYTHON_REQUIRES),
        "dependencies": list(dependencies if dependencies is not None else runtime_dependencies()),
        "artifacts": {
            "instructions": {
                "filename": INSTRUCTIONS_NAME,
                "sha256": instructions_sha256,
            },
            "engine": {
                "version": engine_version,
                "filename": engine_filename,
                "sha256": engine_sha256,
                "bytes": engine_bytes,
            },
            "host": {
                "version": host_version,
                "filename": host_filename,
                "sha256": host_sha256,
                "bytes": host_bytes,
            },
        },
    })
