"""Load language-neutral scoring fixtures under contracts/fixtures/capabilities/."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterator

from astro_engine.contracts import contracts_root

SCORING_FIXTURE_DIRS = (
    "fixtures/capabilities/observing-quality",
    "fixtures/capabilities/fog",
    "fixtures/capabilities/seeing",
    "fixtures/capabilities/transparency",
    "fixtures/capabilities/night-conditions",
    "fixtures/capabilities/night-conditions-score",
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
    return {
        "id": directory.name,
        "path": directory,
        "meta": parse_simple_meta((directory / "meta.yaml").read_text(encoding="utf-8")),
        "input": json.loads((directory / "input.json").read_text(encoding="utf-8")),
        "expected": json.loads((directory / "expected.json").read_text(encoding="utf-8")),
    }


def iter_scoring_fixtures() -> Iterator[dict[str, Any]]:
    root = contracts_root()
    for relative in SCORING_FIXTURE_DIRS:
        directory = root / relative
        if not directory.is_dir():
            continue
        for child in sorted(path for path in directory.iterdir() if path.is_dir()):
            yield load_fixture(child)
