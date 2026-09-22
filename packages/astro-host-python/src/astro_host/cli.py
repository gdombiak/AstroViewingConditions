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
from astro_host.equipment import FileEquipmentStore, EquipmentStore, default_equipment_path
from astro_host.equipment_session import EquipmentSessionService
from astro_host.engine import RecommendationEngine
from astro_host.errors import (
    EngineCallError,
    EquipmentStoreError,
    EyepieceStoreError,
    HostInvariantError,
    InvalidProviderTimezoneError,
    InvalidRequestError,
    LocationStoreError,
    PlaceProviderError,
)
from astro_host.eyepieces import (
    EyepieceStore,
    FileEyepieceStore,
    default_eyepieces_path,
)
from astro_host.optics import explicit_optics, saved_optics
from astro_host.locations import FileLocationStore, LocationStore, default_locations_path
from astro_host.models import (
    BatchCandidate,
    ConditionsRequest,
    EquipmentApertureUnit,
    EquipmentOverride,
    EquipmentOverrideMode,
    EquipmentSelection,
    EquipmentSelectionMode,
    EquipmentState,
    EquipmentType,
    EquipmentWriteResult,
    HostConditionsRequest,
    HostRecommendationsRequest,
    HostSkyFactsRequest,
    InlineEquipmentDraft,
    RECOMMENDATION_OBJECT_TYPES,
    RECOMMENDATION_TARGET_TYPES,
    RecommendationMode,
    Location,
    LocationSource,
    MinimumFit,
    PlaceCandidate,
    PlaceConfirmRequest,
    SavedEquipment,
    SavedEquipmentDraft,
    SavedEyepieceDraft,
    SavedLocationDraft,
    SkyFactsRequest,
)
from astro_host.places import ObservingLocationService
from astro_host.recommendations import DEFAULT_MINIMUM_FIT, RecommendationService
from astro_host.providers.open_meteo_geocoding import OpenMeteoPlaceResolver
from astro_host.providers.place import PlaceResolver
from astro_host.weather_cache_file import FileWeatherCache, default_weather_cache_path
from astro_host.version import HOST_SEMVER

from astro_engine.astronomy import default_ephemeris_path
from astro_engine.contracts import contracts_root, engine_semver
from astro_engine.runtime_resources import default_atlas_path


EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_INVALID_REQUEST = 2
EXIT_USAGE = 3

AGENT_OPERATIONS = (
    "agent.batch_compare",
    "agent.conditions",
    "agent.locations",
    "agent.places",
    "agent.equipment",
    "agent.recommendations",
    "agent.outlook",
    "agent.sky_facts",
    "agent.eyepieces",
    "agent.optics",
)

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


_EQUIPMENT_ACTIONS = frozenset({
    "list",
    "save",
    "get",
    "resolve",
    "select",
    "select_all",
    "select_naked_eye",
    "delete",
    "get_selected",
    "get_active",
})
_EQUIPMENT_ID_OR_QUERY_ACTIONS = frozenset({"get", "select", "delete"})
_EQUIPMENT_OBJECT_KEYS = frozenset({
    "name", "type", "aperture", "aperture_unit", "magnification", "aliases", "id",
    "focal_length_mm",
})
_EYEPIECE_ACTIONS = frozenset({"list", "save", "get", "resolve", "delete"})
_EYEPIECE_ID_OR_QUERY_ACTIONS = frozenset({"get", "delete"})
_EYEPIECE_OBJECT_KEYS = frozenset({
    "name", "focal_length_mm", "afov_degrees", "aliases", "id",
})
_EXPLICIT_OPTICS_KEYS = frozenset({
    "telescope_focal_length_mm",
    "eyepiece_focal_length_mm",
    "telescope_aperture_mm",
    "afov_degrees",
})
_INLINE_EQUIPMENT_KEYS = frozenset({
    "type", "aperture", "aperture_unit", "magnification",
})
_OVERRIDE_KEYS = frozenset({"id", "query", "mode", "inline"})
_SAVE_EQUIPMENT_KEYS = frozenset({"action", "equipment", "select"})


@dataclass(frozen=True)
class EyepieceRequest:
    action: str
    eyepiece: SavedEyepieceDraft | None = None
    id: str | None = None
    query: str | None = None


@dataclass(frozen=True)
class EquipmentRequest:
    action: str
    equipment: SavedEquipmentDraft | None = None
    select: bool = False
    id: str | None = None
    query: str | None = None
    override: EquipmentOverride | None = None


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="astro-host")
    parser.add_argument(
        "operation",
        nargs="?",
        choices=AGENT_OPERATIONS,
    )
    parser.add_argument("--input", dest="input_path")
    parser.add_argument("--runtime-info", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    parser.add_argument("--atlas-path")
    parser.add_argument("--stale-on-error-seconds", type=float)
    parser.add_argument("--weather-cache-path")
    parser.add_argument("--locations-path")
    parser.add_argument("--equipment-path")
    parser.add_argument("--eyepieces-path")
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
        atlas_path=args.atlas_path or default_atlas_path(),
    )


