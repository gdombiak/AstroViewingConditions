"""Load language-neutral scoring fixtures under contracts/fixtures/capabilities/."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterator

from astro_engine.contracts import contracts_root, expand_expected_canonical_data

SCORING_FIXTURE_DIRS = (
    "fixtures/capabilities/observing-quality",
    "fixtures/capabilities/fog",
    "fixtures/capabilities/seeing",
    "fixtures/capabilities/transparency",
    "fixtures/capabilities/night-conditions",
    "fixtures/capabilities/night-conditions-score",
)

DECODE_FIXTURE_DIRS = (
    "fixtures/capabilities/weather-decode",
    "fixtures/capabilities/iss-decode",
)

DETERMINISTIC_FIXTURE_DIRS = (
    "fixtures/capabilities/location-grid",
    "fixtures/capabilities/location-compare",
    "fixtures/capabilities/catalog-deep-sky",
    "fixtures/capabilities/targets-recommend",
    "fixtures/capabilities/equipment-match",
    "fixtures/capabilities/observing-window",
    "fixtures/capabilities/target-metadata",
    "fixtures/capabilities/horizontal-position",
    "fixtures/capabilities/deep-sky-windows",
    "fixtures/capabilities/moon-recommendation",
    "fixtures/capabilities/planet-recommendation",
    "fixtures/capabilities/compose-recommendations",
    "fixtures/capabilities/filter-recommendations-by-equipment",
    "fixtures/capabilities/observing-night-resolve-active",
    "fixtures/capabilities/night-forecast-window",
)


def parse_simple_meta(text: str) -> dict[str, Any]:
    result: dict[str, Any] = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        raw = lines[index]
        if not raw.strip() or raw.lstrip().startswith("#"):
            index += 1
            continue
        if ":" not in raw:
            index += 1
            continue
        key, _, rest = raw.partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest == ">":
            block: list[str] = []
            index += 1
            while index < len(lines) and (
                lines[index].startswith("  ")
                or lines[index].startswith("\t")
                or lines[index] == ""
            ):
                block.append(lines[index].strip())
                index += 1
            result[key] = " ".join(part for part in block if part)
            continue
        if rest.startswith("[") and rest.endswith("]"):
            inner = rest[1:-1]
            result[key] = [item.strip() for item in inner.split(",") if item.strip()]
        elif len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in {'"', "'"}:
            result[key] = rest[1:-1]
        else:
            result[key] = rest
        index += 1
    return result


def load_fixture(directory: Path) -> dict[str, Any]:
    expected = json.loads((directory / "expected.json").read_text(encoding="utf-8"))
    return {
        "id": directory.name,
        "path": directory,
        "meta": parse_simple_meta((directory / "meta.yaml").read_text(encoding="utf-8")),
        "input": json.loads((directory / "input.json").read_text(encoding="utf-8")),
        "expected": expand_expected_canonical_data(expected),
    }


def iter_scoring_fixtures() -> Iterator[dict[str, Any]]:
    yield from _iter_fixture_dirs(SCORING_FIXTURE_DIRS)


def iter_decode_fixtures() -> Iterator[dict[str, Any]]:
    yield from _iter_fixture_dirs(DECODE_FIXTURE_DIRS)


def iter_deterministic_fixtures() -> Iterator[dict[str, Any]]:
    yield from _iter_fixture_dirs(DETERMINISTIC_FIXTURE_DIRS)


def iter_parity_fixtures() -> Iterator[dict[str, Any]]:
    yield from iter_scoring_fixtures()
    yield from iter_decode_fixtures()
    yield from iter_deterministic_fixtures()


def _iter_fixture_dirs(relative_dirs: tuple[str, ...]) -> Iterator[dict[str, Any]]:
    root = contracts_root()
    for relative in relative_dirs:
        directory = root / relative
        if not directory.is_dir():
            continue
        for child in sorted(path for path in directory.iterdir() if path.is_dir()):
            yield load_fixture(child)
