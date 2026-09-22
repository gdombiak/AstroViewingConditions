"""Durable eyepiece inventory. Separate from saved instruments.

``FileEyepieceStore`` takes a sidecar ``fcntl.flock`` and then runs a
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
import uuid

from astro_host.equipment import canonicalize_equipment_id
from astro_host.errors import (
    EyepieceConflictError,
    EyepieceNotFoundError,
    EyepieceStoreCorruptError,
    EyepieceStoreError,
    EyepieceStoreUnsupportedSchemaError,
    InvalidEquipmentError,
    InvalidEyepieceError,
)
from astro_host.locations import normalize_label
from astro_host.models import (
    EyepieceState,
    EyepieceWriteResult,
    SavedEyepiece,
    SavedEyepieceDraft,
)
from astro_host.weather_cache_file import default_state_dir


SCHEMA_VERSION = 1
EYEPIECE_FILENAME = "eyepieces.json"
CANONICAL_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
MAX_ABS_NUMBER = 1e9
MAX_AFOV_DEGREES = 180.0
_KNOWN_DOCUMENT_KEYS = frozenset({"schema_version", "items"})
_KNOWN_ITEM_KEYS = frozenset({
    "id",
    "name",
    "focal_length_mm",
    "afov_degrees",
    "aliases",
})
_T = TypeVar("_T")


def default_eyepieces_path() -> Path:
    return default_state_dir() / EYEPIECE_FILENAME


class EyepieceStore(Protocol):
    def load(self) -> EyepieceState: ...
    def save(self, draft: SavedEyepieceDraft) -> EyepieceWriteResult: ...
    def get(self, id: str) -> SavedEyepiece: ...
    def resolve(self, query: str) -> SavedEyepiece: ...
    def list(self) -> tuple[SavedEyepiece, ...]: ...
    def delete(self, id: str) -> EyepieceWriteResult: ...
    def delete_query(self, query: str) -> EyepieceWriteResult: ...


@dataclass
class _Document:
    items: tuple[SavedEyepiece, ...]
    extra: dict[str, object] = field(default_factory=dict)
    item_extras: dict[str, dict[str, object]] = field(default_factory=dict)

    def as_state(self) -> EyepieceState:
        return EyepieceState(self.items)


def _empty_document() -> _Document:
    return _Document(())


class MemoryEyepieceStore:
    def __init__(self) -> None:
        self._document = _empty_document()

    def load(self) -> EyepieceState:
        return self._document.as_state()

    def save(self, draft: SavedEyepieceDraft) -> EyepieceWriteResult:
        self._document, saved = _apply_save(self._document, draft)
        return EyepieceWriteResult(state=self._document.as_state(), item=saved)

    def get(self, id: str) -> SavedEyepiece:
        return _get(self._document, id)

    def resolve(self, query: str) -> SavedEyepiece:
        return _resolve(self._document, query)

    def list(self) -> tuple[SavedEyepiece, ...]:
        return self._document.items

    def delete(self, id: str) -> EyepieceWriteResult:
        self._document, deleted = _apply_delete(self._document, id)
        return EyepieceWriteResult(state=self._document.as_state(), item=deleted)

    def delete_query(self, query: str) -> EyepieceWriteResult:
        self._document, deleted = _apply_delete_query(self._document, query)
        return EyepieceWriteResult(state=self._document.as_state(), item=deleted)


class FileEyepieceStore:
    def __init__(self, path: Path | str) -> None:
        self.path = Path(path).expanduser().resolve()

    def load(self) -> EyepieceState:
        return self._read().as_state()

    def save(self, draft: SavedEyepieceDraft) -> EyepieceWriteResult:
        _validated_from_draft(draft)

        def body() -> EyepieceWriteResult:
            document, saved = _apply_save(self._load_locked(), draft)
            self._write_locked(document)
            return EyepieceWriteResult(state=document.as_state(), item=saved)

        return self._mutate(body)

    def get(self, id: str) -> SavedEyepiece:
        return _get(self._read(), id)

    def resolve(self, query: str) -> SavedEyepiece:
        return _resolve(self._read(), query)

    def list(self) -> tuple[SavedEyepiece, ...]:
        return self._read().items

    def delete(self, id: str) -> EyepieceWriteResult:
        def body() -> EyepieceWriteResult:
            document, deleted = _apply_delete(self._load_locked(), id)
            self._write_locked(document)
            return EyepieceWriteResult(state=document.as_state(), item=deleted)

        return self._mutate(body)

    def delete_query(self, query: str) -> EyepieceWriteResult:
        def body() -> EyepieceWriteResult:
            document, deleted = _apply_delete_query(self._load_locked(), query)
            self._write_locked(document)
            return EyepieceWriteResult(state=document.as_state(), item=deleted)

        return self._mutate(body)

    def _lock_path(self) -> Path:
        return self.path.with_name(self.path.name + ".lock")

    def _read(self) -> _Document:
        try:
            if not self.path.exists():
                return _empty_document()
            return self._with_lock(self._load_locked)
        except OSError as exc:
            raise EyepieceStoreError(str(exc), code="host_failure") from exc

    def _mutate(self, body: Callable[[], _T]) -> _T:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            return self._with_lock(body)
        except OSError as exc:
            raise EyepieceStoreError(str(exc), code="host_failure") from exc

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
            raise EyepieceStoreError(str(exc), code="host_failure") from exc

    def _load_locked(self) -> _Document:
        if not self.path.exists():
            return _empty_document()
        try:
            raw = self.path.read_bytes()
        except OSError as exc:
            raise EyepieceStoreError(str(exc), code="host_failure") from exc
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise EyepieceStoreCorruptError(
                "eyepiece file is not valid UTF-8"
            ) from exc
        try:
            document = json.loads(text, parse_constant=_reject_constant)
        except json.JSONDecodeError as exc:
            raise EyepieceStoreCorruptError(
                "eyepiece file is not valid JSON"
            ) from exc
        except ValueError as exc:
            raise EyepieceStoreCorruptError(str(exc)) from exc
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
                raise EyepieceStoreError(str(exc), code="host_failure") from exc
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass


def _reject_constant(name: str) -> None:
    raise ValueError(f"non-finite JSON constant {name}")


def _canonical_id(value: str) -> str:
    try:
        return canonicalize_equipment_id(value)
    except InvalidEquipmentError as exc:
        raise InvalidEyepieceError("id must be a UUID") from exc


def _finite_number(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidEyepieceError(f"{name} must be a number")
    try:
        number = float(value)
    except OverflowError as exc:
        raise InvalidEyepieceError(f"{name} must be finite") from exc
    if not math.isfinite(number):
        raise InvalidEyepieceError(f"{name} must be finite")
    if abs(number) > MAX_ABS_NUMBER:
        raise InvalidEyepieceError(f"{name} must have absolute value at most 1e9")
    return number


def _required_focal_length(value: object) -> float:
    number = _finite_number(value, "focal_length_mm")
    if number <= 0:
        raise InvalidEyepieceError("focal_length_mm must be greater than zero")
    return number


def _optional_afov(value: object) -> float | None:
    if value is None:
        return None
    number = _finite_number(value, "afov_degrees")
    if number <= 0 or number > MAX_AFOV_DEGREES:
        raise InvalidEyepieceError(
            "afov_degrees must be greater than zero and at most 180"
        )
    return number


def _required_name(value: object) -> str:
    if not isinstance(value, str):
        raise InvalidEyepieceError("name must be a string")
    name = value.strip()
    if not name:
        raise InvalidEyepieceError("name must be a non-empty string")
    return name


def _validated_aliases(value: object, name: str) -> tuple[str, ...]:
    if value is None:
        raise InvalidEyepieceError("aliases must be an array of strings")
    if isinstance(value, (str, bytes)):
        raise InvalidEyepieceError("aliases must be an array of strings")
    if not isinstance(value, Sequence):
        raise InvalidEyepieceError("aliases must be an array of strings")
    trimmed: list[str] = []
    seen: set[str] = set()
    own = normalize_label(name)
    for item in value:
        if not isinstance(item, str):
            raise InvalidEyepieceError("aliases must be an array of strings")
        alias = item.strip()
        if not alias:
            raise InvalidEyepieceError("aliases must be non-empty after trim")
        key = normalize_label(alias)
        if key == own:
            raise InvalidEyepieceError("alias must not equal the eyepiece name")
        if key in seen:
            raise InvalidEyepieceError("aliases must be unique")
        seen.add(key)
        trimmed.append(alias)
    trimmed.sort(key=normalize_label)
    return tuple(trimmed)


def lookup_saved(items: Sequence[SavedEyepiece], id: str) -> SavedEyepiece:
    canonical = _canonical_id(id)
    for item in items:
        if item.id == canonical:
            return item
    raise EyepieceNotFoundError("saved eyepiece not found", query=canonical)


def resolve_saved(items: Sequence[SavedEyepiece], query: str) -> SavedEyepiece:
    if not isinstance(query, str):
        raise InvalidEyepieceError("query must be a string")
    trimmed = query.strip()
    if not trimmed:
        raise InvalidEyepieceError("query must be a non-empty string")
    try:
        canonical = _canonical_id(trimmed)
    except InvalidEyepieceError:
        canonical = None
    if canonical is not None:
        for item in items:
            if item.id == canonical:
                return item
    needle = normalize_label(trimmed)
    matches = [
        item
        for item in items
        if normalize_label(item.name) == needle
        or any(normalize_label(alias) == needle for alias in item.aliases)
    ]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise EyepieceStoreCorruptError("ambiguous eyepiece label")
    raise EyepieceNotFoundError("saved eyepiece not found", query=trimmed)


def _get(document: _Document, id: str) -> SavedEyepiece:
    return lookup_saved(document.items, id)


def _resolve(document: _Document, query: str) -> SavedEyepiece:
    return resolve_saved(document.items, query)


def _apply_save(
    document: _Document, draft: SavedEyepieceDraft
) -> tuple[_Document, SavedEyepiece]:
    saved = _validated_from_draft(draft)
    if draft.id is None:
        occupied = {item.id for item in document.items}
        labels = _all_normalized_labels(document.items)
        own_labels = {
            normalize_label(saved.name),
            *(normalize_label(alias) for alias in saved.aliases),
        }
        while saved.id in occupied or saved.id in labels or saved.id in own_labels:
            saved = replace(saved, id=str(uuid.uuid4()))
        others = document.items
        created = True
    else:
        others = tuple(item for item in document.items if item.id != saved.id)
        created = len(others) == len(document.items)
    _reject_conflicts(saved, others)
    if created:
        items = (*document.items, saved)
    else:
        items = tuple(
            saved if item.id == saved.id else item for item in document.items
        )
    return replace(document, items=items), saved


def _apply_delete(
    document: _Document, id: str
) -> tuple[_Document, SavedEyepiece]:
    deleted = _get(document, id)
    remaining = tuple(item for item in document.items if item.id != deleted.id)
    extras = {
        key: value
        for key, value in document.item_extras.items()
        if key != deleted.id
    }
    return replace(document, items=remaining, item_extras=extras), deleted


def _apply_delete_query(
    document: _Document, query: str
) -> tuple[_Document, SavedEyepiece]:
    resolved = _resolve(document, query)
    return _apply_delete(document, resolved.id)


def _validated_from_draft(draft: SavedEyepieceDraft) -> SavedEyepiece:
    if draft.id is None:
        identity = str(uuid.uuid4())
    elif not isinstance(draft.id, str):
        raise InvalidEyepieceError("id must be a UUID")
    else:
        identity = _canonical_id(draft.id)
    name = _required_name(draft.name)
    aliases = _validated_aliases(draft.aliases, name)
    return SavedEyepiece(
        id=identity,
        name=name,
        focal_length_mm=_required_focal_length(draft.focal_length_mm),
        afov_degrees=_optional_afov(draft.afov_degrees),
        aliases=aliases,
    )


def _reject_conflicts(
    saved: SavedEyepiece, others: Sequence[SavedEyepiece]
) -> None:
    other_labels = _all_normalized_labels(others)
    live_ids = {item.id for item in others} | {saved.id}
    for label in (saved.name, *saved.aliases):
        key = normalize_label(label)
        if key in other_labels:
            raise EyepieceConflictError(
                "eyepiece name or alias already exists", normalized=key
            )
        if key in live_ids:
            raise EyepieceConflictError(
                "eyepiece name or alias collides with an eyepiece id",
                normalized=key,
            )
    for other in others:
        for label in (other.name, *other.aliases):
            if normalize_label(label) == saved.id:
                raise EyepieceConflictError(
                    "eyepiece id collides with an existing name or alias",
                    normalized=saved.id,
                )


def _all_normalized_labels(items: Sequence[SavedEyepiece]) -> set[str]:
    labels: set[str] = set()
    for item in items:
        labels.add(normalize_label(item.name))
        labels.update(normalize_label(alias) for alias in item.aliases)
    return labels


def _encode_document(document: _Document) -> str:
    payload: dict[str, object] = dict(document.extra)
    payload["items"] = [
        _encode_item(item, document.item_extras.get(item.id, {}))
        for item in document.items
    ]
    payload["schema_version"] = SCHEMA_VERSION
    return json.dumps(
        payload,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    ) + "\n"


def _encode_item(
    item: SavedEyepiece, extras: Mapping[str, object]
) -> dict[str, object]:
    row = dict(extras)
    row["aliases"] = list(item.aliases)
    if item.afov_degrees is None:
        row.pop("afov_degrees", None)
    else:
        row["afov_degrees"] = item.afov_degrees
    row["focal_length_mm"] = item.focal_length_mm
    row["id"] = item.id
    row["name"] = item.name
    return row


def _decode_document(document: object) -> _Document:
    try:
        return _decode_document_inner(document)
    except (EyepieceStoreUnsupportedSchemaError, EyepieceStoreCorruptError):
        raise
    except (
        TypeError,
        KeyError,
        ValueError,
        OverflowError,
        InvalidEyepieceError,
        EyepieceConflictError,
        EyepieceNotFoundError,
    ) as exc:
        raise EyepieceStoreCorruptError(str(exc)) from exc


def _decode_document_inner(document: object) -> _Document:
    if not isinstance(document, Mapping):
        raise EyepieceStoreCorruptError("eyepiece document must be an object")
    if "schema_version" not in document:
        raise EyepieceStoreCorruptError("schema_version is required")
    if "items" not in document:
        raise EyepieceStoreCorruptError("items is required")
    version = document["schema_version"]
    if isinstance(version, int) and not isinstance(version, bool):
        if version != SCHEMA_VERSION:
            raise EyepieceStoreUnsupportedSchemaError(
                "unsupported eyepiece schema_version",
                schema_version=version,
            )
    else:
        raise EyepieceStoreCorruptError("schema_version must be an integer")
    raw_items = document["items"]
    if not isinstance(raw_items, list):
        raise EyepieceStoreCorruptError("items must be an array")
    decoded: list[SavedEyepiece] = []
    extras: dict[str, dict[str, object]] = {}
    seen_ids: set[str] = set()
    for item in raw_items:
        saved, extra = _decode_item(item)
        if saved.id in seen_ids:
            raise EyepieceStoreCorruptError("duplicate eyepiece id")
        seen_ids.add(saved.id)
        decoded.append(saved)
        extras[saved.id] = extra
    _reject_loaded_uniqueness(decoded)
    extra = {
        key: value
        for key, value in document.items()
        if key not in _KNOWN_DOCUMENT_KEYS
    }
    return _Document(tuple(decoded), extra, extras)


def _decode_item(value: object) -> tuple[SavedEyepiece, dict[str, object]]:
    if not isinstance(value, Mapping):
        raise EyepieceStoreCorruptError("eyepiece item must be an object")
    for key in ("id", "name", "focal_length_mm"):
        if key not in value:
            raise EyepieceStoreCorruptError(f"item.{key} is required")
    identity = _canonical_on_disk_id(value["id"])
    name = _required_name(value["name"])
    if "aliases" not in value:
        aliases: tuple[str, ...] = ()
    else:
        aliases = _validated_aliases(value["aliases"], name)
    focal_length_mm = _required_focal_length(value["focal_length_mm"])
    if "afov_degrees" in value and value["afov_degrees"] is not None:
        afov_degrees = _optional_afov(value["afov_degrees"])
    else:
        afov_degrees = None
    saved = SavedEyepiece(
        id=identity,
        name=name,
        focal_length_mm=focal_length_mm,
        afov_degrees=afov_degrees,
        aliases=aliases,
    )
    extra = {
        key: extra_value
        for key, extra_value in value.items()
        if key not in _KNOWN_ITEM_KEYS
    }
    return saved, extra


def _canonical_on_disk_id(value: object) -> str:
    if not isinstance(value, str) or not CANONICAL_UUID.fullmatch(value):
        raise InvalidEyepieceError("id must be a canonical UUID")
    if value != str(uuid.UUID(value)):
        raise InvalidEyepieceError("id must be a canonical UUID")
    return value


def _reject_loaded_uniqueness(items: Sequence[SavedEyepiece]) -> None:
    labels: set[str] = set()
    ids = {item.id for item in items}
    for item in items:
        for label in (item.name, *item.aliases):
            key = normalize_label(label)
            if key in labels:
                raise EyepieceStoreCorruptError("duplicate eyepiece name or alias")
            if key in ids:
                raise EyepieceStoreCorruptError(
                    "eyepiece name or alias collides with an eyepiece id"
                )
            labels.add(key)