def build_default_location_store(args: argparse.Namespace) -> FileLocationStore:
    path = (
        Path(args.locations_path)
        if args.locations_path
        else default_locations_path()
    )
    return FileLocationStore(path)


def build_default_equipment_store(args: argparse.Namespace) -> FileEquipmentStore:
    path = (
        Path(args.equipment_path)
        if args.equipment_path
        else default_equipment_path()
    )
    return FileEquipmentStore(path)


def build_default_eyepiece_store(args: argparse.Namespace) -> FileEyepieceStore:
    path = (
        Path(args.eyepieces_path)
        if args.eyepieces_path
        else default_eyepieces_path()
    )
    return FileEyepieceStore(path)


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
    equipment_store: EquipmentStore | None = None,
    eyepiece_store: EyepieceStore | None = None,
    recommendation_engine: RecommendationEngine | None = None,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exc:
        return EXIT_OK if exc.code == 0 else EXIT_USAGE

    if args.runtime_info:
        if args.operation is not None or args.input_path is not None:
            _write_json({
                "ok": False,
                "error": {
                    "code": "invalid_request",
                    "message": "--runtime-info cannot be combined with an operation or --input",
                },
            }, pretty=args.pretty, stream=stdout)
            return EXIT_INVALID_REQUEST
        return _main_runtime_info(pretty=args.pretty, stdout=stdout)
    if args.operation is None or args.input_path is None:
        print("astro-host: an operation and --input are required", file=stderr)
        return EXIT_USAGE

    if args.operation == "agent.locations":
        return _main_locations(args, store=store, stdout=stdout, stderr=stderr)
    if args.operation == "agent.places":
        return _main_places(
            args, resolver=resolver, stdout=stdout, stderr=stderr
        )
    if args.operation == "agent.equipment":
        return _main_equipment(
            args, store=equipment_store, stdout=stdout, stderr=stderr
        )
    if args.operation == "agent.eyepieces":
        return _main_eyepieces(
            args, store=eyepiece_store, stdout=stdout, stderr=stderr
        )
    if args.operation == "agent.optics":
        return _main_optics(
            args,
            equipment_store=equipment_store,
            eyepiece_store=eyepiece_store,
            stdout=stdout,
            stderr=stderr,
        )
    if args.operation == "agent.recommendations":
        return _main_recommendations(
            args,
            service=service,
            store=store,
            equipment_store=equipment_store,
            recommendation_engine=recommendation_engine,
            stdout=stdout,
            stderr=stderr,
        )
    if args.operation == "agent.outlook":
        return _main_outlook(
            args, service=service, store=store, stdout=stdout, stderr=stderr
        )
    if args.operation == "agent.batch_compare":
        return _main_batch_compare(
            args, service=service, store=store, stdout=stdout, stderr=stderr
        )
    if args.operation == "agent.sky_facts":
        return _main_sky_facts(
            args, service=service, store=store, stdout=stdout, stderr=stderr
        )
    return _main_conditions(
        args, service=service, store=store, stdout=stdout, stderr=stderr
    )


def _main_runtime_info(*, pretty: bool, stdout: TextIO) -> int:
    """Report package identity and verify every immutable runtime resource."""
    try:
        contract_path = contracts_root()
        atlas_path = default_atlas_path()
        ephemeris_path = default_ephemeris_path()
        if atlas_path is None or not atlas_path.is_file():
            raise RuntimeError("production light-pollution atlas is not installed")
        if not ephemeris_path.is_file():
            raise RuntimeError("Skyfield ephemeris is not installed")
        payload: dict[str, object] = {
            "ok": True,
            "astro_host_version": HOST_SEMVER,
            "astro_engine_version": engine_semver(),
            "operations": list(AGENT_OPERATIONS),
            "resources": {
                "contracts_data": str(contract_path / "data"),
                "light_pollution_atlas": str(atlas_path),
                "skyfield_ephemeris": str(ephemeris_path),
            },
        }
        _write_json(payload, pretty=pretty, stream=stdout)
        return EXIT_OK
    except Exception as exc:
        _write_json({
            "ok": False,
            "error": {"code": "runtime_invalid", "message": str(exc)},
        }, pretty=pretty, stream=stdout)
        return EXIT_FAILURE


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


