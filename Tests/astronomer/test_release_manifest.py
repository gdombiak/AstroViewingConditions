from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

import pytest


REPOSITORY = Path(__file__).resolve().parents[2]
TOOLS = REPOSITORY / "tools" / "astronomer"
sys.path.insert(0, str(TOOLS))

from release_manifest import (  # noqa: E402
    INSTRUCTIONS_PATH,
    MANIFEST_NAME,
    ReleaseManifestError,
    build_manifest,
    load_manifest,
    product_tag,
    product_version,
    runtime_dependencies,
    validate_manifest,
)
from validate_release import validate_directory  # noqa: E402
from build_release import require_clean_source_commit  # noqa: E402


COMMIT = "a" * 40
INSTRUCTIONS_SHA = "b" * 64
ENGINE_SHA = "c" * 64
HOST_SHA = "d" * 64


def _manifest(**overrides: object) -> dict[str, object]:
    version = product_version()
    payload: dict[str, object] = {
        "schema_version": 1,
        "version": version,
        "tag": product_tag(version),
        "source_commit": COMMIT,
        "python_requires": {"minimum": [3, 11]},
        "dependencies": runtime_dependencies(),
        "artifacts": {
            "instructions": {
                "filename": "ASTRONOMER.md",
                "sha256": INSTRUCTIONS_SHA,
            },
            "engine": {
                "version": "1.0.0",
                "filename": "astro_engine-1.0.0-py3-none-any.whl",
                "sha256": ENGINE_SHA,
                "bytes": 12,
            },
            "host": {
                "version": "0.1.0",
                "filename": "astro_host-0.1.0-py3-none-any.whl",
                "sha256": HOST_SHA,
                "bytes": 34,
            },
        },
    }
    payload.update(overrides)
    return payload


def test_valid_manifest_round_trip(tmp_path: Path) -> None:
    document = validate_manifest(_manifest())
    path = tmp_path / "astronomer-release.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    loaded = load_manifest(path)
    assert loaded["version"] == product_version()
    assert loaded["tag"] == f"astronomer-v{product_version()}"
    assert loaded["artifacts"]["engine"]["version"] == "1.0.0"
    assert loaded["artifacts"]["host"]["version"] == "0.1.0"
    assert loaded["python_requires"] == {"minimum": [3, 11]}
    assert all("==" in item for item in loaded["dependencies"])


def test_build_manifest_matches_validator() -> None:
    built = build_manifest(
        version=product_version(),
        source_commit=COMMIT,
        instructions_sha256=INSTRUCTIONS_SHA,
        engine_version="1.0.0",
        engine_filename="astro_engine-1.0.0-py3-none-any.whl",
        engine_sha256=ENGINE_SHA,
        engine_bytes=12,
        host_version="0.1.0",
        host_filename="astro_host-0.1.0-py3-none-any.whl",
        host_sha256=HOST_SHA,
        host_bytes=34,
    )
    assert built == validate_manifest(_manifest())


def test_rejects_path_like_filenames() -> None:
    payload = _manifest()
    artifacts = payload["artifacts"]
    assert isinstance(artifacts, dict)
    engine = artifacts["engine"]
    assert isinstance(engine, dict)
    engine["filename"] = "subdir/astro_engine-1.0.0-py3-none-any.whl"
    with pytest.raises(ReleaseManifestError, match="basename"):
        validate_manifest(payload)


def test_rejects_tag_mismatch() -> None:
    with pytest.raises(ReleaseManifestError, match="tag must be"):
        validate_manifest(_manifest(tag="astro-runtime-v0.1.0"))


def test_rejects_uppercase_hash() -> None:
    payload = _manifest()
    artifacts = payload["artifacts"]
    assert isinstance(artifacts, dict)
    instructions = artifacts["instructions"]
    assert isinstance(instructions, dict)
    instructions["sha256"] = "B" * 64
    with pytest.raises(ReleaseManifestError, match="lowercase SHA-256"):
        validate_manifest(payload)


def test_rejects_unhashable_schema_version() -> None:
    with pytest.raises(ReleaseManifestError, match="unsupported schema_version"):
        validate_manifest(_manifest(schema_version=[]))


def test_rejects_missing_dependencies() -> None:
    payload = _manifest()
    del payload["dependencies"]
    with pytest.raises(ReleaseManifestError, match="missing required fields"):
        validate_manifest(payload)


def test_rejects_wheel_filename_version_mismatch() -> None:
    payload = _manifest()
    artifacts = payload["artifacts"]
    assert isinstance(artifacts, dict)
    host = artifacts["host"]
    assert isinstance(host, dict)
    host["version"] = "0.2.0"
    with pytest.raises(ReleaseManifestError, match="filename version must match"):
        validate_manifest(payload)


