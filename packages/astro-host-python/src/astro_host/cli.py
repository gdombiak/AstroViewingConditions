"""JSON boundary for the local ``agent.conditions`` host operation."""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import asdict, is_dataclass
from datetime import date, datetime, timedelta
from enum import Enum
import json
import math
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence, TextIO

from astro_host.conditions import ConditionsService
from astro_host.errors import InvalidRequestError
from astro_host.models import ConditionsRequest, Location


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_INVALID_REQUEST = 2
EXIT_USAGE = 3


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="astro-host")
    parser.add_argument("operation", choices=["agent.conditions"])
    parser.add_argument("--input", required=True, dest="input_path")
    parser.add_argument("--pretty", action="store_true")
    parser.add_argument("--atlas-path")
    parser.add_argument("--stale-on-error-seconds", type=float)
    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    service: ConditionsService | None = None,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exc:
        return EXIT_OK if exc.code == 0 else EXIT_USAGE

    try:
        document = _read_json(args.input_path)
        request = parse_conditions_request(document)
        if service is None:
            stale_age = None
            if args.stale_on_error_seconds is not None:
                if (
                    not math.isfinite(args.stale_on_error_seconds)
                    or args.stale_on_error_seconds <= 0
                ):
                    raise InvalidRequestError(
                        "stale-on-error-seconds must be positive"
                    )
                stale_age = timedelta(seconds=args.stale_on_error_seconds)
            service = ConditionsService(
                stale_on_error_max_age=stale_age,
                atlas_path=args.atlas_path,
            )
        result = asyncio.run(service.conditions(request))
        _write_json({
            "ok": True,
            "operation": "agent.conditions",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.conditions",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.conditions",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def parse_conditions_request(document: object) -> ConditionsRequest:
    if not isinstance(document, Mapping) or set(document) - {
        "location", "reference_time", "observing_date", "force_refresh"
    }:
        raise InvalidRequestError("request must be an object with known fields")
    raw_location = document.get("location")
    if not isinstance(raw_location, Mapping) or set(raw_location) - {
        "latitude", "longitude", "name", "location_id", "elevation_m", "time_zone_hint"
    }:
        raise InvalidRequestError("location must be an object with known fields")
    try:
        if any(isinstance(raw_location[key], bool) for key in ("latitude", "longitude")):
            raise TypeError
        latitude = float(raw_location["latitude"])
        longitude = float(raw_location["longitude"])
    except (KeyError, OverflowError, TypeError, ValueError) as exc:
        raise InvalidRequestError("location latitude and longitude are required numbers") from exc
    if not math.isfinite(latitude) or not math.isfinite(longitude):
        raise InvalidRequestError("location latitude and longitude must be finite")
    reference = document.get("reference_time")
    if not isinstance(reference, str):
        raise InvalidRequestError("reference_time must be an ISO-8601 string")
    try:
        reference_time = datetime.fromisoformat(reference.replace("Z", "+00:00"))
    except ValueError as exc:
        raise InvalidRequestError("reference_time is not valid ISO-8601") from exc
    raw_date = document.get("observing_date")
    try:
        observing_date = None if raw_date is None else date.fromisoformat(raw_date)
    except (TypeError, ValueError) as exc:
        raise InvalidRequestError("observing_date must be YYYY-MM-DD or null") from exc
    force_refresh = document.get("force_refresh", False)
    if not isinstance(force_refresh, bool):
        raise InvalidRequestError("force_refresh must be a boolean")
    return ConditionsRequest(
        location=Location(
            latitude=latitude,
            longitude=longitude,
            name=_optional_string(raw_location, "name"),
            location_id=_optional_string(raw_location, "location_id"),
            elevation_m=_optional_float(raw_location, "elevation_m"),
            time_zone_hint=_optional_string(raw_location, "time_zone_hint"),
        ),
        reference_time=reference_time,
        observing_date=observing_date,
        force_refresh=force_refresh,
    )


def _optional_string(value: Mapping[str, object], key: str) -> str | None:
    raw = value.get(key)
    if raw is None:
        return None
    if not isinstance(raw, str):
        raise InvalidRequestError(f"location.{key} must be a string or null")
    return raw


def _optional_float(value: Mapping[str, object], key: str) -> float | None:
    raw = value.get(key)
    if raw is None:
        return None
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise InvalidRequestError(f"location.{key} must be a number or null")
    try:
        parsed = float(raw)
    except OverflowError as exc:
        raise InvalidRequestError(f"location.{key} must be finite or null") from exc
    if not math.isfinite(parsed):
        raise InvalidRequestError(f"location.{key} must be finite or null")
    return parsed


def _read_json(path: str) -> object:
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _json_value(value: Any) -> Any:
    if is_dataclass(value):
        return {key: _json_value(item) for key, item in asdict(value).items()}
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime):
        return value.isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, Mapping):
        return {str(key): _json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_value(item) for item in value]
    return value


def _write_json(payload: Mapping[str, object], *, pretty: bool, stream: TextIO) -> None:
    serialized = json.dumps(
        payload,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
        sort_keys=True,
        allow_nan=False,
    )
    stream.write(serialized + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
