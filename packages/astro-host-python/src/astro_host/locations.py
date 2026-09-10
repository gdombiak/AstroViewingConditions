"""Authoritative saved observing-location state.

``FileLocationStore`` takes a sidecar ``fcntl.flock`` and then runs a
synchronous read-modify-write. Introducing ``await`` inside that locked
section is a contract break.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field, replace
import fcntl
import json
import math
import os
from pathlib import Path
import re
from typing import Protocol, TypeVar
import unicodedata
import uuid

from astro_host.errors import (
    InvalidLocationError,
    LocationConflictError,
    LocationNotFoundError,
    LocationStoreCorruptError,
    LocationStoreError,
    LocationStoreUnsupportedSchemaError,
)
from astro_host.models import (
    LocationState,
    SavedLocation,
    SavedLocationDraft,
    TimeZoneSource,
)
from astro_host.timezones import validate_iana
from astro_host.weather_cache_file import default_state_dir


SCHEMA_VERSION = 1
LOCATIONS_FILENAME = "locations.json"
CANONICAL_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
_KNOWN_DOCUMENT_KEYS = frozenset(
    {"schema_version", "locations", "selected_location_id"}
)
_KNOWN_LOCATION_KEYS = frozenset(
    {"id", "name", "latitude", "longitude", "time_zone", "aliases", "elevation_m"}
)
_T = TypeVar("_T")


def normalize_label(value: str) -> str:
    return unicodedata.normalize("NFC", value.strip()).casefold()


def canonicalize_location_id(value: str) -> str:
    """Return canonical lowercase 8-4-4-4-12, or raise InvalidLocationError."""
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise InvalidLocationError("id must be a UUID") from exc


def default_locations_path() -> Path:
    return default_state_dir() / LOCATIONS_FILENAME


class LocationStore(Protocol):
    def load(self) -> LocationState: ...
    def save(self, location: SavedLocationDraft) -> SavedLocation: ...
    def get(self, id: str) -> SavedLocation: ...
    def resolve(self, query: str) -> SavedLocation: ...
    def list(self) -> tuple[SavedLocation, ...]: ...
    def select(self, id: str) -> SavedLocation: ...
    def select_query(self, query: str) -> SavedLocation: ...
    def clear_selection(self) -> None: ...
    def delete(self, id: str) -> None: ...
    def delete_query(self, query: str) -> None: ...
    def get_selected(self) -> SavedLocation | None: ...


@dataclass
class _Document:
    locations: tuple[SavedLocation, ...]
    selected_location_id: str | None
    extra: dict[str, object] = field(default_factory=dict)
    location_extras: dict[str, dict[str, object]] = field(default_factory=dict)

    def as_state(self) -> LocationState:
        return LocationState(self.locations, self.selected_location_id)


def _empty_document() -> _Document:
    return _Document((), None)


class MemoryLocationStore:
    def __init__(self) -> None:
        self._document = _empty_document()

    def load(self) -> LocationState:
        return self._document.as_state()

    def save(self, location: SavedLocationDraft) -> SavedLocation:
        self._document, saved = _apply_save(self._document, location)
        return saved

    def get(self, id: str) -> SavedLocation:
        return _get(self._document, id)

    def resolve(self, query: str) -> SavedLocation:
        return _resolve(self._document, query)

    def list(self) -> tuple[SavedLocation, ...]:
        return self._document.locations

    def select(self, id: str) -> SavedLocation:
        self._document, saved = _apply_select(self._document, id)
        return saved

    def select_query(self, query: str) -> SavedLocation:
        document = self._document
        self._document, saved = _apply_select_query(document, query)
        return saved

    def clear_selection(self) -> None:
        self._document = _apply_clear_selection(self._document)

    def delete(self, id: str) -> None:
        self._document = _apply_delete(self._document, id)

    def delete_query(self, query: str) -> None:
        document = self._document
        self._document = _apply_delete_query(document, query)

    def get_selected(self) -> SavedLocation | None:
        return _get_selected(self._document)


class FileLocationStore:
    def __init__(self, path: Path | str) -> None:
        self.path = Path(path).expanduser().resolve()

    def load(self) -> LocationState:
        return self._read().as_state()

    def save(self, location: SavedLocationDraft) -> SavedLocation:
        _validated_from_draft(location)

        def body() -> SavedLocation:
            document, saved = _apply_save(self._load_locked(), location)
            self._write_locked(document)
            return saved

        return self._mutate(body)

    def get(self, id: str) -> SavedLocation:
        return _get(self._read(), id)

    def resolve(self, query: str) -> SavedLocation:
        return _resolve(self._read(), query)

    def list(self) -> tuple[SavedLocation, ...]:
        return self._read().locations

    def select(self, id: str) -> SavedLocation:
        def body() -> SavedLocation:
            document, saved = _apply_select(self._load_locked(), id)
            self._write_locked(document)
            return saved

        return self._mutate(body)

    def select_query(self, query: str) -> SavedLocation:
        def body() -> SavedLocation:
            document, saved = _apply_select_query(self._load_locked(), query)
            self._write_locked(document)
            return saved

        return self._mutate(body)

    def clear_selection(self) -> None:
        def body() -> None:
            self._write_locked(_apply_clear_selection(self._load_locked()))

        self._mutate(body)

    def delete(self, id: str) -> None:
        def body() -> None:
            self._write_locked(_apply_delete(self._load_locked(), id))

        self._mutate(body)

    def delete_query(self, query: str) -> None:
        def body() -> None:
            self._write_locked(_apply_delete_query(self._load_locked(), query))

        self._mutate(body)

    def get_selected(self) -> SavedLocation | None:
        return _get_selected(self._read())

    def _lock_path(self) -> Path:
        return self.path.with_name(self.path.name + ".lock")

    def _read(self) -> _Document:
        try:
            if not self.path.exists():
                return _empty_document()
            return self._with_lock(self._load_locked)
        except OSError as exc:
            raise LocationStoreError(str(exc), code="host_failure") from exc

    def _mutate(self, body: Callable[[], _T]) -> _T:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            return self._with_lock(body)
        except OSError as exc:
            raise LocationStoreError(str(exc), code="host_failure") from exc

    def _with_lock(self, body: Callable[[], _T]) -> _T:
        try:
            with open(self._lock_path(), "a+", encoding="utf-8") as handle:
                fd = handle.fileno()
                fcntl.flock(fd, fcntl.LOCK_EX)
                try:
                    return body()
                finally:
                    fcntl.flock(fd, fcntl.LOCK_UN)
        except OSError as exc:
            raise LocationStoreError(str(exc), code="host_failure") from exc

    def _load_locked(self) -> _Document:
        if not self.path.exists():
            return _empty_document()
        try:
            raw = self.path.read_bytes()
        except OSError as exc:
            raise LocationStoreError(str(exc), code="host_failure") from exc
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise LocationStoreCorruptError("locations file is not valid UTF-8") from exc
        try:
            document = json.loads(text, parse_constant=_reject_constant)
        except json.JSONDecodeError as exc:
            raise LocationStoreCorruptError("locations file is not valid JSON") from exc
        except ValueError as exc:
            raise LocationStoreCorruptError(str(exc)) from exc
        return _decode_document(document)

    def _write_locked(self, document: _Document) -> None:
        payload = _encode_document(document)
        tmp_path = self.path.with_name(
            f"{self.path.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
        )
        try:
            try:
                with open(tmp_path, "w", encoding="utf-8") as handle:
                    handle.write(payload)
                    handle.flush()
                os.replace(tmp_path, self.path)
            except OSError as exc:
                raise LocationStoreError(str(exc), code="host_failure") from exc
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass


def _reject_constant(name: str) -> None:
    raise ValueError(f"non-finite JSON constant {name}")


def _get(document: _Document, id: str) -> SavedLocation:
    canonical = canonicalize_location_id(id)
    for location in document.locations:
        if location.id == canonical:
            return location
    raise LocationNotFoundError("saved location not found", query=canonical)


def _get_selected(document: _Document) -> SavedLocation | None:
    selected = document.selected_location_id
    if selected is None:
        return None
    for location in document.locations:
        if location.id == selected:
            return location
    raise LocationStoreCorruptError("selected_location_id does not match a saved location")


def _resolve(document: _Document, query: str) -> SavedLocation:
    if not isinstance(query, str):
        raise InvalidLocationError("query must be a string")
    trimmed = query.strip()
    if not trimmed:
        raise InvalidLocationError("query must be a non-empty string")
    try:
        canonical = canonicalize_location_id(trimmed)
    except InvalidLocationError:
        canonical = None
    if canonical is not None:
        for location in document.locations:
            if location.id == canonical:
                return location
    needle = normalize_label(trimmed)
    matches = [
        location
        for location in document.locations
        if normalize_label(location.name) == needle
        or any(normalize_label(alias) == needle for alias in location.aliases)
    ]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise LocationStoreCorruptError("ambiguous location label")
    raise LocationNotFoundError("saved location not found", query=trimmed)


def _apply_save(
    document: _Document, draft: SavedLocationDraft
) -> tuple[_Document, SavedLocation]:
    saved = _validated_from_draft(draft)
    if draft.id is None:
        occupied = {location.id for location in document.locations}
        labels = _all_normalized_labels(document.locations)
        own_labels = {normalize_label(saved.name), *(normalize_label(alias) for alias in saved.aliases)}
        while saved.id in occupied or saved.id in labels or saved.id in own_labels:
            saved = replace(saved, id=str(uuid.uuid4()))
        others = document.locations
        created = True
    else:
        others = tuple(
            location for location in document.locations if location.id != saved.id
        )
        created = len(others) == len(document.locations)
    _reject_conflicts(saved, others)
    if created:
        locations = (*document.locations, saved)
        extras = dict(document.location_extras)
    else:
        locations = tuple(
            saved if location.id == saved.id else location
            for location in document.locations
        )
        extras = dict(document.location_extras)
    selected = document.selected_location_id
    if created and len(document.locations) == 0 and len(locations) == 1:
        selected = saved.id
    return replace(
        document,
        locations=locations,
        selected_location_id=selected,
        location_extras=extras,
    ), saved


def _apply_delete(document: _Document, id: str) -> _Document:
    canonical = canonicalize_location_id(id)
    if not any(location.id == canonical for location in document.locations):
        raise LocationNotFoundError("saved location not found", query=canonical)
    remaining = tuple(
        location for location in document.locations if location.id != canonical
    )
    extras = {
        key: value
        for key, value in document.location_extras.items()
        if key != canonical
    }
    selected = document.selected_location_id
    if selected == canonical:
        if len(remaining) == 1:
            selected = remaining[0].id
        else:
            selected = None
    return replace(
        document,
        locations=remaining,
        selected_location_id=selected,
        location_extras=extras,
    )


def _apply_select(document: _Document, id: str) -> tuple[_Document, SavedLocation]:
    saved = _get(document, id)
    return replace(document, selected_location_id=saved.id), saved


def _apply_select_query(
    document: _Document, query: str
) -> tuple[_Document, SavedLocation]:
    resolved = _resolve(document, query)
    return _apply_select(document, resolved.id)


def _apply_delete_query(document: _Document, query: str) -> _Document:
    resolved = _resolve(document, query)
    return _apply_delete(document, resolved.id)


def _apply_clear_selection(document: _Document) -> _Document:
    return replace(document, selected_location_id=None)


def _validated_from_draft(draft: SavedLocationDraft) -> SavedLocation:
    if draft.id is None:
        identity = str(uuid.uuid4())
    elif not isinstance(draft.id, str):
        raise InvalidLocationError("id must be a UUID")
    else:
        identity = canonicalize_location_id(draft.id)
    name = _required_name(draft.name)
    aliases = _validated_aliases(draft.aliases, name)
    latitude = _coordinate(draft.latitude, "latitude", -90, 90)
    longitude = _coordinate(draft.longitude, "longitude", -180, 180)
    elevation = _optional_elevation(draft.elevation_m)
    time_zone = _required_time_zone(draft.time_zone)
    return SavedLocation(
        id=identity,
        name=name,
        latitude=latitude,
        longitude=longitude,
        time_zone=time_zone,
        aliases=aliases,
        elevation_m=elevation,
    )


def _required_name(value: object) -> str:
    if not isinstance(value, str):
        raise InvalidLocationError("name must be a string")
    name = value.strip()
    if not name:
        raise InvalidLocationError("name must be a non-empty string")
    return name


def _validated_aliases(value: object, name: str) -> tuple[str, ...]:
    if value is None:
        raise InvalidLocationError("aliases must be an array of strings")
    if isinstance(value, (str, bytes)):
        raise InvalidLocationError("aliases must be an array of strings")
    if not isinstance(value, Sequence):
        raise InvalidLocationError("aliases must be an array of strings")
    trimmed: list[str] = []
    seen: set[str] = set()
    own = normalize_label(name)
    for item in value:
        if not isinstance(item, str):
            raise InvalidLocationError("aliases must be an array of strings")
        alias = item.strip()
        if not alias:
            raise InvalidLocationError("aliases must be non-empty after trim")
        key = normalize_label(alias)
        if key == own:
            raise InvalidLocationError("alias must not equal the location name")
        if key in seen:
            raise InvalidLocationError("aliases must be unique")
        seen.add(key)
        trimmed.append(alias)
    trimmed.sort(key=normalize_label)
    return tuple(trimmed)


def _required_time_zone(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise InvalidLocationError("time_zone must be a non-empty string")
    ok, reason = validate_iana(value, TimeZoneSource.LOCATION_HINT)
    if not ok:
        raise InvalidLocationError(
            "time_zone must be an IANA identifier accepted by ZoneInfo "
            "and the shared engine catalogue"
            + (f" ({reason})" if reason else "")
        )
    return value


def _coordinate(value: object, name: str, minimum: float, maximum: float) -> float:
    number = _finite_float(value, name)
    if not minimum <= number <= maximum:
        raise InvalidLocationError(
            f"{name} must be finite and between {minimum} and {maximum}"
        )
    return number


def _optional_elevation(value: object) -> float | None:
    if value is None:
        return None
    return _finite_float(value, "elevation_m")


def _finite_float(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidLocationError(f"{name} must be a number")
    try:
        number = float(value)
    except OverflowError as exc:
        raise InvalidLocationError(f"{name} must be finite") from exc
    if not math.isfinite(number):
        raise InvalidLocationError(f"{name} must be finite")
    return number


def _reject_conflicts(
    saved: SavedLocation, others: Sequence[SavedLocation]
) -> None:
    other_labels = _all_normalized_labels(others)
    live_ids = {location.id for location in others} | {saved.id}
    for label in (saved.name, *saved.aliases):
        key = normalize_label(label)
        if key in other_labels:
            raise LocationConflictError(
                "location name or alias already exists", normalized=key
            )
        if key in live_ids:
            raise LocationConflictError(
                "location name or alias collides with a location id",
                normalized=key,
            )
    for other in others:
        for label in (other.name, *other.aliases):
            if normalize_label(label) == saved.id:
                raise LocationConflictError(
                    "location id collides with an existing name or alias",
                    normalized=saved.id,
                )


def _all_normalized_labels(locations: Sequence[SavedLocation]) -> set[str]:
    labels: set[str] = set()
    for location in locations:
        labels.add(normalize_label(location.name))
        labels.update(normalize_label(alias) for alias in location.aliases)
    return labels


def _encode_document(document: _Document) -> str:
    encoded_locations = [
        _encode_location(location, document.location_extras.get(location.id, {}))
        for location in document.locations
    ]
    payload: dict[str, object] = dict(document.extra)
    payload["locations"] = encoded_locations
    payload["schema_version"] = SCHEMA_VERSION
    payload["selected_location_id"] = document.selected_location_id
    return json.dumps(
        payload,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    ) + "\n"


def _encode_location(
    location: SavedLocation, extras: Mapping[str, object]
) -> dict[str, object]:
    row = dict(extras)
    row["aliases"] = list(location.aliases)
    row["id"] = location.id
    row["latitude"] = location.latitude
    row["longitude"] = location.longitude
    row["name"] = location.name
    row["time_zone"] = location.time_zone
    if location.elevation_m is None:
        row.pop("elevation_m", None)
    else:
        row["elevation_m"] = location.elevation_m
    return row


def _decode_document(document: object) -> _Document:
    try:
        return _decode_document_inner(document)
    except (LocationStoreUnsupportedSchemaError, LocationStoreCorruptError):
        raise
    except (
        TypeError,
        KeyError,
        ValueError,
        OverflowError,
        InvalidLocationError,
        LocationConflictError,
    ) as exc:
        raise LocationStoreCorruptError(str(exc)) from exc


def _decode_document_inner(document: object) -> _Document:
    if not isinstance(document, Mapping):
        raise LocationStoreCorruptError("locations document must be an object")
    if "schema_version" not in document:
        raise LocationStoreCorruptError("schema_version is required")
    if "locations" not in document:
        raise LocationStoreCorruptError("locations is required")
    if "selected_location_id" not in document:
        raise LocationStoreCorruptError("selected_location_id is required")
    version = document["schema_version"]
    if isinstance(version, int) and not isinstance(version, bool):
        if version != SCHEMA_VERSION:
            raise LocationStoreUnsupportedSchemaError(
                "unsupported locations schema_version",
                schema_version=version,
            )
    else:
        raise LocationStoreCorruptError("schema_version must be an integer")
    raw_locations = document["locations"]
    if not isinstance(raw_locations, list):
        raise LocationStoreCorruptError("locations must be an array")
    decoded: list[SavedLocation] = []
    extras: dict[str, dict[str, object]] = {}
    seen_ids: set[str] = set()
    for item in raw_locations:
        location, extra = _decode_location(item)
        if location.id in seen_ids:
            raise LocationStoreCorruptError("duplicate location id")
        seen_ids.add(location.id)
        decoded.append(location)
        extras[location.id] = extra
    _reject_loaded_uniqueness(decoded)
    selected = _decode_selected(document["selected_location_id"], decoded)
    extra = {
        key: value
        for key, value in document.items()
        if key not in _KNOWN_DOCUMENT_KEYS
    }
    return _Document(tuple(decoded), selected, extra, extras)


def _decode_location(value: object) -> tuple[SavedLocation, dict[str, object]]:
    if not isinstance(value, Mapping):
        raise LocationStoreCorruptError("location must be an object")
    for key in ("id", "name", "latitude", "longitude", "time_zone"):
        if key not in value:
            raise LocationStoreCorruptError(f"location.{key} is required")
    identity = _canonical_on_disk_id(value["id"])
    name = _required_name(value["name"])
    if "aliases" not in value:
        aliases: tuple[str, ...] = ()
    else:
        aliases = _validated_aliases(value["aliases"], name)
    location = SavedLocation(
        id=identity,
        name=name,
        latitude=_coordinate(value["latitude"], "latitude", -90, 90),
        longitude=_coordinate(value["longitude"], "longitude", -180, 180),
        time_zone=_required_time_zone(value["time_zone"]),
        aliases=aliases,
        elevation_m=_optional_elevation(value.get("elevation_m")),
    )
    extra = {
        key: extra_value
        for key, extra_value in value.items()
        if key not in _KNOWN_LOCATION_KEYS
    }
    return location, extra


def _canonical_on_disk_id(value: object) -> str:
    if not isinstance(value, str) or not CANONICAL_UUID.fullmatch(value):
        raise InvalidLocationError("id must be a canonical UUID")
    if value != str(uuid.UUID(value)):
        raise InvalidLocationError("id must be a canonical UUID")
    return value


def _decode_selected(
    value: object, locations: Sequence[SavedLocation]
) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not CANONICAL_UUID.fullmatch(value):
        raise LocationStoreCorruptError("selected_location_id is not a canonical UUID")
    if value != str(uuid.UUID(value)):
        raise LocationStoreCorruptError("selected_location_id is not a canonical UUID")
    if not any(location.id == value for location in locations):
        raise LocationStoreCorruptError("selected_location_id does not match a saved location")
    return value


def _reject_loaded_uniqueness(locations: Sequence[SavedLocation]) -> None:
    labels: set[str] = set()
    ids = {location.id for location in locations}
    for location in locations:
        for label in (location.name, *location.aliases):
            key = normalize_label(label)
            if key in labels:
                raise LocationStoreCorruptError("duplicate location name or alias")
            if key in ids:
                raise LocationStoreCorruptError(
                    "location name or alias collides with a location id"
                )
            labels.add(key)
