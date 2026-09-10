"""JSON boundary for local host operations."""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import asdict, dataclass, is_dataclass
from datetime import date, datetime, timedelta
from enum import Enum
import json
import math
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence, TextIO

from astro_host.conditions import ConditionsService
from astro_host.errors import InvalidRequestError, LocationStoreError
from astro_host.locations import FileLocationStore, LocationStore, default_locations_path
from astro_host.models import ConditionsRequest, Location, SavedLocationDraft
from astro_host.weather_cache_file import FileWeatherCache, default_weather_cache_path


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_INVALID_REQUEST = 2
EXIT_USAGE = 3

_LOCATION_ACTIONS = frozenset({
    "list",
    "save",
    "get",
    "resolve",
    "select",
    "clear_selection",
    "delete",
    "get_selected",
})
_ID_OR_QUERY_ACTIONS = frozenset({"get", "select", "delete"})
_LOCATION_OBJECT_KEYS = frozenset({
    "name", "latitude", "longitude", "time_zone", "aliases", "elevation_m", "id",
})


@dataclass(frozen=True)
class LocationsRequest:
    action: str
    location: SavedLocationDraft | None = None
    id: str | None = None
    query: str | None = None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="astro-host")
    parser.add_argument("operation", choices=["agent.conditions", "agent.locations"])
    parser.add_argument("--input", required=True, dest="input_path")
    parser.add_argument("--pretty", action="store_true")
    parser.add_argument("--atlas-path")
    parser.add_argument("--stale-on-error-seconds", type=float)
    parser.add_argument("--weather-cache-path")
    parser.add_argument("--locations-path")
    return parser


def build_default_service(args: argparse.Namespace) -> ConditionsService:
    cache_path = (
        Path(args.weather_cache_path)
        if args.weather_cache_path
        else default_weather_cache_path()
    )
    return ConditionsService(
        cache=FileWeatherCache(cache_path),
        stale_on_error_max_age=_stale_age(args),
        atlas_path=args.atlas_path,
    )


def build_default_location_store(args: argparse.Namespace) -> FileLocationStore:
    path = (
        Path(args.locations_path)
        if args.locations_path
        else default_locations_path()
    )
    return FileLocationStore(path)


def _stale_age(args: argparse.Namespace) -> timedelta | None:
    if args.stale_on_error_seconds is None:
        return None
    if (
        not math.isfinite(args.stale_on_error_seconds)
        or args.stale_on_error_seconds <= 0
    ):
        raise InvalidRequestError("stale-on-error-seconds must be positive")
    return timedelta(seconds=args.stale_on_error_seconds)


