"""Authoritative saved equipment inventory and selection policy.

``FileEquipmentStore`` takes a sidecar ``fcntl.flock`` and then runs a
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

from astro_engine.contracts import ContractsRootError, load_canonical_data

from astro_host.errors import (
    EquipmentConflictError,
    EquipmentNotFoundError,
    EquipmentStoreCorruptError,
    EquipmentStoreError,
    EquipmentStoreUnsupportedSchemaError,
    InvalidEquipmentError,
)
from astro_host.locations import normalize_label
from astro_host.models import (
    EquipmentApertureUnit,
    EquipmentSelection,
    EquipmentSelectionMode,
    EquipmentState,
    EquipmentType,
    EquipmentWriteResult,
    InlineEquipmentDraft,
    SavedEquipment,
    SavedEquipmentDraft,
)
from astro_host.weather_cache_file import default_state_dir


SCHEMA_VERSION = 1
EQUIPMENT_FILENAME = "equipment.json"
CANONICAL_UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)
MAX_ABS_NUMBER = 1e9
RESERVED_NAKED_EYE_LABEL = "naked eye"
NAKED_EYE_KEY = "0"
_KNOWN_DOCUMENT_KEYS = frozenset({"schema_version", "selection", "items"})
_KNOWN_ITEM_KEYS = frozenset(
    {
        "id",
        "name",
        "type",
        "aperture_mm",
        "aperture_unit",
        "magnification",
        "aliases",
    }
)
_KNOWN_SELECTION_KEYS = frozenset({"mode", "id"})
_LIMIT_KEYS = (
    "millimeters_per_inch",
    "maximum_binocular_magnification",
    "maximum_binocular_aperture_millimeters",
    "maximum_telescope_aperture_millimeters",
)
_T = TypeVar("_T")


def canonicalize_equipment_id(value: str) -> str:
    """Return canonical lowercase 8-4-4-4-12, or raise InvalidEquipmentError."""
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise InvalidEquipmentError("id must be a UUID") from exc


def default_equipment_path() -> Path:
    return default_state_dir() / EQUIPMENT_FILENAME


class EquipmentStore(Protocol):
    def load(self) -> EquipmentState: ...
    def save(
        self, draft: SavedEquipmentDraft, *, select: bool = False
    ) -> EquipmentWriteResult: ...
    def get(self, id: str) -> SavedEquipment: ...
    def resolve(self, query: str) -> SavedEquipment: ...
    def list(self) -> tuple[SavedEquipment, ...]: ...
    def select(self, id: str) -> EquipmentWriteResult: ...
    def select_query(self, query: str) -> EquipmentWriteResult: ...
    def select_all(self) -> EquipmentWriteResult: ...
    def select_naked_eye(self) -> EquipmentWriteResult: ...
    def delete(self, id: str) -> EquipmentWriteResult: ...
    def delete_query(self, query: str) -> EquipmentWriteResult: ...
    def get_selected(self) -> EquipmentSelection: ...


@dataclass
class _Document:
    items: tuple[SavedEquipment, ...]
    selection: EquipmentSelection
    extra: dict[str, object] = field(default_factory=dict)
    item_extras: dict[str, dict[str, object]] = field(default_factory=dict)
    selection_extra: dict[str, object] = field(default_factory=dict)

    def as_state(self) -> EquipmentState:
        return EquipmentState(self.items, self.selection)


def _empty_document() -> _Document:
    return _Document((), EquipmentSelection(EquipmentSelectionMode.ALL_SAVED))


class MemoryEquipmentStore:
    def __init__(self) -> None:
        self._document = _empty_document()

    def load(self) -> EquipmentState:
        return self._document.as_state()

    def save(
        self, draft: SavedEquipmentDraft, *, select: bool = False
    ) -> EquipmentWriteResult:
        self._document, saved = _apply_save(self._document, draft, select=select)
        return EquipmentWriteResult(state=self._document.as_state(), item=saved)

    def get(self, id: str) -> SavedEquipment:
        return _get(self._document, id)

    def resolve(self, query: str) -> SavedEquipment:
        return _resolve(self._document, query)

    def list(self) -> tuple[SavedEquipment, ...]:
        return self._document.items

    def select(self, id: str) -> EquipmentWriteResult:
        self._document, saved = _apply_select(self._document, id)
        return EquipmentWriteResult(state=self._document.as_state(), item=saved)

    def select_query(self, query: str) -> EquipmentWriteResult:
        document = self._document
        self._document, saved = _apply_select_query(document, query)
        return EquipmentWriteResult(state=self._document.as_state(), item=saved)

    def select_all(self) -> EquipmentWriteResult:
        self._document = _apply_select_all(self._document)
        return EquipmentWriteResult(state=self._document.as_state())

    def select_naked_eye(self) -> EquipmentWriteResult:
        self._document = _apply_select_naked_eye(self._document)
        return EquipmentWriteResult(state=self._document.as_state())

    def delete(self, id: str) -> EquipmentWriteResult:
        self._document, deleted = _apply_delete(self._document, id)
        return EquipmentWriteResult(state=self._document.as_state(), item=deleted)

    def delete_query(self, query: str) -> EquipmentWriteResult:
        document = self._document
        self._document, deleted = _apply_delete_query(document, query)
        return EquipmentWriteResult(state=self._document.as_state(), item=deleted)

    def get_selected(self) -> EquipmentSelection:
        return self._document.selection


class FileEquipmentStore:
    def __init__(self, path: Path | str) -> None:
        self.path = Path(path).expanduser().resolve()

    def load(self) -> EquipmentState:
        return self._read().as_state()

    def save(
        self, draft: SavedEquipmentDraft, *, select: bool = False
    ) -> EquipmentWriteResult:
        _validated_from_draft(draft)

        def body() -> EquipmentWriteResult:
            document, saved = _apply_save(
                self._load_locked(), draft, select=select
            )
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state(), item=saved)

        return self._mutate(body)

    def get(self, id: str) -> SavedEquipment:
        return _get(self._read(), id)

    def resolve(self, query: str) -> SavedEquipment:
        return _resolve(self._read(), query)

    def list(self) -> tuple[SavedEquipment, ...]:
        return self._read().items

    def select(self, id: str) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document, saved = _apply_select(self._load_locked(), id)
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state(), item=saved)

        return self._mutate(body)

    def select_query(self, query: str) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document, saved = _apply_select_query(self._load_locked(), query)
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state(), item=saved)

        return self._mutate(body)

    def select_all(self) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document = _apply_select_all(self._load_locked())
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state())

        return self._mutate(body)

    def select_naked_eye(self) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document = _apply_select_naked_eye(self._load_locked())
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state())

        return self._mutate(body)

    def delete(self, id: str) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document, deleted = _apply_delete(self._load_locked(), id)
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state(), item=deleted)

        return self._mutate(body)

    def delete_query(self, query: str) -> EquipmentWriteResult:
        def body() -> EquipmentWriteResult:
            document, deleted = _apply_delete_query(self._load_locked(), query)
            self._write_locked(document)
            return EquipmentWriteResult(state=document.as_state(), item=deleted)

        return self._mutate(body)

    def get_selected(self) -> EquipmentSelection:
        return self._read().selection

    def _lock_path(self) -> Path:
        return self.path.with_name(self.path.name + ".lock")

    def _read(self) -> _Document:
        try:
            if not self.path.exists():
                return _empty_document()
            return self._with_lock(self._load_locked)
        except OSError as exc:
            raise EquipmentStoreError(str(exc), code="host_failure") from exc

    def _mutate(self, body: Callable[[], _T]) -> _T:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            return self._with_lock(body)
        except OSError as exc:
            raise EquipmentStoreError(str(exc), code="host_failure") from exc

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
            raise EquipmentStoreError(str(exc), code="host_failure") from exc

    def _load_locked(self) -> _Document:
        if not self.path.exists():
            return _empty_document()
        try:
            raw = self.path.read_bytes()
        except OSError as exc:
            raise EquipmentStoreError(str(exc), code="host_failure") from exc
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise EquipmentStoreCorruptError(
                "equipment file is not valid UTF-8"
            ) from exc
        try:
            document = json.loads(text, parse_constant=_reject_constant)
        except json.JSONDecodeError as exc:
            raise EquipmentStoreCorruptError(
                "equipment file is not valid JSON"
            ) from exc
        except ValueError as exc:
            raise EquipmentStoreCorruptError(str(exc)) from exc
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
                raise EquipmentStoreError(str(exc), code="host_failure") from exc
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass


def _reject_constant(name: str) -> None:
    raise ValueError(f"non-finite JSON constant {name}")


def load_equipment_limits() -> dict[str, float]:
    try:
        raw = load_canonical_data("catalog/equipment-limits.json")
    except (ContractsRootError, OSError, UnicodeError) as exc:
        raise EquipmentStoreError(
            f"equipment limits could not be loaded: {exc}",
            code="host_failure",
        ) from exc
    if not isinstance(raw, Mapping):
        raise EquipmentStoreError(
            "equipment-limits.json must be an object", code="host_failure"
        )
    limits: dict[str, float] = {}
    for key in _LIMIT_KEYS:
        if key not in raw:
            raise EquipmentStoreError(
                f"equipment-limits.json missing {key}", code="host_failure"
            )
        value = raw[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise EquipmentStoreError(
                f"equipment-limits.json {key} must be a number",
                code="host_failure",
            )
        try:
            number = float(value)
        except OverflowError as exc:
            raise EquipmentStoreError(
                f"equipment-limits.json {key} must be finite",
                code="host_failure",
            ) from exc
        if not math.isfinite(number) or number <= 0:
            raise EquipmentStoreError(
                f"equipment-limits.json {key} must be a positive finite number",
                code="host_failure",
            )
        limits[key] = number
    return limits


def validate_optics(
    type: EquipmentType,
    aperture: object,
    aperture_unit: EquipmentApertureUnit,
    magnification: object,
) -> tuple[float, EquipmentApertureUnit, float | None]:
    if not isinstance(type, EquipmentType):
        raise InvalidEquipmentError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        )
    if not isinstance(aperture_unit, EquipmentApertureUnit):
        raise InvalidEquipmentError(
            "aperture_unit must be millimeters or inches"
        )
    limits = load_equipment_limits()
    aperture_value = _finite_number(aperture, "aperture")
    if aperture_value <= 0 or abs(aperture_value) > MAX_ABS_NUMBER:
        raise InvalidEquipmentError(
            "aperture must be finite, greater than zero, and at most 1e9"
        )
    millimeters_per_inch = limits["millimeters_per_inch"]
    aperture_mm = (
        aperture_value * millimeters_per_inch
        if aperture_unit is EquipmentApertureUnit.INCHES
        else aperture_value
    )
    if not math.isfinite(aperture_mm) or aperture_mm <= 0:
        raise InvalidEquipmentError("aperture must be finite and greater than zero")
    maximum = (
        limits["maximum_binocular_aperture_millimeters"]
        if type is EquipmentType.BINOCULARS
        else limits["maximum_telescope_aperture_millimeters"]
    )
    if aperture_mm > maximum:
        raise InvalidEquipmentError("aperture is too large")
    if type is EquipmentType.BINOCULARS:
        if magnification is None:
            raise InvalidEquipmentError("magnification is required for binoculars")
        mag = _finite_number(magnification, "magnification")
        if mag <= 0 or abs(mag) > MAX_ABS_NUMBER:
            raise InvalidEquipmentError(
                "magnification must be finite, greater than zero, and at most 1e9"
            )
        if mag > limits["maximum_binocular_magnification"]:
            raise InvalidEquipmentError("magnification is too high")
        return aperture_mm, aperture_unit, mag
    if magnification is not None:
        raise InvalidEquipmentError("magnification is not used for telescopes")
    return aperture_mm, aperture_unit, None


def _finite_number(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidEquipmentError(f"{name} must be a number")
    try:
        number = float(value)
    except OverflowError as exc:
        raise InvalidEquipmentError(f"{name} must be finite") from exc
    if not math.isfinite(number):
        raise InvalidEquipmentError(f"{name} must be finite")
    if abs(number) > MAX_ABS_NUMBER:
        raise InvalidEquipmentError(f"{name} must have absolute value at most 1e9")
    return number


def lookup_saved(items: Sequence[SavedEquipment], id: str) -> SavedEquipment:
    canonical = canonicalize_equipment_id(id)
    for item in items:
        if item.id == canonical:
            return item
    raise EquipmentNotFoundError("saved equipment not found", query=canonical)


def resolve_saved(items: Sequence[SavedEquipment], query: str) -> SavedEquipment:
    if not isinstance(query, str):
        raise InvalidEquipmentError("query must be a string")
    trimmed = query.strip()
    if not trimmed:
        raise InvalidEquipmentError("query must be a non-empty string")
    try:
        canonical = canonicalize_equipment_id(trimmed)
    except InvalidEquipmentError:
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
        raise EquipmentStoreCorruptError("ambiguous equipment label")
    raise EquipmentNotFoundError("saved equipment not found", query=trimmed)


def _get(document: _Document, id: str) -> SavedEquipment:
    return lookup_saved(document.items, id)


def _resolve(document: _Document, query: str) -> SavedEquipment:
    return resolve_saved(document.items, query)


def _apply_save(
    document: _Document, draft: SavedEquipmentDraft, *, select: bool = False
) -> tuple[_Document, SavedEquipment]:
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
        extras = dict(document.item_extras)
    else:
        items = tuple(
            saved if item.id == saved.id else item for item in document.items
        )
        extras = dict(document.item_extras)
    selection = document.selection
    if select:
        selection = EquipmentSelection(EquipmentSelectionMode.ITEM, saved.id)
    return replace(
        document,
        items=items,
        selection=selection,
        item_extras=extras,
    ), saved


def _apply_delete(
    document: _Document, id: str
) -> tuple[_Document, SavedEquipment]:
    deleted = _get(document, id)
    remaining = tuple(item for item in document.items if item.id != deleted.id)
    extras = {
        key: value
        for key, value in document.item_extras.items()
        if key != deleted.id
    }
    selection = document.selection
    if (
        selection.mode is EquipmentSelectionMode.ITEM
        and selection.id == deleted.id
    ):
        selection = EquipmentSelection(EquipmentSelectionMode.ALL_SAVED)
    return replace(
        document,
        items=remaining,
        selection=selection,
        item_extras=extras,
    ), deleted


def _apply_select(
    document: _Document, id: str
) -> tuple[_Document, SavedEquipment]:
    saved = _get(document, id)
    return replace(
        document,
        selection=EquipmentSelection(EquipmentSelectionMode.ITEM, saved.id),
    ), saved


def _apply_select_query(
    document: _Document, query: str
) -> tuple[_Document, SavedEquipment]:
    resolved = _resolve(document, query)
    return _apply_select(document, resolved.id)


def _apply_delete_query(
    document: _Document, query: str
) -> tuple[_Document, SavedEquipment]:
    resolved = _resolve(document, query)
    return _apply_delete(document, resolved.id)


def _apply_select_all(document: _Document) -> _Document:
    return replace(
        document, selection=EquipmentSelection(EquipmentSelectionMode.ALL_SAVED)
    )


def _apply_select_naked_eye(document: _Document) -> _Document:
    return replace(
        document,
        selection=EquipmentSelection(EquipmentSelectionMode.NAKED_EYE_ONLY),
    )


def _validated_from_draft(draft: SavedEquipmentDraft) -> SavedEquipment:
    if draft.id is None:
        identity = str(uuid.uuid4())
    elif not isinstance(draft.id, str):
        raise InvalidEquipmentError("id must be a UUID")
    else:
        identity = canonicalize_equipment_id(draft.id)
    name = _required_name(draft.name)
    aliases = _validated_aliases(draft.aliases, name)
    _reject_reserved_labels(name, aliases)
    if not isinstance(draft.type, EquipmentType):
        raise InvalidEquipmentError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        )
    if not isinstance(draft.aperture_unit, EquipmentApertureUnit):
        raise InvalidEquipmentError(
            "aperture_unit must be millimeters or inches"
        )
    aperture_mm, unit, magnification = validate_optics(
        draft.type, draft.aperture, draft.aperture_unit, draft.magnification
    )
    return SavedEquipment(
        id=identity,
        name=name,
        type=draft.type,
        aperture_mm=aperture_mm,
        aperture_unit=unit,
        aliases=aliases,
        magnification=magnification,
    )


def validate_inline(draft: InlineEquipmentDraft) -> tuple[float, float | None]:
    if not isinstance(draft.type, EquipmentType):
        raise InvalidEquipmentError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        )
    if not isinstance(draft.aperture_unit, EquipmentApertureUnit):
        raise InvalidEquipmentError(
            "aperture_unit must be millimeters or inches"
        )
    aperture_mm, _unit, magnification = validate_optics(
        draft.type, draft.aperture, draft.aperture_unit, draft.magnification
    )
    return aperture_mm, magnification


def _required_name(value: object) -> str:
    if not isinstance(value, str):
        raise InvalidEquipmentError("name must be a string")
    name = value.strip()
    if not name:
        raise InvalidEquipmentError("name must be a non-empty string")
    return name


def _validated_aliases(value: object, name: str) -> tuple[str, ...]:
    if value is None:
        raise InvalidEquipmentError("aliases must be an array of strings")
    if isinstance(value, (str, bytes)):
        raise InvalidEquipmentError("aliases must be an array of strings")
    if not isinstance(value, Sequence):
        raise InvalidEquipmentError("aliases must be an array of strings")
    trimmed: list[str] = []
    seen: set[str] = set()
    own = normalize_label(name)
    for item in value:
        if not isinstance(item, str):
            raise InvalidEquipmentError("aliases must be an array of strings")
        alias = item.strip()
        if not alias:
            raise InvalidEquipmentError("aliases must be non-empty after trim")
        key = normalize_label(alias)
        if key == own:
            raise InvalidEquipmentError("alias must not equal the equipment name")
        if key in seen:
            raise InvalidEquipmentError("aliases must be unique")
        seen.add(key)
        trimmed.append(alias)
    trimmed.sort(key=normalize_label)
    return tuple(trimmed)


def _reject_reserved_labels(name: str, aliases: Sequence[str]) -> None:
    for label in (name, *aliases):
        if normalize_label(label) == RESERVED_NAKED_EYE_LABEL:
            raise EquipmentConflictError(
                "naked eye is a reserved equipment label",
                normalized=RESERVED_NAKED_EYE_LABEL,
            )


def _reject_conflicts(
    saved: SavedEquipment, others: Sequence[SavedEquipment]
) -> None:
    other_labels = _all_normalized_labels(others)
    live_ids = {item.id for item in others} | {saved.id}
    for label in (saved.name, *saved.aliases):
        key = normalize_label(label)
        if key in other_labels:
            raise EquipmentConflictError(
                "equipment name or alias already exists", normalized=key
            )
        if key in live_ids:
            raise EquipmentConflictError(
                "equipment name or alias collides with an equipment id",
                normalized=key,
            )
    for other in others:
        for label in (other.name, *other.aliases):
            if normalize_label(label) == saved.id:
                raise EquipmentConflictError(
                    "equipment id collides with an existing name or alias",
                    normalized=saved.id,
                )


def _all_normalized_labels(items: Sequence[SavedEquipment]) -> set[str]:
    labels: set[str] = set()
    for item in items:
        labels.add(normalize_label(item.name))
        labels.update(normalize_label(alias) for alias in item.aliases)
    return labels


def _encode_document(document: _Document) -> str:
    encoded_items = [
        _encode_item(item, document.item_extras.get(item.id, {}))
        for item in document.items
    ]
    payload: dict[str, object] = dict(document.extra)
    payload["items"] = encoded_items
    payload["schema_version"] = SCHEMA_VERSION
    payload["selection"] = _encode_selection(
        document.selection, document.selection_extra
    )
    return json.dumps(
        payload,
        separators=(",", ":"),
        sort_keys=True,
        allow_nan=False,
    ) + "\n"


def _encode_item(
    item: SavedEquipment, extras: Mapping[str, object]
) -> dict[str, object]:
    row = dict(extras)
    row["aliases"] = list(item.aliases)
    row["aperture_mm"] = item.aperture_mm
    row["aperture_unit"] = item.aperture_unit.value
    row["id"] = item.id
    row["name"] = item.name
    row["type"] = item.type.value
    if item.magnification is None:
        row.pop("magnification", None)
    else:
        row["magnification"] = item.magnification
    return row


def _encode_selection(
    selection: EquipmentSelection, extras: Mapping[str, object]
) -> dict[str, object]:
    row = dict(extras)
    row["mode"] = selection.mode.value
    if selection.mode is EquipmentSelectionMode.ITEM:
        row["id"] = selection.id
    else:
        row.pop("id", None)
    return row


def _decode_document(document: object) -> _Document:
    try:
        return _decode_document_inner(document)
    except (EquipmentStoreUnsupportedSchemaError, EquipmentStoreCorruptError):
        raise
    except (
        TypeError,
        KeyError,
        ValueError,
        OverflowError,
        InvalidEquipmentError,
        EquipmentConflictError,
        EquipmentNotFoundError,
    ) as exc:
        raise EquipmentStoreCorruptError(str(exc)) from exc


def _decode_document_inner(document: object) -> _Document:
    if not isinstance(document, Mapping):
        raise EquipmentStoreCorruptError("equipment document must be an object")
    if "schema_version" not in document:
        raise EquipmentStoreCorruptError("schema_version is required")
    if "items" not in document:
        raise EquipmentStoreCorruptError("items is required")
    if "selection" not in document:
        raise EquipmentStoreCorruptError("selection is required")
    version = document["schema_version"]
    if isinstance(version, int) and not isinstance(version, bool):
        if version != SCHEMA_VERSION:
            raise EquipmentStoreUnsupportedSchemaError(
                "unsupported equipment schema_version",
                schema_version=version,
            )
    else:
        raise EquipmentStoreCorruptError("schema_version must be an integer")
    raw_items = document["items"]
    if not isinstance(raw_items, list):
        raise EquipmentStoreCorruptError("items must be an array")
    decoded: list[SavedEquipment] = []
    extras: dict[str, dict[str, object]] = {}
    seen_ids: set[str] = set()
    for item in raw_items:
        saved, extra = _decode_item(item)
        if saved.id in seen_ids:
            raise EquipmentStoreCorruptError("duplicate equipment id")
        seen_ids.add(saved.id)
        decoded.append(saved)
        extras[saved.id] = extra
    _reject_loaded_uniqueness(decoded)
    selection, selection_extra = _decode_selection(document["selection"], decoded)
    extra = {
        key: value
        for key, value in document.items()
        if key not in _KNOWN_DOCUMENT_KEYS
    }
    return _Document(
        tuple(decoded), selection, extra, extras, selection_extra
    )


def _decode_item(value: object) -> tuple[SavedEquipment, dict[str, object]]:
    if not isinstance(value, Mapping):
        raise EquipmentStoreCorruptError("equipment item must be an object")
    for key in ("id", "name", "type", "aperture_mm", "aperture_unit"):
        if key not in value:
            raise EquipmentStoreCorruptError(f"item.{key} is required")
    identity = _canonical_on_disk_id(value["id"])
    name = _required_name(value["name"])
    if "aliases" not in value:
        aliases: tuple[str, ...] = ()
    else:
        aliases = _validated_aliases(value["aliases"], name)
    _reject_reserved_labels(name, aliases)
    kind = _decode_type(value["type"])
    unit = _decode_unit(value["aperture_unit"])
    aperture_mm = _finite_number(value["aperture_mm"], "aperture_mm")
    if aperture_mm <= 0:
        raise InvalidEquipmentError("aperture_mm must be greater than zero")
    limits = load_equipment_limits()
    maximum = (
        limits["maximum_binocular_aperture_millimeters"]
        if kind is EquipmentType.BINOCULARS
        else limits["maximum_telescope_aperture_millimeters"]
    )
    if aperture_mm > maximum:
        raise InvalidEquipmentError("aperture is too large")
    if kind is EquipmentType.BINOCULARS:
        if "magnification" not in value or value["magnification"] is None:
            raise InvalidEquipmentError("magnification is required for binoculars")
        magnification = _finite_number(value["magnification"], "magnification")
        if magnification <= 0:
            raise InvalidEquipmentError("magnification must be greater than zero")
        if magnification > limits["maximum_binocular_magnification"]:
            raise InvalidEquipmentError("magnification is too high")
    else:
        if "magnification" in value and value["magnification"] is not None:
            raise InvalidEquipmentError("magnification is not used for telescopes")
        magnification = None
    saved = SavedEquipment(
        id=identity,
        name=name,
        type=kind,
        aperture_mm=aperture_mm,
        aperture_unit=unit,
        aliases=aliases,
        magnification=magnification,
    )
    extra = {
        key: extra_value
        for key, extra_value in value.items()
        if key not in _KNOWN_ITEM_KEYS
    }
    return saved, extra


def _decode_type(value: object) -> EquipmentType:
    if not isinstance(value, str):
        raise InvalidEquipmentError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        )
    try:
        return EquipmentType(value)
    except ValueError as exc:
        raise InvalidEquipmentError(
            "type must be binoculars, visualTelescope, or smartTelescope"
        ) from exc


def _decode_unit(value: object) -> EquipmentApertureUnit:
    if not isinstance(value, str):
        raise InvalidEquipmentError("aperture_unit must be millimeters or inches")
    try:
        return EquipmentApertureUnit(value)
    except ValueError as exc:
        raise InvalidEquipmentError(
            "aperture_unit must be millimeters or inches"
        ) from exc


def _canonical_on_disk_id(value: object) -> str:
    if not isinstance(value, str) or not CANONICAL_UUID.fullmatch(value):
        raise InvalidEquipmentError("id must be a canonical UUID")
    if value != str(uuid.UUID(value)):
        raise InvalidEquipmentError("id must be a canonical UUID")
    return value


def _decode_selection(
    value: object, items: Sequence[SavedEquipment]
) -> tuple[EquipmentSelection, dict[str, object]]:
    if not isinstance(value, Mapping):
        raise EquipmentStoreCorruptError("selection must be an object")
    if "mode" not in value:
        raise EquipmentStoreCorruptError("selection.mode is required")
    mode_value = value["mode"]
    if not isinstance(mode_value, str):
        raise EquipmentStoreCorruptError("selection.mode is invalid")
    try:
        mode = EquipmentSelectionMode(mode_value)
    except ValueError as exc:
        raise EquipmentStoreCorruptError("selection.mode is invalid") from exc
    extra = {
        key: extra_value
        for key, extra_value in value.items()
        if key not in _KNOWN_SELECTION_KEYS
    }
    if mode is EquipmentSelectionMode.ITEM:
        if "id" not in value:
            raise EquipmentStoreCorruptError("selection.id is required")
        identity = value["id"]
        if not isinstance(identity, str) or not CANONICAL_UUID.fullmatch(identity):
            raise EquipmentStoreCorruptError(
                "selection.id is not a canonical UUID"
            )
        if identity != str(uuid.UUID(identity)):
            raise EquipmentStoreCorruptError(
                "selection.id is not a canonical UUID"
            )
        if not any(item.id == identity for item in items):
            raise EquipmentStoreCorruptError(
                "selection.id does not match saved equipment"
            )
        return EquipmentSelection(mode, identity), extra
    if "id" in value:
        raise EquipmentStoreCorruptError(
            "selection.id is not allowed unless mode is item"
        )
    return EquipmentSelection(mode), extra


def _reject_loaded_uniqueness(items: Sequence[SavedEquipment]) -> None:
    labels: set[str] = set()
    ids = {item.id for item in items}
    for item in items:
        for label in (item.name, *item.aliases):
            key = normalize_label(label)
            if key == RESERVED_NAKED_EYE_LABEL:
                raise EquipmentStoreCorruptError(
                    "naked eye is a reserved equipment label"
                )
            if key in labels:
                raise EquipmentStoreCorruptError(
                    "duplicate equipment name or alias"
                )
            if key in ids:
                raise EquipmentStoreCorruptError(
                    "equipment name or alias collides with an equipment id"
                )
            labels.add(key)
