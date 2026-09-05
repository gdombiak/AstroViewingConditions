"""F2 test helpers: fixture loading and a *narrow* OQ equality comparator.

This is not the Phase 10 generic parity runner. It only understands the two
OQ policy IDs and the comparators those policies currently use. Field names
and comparator ids are read from `contracts/equality-policy.yaml` so a
tolerance/name change there fails these tests instead of drifting silently.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterator

from astro_engine.contracts import contracts_root
from astro_engine.semver import satisfies

OQ_FIXTURE_DIR = "fixtures/capabilities/observing-quality"


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
                lines[index].startswith("  ") or lines[index].startswith("\t") or lines[index] == ""
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


def iter_oq_fixtures() -> Iterator[dict[str, Any]]:
    yield from iter_capability_fixtures(OQ_FIXTURE_DIR)


def iter_capability_fixtures(relative: str) -> Iterator[dict[str, Any]]:
    root = contracts_root() / relative
    for directory in sorted(path for path in root.iterdir() if path.is_dir()):
        yield load_fixture(directory)


def load_fixture(directory: Path) -> dict[str, Any]:
    meta = parse_simple_meta((directory / "meta.yaml").read_text(encoding="utf-8"))
    payload = {
        "id": directory.name,
        "path": directory,
        "meta": meta,
        "input": json.loads((directory / "input.json").read_text(encoding="utf-8")),
        "expected": json.loads((directory / "expected.json").read_text(encoding="utf-8")),
    }
    return payload


def assert_engine_applies(version: str, fixture: dict[str, Any]) -> None:
    range_expr = fixture["meta"]["engine_semver"]
    assert satisfies(version, range_expr), (
        f"{fixture['id']}: runtime {version} does not satisfy {range_expr}"
    )


_ABS_TOL = {
    "abs_1e9": 1e-9,
    "abs_1e12": 1e-12,
    "abs_1e4": 1e-4,
}

_OQ_POLICY_IDS = frozenset({"observing_quality", "observing_quality_anchor"})


def load_policy_fields(policy_id: str) -> dict[str, str]:
    """Read the `fields:` map for one policy from equality-policy.yaml.

    Indentation-based, not a YAML library. F2 only.
    """
    header = f"  {policy_id}:"
    lines = (contracts_root() / "equality-policy.yaml").read_text(encoding="utf-8").splitlines()
    in_policy = False
    in_fields = False
    fields: dict[str, str] = {}
    for line in lines:
        if line.startswith("  ") and not line.startswith("    ") and line.rstrip().endswith(":"):
            in_policy = line.rstrip() == header
            in_fields = False
            continue
        if in_policy and line.strip() == "fields:":
            in_fields = True
            continue
        if in_fields:
            if line.strip().startswith("#"):
                continue
            if not line.startswith("      "):
                break
            stripped = line.strip().split("#", 1)[0].strip()
            if not stripped or ":" not in stripped:
                continue
            key, _, value = stripped.partition(":")
            fields[key.strip()] = value.strip()
    if not fields:
        raise AssertionError(f"no fields found for policy {policy_id!r} in equality-policy.yaml")
    return fields


def _numbers_equal(actual: Any, expected: Any, *, abs_tol: float) -> bool:
    return isinstance(actual, (int, float)) and isinstance(expected, (int, float)) and abs(
        float(actual) - float(expected)
    ) <= abs_tol


def _compare_spec(actual: Any, expected: Any, spec: str, *, path: str) -> None:
    if spec == "exact":
        assert actual == expected, f"{path}: {actual!r} != {expected!r}"
    elif spec == "null_or_object":
        if expected is None:
            assert actual is None, f"{path}: expected null"
        else:
            assert isinstance(expected, dict) and isinstance(actual, dict), f"{path}: expected object"
    elif spec in _ABS_TOL:
        assert _numbers_equal(actual, expected, abs_tol=_ABS_TOL[spec]), (
            f"{path}: {actual!r} not within {spec} of {expected!r}"
        )
    else:
        raise AssertionError(
            f"F2 OQ test helper does not implement comparator {spec!r} at {path}; "
            "the Phase 10 parity runner must read the contract"
        )


def compare_observing_quality_result(
    actual: dict[str, Any],
    expected: dict[str, Any],
    *,
    policy_id: str,
) -> None:
    """Compare an OQ result using field specs from equality-policy.yaml."""
    if policy_id not in _OQ_POLICY_IDS:
        raise AssertionError(f"F2 helper only implements {_OQ_POLICY_IDS}, not {policy_id!r}")
    fields = load_policy_fields(policy_id)

    extra = set(actual) - set(expected)
    missing = set(expected) - set(actual)
    assert not extra, f"extra result keys: {sorted(extra)}"
    assert not missing, f"missing result keys: {sorted(missing)}"

    for key, expected_value in expected.items():
        spec = fields.get(key, "exact")
        actual_value = actual[key]
        _compare_spec(actual_value, expected_value, spec, path=key)
        if spec == "null_or_object" and isinstance(expected_value, dict) and isinstance(actual_value, dict):
            nested_extra = set(actual_value) - set(expected_value)
            nested_missing = set(expected_value) - set(actual_value)
            assert not nested_extra, nested_extra
            assert not nested_missing, nested_missing
            for nested_key, nested_expected in expected_value.items():
                nested_spec = fields.get(f"{key}.{nested_key}", "exact")
                _compare_spec(
                    actual_value[nested_key],
                    nested_expected,
                    nested_spec,
                    path=f"{key}.{nested_key}",
                )