def test_validate_directory_accepts_matching_bytes(tmp_path: Path) -> None:
    instructions = tmp_path / "ASTRONOMER.md"
    engine = tmp_path / "astro_engine-1.0.0-py3-none-any.whl"
    host = tmp_path / "astro_host-0.1.0-py3-none-any.whl"
    instructions.write_bytes(b"instructions")
    engine.write_bytes(b"engine-wheel")
    host.write_bytes(b"host-wheel")
    manifest = build_manifest(
        version=product_version(),
        source_commit=COMMIT,
        instructions_sha256=hashlib.sha256(b"instructions").hexdigest(),
        engine_version="1.0.0",
        engine_filename=engine.name,
        engine_sha256=hashlib.sha256(b"engine-wheel").hexdigest(),
        engine_bytes=len(b"engine-wheel"),
        host_version="0.1.0",
        host_filename=host.name,
        host_sha256=hashlib.sha256(b"host-wheel").hexdigest(),
        host_bytes=len(b"host-wheel"),
    )
    (tmp_path / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    loaded = validate_directory(tmp_path)
    assert loaded["tag"] == f"astronomer-v{product_version()}"


def test_validate_directory_rejects_checksum_mismatch(tmp_path: Path) -> None:
    instructions = tmp_path / "ASTRONOMER.md"
    engine = tmp_path / "astro_engine-1.0.0-py3-none-any.whl"
    host = tmp_path / "astro_host-0.1.0-py3-none-any.whl"
    instructions.write_bytes(b"instructions")
    engine.write_bytes(b"engine-wheel")
    host.write_bytes(b"host-wheel")
    manifest = build_manifest(
        version=product_version(),
        source_commit=COMMIT,
        instructions_sha256=hashlib.sha256(b"instructions").hexdigest(),
        engine_version="1.0.0",
        engine_filename=engine.name,
        engine_sha256=hashlib.sha256(b"engine-wheel").hexdigest(),
        engine_bytes=len(b"engine-wheel"),
        host_version="0.1.0",
        host_filename=host.name,
        host_sha256=hashlib.sha256(b"host-wheel").hexdigest(),
        host_bytes=len(b"host-wheel"),
    )
    (tmp_path / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    host.write_bytes(b"tampered")
    with pytest.raises(ReleaseManifestError, match="checksum mismatch"):
        validate_directory(tmp_path)


def test_require_clean_source_commit_rejects_dirty_worktree(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    class Completed:
        def __init__(self, stdout: str) -> None:
            self.stdout = stdout
            self.returncode = 0

    def fake_run(command, **kwargs):
        if command[:3] == ["git", "status", "--porcelain"]:
            return Completed(" M astronomer/ASTRONOMER.md\n")
        raise AssertionError(command)

    import build_release as build_release_module

    monkeypatch.setattr(build_release_module.subprocess, "run", fake_run)
    with pytest.raises(RuntimeError, match="dirty Git worktree"):
        require_clean_source_commit(cwd=tmp_path)


def test_require_clean_source_commit_uses_head(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    class Completed:
        def __init__(self, stdout: str) -> None:
            self.stdout = stdout
            self.returncode = 0

    def fake_run(command, **kwargs):
        if command[:3] == ["git", "status", "--porcelain"]:
            return Completed("")
        if command[:2] == ["git", "rev-parse"]:
            return Completed(COMMIT + "\n")
        raise AssertionError(command)

    import build_release as build_release_module

    monkeypatch.setattr(build_release_module.subprocess, "run", fake_run)
    assert require_clean_source_commit(cwd=tmp_path) == COMMIT


def test_canonical_instructions_hash_is_stable_input_for_manifest() -> None:
    digest = hashlib.sha256(INSTRUCTIONS_PATH.read_bytes()).hexdigest()
    built = build_manifest(
        version=product_version(),
        source_commit=COMMIT,
        instructions_sha256=digest,
        engine_version="1.0.0",
        engine_filename="astro_engine-1.0.0-py3-none-any.whl",
        engine_sha256=ENGINE_SHA,
        engine_bytes=12,
        host_version="0.1.0",
        host_filename="astro_host-0.1.0-py3-none-any.whl",
        host_sha256=HOST_SHA,
        host_bytes=34,
    )
    assert built["artifacts"]["instructions"]["sha256"] == digest
    assert built["artifacts"]["instructions"]["filename"] == "ASTRONOMER.md"
