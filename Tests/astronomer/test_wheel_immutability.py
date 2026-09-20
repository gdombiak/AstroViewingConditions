from __future__ import annotations

import json
from pathlib import Path
import sys

import pytest


REPOSITORY = Path(__file__).resolve().parents[2]
TOOLS = REPOSITORY / "tools" / "astronomer"
sys.path.insert(0, str(TOOLS))

from release_manifest import (  # noqa: E402
    ReleaseManifestError,
    build_manifest,
    product_tag,
    product_version,
    runtime_dependencies,
)
from wheel_immutability import (  # noqa: E402
    check_product_version_monotonicity,
    check_wheel_immutability,
    fetch_published_asset,
    fetch_published_manifests,
    qualifying_release_tags,
    require_manifest_matches_release_tag,
    select_published_wheel,
)


COMMIT = "a" * 40
INSTRUCTIONS_SHA = "b" * 64
ENGINE_SHA = "c" * 64
HOST_SHA = "d" * 64
OTHER_SHA = "e" * 64


def _manifest(
    *,
    version: str | None = None,
    engine_version: str = "1.0.0",
    engine_sha: str = ENGINE_SHA,
    engine_bytes: int = 12,
    host_version: str = "0.1.0",
    host_sha: str = HOST_SHA,
    host_bytes: int = 34,
    instructions_sha: str = INSTRUCTIONS_SHA,
) -> dict[str, object]:
    product = version or product_version()
    return build_manifest(
        version=product,
        source_commit=COMMIT,
        instructions_sha256=instructions_sha,
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


def test_same_filename_same_hash_and_size_is_accepted() -> None:
    check_wheel_immutability(_manifest(version="0.1.1"), [_manifest(version="0.1.0")])


def test_same_filename_different_hash_is_rejected() -> None:
    with pytest.raises(ReleaseManifestError, match="changed SHA-256"):
        check_wheel_immutability(
            _manifest(version="0.1.1", engine_sha=OTHER_SHA),
            [_manifest(version="0.1.0")],
        )


def test_same_filename_different_size_is_rejected() -> None:
    with pytest.raises(ReleaseManifestError, match="changed byte size"):
        check_wheel_immutability(
            _manifest(version="0.1.1", host_bytes=99),
            [_manifest(version="0.1.0")],
        )


def test_product_version_strictly_greater_than_priors_is_accepted() -> None:
    check_product_version_monotonicity(
        _manifest(version="0.1.1"), [_manifest(version="0.1.0")]
    )
    check_product_version_monotonicity(
        _manifest(version="0.1.10"), [_manifest(version="0.1.9")]
    )
    check_product_version_monotonicity(_manifest(version="0.1.0"), [])


def test_equal_product_version_is_rejected() -> None:
    with pytest.raises(ReleaseManifestError, match="not strictly greater"):
        check_product_version_monotonicity(
            _manifest(version="0.1.0"), [_manifest(version="0.1.0")]
        )


def test_lower_product_version_is_rejected() -> None:
    with pytest.raises(ReleaseManifestError, match="not strictly greater"):
        check_product_version_monotonicity(
            _manifest(version="0.0.9"), [_manifest(version="0.1.0")]
        )


def test_monotonicity_ignores_unrelated_tags_by_using_only_supplied_priors() -> None:
    # qualifying_release_tags already drops drafts/prereleases/other prefixes;
    # monotonicity only sees the priors that path kept.
    check_product_version_monotonicity(
        _manifest(version="0.2.0"),
        [_manifest(version="0.1.0")],
    )


def test_different_filename_and_version_is_accepted() -> None:
    check_wheel_immutability(
        _manifest(version="0.1.1", engine_version="1.1.0", engine_sha=OTHER_SHA, engine_bytes=99),
        [_manifest(version="0.1.0")],
    )


def test_instruction_hash_may_change_for_same_filename() -> None:
    check_wheel_immutability(
        _manifest(version="0.1.1", instructions_sha=OTHER_SHA),
        [_manifest(version="0.1.0")],
    )


def test_qualifying_tags_ignore_drafts_prereleases_and_other_prefixes() -> None:
    tags = qualifying_release_tags([
        {"tag_name": "2.3.1", "draft": False, "prerelease": False},
        {"tag_name": "astro-runtime-v0.1.0", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v0.1.0-rc.1", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v0.1.0", "draft": True, "prerelease": False},
        {"tag_name": "astronomer-v0.1.1", "draft": False, "prerelease": True},
        {"tag_name": "astronomer-v0.2.0", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v1.0.0", "draft": False, "prerelease": False},
    ])
    assert tags == ["astronomer-v0.2.0", "astronomer-v1.0.0"]
    assert product_tag(product_version()) == "astronomer-v0.1.1"


def test_manifest_matching_github_tag_is_accepted() -> None:
    bound = require_manifest_matches_release_tag(
        _manifest(version="0.2.0"), "astronomer-v0.2.0"
    )
    assert bound["tag"] == "astronomer-v0.2.0"
    assert bound["version"] == "0.2.0"


def test_manifest_for_different_github_tag_is_rejected() -> None:
    with pytest.raises(ReleaseManifestError, match="astronomer-v0.2.0"):
        require_manifest_matches_release_tag(
            _manifest(version="0.1.0"), "astronomer-v0.2.0"
        )


class _FakeResponse:
    def __init__(self, payload: object) -> None:
        self._body = json.dumps(payload).encode("utf-8")
        self.headers = {}

    def read(self) -> bytes:
        return self._body

    def __enter__(self) -> "_FakeResponse":
        return self

    def __exit__(self, *args: object) -> bool:
        return False


def _opener_for(releases: list[dict[str, object]], manifests: dict[str, dict[str, object]]):
    def opener(request, timeout=30):
        url = request.full_url
        if "api.github.com" in url and url.endswith("/releases?per_page=100"):
            return _FakeResponse(releases)
        for tag, document in manifests.items():
            if url.endswith(f"/{tag}/astronomer-release.json"):
                return _FakeResponse(document)
        raise AssertionError(url)

    return opener


def test_fetch_binds_downloaded_manifest_to_github_tag(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NO_NETWORK", raising=False)
    releases = [
        {"tag_name": "astronomer-v0.2.0", "draft": False, "prerelease": False},
        {"tag_name": "astro-runtime-v0.1.0", "draft": False, "prerelease": False},
        {"tag_name": "astronomer-v0.1.1", "draft": False, "prerelease": True},
        {"tag_name": "2.3.1", "draft": False, "prerelease": False},
    ]
    matching = _manifest(version="0.2.0")
    fetched = fetch_published_manifests(
        opener=_opener_for(releases, {"astronomer-v0.2.0": matching})
    )
    assert len(fetched) == 1
    assert fetched[0]["tag"] == "astronomer-v0.2.0"
    assert fetched[0]["version"] == "0.2.0"

    with pytest.raises(ReleaseManifestError, match="identity is"):
        fetch_published_manifests(
            opener=_opener_for(releases, {"astronomer-v0.2.0": _manifest(version="0.1.0")})
        )


def test_fetch_published_manifests_respects_no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NO_NETWORK", "1")
    with pytest.raises(ReleaseManifestError, match="NO_NETWORK"):
        fetch_published_manifests()


def test_select_published_wheel_returns_none_without_priors() -> None:
    assert (
        select_published_wheel(
            role="engine",
            version="1.0.0",
            filename="astro_engine-1.0.0-py3-none-any.whl",
            priors=[],
        )
        is None
    )


def test_select_published_wheel_uses_newest_matching_release() -> None:
    selected = select_published_wheel(
        role="engine",
        version="1.0.0",
        filename="astro_engine-1.0.0-py3-none-any.whl",
        priors=[_manifest(version="0.1.0"), _manifest(version="0.1.1")],
    )
    assert selected is not None
    assert selected["tag"] == "astronomer-v0.1.1"
    assert selected["sha256"] == ENGINE_SHA
    assert selected["bytes"] == 12


def test_select_published_wheel_searches_older_than_newest_product() -> None:
    oldest = _manifest(version="0.1.0")
    newest = _manifest(
        version="0.2.0",
        engine_version="1.1.0",
        engine_sha=OTHER_SHA,
        engine_bytes=99,
    )
    selected = select_published_wheel(
        role="engine",
        version="1.0.0",
        filename="astro_engine-1.0.0-py3-none-any.whl",
        priors=[oldest, newest],
    )
    assert selected is not None
    assert selected["tag"] == "astronomer-v0.1.0"
    assert selected["filename"] == "astro_engine-1.0.0-py3-none-any.whl"


def test_select_published_wheel_rejects_hash_disagreement() -> None:
    with pytest.raises(ReleaseManifestError, match="disagrees"):
        select_published_wheel(
            role="engine",
            version="1.0.0",
            filename="astro_engine-1.0.0-py3-none-any.whl",
            priors=[
                _manifest(version="0.1.0"),
                _manifest(version="0.1.1", engine_sha=OTHER_SHA),
            ],
        )


def test_select_published_wheel_rejects_filename_version_mismatch() -> None:
    prior = _manifest(version="0.1.0")
    artifacts = prior["artifacts"]
    assert isinstance(artifacts, dict)
    engine = artifacts["engine"]
    assert isinstance(engine, dict)
    engine["version"] = "9.9.9"
    with pytest.raises(ReleaseManifestError, match="filename/version mismatch"):
        select_published_wheel(
            role="engine",
            version="1.0.0",
            filename="astro_engine-1.0.0-py3-none-any.whl",
            priors=[prior],
        )


def test_fetch_published_asset_respects_no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NO_NETWORK", "1")
    with pytest.raises(ReleaseManifestError, match="NO_NETWORK"):
        fetch_published_asset(
            "astronomer-v0.1.0", "astro_engine-1.0.0-py3-none-any.whl"
        )


def test_fetch_published_asset_rejects_path_filename(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("NO_NETWORK", raising=False)
    with pytest.raises(ReleaseManifestError, match="basename"):
        fetch_published_asset(
            "astronomer-v0.1.0", "../astro_engine-1.0.0-py3-none-any.whl"
        )


def test_fetch_published_asset_returns_bytes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("NO_NETWORK", raising=False)

    class _BytesResponse:
        def __init__(self, body: bytes) -> None:
            self._body = body

        def read(self) -> bytes:
            return self._body

        def __enter__(self) -> "_BytesResponse":
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    def opener(request, timeout=60):
        assert request.full_url.endswith(
            "/astronomer-v0.1.0/astro_engine-1.0.0-py3-none-any.whl"
        )
        return _BytesResponse(b"wheel-bytes")

    assert (
        fetch_published_asset(
            "astronomer-v0.1.0",
            "astro_engine-1.0.0-py3-none-any.whl",
            opener=opener,
        )
        == b"wheel-bytes"
    )


def test_against_published_accepts_unchanged_wheels(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import hashlib
    import validate_release

    instructions = tmp_path / "ASTRONOMER.md"
    engine = tmp_path / "astro_engine-1.0.0-py3-none-any.whl"
    host = tmp_path / "astro_host-0.1.0-py3-none-any.whl"
    instructions.write_bytes(b"x")
    engine.write_bytes(b"engine-wheel")
    host.write_bytes(b"host-wheel")
    matching = build_manifest(
        version="0.1.1",
        source_commit=COMMIT,
        instructions_sha256=hashlib.sha256(instructions.read_bytes()).hexdigest(),
        engine_version="1.0.0",
        engine_filename=engine.name,
        engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
        engine_bytes=engine.stat().st_size,
        host_version="0.1.0",
        host_filename=host.name,
        host_sha256=hashlib.sha256(host.read_bytes()).hexdigest(),
        host_bytes=host.stat().st_size,
    )
    (tmp_path / "astronomer-release.json").write_text(
        json.dumps(matching, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    artifacts = matching["artifacts"]
    assert isinstance(artifacts, dict)
    engine_meta = artifacts["engine"]
    host_meta = artifacts["host"]
    assert isinstance(engine_meta, dict) and isinstance(host_meta, dict)
    prior = _manifest(
        version="0.1.0",
        engine_sha=str(engine_meta["sha256"]),
        engine_bytes=int(engine_meta["bytes"]),
        host_sha=str(host_meta["sha256"]),
        host_bytes=int(host_meta["bytes"]),
    )
    monkeypatch.setattr(validate_release, "fetch_published_manifests", lambda: [prior])
    assert validate_release.main([str(tmp_path), "--against-published"]) == 0
