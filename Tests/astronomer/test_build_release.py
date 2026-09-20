from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

import pytest


REPOSITORY = Path(__file__).resolve().parents[2]
TOOLS = REPOSITORY / "tools" / "astronomer"
sys.path.insert(0, str(TOOLS))

import build_release as build_release_module  # noqa: E402
from release_manifest import (  # noqa: E402
    MANIFEST_NAME,
    ReleaseManifestError,
    build_manifest,
    load_manifest,
    product_version,
    runtime_dependencies,
)
from validate_release import validate_directory  # noqa: E402
from wheel_immutability import fetch_published_manifests  # noqa: E402


COMMIT = "a" * 40
PRIOR_COMMIT = "b" * 40
INSTRUCTIONS_SHA = "c" * 64
ENGINE_WHEEL = "astro_engine-1.0.0-py3-none-any.whl"
HOST_WHEEL_010 = "astro_host-0.1.0-py3-none-any.whl"
HOST_WHEEL_011 = "astro_host-0.1.1-py3-none-any.whl"
ENGINE_WHEEL_110 = "astro_engine-1.1.0-py3-none-any.whl"


def _digest(payload: bytes) -> tuple[str, int]:
    return hashlib.sha256(payload).hexdigest(), len(payload)


def _prior(
    *,
    version: str,
    engine_version: str,
    engine_payload: bytes,
    host_version: str,
    host_payload: bytes,
    source_commit: str = PRIOR_COMMIT,
) -> dict[str, object]:
    engine_sha, engine_bytes = _digest(engine_payload)
    host_sha, host_bytes = _digest(host_payload)
    return build_manifest(
        version=version,
        source_commit=source_commit,
        instructions_sha256=INSTRUCTIONS_SHA,
        engine_version=engine_version,
        engine_filename=f"astro_engine-{engine_version}-py3-none-any.whl",
        engine_sha256=engine_sha,
        engine_bytes=engine_bytes,
        host_version=host_version,
        host_filename=f"astro_host-{host_version}-py3-none-any.whl",
        host_sha256=host_sha,
        host_bytes=host_bytes,
        dependencies=runtime_dependencies(),
    )


def _prepare_build(
    monkeypatch: pytest.MonkeyPatch,
    *,
    priors: list[dict[str, object]],
    engine_version: str = "1.0.0",
    host_version: str = "0.1.1",
    assets: dict[tuple[str, str], bytes] | None = None,
) -> tuple[list[str], list[str]]:
    built: list[str] = []
    reused: list[str] = []
    monkeypatch.setattr(
        build_release_module,
        "require_clean_source_commit",
        lambda **kwargs: COMMIT,
    )
    monkeypatch.setattr(
        build_release_module,
        "fetch_published_manifests",
        lambda **kwargs: list(priors),
    )

    def fake_package_version(pyproject: Path) -> str:
        text = str(pyproject)
        if "astro-engine-python" in text:
            return engine_version
        if "astro-host-python" in text:
            return host_version
        raise AssertionError(pyproject)

    monkeypatch.setattr(build_release_module, "package_version", fake_package_version)

    def fake_build_wheel(
        *, package: Path, output: Path, filename: str, no_build_isolation: bool
    ) -> None:
        built.append(filename)
        (output / filename).write_bytes(f"built-{filename}".encode())

    monkeypatch.setattr(build_release_module, "_build_wheel", fake_build_wheel)

    asset_map = assets or {}

    def fake_fetch(tag: str, filename: str, *, opener: object = None) -> bytes:
        reused.append(filename)
        try:
            return asset_map[(tag, filename)]
        except KeyError as exc:
            raise AssertionError((tag, filename)) from exc

    monkeypatch.setattr(build_release_module, "fetch_published_asset", fake_fetch)
    return built, reused


def test_first_release_builds_both(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    built, reused = _prepare_build(monkeypatch, priors=[])
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert reused == []
    assert built == [ENGINE_WHEEL, HOST_WHEEL_011]
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    assert manifest["version"] == product_version()
    assert manifest["source_commit"] == COMMIT
    assert manifest["artifacts"]["engine"]["filename"] == ENGINE_WHEEL
    assert manifest["artifacts"]["host"]["filename"] == HOST_WHEEL_011
    validate_directory(tmp_path)


def test_host_changed_reuses_engine_bytes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    host_payload = b"published-host-0.1.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=host_payload,
    )
    (tmp_path / ENGINE_WHEEL).write_bytes(b"stale-local-engine")
    built, reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        assets={("astronomer-v0.1.0", ENGINE_WHEEL): engine_payload},
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert reused == [ENGINE_WHEEL]
    assert built == [HOST_WHEEL_011]
    assert (tmp_path / ENGINE_WHEEL).read_bytes() == engine_payload
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    artifacts = manifest["artifacts"]
    assert isinstance(artifacts, dict)
    engine = artifacts["engine"]
    host = artifacts["host"]
    assert isinstance(engine, dict) and isinstance(host, dict)
    assert engine["version"] == "1.0.0"
    assert engine["filename"] == ENGINE_WHEEL
    assert engine["sha256"] == hashlib.sha256(engine_payload).hexdigest()
    assert engine["bytes"] == len(engine_payload)
    assert host["version"] == "0.1.1"
    assert host["filename"] == HOST_WHEEL_011
    assert manifest["source_commit"] == COMMIT
    validate_directory(tmp_path)


