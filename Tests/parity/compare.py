"""Field-level compare using contracts/equality-policy.yaml.

Phase 10 CI invokes this via scripts/parity. Extra/missing keys fail.
Numbers compare numerically. This is not a second comparator.
"""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.contracts import contracts_root

_ABS_TOL = {
    "abs_1e9": 1e-9,
    "abs_1e12": 1e-12,
    "abs_1e4": 1e-4,
    "abs_0_5": 0.5,
}


def load_policy_fields(policy_id: str) -> dict[str, str]:
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
        raise AssertionError(f"no fields found for policy {policy_id!r}")
    return fields


def compare_envelope(
    actual: Mapping[str, Any],
    expected: Mapping[str, Any],
    *,
    policy_id: str,
) -> None:
    assert actual.get("capability") == expected.get("capability"), (
        f"capability {actual.get('capability')!r} != {expected.get('capability')!r}"
    )
    assert "engine_semver" not in expected
    assert actual.get("ok") is expected.get("ok"), (
        f"ok {actual.get('ok')!r} != {expected.get('ok')!r}"
    )
    fields = load_policy_fields(policy_id)
    if expected.get("ok") is True:
        assert "result" in actual and "result" in expected
        compare_value(actual["result"], expected["result"], fields, path="")
    else:
        assert "error" in actual and "error" in expected
        compare_value(actual["error"], expected["error"], fields, path="")


def compare_value(
    actual: Any,
    expected: Any,
    fields: Mapping[str, str],
    *,
    path: str,
) -> None:
    spec = _spec_for(path, fields)
    if spec == "null_or_seconds_60":
        if actual is None or expected is None:
            assert actual is None and expected is None, f"{path}: null/event mismatch"
        else:
            from astro_engine.astronomy import instant
            assert abs((instant(actual) - instant(expected)).total_seconds()) <= 60, f"{path}: events differ by more than 60s"
        return
    if spec == "integer_abs_1":
        assert type(actual) is int and type(expected) is int, f"{path}: expected integer percents"
        assert 0 <= actual <= 100 and 0 <= expected <= 100, f"{path}: percent out of range"
        _assert_number(actual, expected, abs_tol=1, path=path)
        return
    if spec in {"null_or_object"}:
        if expected is None:
            assert actual is None, f"{path}: expected null, got {actual!r}"
            return
        assert isinstance(actual, dict) and isinstance(expected, dict), (
            f"{path}: expected object, got {type(actual)}"
        )
        _compare_object(actual, expected, fields, path=path)
        return
    if spec.startswith("null_or_abs_"):
        if expected is None:
            assert actual is None, f"{path}: expected null, got {actual!r}"
            return
        _assert_number(actual, expected, abs_tol=_abs_from_spec(spec), path=path)
        return
    if spec.startswith("optional_abs_"):
        _assert_number(actual, expected, abs_tol=_abs_from_spec(spec), path=path)
        return
    if spec in _ABS_TOL:
        _assert_number(actual, expected, abs_tol=_ABS_TOL[spec], path=path)
        return
    if spec == "ordered_ids":
        assert isinstance(actual, list), f"{path}: expected ordered id array, got {type(actual)}"
        assert isinstance(expected, list), f"{path}: expected ordered id array golden"
        assert len(actual) == len(expected), (
            f"{path}: array length {len(actual)} != {len(expected)}"
        )
        for index, (act_item, exp_item) in enumerate(zip(actual, expected, strict=True)):
            assert act_item == exp_item, f"{path}.{index}: {act_item!r} != {exp_item!r}"
        return
    if spec == "exact":
        if isinstance(expected, dict):
            assert isinstance(actual, dict), f"{path}: expected object"
            _compare_object(actual, expected, fields, path=path)
            return
        if isinstance(expected, list):
            assert isinstance(actual, list), f"{path}: expected array"
            assert len(actual) == len(expected), (
                f"{path}: array length {len(actual)} != {len(expected)}"
            )
            for index, (act_item, exp_item) in enumerate(zip(actual, expected, strict=True)):
                compare_value(act_item, exp_item, fields, path=_index_path(path, index))
            return
        if isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
            assert actual == expected, f"{path}: {actual!r} != {expected!r}"
            return
        assert actual == expected, f"{path}: {actual!r} != {expected!r}"
        return
    raise AssertionError(f"unimplemented comparator {spec!r} at {path}")


def _compare_object(
    actual: Mapping[str, Any],
    expected: Mapping[str, Any],
    fields: Mapping[str, str],
    *,
    path: str,
) -> None:
    extra = set(actual) - set(expected)
    missing = set(expected) - set(actual)
    assert not extra, f"{path or '$'}: extra keys {sorted(extra)}"
    assert not missing, f"{path or '$'}: missing keys {sorted(missing)}"
    for key, expected_value in expected.items():
        child = f"{path}.{key}" if path else key
        compare_value(actual[key], expected_value, fields, path=child)


def _spec_for(path: str, fields: Mapping[str, str]) -> str:
    if not path:
        return "exact"
    if path in fields:
        return fields[path]
    wildcard = _wildcard_path(path)
    if wildcard in fields:
        return fields[wildcard]
    return "exact"


def _wildcard_path(path: str) -> str:
    parts = path.split(".")
    wild: list[str] = []
    for part in parts:
        if part.isdigit():
            wild.append("[]")
        else:
            wild.append(part)
    rendered: list[str] = []
    for part in wild:
        if part == "[]":
            if rendered:
                rendered[-1] = rendered[-1] + "[]"
            else:
                rendered.append("[]")
        else:
            rendered.append(part)
    return ".".join(rendered)


def _index_path(path: str, index: int) -> str:
    if not path:
        return str(index)
    return f"{path}.{index}"


def _abs_from_spec(spec: str) -> float:
    token = spec.split("abs_", 1)[1]
    if token in {"1e9", "1e12", "1e4"}:
        return _ABS_TOL[f"abs_{token}"]
    raise AssertionError(f"unknown abs token {token!r} in {spec!r}")


def _assert_number(actual: Any, expected: Any, *, abs_tol: float, path: str) -> None:
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
        f"{path}: expected number, got {actual!r}"
    )
    assert isinstance(expected, (int, float)) and not isinstance(expected, bool), (
        f"{path}: expected number golden, got {expected!r}"
    )
    assert abs(float(actual) - float(expected)) <= abs_tol, (
        f"{path}: {actual!r} not within {abs_tol} of {expected!r}"
    )
