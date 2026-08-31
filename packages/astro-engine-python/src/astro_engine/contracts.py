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


@lru_cache(maxsize=1)
def observing_quality_calibration() -> dict:
    path = data_root() / "calibration" / "observing-quality.json"
    if not path.is_file():
        raise ContractsRootError(f"missing calibration file: {path}")
    return load_json_bytes(path.read_bytes())