def test_engine_changed_reuses_host_bytes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    host_payload = b"published-host-0.1.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=host_payload,
    )
    built, reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        engine_version="1.1.0",
        host_version="0.1.0",
        assets={("astronomer-v0.1.0", HOST_WHEEL_010): host_payload},
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert reused == [HOST_WHEEL_010]
    assert built == [ENGINE_WHEEL_110]
    assert (tmp_path / HOST_WHEEL_010).read_bytes() == host_payload
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    assert manifest["artifacts"]["engine"]["version"] == "1.1.0"
    assert manifest["artifacts"]["host"]["version"] == "0.1.0"
    assert manifest["source_commit"] == COMMIT
    validate_directory(tmp_path)


def test_product_only_release_reuses_both_wheels(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    host_payload = b"published-host-0.1.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=host_payload,
    )
    built, reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        engine_version="1.0.0",
        host_version="0.1.0",
        assets={
            ("astronomer-v0.1.0", ENGINE_WHEEL): engine_payload,
            ("astronomer-v0.1.0", HOST_WHEEL_010): host_payload,
        },
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert built == []
    assert reused == [ENGINE_WHEEL, HOST_WHEEL_010]
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    assert manifest["source_commit"] == COMMIT
    assert manifest["source_commit"] != PRIOR_COMMIT
    assert manifest["version"] == product_version()
    assert (tmp_path / ENGINE_WHEEL).read_bytes() == engine_payload
    assert (tmp_path / HOST_WHEEL_010).read_bytes() == host_payload
    validate_directory(tmp_path)


def test_both_changed_builds_both(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=b"old-engine",
        host_version="0.1.0",
        host_payload=b"old-host",
    )
    built, reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        engine_version="1.1.0",
        host_version="0.1.1",
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert reused == []
    assert built == [ENGINE_WHEEL_110, HOST_WHEEL_011]
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    assert manifest["artifacts"]["engine"]["version"] == "1.1.0"
    assert manifest["artifacts"]["host"]["version"] == "0.1.1"
    validate_directory(tmp_path)


