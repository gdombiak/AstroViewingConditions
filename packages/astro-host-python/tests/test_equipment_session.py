from __future__ import annotations

from pathlib import Path

import pytest

from astro_engine.equipment import match_equipment
from astro_engine.filter_recommendations_by_equipment import (
    filter_recommendations_by_equipment,
)
from astro_host.equipment import FileEquipmentStore, MemoryEquipmentStore, validate_optics
from astro_host.equipment_session import EquipmentSessionService, compose_active
from astro_host.errors import EquipmentNotFoundError, InvalidEquipmentError
from astro_host.models import (
    EquipmentApertureUnit,
    EquipmentOverride,
    EquipmentOverrideMode,
    EquipmentSelectionMode,
    EquipmentSource,
    EquipmentType,
    InlineEquipmentDraft,
)

from test_equipment import S30_ID, VIRTUOSO_ID, s30, virtuoso


@pytest.fixture(params=["memory", "file"])
def store(request, tmp_path: Path):
    if request.param == "memory":
        return MemoryEquipmentStore()
    return FileEquipmentStore(tmp_path / "equipment.json")


def test_override_id_does_not_mutate_store(store) -> None:
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    before = store.load()
    active = compose_active(
        before, EquipmentOverride(id=VIRTUOSO_ID),
    )
    assert active.override_applied is True
    assert active.source is EquipmentSource.EXPLICIT_OVERRIDE
    assert [row.id for row in active.identities] == [VIRTUOSO_ID]
    assert store.load() == before
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED


def test_override_mode_item_is_invalid_request(store) -> None:
    store.save(s30(id=S30_ID, aliases=()), select=True)
    with pytest.raises(InvalidEquipmentError):
        compose_active(
            store.load(),
            EquipmentOverride(mode=EquipmentSelectionMode.ITEM),  # type: ignore[arg-type]
        )
    assert store.get_selected().id == S30_ID


def test_invalid_override_does_not_fall_back(store) -> None:
    store.save(s30(id=S30_ID, aliases=()), select=True)
    before = store.load()
    with pytest.raises(EquipmentNotFoundError):
        compose_active(before, EquipmentOverride(id=VIRTUOSO_ID))
    with pytest.raises(InvalidEquipmentError):
        compose_active(before, EquipmentOverride())
    assert store.load() == before
    persisted = compose_active(store.load())
    assert persisted.source is EquipmentSource.SELECTED_ITEM
    assert persisted.identities[0].id == S30_ID


def test_override_mode_naked_eye_only_empty_inventory(store) -> None:
    active = compose_active(
        store.load(),
        EquipmentOverride(mode=EquipmentOverrideMode.NAKED_EYE_ONLY),
    )
    assert active.has_saved_inventory is False
    assert active.engine_has_saved_inventory is True
    assert [row.type for row in active.capabilities] == ["nakedEye"]
    assert active.override_applied is True
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED


def test_override_mode_all_saved_empty_inventory(store) -> None:
    active = compose_active(
        store.load(),
        EquipmentOverride(mode=EquipmentOverrideMode.ALL_SAVED),
    )
    assert active.engine_has_saved_inventory is False
    assert active.capabilities == ()


def test_inline_override_empty_inventory_enables_filter(store) -> None:
    active = compose_active(
        store.load(),
        EquipmentOverride(inline=InlineEquipmentDraft(
            type=EquipmentType.SMART_TELESCOPE,
            aperture=30,
            aperture_unit=EquipmentApertureUnit.MILLIMETERS,
        )),
    )
    assert active.has_saved_inventory is False
    assert active.engine_has_saved_inventory is True
    assert active.capabilities[0].key == "override"
    assert active.capabilities[0].aperture_mm == 30
    assert store.list() == ()


def test_inline_over_limit_rejected_same_as_save(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        compose_active(
            store.load(),
            EquipmentOverride(inline=InlineEquipmentDraft(
                type=EquipmentType.VISUAL_TELESCOPE,
                aperture=2001,
                aperture_unit=EquipmentApertureUnit.MILLIMETERS,
            )),
        )
    with pytest.raises(InvalidEquipmentError):
        store.save(virtuoso(aperture=2001))


def test_inline_and_save_share_optical_validation() -> None:
    mm, _unit, mag = validate_optics(
        EquipmentType.BINOCULARS,
        50,
        EquipmentApertureUnit.MILLIMETERS,
        10,
    )
    assert mm == 50
    assert mag == 10
    with pytest.raises(InvalidEquipmentError):
        validate_optics(
            EquipmentType.BINOCULARS,
            50,
            EquipmentApertureUnit.MILLIMETERS,
            None,
        )


def test_override_query_resolves_alias(store) -> None:
    store.save(s30(id=S30_ID))
    active = compose_active(store.load(), EquipmentOverride(query="Seestar"))
    assert active.identities[0].id == S30_ID


def test_session_service_reads_store(store) -> None:
    store.save(s30(id=S30_ID, aliases=()), select=True)
    active = EquipmentSessionService(store).active()
    assert active.source is EquipmentSource.SELECTED_ITEM
    overridden = EquipmentSessionService(store).active(
        EquipmentOverride(mode=EquipmentOverrideMode.NAKED_EYE_ONLY)
    )
    assert overridden.override_applied is True
    assert store.get_selected().mode is EquipmentSelectionMode.ITEM


def test_compose_active_is_valid_engine_input(store) -> None:
    store.save(s30(id=S30_ID, aliases=()))
    active = compose_active(store.load())
    capabilities = list(active.engine_capabilities())
    assert capabilities
    assert all(
        set(row) == {"key", "type", "aperture_mm", "magnification"}
        for row in capabilities
    )
    matched = match_equipment({
        "requirement": {},
        "capabilities": capabilities,
        "is_planet": False,
    })
    assert matched["match"]["key"] in {row["key"] for row in capabilities}
    filtered = filter_recommendations_by_equipment({
        "candidates": [],
        "capabilities": capabilities,
        "has_saved_inventory": active.engine_has_saved_inventory,
        "minimum_fit": "any",
    })
    assert filtered == {"selected": []}
