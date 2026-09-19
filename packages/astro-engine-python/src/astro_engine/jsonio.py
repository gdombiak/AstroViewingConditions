"""JSON load/dump that rejects NaN/Inf and Python's non-standard constants."""

from __future__ import annotations

import json
import math
from typing import Any

STDIN_LIMIT_BYTES = 1_048_576  # 1 MiB


class JSONCodecError(ValueError):
    pass


def _reject_constant(value: str) -> Any:
    raise JSONCodecError(f"non-finite JSON value {value!r} is not allowed")


def _assert_finite(value: Any, *, path: str = "$") -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise JSONCodecError(f"non-finite number at {path}")
    if isinstance(value, dict):
        for key, item in value.items():
            _assert_finite(item, path=f"{path}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _assert_finite(item, path=f"{path}[{index}]")


def load_json_bytes(data: bytes) -> Any:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise JSONCodecError("stdin/input is not UTF-8") from exc
    try:
        value = json.loads(text, parse_constant=_reject_constant)
    except JSONCodecError:
        raise
    except json.JSONDecodeError as exc:
        raise JSONCodecError(f"malformed JSON: {exc.msg}") from exc
    _assert_finite(value)
    return value


def dump_json(value: Any, *, pretty: bool = False) -> str:
    _assert_finite(value)
    if pretty:
        return json.dumps(value, allow_nan=False, sort_keys=True, indent=2) + "\n"
    return json.dumps(value, allow_nan=False, separators=(",", ":")) + "\n"
