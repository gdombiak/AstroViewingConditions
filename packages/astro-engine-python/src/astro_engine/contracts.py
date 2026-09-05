"""Locate `contracts/` and load canonical data. No copied package data."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from astro_engine.jsonio import load_json_bytes

MAX_ANCESTOR_WALK = 16


class ContractsRootError(RuntimeError):
    pass


def contracts_root(*, start: Path | None = None) -> Path:
    """Resolve the contracts directory.

    1. `CONTRACTS_ROOT` must contain `ENGINE_VERSION` or the lookup fails.
    2. Otherwise walk ancestors of `start` or this file until
       `contracts/ENGINE_VERSION` is found.
    """
    env = os.environ.get("CONTRACTS_ROOT")
    if env:
        path = Path(env)
        if not (path / "ENGINE_VERSION").is_file():
            raise ContractsRootError(
                f"CONTRACTS_ROOT={env!r} does not contain ENGINE_VERSION"
            )
        return path.resolve()

    here = (start or Path(__file__)).resolve()
    if here.is_file():
        here = here.parent
    for _ in range(MAX_ANCESTOR_WALK):
        candidate = here / "contracts"
        if (candidate / "ENGINE_VERSION").is_file():
            return candidate.resolve()
        parent = here.parent
        if parent == here:
            break
        here = parent
    raise ContractsRootError("could not find contracts/ENGINE_VERSION")


def data_root() -> Path:
    env = os.environ.get("ASTRO_ENGINE_DATA_ROOT")
    if env:
        return Path(env).resolve()
    return contracts_root() / "data"


def engine_semver() -> str:
    text = (contracts_root() / "ENGINE_VERSION").read_text(encoding="utf-8").strip()
    if not text:
        raise ContractsRootError("ENGINE_VERSION is empty")
    return text


@lru_cache(maxsize=None)
def load_calibration(stem: str) -> dict:
    """Load `contracts/data/calibration/<stem>.json`. No package-local copies."""
    path = data_root() / "calibration" / f"{stem}.json"
    if not path.is_file():
        raise ContractsRootError(f"missing calibration file: {path}")
    return load_json_bytes(path.read_bytes())


def observing_quality_calibration() -> dict:
    return load_calibration("observing-quality")


def fog_calibration() -> dict:
    return load_calibration("fog")


def seeing_calibration() -> dict:
    return load_calibration("seeing")


def transparency_calibration() -> dict:
    return load_calibration("transparency")


def night_quality_calibration() -> dict:
    return load_calibration("night-quality")


def fixtures_root() -> Path:
    """`contracts/fixtures`. Raises ContractsRootError if the directory is missing."""
    path = contracts_root() / "fixtures"
    if not path.is_dir():
        raise ContractsRootError(f"contracts/fixtures is missing at {path}")
    return path.resolve()


def resolve_fixture_ref(relative_path: str) -> Path:
    """Resolve a POSIX-relative path under `contracts/fixtures`.

    Not JSON Schema `$ref`. Rejects `..`, `.`, empty components, absolute
    paths, backslashes, and symlink targets that escape the fixtures tree.
    """
    from astro_engine.errors import FixtureRefError

    if (
        not isinstance(relative_path, str)
        or not relative_path
        or relative_path.startswith("/")
        or "\\" in relative_path
    ):
        raise FixtureRefError(
            "ref_escape",
            f"fixture path escapes contracts/fixtures: {relative_path}",
        )
    parts = relative_path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise FixtureRefError(
            "ref_escape",
            f"fixture path escapes contracts/fixtures: {relative_path}",
        )

    try:
        fixtures = fixtures_root()
    except ContractsRootError as exc:
        raise FixtureRefError("engine_failure", str(exc)) from exc
    candidate = fixtures.joinpath(*parts)
    resolved = candidate.resolve()
    try:
        resolved.relative_to(fixtures)
    except ValueError as exc:
        raise FixtureRefError(
            "ref_escape",
            f"fixture path escapes contracts/fixtures: {relative_path}",
        ) from exc
    if not resolved.is_file():
        raise FixtureRefError("fixture_missing", f"missing contract fixture: {relative_path}")
    return resolved


def load_fixture_ref(relative_path: str) -> object:
    """Load JSON at a confined `$ref` under `contracts/fixtures`."""
    return load_json_bytes(resolve_fixture_ref(relative_path).read_bytes())


def resolve_canonical_data(relative_path: str) -> Path:
    """Resolve a POSIX-relative path under `contracts/data`.

    Same confinement rules as fixture `$ref`: no `..`, absolute paths,
    backslashes, or symlink targets that escape the data tree.
    """
    if (
        not isinstance(relative_path, str)
        or not relative_path
        or relative_path.startswith("/")
        or "\\" in relative_path
    ):
        raise ContractsRootError(
            f"canonical data path escapes contracts/data: {relative_path}"
        )
    parts = relative_path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ContractsRootError(
            f"canonical data path escapes contracts/data: {relative_path}"
        )

    root = data_root()
    candidate = root.joinpath(*parts)
    resolved = candidate.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ContractsRootError(
            f"canonical data path escapes contracts/data: {relative_path}"
        ) from exc
    if not resolved.is_file():
        raise ContractsRootError(f"missing canonical data file: {relative_path}")
    return resolved


def load_canonical_data(relative_path: str) -> object:
    """Load JSON at a confined path under `contracts/data`."""
    return load_json_bytes(resolve_canonical_data(relative_path).read_bytes())


def expand_expected_canonical_data(expected: dict) -> dict:
    """Replace `result: {$canonical_data: rel}` with the contracts/data JSON document."""
    result = expected.get("result")
    if not isinstance(result, dict) or list(result.keys()) != ["$canonical_data"]:
        return expected
    relative = result["$canonical_data"]
    if not isinstance(relative, str):
        raise ContractsRootError("$canonical_data must be a string path under contracts/data")
    expanded = dict(expected)
    expanded["result"] = load_canonical_data(relative)
    return expanded
