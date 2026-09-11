"""Project persisted equipment state into engine-shaped capability facts."""

from __future__ import annotations

from astro_host.equipment import (
    EquipmentStore,
    NAKED_EYE_KEY,
    lookup_saved,
    resolve_saved,
    validate_inline,
)
from astro_host.errors import InvalidEquipmentError
from astro_host.models import (
    ActiveEquipment,
    EquipmentCapabilityFact,
    EquipmentCapabilityIdentity,
    EquipmentOverride,
    EquipmentOverrideMode,
    EquipmentSelectionMode,
    EquipmentSource,
    EquipmentState,
    SavedEquipment,
)

NAKED_EYE_NAME = "Naked Eye"
INLINE_OVERRIDE_KEY = "override"

_Projected = tuple[
    tuple[EquipmentCapabilityFact, ...],
    tuple[EquipmentCapabilityIdentity, ...],
]


def naked_eye_capability() -> EquipmentCapabilityFact:
    return EquipmentCapabilityFact(
        key=NAKED_EYE_KEY,
        type="nakedEye",
        aperture_mm=None,
        magnification=None,
    )


def naked_eye_identity() -> EquipmentCapabilityIdentity:
    return EquipmentCapabilityIdentity(
        key=NAKED_EYE_KEY,
        id=None,
        name=NAKED_EYE_NAME,
    )


def compose_active(
    state: EquipmentState,
    override: EquipmentOverride | None = None,
) -> ActiveEquipment:
    has_saved_inventory = bool(state.items)
    if override is None:
        capabilities, identities, source, engine_flag = _project_selection(state)
        return ActiveEquipment(
            source=source,
            has_saved_inventory=has_saved_inventory,
            engine_has_saved_inventory=engine_flag,
            selection=state.selection,
            capabilities=capabilities,
            identities=identities,
            override_applied=False,
        )
    capabilities, identities, engine_flag = _project_override(state, override)
    return ActiveEquipment(
        source=EquipmentSource.EXPLICIT_OVERRIDE,
        has_saved_inventory=has_saved_inventory,
        engine_has_saved_inventory=engine_flag,
        selection=state.selection,
        capabilities=capabilities,
        identities=identities,
        override_applied=True,
    )


class EquipmentSessionService:
    def __init__(self, store: EquipmentStore) -> None:
        self._store = store

    def active(
        self, override: EquipmentOverride | None = None
    ) -> ActiveEquipment:
        return compose_active(self._store.load(), override)


def _project_selection(
    state: EquipmentState,
) -> tuple[
    tuple[EquipmentCapabilityFact, ...],
    tuple[EquipmentCapabilityIdentity, ...],
    EquipmentSource,
    bool,
]:
    selection = state.selection
    if selection.mode is EquipmentSelectionMode.NAKED_EYE_ONLY:
        return (
            (naked_eye_capability(),),
            (naked_eye_identity(),),
            EquipmentSource.NAKED_EYE_ONLY,
            True,
        )
    if selection.mode is EquipmentSelectionMode.ITEM:
        item = _item(state, selection.id or "")
        facts, identities = _from_items((item,))
        return facts, identities, EquipmentSource.SELECTED_ITEM, True
    if not state.items:
        return (), (), EquipmentSource.NO_EQUIPMENT, False
    facts, identities = _from_items(state.items, include_naked_eye=True)
    return facts, identities, EquipmentSource.ALL_SAVED, True


def _project_override(
    state: EquipmentState, override: EquipmentOverride
) -> tuple[
    tuple[EquipmentCapabilityFact, ...],
    tuple[EquipmentCapabilityIdentity, ...],
    bool,
]:
    _require_single_override(override)
    if override.id is not None:
        item = _item(state, override.id)
        facts, identities = _from_items((item,))
        return facts, identities, True
    if override.query is not None:
        item = _resolve_in_state(state, override.query)
        facts, identities = _from_items((item,))
        return facts, identities, True
    if override.mode is EquipmentOverrideMode.NAKED_EYE_ONLY:
        return (naked_eye_capability(),), (naked_eye_identity(),), True
    if override.mode is EquipmentOverrideMode.ALL_SAVED:
        if not state.items:
            return (), (), False
        facts, identities = _from_items(state.items, include_naked_eye=True)
        return facts, identities, True
    if override.inline is not None:
        aperture_mm, magnification = validate_inline(override.inline)
        fact = EquipmentCapabilityFact(
            key=INLINE_OVERRIDE_KEY,
            type=override.inline.type.value,
            aperture_mm=aperture_mm,
            magnification=magnification,
        )
        identity = EquipmentCapabilityIdentity(
            key=INLINE_OVERRIDE_KEY,
            id=None,
            name=None,
        )
        return (fact,), (identity,), True
    raise InvalidEquipmentError(
        "override must be exactly one of id, query, mode, inline"
    )


def _from_items(
    items: tuple[SavedEquipment, ...],
    *,
    include_naked_eye: bool = False,
) -> _Projected:
    facts = tuple(item.to_capability_fact() for item in items)
    identities = tuple(item.to_capability_identity() for item in items)
    if include_naked_eye:
        facts = (naked_eye_capability(),) + facts
        identities = (naked_eye_identity(),) + identities
    return facts, identities


def _require_single_override(override: EquipmentOverride) -> None:
    present = [
        override.id is not None,
        override.query is not None,
        override.mode is not None,
        override.inline is not None,
    ]
    if sum(present) != 1:
        raise InvalidEquipmentError(
            "override must be exactly one of id, query, mode, inline"
        )
    if override.mode is not None and not isinstance(
        override.mode, EquipmentOverrideMode
    ):
        raise InvalidEquipmentError(
            "override mode must be all_saved or naked_eye_only"
        )


def _item(state: EquipmentState, identity: str) -> SavedEquipment:
    return lookup_saved(state.items, identity)


def _resolve_in_state(state: EquipmentState, query: str) -> SavedEquipment:
    return resolve_saved(state.items, query)
