from __future__ import annotations

from dataclasses import replace
import math
from pathlib import Path
import uuid

import pytest

from astro_host.equipment import FileEquipmentStore, MemoryEquipmentStore
from astro_host.equipment_session import compose_active
from astro_host.errors import (
    EquipmentConflictError,
    EquipmentNotFoundError,
    InvalidEquipmentError,
)
from astro_host.models import (
    EquipmentApertureUnit,
    EquipmentOverride,
    EquipmentOverrideMode,
    EquipmentSelectionMode,
    EquipmentSource,
    EquipmentType,
    SavedEquipmentDraft,
)
import astro_host.equipment as equipment_module
from astro_host.locations import normalize_label


S30_ID = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
VIRTUOSO_ID = "11111111-1111-4111-8111-111111111111"
BINO_ID = "22222222-2222-4222-8222-222222222222"


def s30(**overrides) -> SavedEquipmentDraft:
    fields = dict(
        name="S30 Pro",
        type=EquipmentType.SMART_TELESCOPE,
        aperture=30,
        aperture_unit=EquipmentApertureUnit.MILLIMETERS,
        aliases=("Seestar", "S30"),
    )
    fields.update(overrides)
    return SavedEquipmentDraft(**fields)


def virtuoso(**overrides) -> SavedEquipmentDraft:
    fields = dict(
        name="Virtuoso",
        type=EquipmentType.VISUAL_TELESCOPE,
        aperture=150,
        aperture_unit=EquipmentApertureUnit.MILLIMETERS,
    )
    fields.update(overrides)
    return SavedEquipmentDraft(**fields)


def binoculars(**overrides) -> SavedEquipmentDraft:
    fields = dict(
        name="Nikon 10x50",
        type=EquipmentType.BINOCULARS,
        aperture=50,
        aperture_unit=EquipmentApertureUnit.MILLIMETERS,
        magnification=10,
        aliases=("10x50",),
    )
    fields.update(overrides)
    return SavedEquipmentDraft(**fields)


@pytest.fixture(params=["memory", "file"])
def store(request, tmp_path: Path):
    if request.param == "memory":
        return MemoryEquipmentStore()
    return FileEquipmentStore(tmp_path / "equipment.json")


def test_first_save_does_not_exclusive_select(store) -> None:
    saved = store.save(s30()).item
    assert saved is not None
    selection = store.get_selected()
    assert selection.mode is EquipmentSelectionMode.ALL_SAVED
    assert selection.id is None
    assert store.list() == (saved,)
    active = compose_active(store.load())
    assert active.source is EquipmentSource.ALL_SAVED
    assert active.engine_has_saved_inventory is True
    assert [row.key for row in active.capabilities] == ["0", "1" + saved.id]


def test_save_select_true_is_one_write(store) -> None:
    saved = store.save(s30(id=S30_ID), select=True).item
    assert saved is not None
    selection = store.get_selected()
    assert selection.mode is EquipmentSelectionMode.ITEM
    assert selection.id == saved.id == S30_ID
    active = compose_active(store.load())
    assert active.source is EquipmentSource.SELECTED_ITEM
    assert [row.id for row in active.identities] == [S30_ID]
    assert all(row.type != "nakedEye" for row in active.capabilities)


def test_second_save_under_all_saved_includes_both(store) -> None:
    first = store.save(s30(id=S30_ID)).item
    second = store.save(virtuoso(id=VIRTUOSO_ID)).item
    assert first is not None and second is not None
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED
    active = compose_active(store.load())
    assert [row.id for row in active.identities[1:]] == [first.id, second.id]


def test_select_select_all_select_naked_eye_and_deletes(store) -> None:
    store.save(s30(id=S30_ID))
    store.save(virtuoso(id=VIRTUOSO_ID))
    selected = store.select(S30_ID)
    assert selected.state.selection.mode is EquipmentSelectionMode.ITEM
    assert selected.item is not None and selected.item.id == S30_ID
    store.select_all()
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED
    store.select_query("Virtuoso")
    assert store.get_selected().id == VIRTUOSO_ID
    store.select_naked_eye()
    assert store.get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY
    store.delete(S30_ID)
    assert store.get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY
    assert [row.id for row in store.list()] == [VIRTUOSO_ID]


def test_delete_selected_item_falls_back_to_all_saved(store) -> None:
    store.save(s30(id=S30_ID), select=True)
    store.save(virtuoso(id=VIRTUOSO_ID))
    store.delete(S30_ID)
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED
    assert [row.id for row in store.list()] == [VIRTUOSO_ID]


