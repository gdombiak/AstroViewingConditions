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
from astro_host.errors import (
    InvalidProviderTimezoneError,
    InvalidRequestError,
    LocationStoreError,
    PlaceProviderError,
)
from astro_host.locations import FileLocationStore, LocationStore, default_locations_path
from astro_host.models import (
    ConditionsRequest,
    HostConditionsRequest,
    Location,
    LocationSource,
    PlaceCandidate,
    PlaceConfirmRequest,
    SavedLocationDraft,
)
from astro_host.places import ObservingLocationService
from astro_host.providers.open_meteo_geocoding import OpenMeteoPlaceResolver
from astro_host.providers.place import PlaceResolver
from astro_host.weather_cache_file import FileWeatherCache, default_weather_cache_path


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_INVALID_REQUEST = 2
EXIT_USAGE = 3

_LOCATION_ACTIONS = frozenset({
    "list",
    "save",
    "save_from_candidate",
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
_SAVE_FROM_CANDIDATE_KEYS = frozenset({
    "action", "candidate", "name", "aliases", "select",
})
_CANDIDATE_KEYS = frozenset({
    "provider",
    "provider_place_id",
    "name",
    "display_name",
    "latitude",
    "longitude",
    "time_zone",
    "usable",
    "unusable_reason",
    "elevation_m",
    "country",
    "admin1",
    "admin2",
    "country_code",
    "feature_code",
    "population",
    "rank",
})


@dataclass(frozen=True)
class LocationsRequest:
    action: str
    location: SavedLocationDraft | None = None
    id: str | None = None
    query: str | None = None
    confirm: PlaceConfirmRequest | None = None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="astro-host")
    parser.add_argument(
        "operation",
        choices=["agent.conditions", "agent.locations", "agent.places"],
    )
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
    resolver: PlaceResolver | None = None,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exc:
        return EXIT_OK if exc.code == 0 else EXIT_USAGE

    if args.operation == "agent.locations":
        return _main_locations(args, store=store, stdout=stdout, stderr=stderr)
    if args.operation == "agent.places":
        return _main_places(
            args, resolver=resolver, stdout=stdout, stderr=stderr
        )
    return _main_conditions(
        args, service=service, store=store, stdout=stdout, stderr=stderr
    )


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
    store: LocationStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        host_request = parse_conditions_request(document)
        location, location_source = _compose_conditions_location(
            args, host_request.location, store
        )
        request = ConditionsRequest(
            location=location,
            reference_time=host_request.reference_time,
            observing_date=host_request.observing_date,
            force_refresh=host_request.force_refresh,
        )
        if service is None:
            service = build_default_service(args)
        result = asyncio.run(service.conditions(request))
        payload = _json_value(result)
        payload["location_source"] = location_source.value
        _write_json({
            "ok": True,
            "operation": "agent.conditions",
            "result": payload,
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.conditions",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.conditions",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.conditions",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_places(
    args: argparse.Namespace,
    *,
    resolver: PlaceResolver | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        query = parse_places_request(document)
        if resolver is None:
            resolver = OpenMeteoPlaceResolver()
        resolution = asyncio.run(
            ObservingLocationService(resolver=resolver).resolve_place(query)
        )
        payload = _json_value(resolution)
        payload["action"] = "resolve"
        _write_json({
            "ok": True,
            "operation": "agent.places",
            "result": payload,
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.places",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except PlaceProviderError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.places",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE
    except InvalidProviderTimezoneError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.places",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.places",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _compose_conditions_location(
    args: argparse.Namespace,
    explicit: Location | None,
    store: LocationStore | None,
) -> tuple[Location, LocationSource]:
    if explicit is not None:
        return explicit, LocationSource.EXPLICIT_OVERRIDE
    if store is None:
        store = build_default_location_store(args)
    return ObservingLocationService(store=store).location_for_conditions(None)


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
    if action == "save_from_candidate":
        assert request.confirm is not None
        saved = ObservingLocationService(store=store).confirm_save(request.confirm)
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
    if action == "save_from_candidate":
        if "candidate" not in document or keys - _SAVE_FROM_CANDIDATE_KEYS:
            raise InvalidRequestError("request must be an object with known fields")
        return LocationsRequest(
            action=action,
            confirm=_parse_confirm_request(document),
        )
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


def parse_places_request(document: object) -> str:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    action = document.get("action")
    if action != "resolve":
        raise InvalidRequestError("action must be a supported agent.places action")
    if set(document) != {"action", "query"}:
        raise InvalidRequestError("request must be an object with known fields")
    return _required_query(document.get("query"))


def parse_conditions_request(document: object) -> HostConditionsRequest:
    if not isinstance(document, Mapping) or set(document) - {
        "location", "reference_time", "observing_date", "force_refresh"
    }:
        raise InvalidRequestError("request must be an object with known fields")
    location: Location | None
    if "location" not in document:
        location = None
    else:
        raw_location = document.get("location")
        if raw_location is None:
            raise InvalidRequestError("location must be an object with known fields")
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
        location = Location(
            latitude=latitude,
            longitude=longitude,
            name=_optional_string(raw_location, "name"),
            location_id=_optional_string(raw_location, "location_id"),
            elevation_m=_optional_float(raw_location, "elevation_m"),
            time_zone_hint=_optional_string(raw_location, "time_zone_hint"),
        )
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
    return HostConditionsRequest(
        location=location,
        reference_time=reference_time,
        observing_date=observing_date,
        force_refresh=force_refresh,
    )


def _parse_confirm_request(document: Mapping[str, object]) -> PlaceConfirmRequest:
    name = document.get("name") if "name" in document else None
    if name is not None and not isinstance(name, str):
        raise InvalidRequestError("name must be a string")
    aliases = ()
    if "aliases" in document:
        raw_aliases = document["aliases"]
        if (
            raw_aliases is None
            or not isinstance(raw_aliases, list)
            or any(not isinstance(item, str) for item in raw_aliases)
        ):
            raise InvalidRequestError("aliases must be an array of strings")
        aliases = tuple(raw_aliases)
    select = document.get("select", False)
    if not isinstance(select, bool):
        raise InvalidRequestError("select must be a boolean")
    return PlaceConfirmRequest(
        candidate=_parse_place_candidate(document.get("candidate")),
        name=name,
        aliases=aliases,
        select=select,
    )


def _parse_place_candidate(value: object) -> PlaceCandidate:
    if not isinstance(value, Mapping) or set(value) - _CANDIDATE_KEYS:
        raise InvalidRequestError("candidate must be an object with known fields")
    missing = {"provider", "name", "latitude", "longitude", "time_zone", "usable"} - set(value)
    if missing:
        raise InvalidRequestError(
            "candidate provider, name, latitude, longitude, time_zone, and usable are required"
        )
    provider = value.get("provider")
    name = value.get("name")
    if not isinstance(provider, str):
        raise InvalidRequestError("candidate.provider must be a string")
    if not isinstance(name, str):
        raise InvalidRequestError("candidate.name must be a string")
    usable = value.get("usable")
    if not isinstance(usable, bool):
        raise InvalidRequestError("candidate.usable must be a boolean")
    time_zone = value.get("time_zone")
    if time_zone is not None and not isinstance(time_zone, str):
        raise InvalidRequestError("candidate.time_zone must be a string or null")
    display_name = value.get("display_name", name)
    if not isinstance(display_name, str):
        raise InvalidRequestError("candidate.display_name must be a string")
    rank = value.get("rank", 1)
    if isinstance(rank, bool) or not isinstance(rank, int):
        raise InvalidRequestError("candidate.rank must be an integer")
    return PlaceCandidate(
        provider=provider,
        provider_place_id=_optional_int_field(value, "provider_place_id"),
        name=name,
        display_name=display_name,
        latitude=_required_finite(value, "latitude"),
        longitude=_required_finite(value, "longitude"),
        time_zone=time_zone,
        usable=usable,
        unusable_reason=_optional_string(value, "unusable_reason"),
        elevation_m=_optional_float(value, "elevation_m"),
        country=_optional_string(value, "country"),
        admin1=_optional_string(value, "admin1"),
        admin2=_optional_string(value, "admin2"),
        country_code=_optional_string(value, "country_code"),
        feature_code=_optional_string(value, "feature_code"),
        population=_optional_int_field(value, "population"),
        rank=rank,
    )


def _optional_int_field(value: Mapping[str, object], key: str) -> int | None:
    if key not in value:
        return None
    raw = value[key]
    if raw is None:
        return None
    if isinstance(raw, bool) or not isinstance(raw, int):
        raise InvalidRequestError(f"candidate.{key} must be an integer or null")
    return raw


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