def _main_batch_compare(
    args: argparse.Namespace,
    *,
    service: ConditionsService | None,
    store: LocationStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    operation = "agent.batch_compare"
    try:
        document = _read_json(args.input_path)
        host_request, candidates = parse_batch_compare_request(document)
        center, source = _compose_conditions_location(args, host_request.location, store)
        request = ConditionsRequest(
            location=center,
            reference_time=host_request.reference_time,
            observing_date=host_request.observing_date,
            force_refresh=host_request.force_refresh,
        )
        if service is None:
            service = build_default_service(args)
        result = asyncio.run(service.batch_compare(request, candidates))
        result["center_source"] = source.value
        _write_json({"ok": True, "operation": operation, "result": _json_value(result)},
                    pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({"ok": False, "operation": operation,
                     "error": {"code": "invalid_request", "message": str(exc)}},
                    pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({"ok": False, "operation": operation,
                     "error": {"code": exc.code, "message": str(exc)}},
                    pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({"ok": False, "operation": operation,
                     "error": {"code": "host_failure", "message": str(exc)}},
                    pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_sky_facts(
    args: argparse.Namespace,
    *,
    service: ConditionsService | None,
    store: LocationStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        host_request = parse_sky_facts_request(document)
        location, location_source = _compose_conditions_location(
            args, host_request.location, store
        )
        request = SkyFactsRequest(
            location=location,
            reference_time=host_request.reference_time,
            observing_date=host_request.observing_date,
        )
        if service is None:
            service = build_default_service(args)
        result = service.sky_facts(request)
        payload = _json_value(result)
        payload["location_source"] = location_source.value
        _write_json({
            "ok": True,
            "operation": "agent.sky_facts",
            "result": payload,
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.sky_facts",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.sky_facts",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.sky_facts",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_outlook(
    args: argparse.Namespace,
    *,
    service: ConditionsService | None,
    store: LocationStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        host_request = parse_outlook_request(document)
        location, location_source = _compose_conditions_location(
            args, host_request.location, store
        )
        request = ConditionsRequest(
            location=location,
            reference_time=host_request.reference_time,
            force_refresh=host_request.force_refresh,
        )
        if service is None:
            service = build_default_service(args)
        result = asyncio.run(service.outlook(request))
        payload = _json_value(result)
        payload["location_source"] = location_source.value
        _write_json({
            "ok": True,
            "operation": "agent.outlook",
            "result": payload,
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.outlook",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.outlook",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.outlook",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_recommendations(
    args: argparse.Namespace,
    *,
    service: ConditionsService | None,
    store: LocationStore | None,
    equipment_store: EquipmentStore | None,
    recommendation_engine: RecommendationEngine | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        host_request = parse_recommendations_request(document)
        location, location_source = _compose_conditions_location(
            args, host_request.location, store
        )
        if equipment_store is None:
            equipment_store = build_default_equipment_store(args)
        active = EquipmentSessionService(equipment_store).active(host_request.equipment)
        if service is None:
            service = build_default_service(args)
        result = asyncio.run(
            RecommendationService(
                service, engine=recommendation_engine
            ).recommend(
                location=location,
                location_source=location_source,
                reference_time=host_request.reference_time,
                mode=host_request.mode,
                observing_date=host_request.observing_date,
                force_refresh=host_request.force_refresh,
                equipment=active,
                minimum_fit=host_request.minimum_fit or DEFAULT_MINIMUM_FIT,
                target_types=host_request.target_types,
                object_types=host_request.object_types,
                minimum_score=host_request.minimum_score,
                limit=host_request.limit,
            )
        )
        _write_json({
            "ok": True,
            "operation": "agent.recommendations",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except LocationStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except EquipmentStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except EngineCallError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
            "error": {
                "code": "engine_failure",
                "message": exc.message,
                "details": {
                    "capability": exc.capability,
                    "engine_code": exc.code,
                },
            },
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE
    except HostInvariantError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
            "error": {
                "code": exc.code,
                "message": str(exc),
                "details": exc.details,
            },
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.recommendations",
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


def _main_equipment(
    args: argparse.Namespace,
    *,
    store: EquipmentStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        request = parse_equipment_request(document)
        if store is None:
            store = build_default_equipment_store(args)
        result = _dispatch_equipment(store, request)
        _write_json({
            "ok": True,
            "operation": "agent.equipment",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.equipment",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except EquipmentStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.equipment",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.equipment",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _main_eyepieces(
    args: argparse.Namespace,
    *,
    store: EyepieceStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        request = parse_eyepiece_request(document)
        if store is None:
            store = build_default_eyepiece_store(args)
        result = _dispatch_eyepieces(store, request)
        _write_json({
            "ok": True,
            "operation": "agent.eyepieces",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.eyepieces",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except EyepieceStoreError as exc:
        _write_json({
            "ok": False,
            "operation": "agent.eyepieces",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.eyepieces",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _dispatch_eyepieces(
    store: EyepieceStore, request: EyepieceRequest
) -> dict[str, object]:
    action = request.action
    if action == "list":
        return {"action": action, "items": store.list()}
    if action == "save":
        assert request.eyepiece is not None
        written = store.save(request.eyepiece)
        return {"action": action, "item": written.item}
    if action == "get":
        saved = (
            store.resolve(request.query)
            if request.query is not None
            else store.get(request.id or "")
        )
        return {"action": action, "item": saved}
    if action == "resolve":
        return {"action": action, "item": store.resolve(request.query or "")}
    deleted = (
        store.delete_query(request.query)
        if request.query is not None
        else store.delete(request.id or "")
    )
    return {"action": action, "item": deleted.item}


def parse_eyepiece_request(document: object) -> EyepieceRequest:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    action = document.get("action")
    if not isinstance(action, str) or action not in _EYEPIECE_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.eyepieces action")
    keys = set(document)
    if action == "list":
        if keys != {"action"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EyepieceRequest(action=action)
    if action == "save":
        if keys != {"action", "eyepiece"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EyepieceRequest(
            action=action, eyepiece=_parse_eyepiece_draft(document.get("eyepiece"))
        )
    if action == "resolve":
        if keys != {"action", "query"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EyepieceRequest(action=action, query=_required_query(document.get("query")))
    if action not in _EYEPIECE_ID_OR_QUERY_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.eyepieces action")
    has_id = "id" in document
    has_query = "query" in document
    if has_id == has_query or keys - {"action", "id", "query"}:
        raise InvalidRequestError("request must include exactly one of id or query")
    if has_id:
        return EyepieceRequest(action=action, id=_required_id(document.get("id")))
    return EyepieceRequest(action=action, query=_required_query(document.get("query")))


def _parse_eyepiece_draft(value: object) -> SavedEyepieceDraft:
    if not isinstance(value, Mapping) or set(value) - _EYEPIECE_OBJECT_KEYS:
        raise InvalidRequestError("eyepiece must be an object with known fields")
    missing = {"name", "focal_length_mm"} - set(value)
    if missing:
        raise InvalidRequestError("eyepiece name and focal_length_mm are required")
    name = value.get("name")
    if not isinstance(name, str):
        raise InvalidRequestError("eyepiece.name must be a string")
    focal_length = value.get("focal_length_mm")
    if focal_length is None:
        raise InvalidRequestError("eyepiece focal_length_mm is required")
    return SavedEyepieceDraft(
        name=name,
        focal_length_mm=_required_equipment_number(value, "focal_length_mm"),
        afov_degrees=_optional_equipment_number(value, "afov_degrees"),
        aliases=_parse_eyepiece_aliases(value),
        id=_optional_string(value, "id"),
    )


def _parse_eyepiece_aliases(value: Mapping[str, object]) -> tuple[str, ...]:
    if "aliases" not in value:
        return ()
    raw = value["aliases"]
    if raw is None or not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        raise InvalidRequestError("eyepiece.aliases must be an array of strings")
    return tuple(raw)


def _main_optics(
    args: argparse.Namespace,
    *,
    equipment_store: EquipmentStore | None,
    eyepiece_store: EyepieceStore | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    try:
        document = _read_json(args.input_path)
        if not isinstance(document, Mapping):
            raise InvalidRequestError("request must be an object with known fields")
        if "telescope" in document:
            result = _saved_optics_request(
                document,
                equipment_store or build_default_equipment_store(args),
                eyepiece_store or build_default_eyepiece_store(args),
            )
        else:
            result = explicit_optics(**_parse_explicit_optics(document))
        _write_json({
            "ok": True,
            "operation": "agent.optics",
            "result": _json_value(result),
        }, pretty=args.pretty, stream=stdout)
        return EXIT_OK
    except (InvalidRequestError, json.JSONDecodeError, OSError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.optics",
            "error": {"code": "invalid_request", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST
    except (EquipmentStoreError, EyepieceStoreError) as exc:
        _write_json({
            "ok": False,
            "operation": "agent.optics",
            "error": {"code": exc.code, "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_INVALID_REQUEST if exc.code == "invalid_request" else EXIT_FAILURE
    except Exception as exc:
        print(f"astro-host: {exc}", file=stderr)
        _write_json({
            "ok": False,
            "operation": "agent.optics",
            "error": {"code": "host_failure", "message": str(exc)},
        }, pretty=args.pretty, stream=stdout)
        return EXIT_FAILURE


def _parse_explicit_optics(document: Mapping[str, object]) -> dict[str, float | None]:
    if not set(document) or set(document) - _EXPLICIT_OPTICS_KEYS:
        raise InvalidRequestError("request must be an object with known fields")
    return {
        "telescope_focal_length_mm": _optional_equipment_number(
            document, "telescope_focal_length_mm"
        ),
        "eyepiece_focal_length_mm": _optional_equipment_number(
            document, "eyepiece_focal_length_mm"
        ),
        "telescope_aperture_mm": _optional_equipment_number(
            document, "telescope_aperture_mm"
        ),
        "afov_degrees": _optional_equipment_number(document, "afov_degrees"),
    }


def _saved_optics_request(
    document: Mapping[str, object],
    equipment: EquipmentStore,
    eyepieces: EyepieceStore,
) -> dict[str, object]:
    keys = set(document)
    if "eyepiece" in keys and "eyepieces" in keys:
        raise InvalidRequestError("request must be an object with known fields")
    if keys != {"telescope", "eyepiece"} and keys != {"telescope", "eyepieces"}:
        raise InvalidRequestError("request must be an object with known fields")
    telescope_id, telescope_query = _parse_saved_ref(document.get("telescope"), "telescope")
    if "eyepieces" in keys:
        if document.get("eyepieces") != "saved":
            raise InvalidRequestError('eyepieces must be "saved"')
        return saved_optics(
            equipment,
            eyepieces,
            telescope_id=telescope_id,
            telescope_query=telescope_query,
            all_eyepieces=True,
        )
    eyepiece_id, eyepiece_query = _parse_saved_ref(document.get("eyepiece"), "eyepiece")
    return saved_optics(
        equipment,
        eyepieces,
        telescope_id=telescope_id,
        telescope_query=telescope_query,
        eyepiece_id=eyepiece_id,
        eyepiece_query=eyepiece_query,
    )


def _parse_saved_ref(value: object, label: str) -> tuple[str | None, str | None]:
    if not isinstance(value, Mapping) or set(value) not in ({"id"}, {"query"}):
        raise InvalidRequestError(f"{label} must include exactly one of id or query")
    if "id" in value:
        return _required_id(value.get("id")), None
    return None, _required_query(value.get("query"))


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


def _dispatch_equipment(
    store: EquipmentStore, request: EquipmentRequest
) -> dict[str, object]:
    action = request.action
    if action == "list":
        state = store.load()
        return {
            "action": action,
            "items": state.items,
            "selection": _selection_json(state.selection),
        }
    if action == "get_selected":
        state = store.load()
        return {
            "action": action,
            "selection": _selection_json(state.selection),
            "selected_item": _selected_item(state),
        }
    if action == "get_active":
        active = EquipmentSessionService(store).active(request.override)
        return {
            "action": action,
            "source": active.source,
            "has_saved_inventory": active.has_saved_inventory,
            "engine_has_saved_inventory": active.engine_has_saved_inventory,
            "override_applied": active.override_applied,
            "selection": _selection_json(active.selection),
            "capabilities": active.engine_capabilities(),
            "identities": active.identities,
        }
    if action == "save":
        assert request.equipment is not None
        written = store.save(request.equipment, select=request.select)
        return _mutation_result(action, written, include_item=True)
    if action == "select_all":
        return _mutation_result(action, store.select_all())
    if action == "select_naked_eye":
        return _mutation_result(action, store.select_naked_eye())
    if action == "get":
        saved = (
            store.resolve(request.query)
            if request.query is not None
            else store.get(request.id or "")
        )
        state = store.load()
        return {
            "action": action,
            "item": saved,
            "selection": _selection_json(state.selection),
            "selected_item": _selected_item(state),
        }
    if action == "resolve":
        saved = store.resolve(request.query or "")
        state = store.load()
        return {
            "action": action,
            "item": saved,
            "selection": _selection_json(state.selection),
            "selected_item": _selected_item(state),
        }
    if action == "select":
        written = (
            store.select_query(request.query)
            if request.query is not None
            else store.select(request.id or "")
        )
        return _mutation_result(action, written, include_item=True)
    written = (
        store.delete_query(request.query)
        if request.query is not None
        else store.delete(request.id or "")
    )
    return _mutation_result(action, written)


def _mutation_result(
    action: str,
    written: EquipmentWriteResult,
    *,
    include_item: bool = False,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "action": action,
        "selection": _selection_json(written.state.selection),
        "selected_item": _selected_item(written.state),
    }
    if include_item:
        payload["item"] = written.item
    return payload


def _selection_json(selection: EquipmentSelection) -> dict[str, object]:
    if selection.mode is EquipmentSelectionMode.ITEM:
        return {"mode": "item", "id": selection.id}
    return {"mode": selection.mode.value}


def _selected_item(state: EquipmentState) -> SavedEquipment | None:
    if state.selection.mode is not EquipmentSelectionMode.ITEM:
        return None
    identity = state.selection.id
    if identity is None:
        return None
    for item in state.items:
        if item.id == identity:
            return item
    return None


def parse_equipment_request(document: object) -> EquipmentRequest:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    action = document.get("action")
    if not isinstance(action, str) or action not in _EQUIPMENT_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.equipment action")
    keys = set(document)
    if action in {"list", "get_selected", "select_all", "select_naked_eye"}:
        if keys != {"action"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EquipmentRequest(action=action)
    if action == "get_active":
        if keys == {"action"}:
            return EquipmentRequest(action=action)
        if keys != {"action", "equipment"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EquipmentRequest(
            action=action,
            override=_parse_equipment_override(document.get("equipment")),
        )
    if action == "save":
        if "equipment" not in document or keys - _SAVE_EQUIPMENT_KEYS:
            raise InvalidRequestError("request must be an object with known fields")
        select = document.get("select", False)
        if not isinstance(select, bool):
            raise InvalidRequestError("select must be a boolean")
        return EquipmentRequest(
            action=action,
            equipment=_parse_equipment_draft(document.get("equipment")),
            select=select,
        )
    if action == "resolve":
        if keys != {"action", "query"}:
            raise InvalidRequestError("request must be an object with known fields")
        return EquipmentRequest(action=action, query=_required_query(document.get("query")))
    if action not in _EQUIPMENT_ID_OR_QUERY_ACTIONS:
        raise InvalidRequestError("action must be a supported agent.equipment action")
    has_id = "id" in document
    has_query = "query" in document
    if has_id == has_query or keys - {"action", "id", "query"}:
        raise InvalidRequestError("request must include exactly one of id or query")
    if has_id:
        return EquipmentRequest(action=action, id=_required_id(document.get("id")))
    return EquipmentRequest(action=action, query=_required_query(document.get("query")))


def _parse_equipment_draft(value: object) -> SavedEquipmentDraft:
    if not isinstance(value, Mapping) or set(value) - _EQUIPMENT_OBJECT_KEYS:
        raise InvalidRequestError("equipment must be an object with known fields")
    missing = {"name", "type", "aperture", "aperture_unit"} - set(value)
    if missing:
        raise InvalidRequestError(
            "equipment name, type, aperture, and aperture_unit are required"
        )
    name = value.get("name")
    if not isinstance(name, str):
        raise InvalidRequestError("equipment.name must be a string")
    kind = _parse_equipment_type(value.get("type"))
    unit = _parse_aperture_unit(value.get("aperture_unit"))
    aliases = _parse_equipment_aliases(value)
    magnification = _optional_equipment_number(value, "magnification")
    return SavedEquipmentDraft(
        name=name,
        type=kind,
        aperture=_required_equipment_number(value, "aperture"),
        aperture_unit=unit,
        aliases=aliases,
        magnification=magnification,
        id=_optional_string(value, "id"),
        focal_length_mm=_optional_equipment_number(value, "focal_length_mm"),
    )


def _parse_equipment_override(value: object) -> EquipmentOverride:
    if not isinstance(value, Mapping) or set(value) - _OVERRIDE_KEYS:
        raise InvalidRequestError("equipment must be an object with known fields")
    present = [key for key in ("id", "query", "mode", "inline") if key in value]
    if len(present) != 1:
        raise InvalidRequestError(
            "equipment override must include exactly one of id, query, mode, inline"
        )
    if "id" in value:
        return EquipmentOverride(id=_required_id(value.get("id")))
    if "query" in value:
        return EquipmentOverride(query=_required_query(value.get("query")))
    if "mode" in value:
        return EquipmentOverride(mode=_parse_override_mode(value.get("mode")))
    return EquipmentOverride(inline=_parse_inline_draft(value.get("inline")))


def _parse_override_mode(value: object) -> EquipmentOverrideMode:
    if value == "item":
        raise InvalidRequestError(
            "override mode item requires id or query"
        )
    if not isinstance(value, str):
        raise InvalidRequestError("override mode must be all_saved or naked_eye_only")
    try:
        return EquipmentOverrideMode(value)
    except ValueError as exc:
        raise InvalidRequestError(
            "override mode must be all_saved or naked_eye_only"
        ) from exc


def _parse_inline_draft(value: object) -> InlineEquipmentDraft:
    if not isinstance(value, Mapping) or set(value) - _INLINE_EQUIPMENT_KEYS:
        raise InvalidRequestError("inline must be an object with known fields")
    missing = {"type", "aperture", "aperture_unit"} - set(value)
    if missing:
        raise InvalidRequestError(
            "inline type, aperture, and aperture_unit are required"
        )
    return InlineEquipmentDraft(
        type=_parse_equipment_type(value.get("type")),
        aperture=_required_equipment_number(value, "aperture"),
        aperture_unit=_parse_aperture_unit(value.get("aperture_unit")),
        magnification=_optional_equipment_number(value, "magnification"),
    )


def _parse_equipment_type(value: object) -> EquipmentType:
    if not isinstance(value, str):
        raise InvalidRequestError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        )
    try:
        return EquipmentType(value)
    except ValueError as exc:
        raise InvalidRequestError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        ) from exc


def _parse_aperture_unit(value: object) -> EquipmentApertureUnit:
    if not isinstance(value, str):
        raise InvalidRequestError("aperture_unit must be millimeters or inches")
    try:
        return EquipmentApertureUnit(value)
    except ValueError as exc:
        raise InvalidRequestError(
            "aperture_unit must be millimeters or inches"
        ) from exc


def _parse_equipment_aliases(value: Mapping[str, object]) -> tuple[str, ...]:
    if "aliases" not in value:
        return ()
    raw = value["aliases"]
    if raw is None or not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        raise InvalidRequestError("equipment.aliases must be an array of strings")
    return tuple(raw)


def _required_equipment_number(value: Mapping[str, object], key: str) -> float:
    raw = value.get(key)
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise InvalidRequestError(f"{key} must be a number")
    try:
        parsed = float(raw)
    except OverflowError as exc:
        raise InvalidRequestError(f"{key} must be finite") from exc
    if not math.isfinite(parsed):
        raise InvalidRequestError(f"{key} must be finite")
    return parsed


def _optional_equipment_number(
    value: Mapping[str, object], key: str
) -> float | None:
    if key not in value:
        return None
    raw = value[key]
    if raw is None:
        return None
    if isinstance(raw, bool) or not isinstance(raw, (int, float)):
        raise InvalidRequestError(f"{key} must be a number or null")
    try:
        parsed = float(raw)
    except OverflowError as exc:
        raise InvalidRequestError(f"{key} must be finite or null") from exc
    if not math.isfinite(parsed):
        raise InvalidRequestError(f"{key} must be finite or null")
    return parsed


def parse_places_request(document: object) -> str:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    action = document.get("action")
    if action != "resolve":
        raise InvalidRequestError("action must be a supported agent.places action")
    if set(document) != {"action", "query"}:
        raise InvalidRequestError("request must be an object with known fields")
    return _required_query(document.get("query"))


_SKY_FACTS_KEYS = frozenset({"location", "reference_time", "observing_date"})
_OUTLOOK_KEYS = frozenset({"location", "reference_time", "force_refresh"})


def parse_sky_facts_request(document: object) -> HostSkyFactsRequest:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    if "force_refresh" in document:
        raise InvalidRequestError("agent.sky_facts does not accept force_refresh")
    if set(document) - _SKY_FACTS_KEYS:
        raise InvalidRequestError("request must be an object with known fields")
    parsed = parse_conditions_request(document)
    return HostSkyFactsRequest(
        location=parsed.location,
        reference_time=parsed.reference_time,
        observing_date=parsed.observing_date,
    )


def parse_outlook_request(document: object) -> HostConditionsRequest:
    if not isinstance(document, Mapping):
        raise InvalidRequestError("request must be an object with known fields")
    if "observing_date" in document:
        raise InvalidRequestError("agent.outlook does not accept observing_date")
    if set(document) - _OUTLOOK_KEYS:
        raise InvalidRequestError("request must be an object with known fields")
    return parse_conditions_request(document)


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


def parse_batch_compare_request(
    document: object,
) -> tuple[HostConditionsRequest, tuple[BatchCandidate, ...]]:
    if not isinstance(document, Mapping) or set(document) - {
        "center", "reference_time", "observing_date", "force_refresh", "candidates"
    }:
        raise InvalidRequestError("batch request must be an object with known fields")
    raw_candidates = document.get("candidates")
    if not isinstance(raw_candidates, list) or not 1 <= len(raw_candidates) <= 16:
        raise InvalidRequestError("candidates must contain 1 to 16 places")
    center_request = parse_conditions_request({
        **({"location": document["center"]} if "center" in document else {}),
        "reference_time": document.get("reference_time"),
        **({"observing_date": document["observing_date"]}
           if "observing_date" in document else {}),
        **({"force_refresh": document["force_refresh"]}
           if "force_refresh" in document else {}),
    })
    candidates: list[BatchCandidate] = []
    for row in raw_candidates:
        if not isinstance(row, Mapping) or set(row) - {
            "key", "name", "latitude", "longitude", "source_url", "map_url", "metadata"
        }:
            raise InvalidRequestError("candidate must be an object with known fields")
        key, name = row.get("key"), row.get("name")
        if not isinstance(key, str) or not key.strip():
            raise InvalidRequestError("candidate key must be nonempty")
        if not isinstance(name, str) or not name.strip():
            raise InvalidRequestError("candidate name must be nonempty")
        latitude, longitude = row.get("latitude"), row.get("longitude")
        if (isinstance(latitude, bool) or not isinstance(latitude, (int, float)) or
            isinstance(longitude, bool) or not isinstance(longitude, (int, float)) or
            not math.isfinite(latitude) or not math.isfinite(longitude) or
            not -90 <= latitude <= 90 or not -180 <= longitude <= 180):
            raise InvalidRequestError("candidate coordinates are invalid")
        for field in ("source_url", "map_url"):
            if row.get(field) is not None and not isinstance(row[field], str):
                raise InvalidRequestError(f"{field} must be a string or null")
        metadata = row.get("metadata", {})
        if not isinstance(metadata, Mapping):
            raise InvalidRequestError("candidate metadata must be an object")
        candidates.append(BatchCandidate(
            key=key, name=name,
            location=Location(latitude=float(latitude), longitude=float(longitude), name=name),
            source_url=row.get("source_url"), map_url=row.get("map_url"),
            metadata=dict(metadata),
        ))
    return center_request, tuple(candidates)


_RECOMMENDATIONS_KEYS = frozenset({
    "mode",
    "location",
    "reference_time",
    "observing_date",
    "force_refresh",
    "equipment",
    "minimum_fit",
    "target_types",
    "object_types",
    "minimum_score",
    "limit",
})
_BROWSE_ONLY_KEYS = frozenset({
    "target_types",
    "object_types",
    "minimum_score",
    "limit",
})
_MINIMUM_FIT_VALUES = frozenset(item.value for item in MinimumFit)
_TARGET_TYPE_VALUES = frozenset(RECOMMENDATION_TARGET_TYPES)
_OBJECT_TYPE_VALUES = frozenset(RECOMMENDATION_OBJECT_TYPES)


def parse_recommendations_request(document: object) -> HostRecommendationsRequest:
    if not isinstance(document, Mapping) or set(document) - _RECOMMENDATIONS_KEYS:
        raise InvalidRequestError("request must be an object with known fields")
    raw_mode = document.get("mode")
    if not isinstance(raw_mode, str) or raw_mode not in {
        item.value for item in RecommendationMode
    }:
        raise InvalidRequestError("mode must be best or browse")
    mode = RecommendationMode(raw_mode)
    if mode is RecommendationMode.BEST:
        present = sorted(_BROWSE_ONLY_KEYS & set(document))
        if present:
            raise InvalidRequestError(
                "best mode does not accept " + ", ".join(present)
            )
    base = {
        key: document[key]
        for key in ("location", "reference_time", "observing_date", "force_refresh")
        if key in document
    }
    conditions = parse_conditions_request(base)
    equipment = None
    if "equipment" in document:
        equipment = _parse_equipment_override(document["equipment"])
    minimum_fit = None
    if "minimum_fit" in document:
        raw = document["minimum_fit"]
        if not isinstance(raw, str) or raw not in _MINIMUM_FIT_VALUES:
            raise InvalidRequestError(
                "minimum_fit must be any, challengingOrBetter, goodOrBetter, or excellentOnly"
            )
        minimum_fit = MinimumFit(raw)
    target_types = None
    object_types = None
    minimum_score = None
    limit = None
    if mode is RecommendationMode.BROWSE:
        if "target_types" in document:
            target_types = _parse_unique_enum_array(
                document["target_types"], "target_types", _TARGET_TYPE_VALUES
            )
        if "object_types" in document:
            object_types = _parse_unique_enum_array(
                document["object_types"], "object_types", _OBJECT_TYPE_VALUES
            )
        if "minimum_score" in document:
            minimum_score = _parse_int_in_range(
                document["minimum_score"], "minimum_score", 0, 100
            )
        if "limit" in document:
            limit = _parse_int_in_range(document["limit"], "limit", 1, 100)
    return HostRecommendationsRequest(
        location=conditions.location,
        reference_time=conditions.reference_time,
        mode=mode,
        observing_date=conditions.observing_date,
        force_refresh=conditions.force_refresh,
        equipment=equipment,
        minimum_fit=minimum_fit,
        target_types=target_types,
        object_types=object_types,
        minimum_score=minimum_score,
        limit=limit,
    )


def _parse_unique_enum_array(
    value: object, field: str, allowed: frozenset[str]
) -> tuple[str, ...]:
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise InvalidRequestError(f"{field} must be an array of strings")
    if not value:
        raise InvalidRequestError(f"{field} must be a non-empty array")
    if len(value) != len(set(value)):
        raise InvalidRequestError(f"{field} must not contain duplicates")
    if any(item not in allowed for item in value):
        raise InvalidRequestError(f"{field} contains unknown values")
    return tuple(value)


def _parse_int_in_range(value: object, field: str, lo: int, hi: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidRequestError(f"{field} must be an integer")
    if value < lo or value > hi:
        raise InvalidRequestError(f"{field} must be between {lo} and {hi}")
    return value


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