def main(
    argv: Sequence[str] | None = None,
    *,
    service: ConditionsService | None = None,
    store: LocationStore | None = None,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exc:
        return EXIT_OK if exc.code == 0 else EXIT_USAGE

    if args.operation == "agent.locations":
        return _main_locations(args, store=store, stdout=stdout, stderr=stderr)
    return _main_conditions(args, service=service, stdout=stdout, stderr=stderr)


def _main_locations(
    args: argparse.Namespace,
    *,
    store: LocationStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        request = parse_locations_request(document)
        if store is None:
            store = build_default_location_store(args)
        result = _dispatch_locations(store, request)
        _write_json({
            "ok": True,
            "operation": "agent.locations",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.locations",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.locations",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.locations",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_conditions(
    args: argparse.Namespace,
    *,
    service: ConditionsService | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        request = parse_conditions_request(document)
        if service is None:
            service = build_default_service(args)
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


def _dispatch_locations(store: LocationStore, request: LocationsRequest) -> dict[str, object]:
    action = request.action
    if action == "list":
        state = store.load()
        return {
            "action": action,
            "locations": state.locations,
            "selected_location_id": state.selected_location_id,
        }
    if action == "get_selected":
        state = store.load()
        return {
            "action": action,
            "location": _get_selected_row(state),
            "selected_location_id": state.selected_location_id,
        }
    if action == "save":
        assert request.location is not None
        saved = store.save(request.location)
        selected = store.get_selected()
        return {
            "action": action,
            "location": saved,
            "selected_location_id": None if selected is None else selected.id,
        }
    if action == "clear_selection":
        store.clear_selection()
        selected = store.get_selected()
        return {
            "action": action,
            "selected_location_id": None if selected is None else selected.id,
        }
    if action == "get":
        saved = (
            store.resolve(request.query)
            if request.query is not None
            else store.get(request.id or "")
        )
        selected = store.get_selected()
        return {
            "action": action,
            "location": saved,
            "selected_location_id": None if selected is None else selected.id,
        }
    if action == "resolve":
        saved = store.resolve(request.query or "")
        selected = store.get_selected()
        return {
            "action": action,
            "location": saved,
            "selected_location_id": None if selected is None else selected.id,
        }
    if action == "select":
        saved = (
            store.select_query(request.query)
            if request.query is not None
            else store.select(request.id or "")
        )
        return {
            "action": action,
            "location": saved,
            "selected_location_id": saved.id,
        }
    if request.query is not None:
        store.delete_query(request.query)
    else:
        store.delete(request.id or "")
    selected = store.get_selected()
    return {
        "action": action,
        "selected_location_id": None if selected is None else selected.id,
    }


def _get_selected_row(state) -> object:
    if state.selected_location_id is None:
        return None
    for location in state.locations:
        if location.id == state.selected_location_id:
            return location
    return None


def parse_locations_request(document: object) -> LocationsRequest:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    action = document.get("action")
    if not isinstance(action, str) or action not in _LOCATION_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.locations action")
    keys = set(document)
    if action in {"list", "get_selected", "clear_selection"}:
        if keys != {"action"}:
            raise InvalidRequestError("request must be an object with known fields")
        return LocationsRequest(action=action)
    if action == "save":
        if keys != {"action", "location"}:
            raise InvalidRequestError("request must be an object with known fields")
        return LocationsRequest(action=action, location=_parse_location_draft(document.get("location")))
    if action == "resolve":
        if keys != {"action", "query"}:
            raise InvalidRequestError("request must be an object with known fields")
        return LocationsRequest(action=action, query=_required_query(document.get("query")))
    if action not in _ID_OR_QUERY_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.locations action")
    has_id = "id" in document
    has_query = "query" in document
    if has_id == has_query or keys - {"action", "id", "query"}:
        raise InvalidRequestError("request must include exactly one of id or query")
    if has_id:
        return LocationsRequest(action=action, id=_required_id(document.get("id")))
    return LocationsRequest(action=action, query=_required_query(document.get("query")))


def _parse_location_draft(value: object) -> SavedLocationDraft:
    if not isinstance(value, Mapping) or set(value) - _LOCATION_OBJECT_KEYS:
        raise InvalidRequestError("location must be an object with known fields")
    missing = {"name", "latitude", "longitude", "time_zone"} - set(value)
    if missing:
        raise InvalidRequestError("location name, latitude, longitude, and time_zone are required")
    latitude = _required_finite(value, "latitude")
    longitude = _required_finite(value, "longitude")
    name = value.get("name")
    time_zone = value.get("time_zone")
    if not isinstance(name, str):
        raise InvalidRequestError("location.name must be a string")
    if not isinstance(time_zone, str):
        raise InvalidRequestError("location.time_zone must be a string")
    aliases = _parse_aliases(value)
    return SavedLocationDraft(
        name=name,
        latitude=latitude,
        longitude=longitude,
        time_zone=time_zone,
        aliases=aliases,
        elevation_m=_optional_float(value, "elevation_m"),
        id=_optional_string(value, "id"),
    )


def _parse_aliases(value: Mapping[str, object]) -> tuple[str, ...]:
    if "aliases" not in value:
        return ()
    raw = value["aliases"]
    if raw is None or not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        raise InvalidRequestError("location.aliases must be an array of strings")
    return tuple(raw)


def _required_finite(value: Mapping[str, object], key: str) -> float:
    raw = value.get(key)
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise InvalidRequestError(f"location.{key} must be a number")
    try:
        parsed = float(raw)
    except OverflowError as exc:
        raise InvalidRequestError(f"location.{key} must be finite") from exc
    if not math.isfinite(parsed):
        raise InvalidRequestError(f"location.{key} must be finite")
    return parsed


def _required_id(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise InvalidRequestError("id must be a string")
    return value


def _required_query(value: object) -> str:
    if not isinstance(value, str) or not value.strip():
        raise InvalidRequestError("query must be a non-empty string")
    return value


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