def test_reused_sha_mismatch_is_hard_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=b"published-host-0.1.0",
    )
    built, _reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        assets={("astronomer-v0.1.0", ENGINE_WHEEL): b"x" * len(engine_payload)},
    )
    with pytest.raises(ReleaseManifestError, match="SHA-256 mismatch"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []


def test_reused_byte_size_mismatch_is_hard_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=b"published-host-0.1.0",
    )
    built, _reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        assets={("astronomer-v0.1.0", ENGINE_WHEEL): b"short"},
    )
    with pytest.raises(ReleaseManifestError, match="byte size mismatch"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []


def test_reused_filename_version_mismatch_is_hard_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=b"published-engine-1.0.0",
        host_version="0.1.0",
        host_payload=b"published-host-0.1.0",
    )
    built, reused = _prepare_build(monkeypatch, priors=[prior])

    def mismatched(**kwargs: object) -> dict[str, object] | None:
        if kwargs["role"] == "engine":
            return {
                "tag": "astronomer-v0.1.0",
                "role": "engine",
                "version": "1.0.0",
                "filename": ENGINE_WHEEL_110,
                "sha256": "d" * 64,
                "bytes": 12,
            }
        return None

    monkeypatch.setattr(build_release_module, "select_published_wheel", mismatched)
    with pytest.raises(ReleaseManifestError, match="filename/version mismatch"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []
    assert reused == []


def test_missing_reused_asset_is_hard_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=b"published-engine-1.0.0",
        host_version="0.1.0",
        host_payload=b"published-host-0.1.0",
    )
    built, _reused = _prepare_build(monkeypatch, priors=[prior], assets={})

    def missing_asset(*args: object, **kwargs: object) -> bytes:
        raise ReleaseManifestError("cannot fetch published wheel")

    monkeypatch.setattr(build_release_module, "fetch_published_asset", missing_asset)
    with pytest.raises(ReleaseManifestError, match="cannot fetch"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []


def test_dirty_worktree_still_rejected_before_fetch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fetched: list[int] = []
    built: list[str] = []

    def fail_dirty(**kwargs: object) -> str:
        raise RuntimeError("refusing to record source_commit from a dirty Git worktree")

    monkeypatch.setattr(build_release_module, "require_clean_source_commit", fail_dirty)
    monkeypatch.setattr(
        build_release_module,
        "fetch_published_manifests",
        lambda **kwargs: fetched.append(1),
    )
    monkeypatch.setattr(
        build_release_module,
        "_build_wheel",
        lambda **kwargs: built.append("called"),
    )
    with pytest.raises(RuntimeError, match="dirty Git worktree"):
        build_release_module.main(["--output", str(tmp_path)])
    assert fetched == []
    assert built == []


def test_source_commit_is_current_head_when_wheels_reused(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    engine_payload = b"published-engine-1.0.0"
    host_payload = b"published-host-0.1.0"
    prior = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=host_payload,
    )
    _prepare_build(
        monkeypatch,
        priors=[prior],
        engine_version="1.0.0",
        host_version="0.1.0",
        assets={
            ("astronomer-v0.1.0", ENGINE_WHEEL): engine_payload,
            ("astronomer-v0.1.0", HOST_WHEEL_010): host_payload,
        },
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    manifest = load_manifest(tmp_path / MANIFEST_NAME)
    assert manifest["source_commit"] == COMMIT
    assert prior["source_commit"] == PRIOR_COMMIT


def test_product_version_monotonicity_still_enforced(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    prior = _prior(
        version=product_version(),
        engine_version="1.0.0",
        engine_payload=b"published-engine-1.0.0",
        host_version="0.1.1",
        host_payload=b"published-host-0.1.1",
    )
    built, reused = _prepare_build(
        monkeypatch,
        priors=[prior],
        assets={
            ("astronomer-v" + product_version(), ENGINE_WHEEL): b"published-engine-1.0.0",
            ("astronomer-v" + product_version(), HOST_WHEEL_011): b"published-host-0.1.1",
        },
    )
    with pytest.raises(ReleaseManifestError, match="not strictly greater"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []
    assert reused == []


def test_no_network_fails_without_rebuilding(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("NO_NETWORK", "1")
    monkeypatch.setattr(
        build_release_module,
        "require_clean_source_commit",
        lambda **kwargs: COMMIT,
    )
    built: list[str] = []
    monkeypatch.setattr(
        build_release_module,
        "_build_wheel",
        lambda **kwargs: built.append(kwargs["filename"]),
    )
    with pytest.raises(ReleaseManifestError, match="NO_NETWORK"):
        build_release_module.main(["--output", str(tmp_path)])
    assert built == []
    assert not (tmp_path / ENGINE_WHEEL).exists()
    assert not (tmp_path / HOST_WHEEL_011).exists()


def test_unrelated_github_tags_are_ignored(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("NO_NETWORK", raising=False)
    engine_payload = b"published-engine-1.0.0"
    host_payload = b"published-host-0.1.0"
    qualifying = _prior(
        version="0.1.0",
        engine_version="1.0.0",
        engine_payload=engine_payload,
        host_version="0.1.0",
        host_payload=host_payload,
    )
    releases = [
        {"tag_name": "2.3.1", "draft": False, "prerelease": False},
        {"tag_name": "astro-runtime-v0.1.0", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v0.1.0-rc.1", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v0.1.0", "draft": True, "prerelease": False},
        {"tag_name": "astronomer-v0.1.1", "draft": False, "prerelease": True},
        {"tag_name": "astronomer-v0.1.0", "draft": False, "prerelease": False},
    ]

    class _JsonResponse:
        def __init__(self, payload: object) -> None:
            self._body = json.dumps(payload).encode("utf-8")
            self.headers: dict[str, str] = {}

        def read(self) -> bytes:
            return self._body

        def __enter__(self) -> "_JsonResponse":
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    def opener(request, timeout=30):
        url = request.full_url
        if "api.github.com" in url and url.endswith("/releases?per_page=100"):
            return _JsonResponse(releases)
        if url.endswith("/astronomer-v0.1.0/astronomer-release.json"):
            return _JsonResponse(qualifying)
        raise AssertionError(url)

    monkeypatch.setattr(
        build_release_module,
        "require_clean_source_commit",
        lambda **kwargs: COMMIT,
    )
    monkeypatch.setattr(
        build_release_module,
        "fetch_published_manifests",
        lambda **kwargs: fetch_published_manifests(opener=opener),
    )
    monkeypatch.setattr(
        build_release_module,
        "package_version",
        lambda pyproject: (
            "1.0.0" if "astro-engine-python" in str(pyproject) else "0.1.1"
        ),
    )
    built: list[str] = []

    def fake_build_wheel(
        *, package: Path, output: Path, filename: str, no_build_isolation: bool
    ) -> None:
        built.append(filename)
        (output / filename).write_bytes(f"built-{filename}".encode())

    monkeypatch.setattr(build_release_module, "_build_wheel", fake_build_wheel)
    monkeypatch.setattr(
        build_release_module,
        "fetch_published_asset",
        lambda tag, filename, **kwargs: {
            ("astronomer-v0.1.0", ENGINE_WHEEL): engine_payload,
        }[(tag, filename)],
    )
    assert build_release_module.main(["--output", str(tmp_path)]) == 0
    assert built == [HOST_WHEEL_011]
    assert (tmp_path / ENGINE_WHEEL).read_bytes() == engine_payload