def test_delete_unselected_keeps_item_selection(store) -> None:
    store.save(s30(id=S30_ID), select=True)
    store.save(virtuoso(id=VIRTUOSO_ID))
    store.delete(VIRTUOSO_ID)
    assert store.get_selected().mode is EquipmentSelectionMode.ITEM
    assert store.get_selected().id == S30_ID


def test_delete_last_item_mode_becomes_all_saved(store) -> None:
    store.save(s30(id=S30_ID), select=True)
    store.delete(S30_ID)
    assert store.list() == ()
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED


def test_delete_last_naked_eye_only_preserves_mode(store) -> None:
    store.save(s30(id=S30_ID))
    store.select_naked_eye()
    store.delete(S30_ID)
    assert store.list() == ()
    assert store.get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY
    active = compose_active(store.load())
    assert active.source is EquipmentSource.NAKED_EYE_ONLY
    assert active.has_saved_inventory is False
    assert active.engine_has_saved_inventory is True
    assert [row.type for row in active.capabilities] == ["nakedEye"]


def test_save_while_naked_eye_only_does_not_activate(store) -> None:
    store.select_naked_eye()
    store.save(s30(id=S30_ID))
    assert store.get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY
    active = compose_active(store.load())
    assert [row.type for row in active.capabilities] == ["nakedEye"]


def test_replace_by_id_keeps_uuid_position_and_selection(store) -> None:
    store.save(s30(id=S30_ID), select=True)
    store.save(virtuoso(id=VIRTUOSO_ID))
    updated = store.save(s30(id=S30_ID, name="Seestar S30 Pro", aliases=("S30",)))
    assert updated.item is not None
    assert updated.item.id == S30_ID
    assert updated.item.name == "Seestar S30 Pro"
    assert [row.id for row in store.list()] == [S30_ID, VIRTUOSO_ID]
    assert store.get_selected().id == S30_ID


def test_minted_id_is_canonical_uuid4_lowercase(store) -> None:
    saved = store.save(s30()).item
    assert saved is not None
    assert saved.id == str(uuid.UUID(saved.id))
    assert uuid.UUID(saved.id).version == 4


def test_uppercase_supplied_id_stored_lowercase(store) -> None:
    saved = store.save(s30(id=S30_ID.upper())).item
    assert saved is not None
    assert saved.id == S30_ID


def test_get_select_delete_uppercase_of_live_id(store) -> None:
    store.save(s30(id=S30_ID))
    store.save(virtuoso(id=VIRTUOSO_ID))
    assert store.get(S30_ID.upper()).id == S30_ID
    selected = store.select(VIRTUOSO_ID.upper())
    assert selected.item is not None and selected.item.id == VIRTUOSO_ID
    store.delete(VIRTUOSO_ID.upper())
    assert [row.id for row in store.list()] == [S30_ID]


def test_duplicate_normalized_name_conflicts(store) -> None:
    store.save(s30())
    with pytest.raises(EquipmentConflictError):
        store.save(virtuoso(name=" S30 PRO "))
    assert len(store.list()) == 1


def test_alias_conflicts_with_other_name(store) -> None:
    store.save(s30())
    with pytest.raises(EquipmentConflictError):
        store.save(virtuoso(aliases=("s30 pro",)))


def test_alias_equal_own_name_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aliases=("S30 Pro",)))


def test_duplicate_aliases_in_draft_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aliases=("S30", "s30")))


def test_identical_optics_allowed_if_names_differ(store) -> None:
    store.save(s30(name="Backyard S30", aliases=()))
    second = store.save(s30(name="Travel S30", aliases=("travel",))).item
    assert second is not None
    assert second.aperture_mm == 30
    assert len(store.list()) == 2


def test_reserved_naked_eye_name_and_alias_rejected(store) -> None:
    with pytest.raises(EquipmentConflictError):
        store.save(s30(name="Naked Eye", aliases=()))
    with pytest.raises(EquipmentConflictError):
        store.save(s30(aliases=("naked eye",)))


def test_binoculars_require_magnification(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(binoculars(magnification=None))


def test_telescopes_reject_magnification(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(magnification=50))
    with pytest.raises(InvalidEquipmentError):
        store.save(virtuoso(magnification=75))


def test_inches_convert_with_canonical_factor(store) -> None:
    saved = store.save(binoculars(
        aperture=2,
        aperture_unit=EquipmentApertureUnit.INCHES,
        magnification=10,
    )).item
    assert saved is not None
    assert saved.aperture_mm == pytest.approx(50.8)
    assert saved.aperture_unit is EquipmentApertureUnit.INCHES
    assert saved.magnification == 10


def test_boolean_aperture_and_magnification_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aperture=True))  # type: ignore[arg-type]
    with pytest.raises(InvalidEquipmentError):
        store.save(binoculars(magnification=True))  # type: ignore[arg-type]


def test_non_finite_and_overflow_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aperture=math.nan))
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aperture=math.inf))
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aperture=int("1" + "0" * 400)))


def test_over_limit_aperture_and_magnification_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aperture=2001))
    with pytest.raises(InvalidEquipmentError):
        store.save(binoculars(aperture=301))
    with pytest.raises(InvalidEquipmentError):
        store.save(binoculars(magnification=101))


def test_empty_after_trim_name_and_alias_rejected(store) -> None:
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(name="  "))
    with pytest.raises(InvalidEquipmentError):
        store.save(s30(aliases=("  ",)))


def test_nfc_and_casefold_uniqueness(store) -> None:
    store.save(s30(name="é", aliases=()))
    with pytest.raises(EquipmentConflictError):
        store.save(virtuoso(name="e\u0301"))
    store.save(virtuoso(name="Straße"))
    with pytest.raises(EquipmentConflictError):
        store.save(s30(name="STRASSE", aliases=(), aperture=40))


def test_display_form_persisted_not_folded(store) -> None:
    saved = store.save(s30(name="S30 Pro")).item
    assert saved is not None
    assert saved.name == "S30 Pro"


def test_select_unknown_does_not_mutate(store) -> None:
    store.save(s30(id=S30_ID), select=True)
    with pytest.raises(EquipmentNotFoundError):
        store.select(VIRTUOSO_ID)
    assert store.get_selected().id == S30_ID


def test_select_naked_eye_on_empty_inventory(store) -> None:
    written = store.select_naked_eye()
    assert written.state.selection.mode is EquipmentSelectionMode.NAKED_EYE_ONLY
    active = compose_active(store.load())
    assert active.source is EquipmentSource.NAKED_EYE_ONLY
    assert active.has_saved_inventory is False
    assert active.engine_has_saved_inventory is True
    assert [row.type for row in active.capabilities] == ["nakedEye"]


def test_get_active_empty_all_saved_is_no_equipment(store) -> None:
    active = compose_active(store.load())
    assert active.source is EquipmentSource.NO_EQUIPMENT
    assert active.engine_has_saved_inventory is False
    assert active.capabilities == ()
    assert active.identities == ()


def test_resolve_by_id_name_and_alias(store) -> None:
    saved = store.save(s30(id=S30_ID)).item
    assert saved is not None
    assert store.resolve(S30_ID).id == saved.id
    assert store.resolve("S30 Pro").id == saved.id
    assert store.resolve("Seestar").id == saved.id
    assert store.resolve("  S30  ").id == saved.id


def test_get_unparseable_id_is_invalid(store) -> None:
    store.save(s30())
    with pytest.raises(InvalidEquipmentError):
        store.get("S30 Pro")


def test_name_or_alias_equal_live_id_conflicts(store) -> None:
    store.save(s30(id=S30_ID, aliases=()))
    with pytest.raises(EquipmentConflictError):
        store.save(virtuoso(name=S30_ID))
    with pytest.raises(EquipmentConflictError):
        store.save(virtuoso(aliases=(S30_ID,)))


def test_select_query_does_not_use_a_later_snapshot(store, monkeypatch) -> None:
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    real = equipment_module._resolve

    def hijack(document, query):
        found = real(document, query)
        if hasattr(store, "_document"):
            swapped = []
            for item in store._document.items:
                if item.id == S30_ID:
                    swapped.append(replace(item, name="Virtuoso"))
                elif item.id == VIRTUOSO_ID:
                    swapped.append(replace(item, name="S30 Pro"))
                else:
                    swapped.append(item)
            store._document = replace(store._document, items=tuple(swapped))
        else:
            import json
            path = store.path
            document_json = json.loads(path.read_text(encoding="utf-8"))
            for row in document_json["items"]:
                if row["id"] == S30_ID:
                    row["name"] = "Virtuoso"
                elif row["id"] == VIRTUOSO_ID:
                    row["name"] = "S30 Pro"
            path.write_text(json.dumps(document_json), encoding="utf-8")
        return found

    monkeypatch.setattr(equipment_module, "_resolve", hijack)
    selected = store.select_query("S30 Pro")
    assert selected.item is not None
    assert selected.item.id == S30_ID
    assert selected.item.name == "S30 Pro"
    assert store.get_selected().id == S30_ID


def test_normalize_label_helper_is_shared() -> None:
    assert normalize_label(" S30 ") == normalize_label("s30")
