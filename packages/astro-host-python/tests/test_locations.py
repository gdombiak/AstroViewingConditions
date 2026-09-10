from __future__ import annotations

import asyncio
from dataclasses import replace
import json
import math
from pathlib import Path
import uuid

import pytest

from astro_host.conditions import ConditionsService
from astro_host.errors import (
    InvalidLocationError,
    LocationConflictError,
    LocationNotFoundError,
    TimeZoneCatalogError,
)
from astro_host.locations import FileLocationStore, MemoryLocationStore
import astro_host.locations as locations_module
from astro_host.models import ConditionsRequest, Location, SavedLocationDraft
import astro_host.timezones as timezone_module

from support import FakeEngine, FakeProvider, NOW


HOME_ID = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
BEND_ID = "11111111-1111-4111-8111-111111111111"
HOOD_ID = "22222222-2222-4222-8222-222222222222"


def home(**overrides) -> SavedLocationDraft:
    fields = dict(
        name="Home",
        latitude=34.05,
        longitude=-118.24,
        time_zone="America/Los_Angeles",
    )
    fields.update(overrides)
    return SavedLocationDraft(**fields)


def hood(**overrides) -> SavedLocationDraft:
    fields = dict(
        name="Hood",
        latitude=45.37,
        longitude=-121.70,
        time_zone="America/Los_Angeles",
    )
    fields.update(overrides)
    return SavedLocationDraft(**fields)


def bend(**overrides) -> SavedLocationDraft:
    fields = dict(
        name="Bend",
        latitude=44.0582,
        longitude=-121.3153,
        time_zone="America/Los_Angeles",
    )
    fields.update(overrides)
    return SavedLocationDraft(**fields)


@pytest.fixture(params=["memory", "file"])
def store(request, tmp_path: Path):
    if request.param == "memory":
        return MemoryLocationStore()
    return FileLocationStore(tmp_path / "locations.json")


def test_first_save_auto_selects_sole_location(store) -> None:
    saved = store.save(home())
    selected = store.get_selected()
    assert selected is not None
    assert selected.id == saved.id
    assert store.load().selected_location_id == saved.id


def test_second_save_does_not_change_selection(store) -> None:
    first = store.save(home())
    store.save(hood())
    assert store.get_selected() is not None
    assert store.get_selected().id == first.id


def test_save_with_supplied_id_is_idempotent_replace(store) -> None:
    first = store.save(home(id=HOME_ID, aliases=("house",)))
    store.save(hood())
    updated = store.save(home(
        id=HOME_ID,
        name="Casa",
        latitude=34.06,
        longitude=-118.25,
        time_zone="America/Los_Angeles",
        aliases=("homebase",),
        elevation_m=12.0,
    ))
    assert updated.id == first.id == HOME_ID
    assert updated.name == "Casa"
    assert updated.latitude == 34.06
    assert updated.aliases == ("homebase",)
    assert updated.elevation_m == 12.0
    assert store.list()[0].id == HOME_ID
    assert store.get_selected().id == HOME_ID


def test_save_with_new_supplied_id_inserts(store) -> None:
    store.save(home(id=HOME_ID))
    imported = store.save(hood(id=HOOD_ID))
    assert imported.id == HOOD_ID
    assert [row.id for row in store.list()] == [HOME_ID, HOOD_ID]


def test_minted_id_is_canonical_uuid4_lowercase(store) -> None:
    saved = store.save(home())
    assert saved.id == str(uuid.UUID(saved.id))
    assert uuid.UUID(saved.id).version == 4


def test_uppercase_supplied_id_on_save_is_stored_lowercase(store) -> None:
    upper = HOME_ID.upper()
    saved = store.save(home(id=upper))
    assert saved.id == str(uuid.UUID(upper))
    assert saved.id == HOME_ID


def test_get_select_delete_uppercase_of_live_id_succeeds(store) -> None:
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    assert store.get(HOME_ID.upper()).id == HOME_ID
    selected = store.select(HOOD_ID.upper())
    assert selected.id == HOOD_ID
    store.delete(HOOD_ID.upper())
    assert [row.id for row in store.list()] == [HOME_ID]


def test_duplicate_coordinates_allowed(store) -> None:
    store.save(home())
    backyard = store.save(home(name="Backyard"))
    assert backyard.latitude == 34.05
    assert len(store.list()) == 2


def test_duplicate_normalized_name_conflicts(store) -> None:
    store.save(home())
    with pytest.raises(LocationConflictError):
        store.save(home(name=" HOME "))
    assert len(store.list()) == 1


def test_alias_conflicts_with_other_name(store) -> None:
    store.save(home())
    with pytest.raises(LocationConflictError):
        store.save(hood(aliases=("home",)))


def test_alias_conflicts_with_other_alias(store) -> None:
    store.save(home(aliases=("house",)))
    with pytest.raises(LocationConflictError):
        store.save(hood(aliases=("House",)))


def test_alias_equal_own_name_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(aliases=("Home",)))


def test_duplicate_aliases_in_draft_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(aliases=("house", "HOUSE")))


def test_nfc_and_casefold_uniqueness(store) -> None:
    store.save(home(name="é"))
    with pytest.raises(LocationConflictError):
        store.save(hood(name="e\u0301"))
    store.save(bend(name="Straße"))
    with pytest.raises(LocationConflictError):
        store.save(home(name="STRASSE", latitude=10.0))


def test_display_form_persisted_not_folded(store) -> None:
    saved = store.save(home(name="Home"))
    assert saved.name == "Home"


def test_boolean_coordinates_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(latitude=True))  # type: ignore[arg-type]


def test_boolean_elevation_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(elevation_m=True))  # type: ignore[arg-type]


def test_out_of_range_coordinates_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(latitude=90.1))
    with pytest.raises(InvalidLocationError):
        store.save(home(longitude=180.1))


def test_non_finite_elevation_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(elevation_m=math.nan))
    with pytest.raises(InvalidLocationError):
        store.save(home(elevation_m=math.inf))


def test_empty_or_whitespace_name_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(name=""))
    with pytest.raises(InvalidLocationError):
        store.save(home(name="   "))


def test_empty_after_trim_alias_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(aliases=("  ",)))


def test_unicode_whitespace_trim(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(name="\u00a0"))


def test_resolve_by_id_name_and_alias(store) -> None:
    saved = store.save(home(id=HOME_ID, aliases=("house",)))
    assert store.resolve(HOME_ID).id == saved.id
    assert store.resolve("Home").id == saved.id
    assert store.resolve("house").id == saved.id


def test_resolve_trims_query(store) -> None:
    saved = store.save(home())
    assert store.resolve("  Home  ").id == saved.id


def test_resolve_does_not_mutate_selection(store) -> None:
    first = store.save(home())
    store.save(hood())
    store.resolve("Hood")
    assert store.get_selected().id == first.id


def test_get_unparseable_id_is_invalid_location_error(store) -> None:
    store.save(home())
    with pytest.raises(InvalidLocationError):
        store.get("Home")


def test_get_unknown_canonical_id_is_not_found(store) -> None:
    store.save(home(id=HOME_ID))
    with pytest.raises(LocationNotFoundError):
        store.get(BEND_ID)


def test_name_or_alias_equal_live_id_conflicts(store) -> None:
    store.save(home(id=HOME_ID))
    with pytest.raises(LocationConflictError):
        store.save(hood(name=HOME_ID))
    with pytest.raises(LocationConflictError):
        store.save(hood(aliases=(HOME_ID,)))


def test_supplied_id_equal_other_row_label_conflicts(store) -> None:
    store.save(home(name=BEND_ID))
    with pytest.raises(LocationConflictError):
        store.save(hood(id=BEND_ID, name="Other"))


def test_zero_locations_selected_none(store) -> None:
    assert store.list() == ()
    assert store.get_selected() is None
    assert store.load().selected_location_id is None


def test_select_unknown_id_no_mutation(store) -> None:
    saved = store.save(home())
    with pytest.raises(LocationNotFoundError):
        store.select(BEND_ID)
    assert store.get_selected().id == saved.id


def test_select_then_get_selected(store) -> None:
    store.save(home(id=HOME_ID))
    other = store.save(hood(id=HOOD_ID))
    store.select(other.id)
    assert store.get_selected().id == HOOD_ID


def test_clear_selection_with_one_and_many(store) -> None:
    store.save(home())
    store.clear_selection()
    assert store.get_selected() is None
    assert len(store.list()) == 1
    store.save(hood())
    store.select(store.list()[0].id)
    store.clear_selection()
    assert store.get_selected() is None
    assert len(store.list()) == 2


def test_delete_selected_none_remain(store) -> None:
    saved = store.save(home())
    store.delete(saved.id)
    assert store.list() == ()
    assert store.get_selected() is None


def test_delete_selected_one_remains_auto_selects(store) -> None:
    first = store.save(home())
    second = store.save(hood())
    store.delete(first.id)
    assert store.get_selected().id == second.id


def test_delete_selected_several_remain_clears(store) -> None:
    first = store.save(home())
    store.save(hood())
    store.save(bend())
    store.delete(first.id)
    assert store.get_selected() is None
    assert len(store.list()) == 2


def test_delete_non_selected_keeps_selection(store) -> None:
    first = store.save(home())
    second = store.save(hood())
    store.delete(second.id)
    assert store.get_selected().id == first.id


def test_delete_one_of_two_unselected_leaves_sole_unselected(store) -> None:
    first = store.save(home())
    second = store.save(hood())
    store.clear_selection()
    store.delete(first.id)
    assert store.list()[0].id == second.id
    assert store.get_selected() is None


def test_delete_unknown_no_mutation(store) -> None:
    saved = store.save(home())
    with pytest.raises(LocationNotFoundError):
        store.delete(BEND_ID)
    assert store.list()[0].id == saved.id


def test_replace_selected_row_keeps_id_as_selected(store) -> None:
    store.save(home(id=HOME_ID))
    store.save(home(id=HOME_ID, name="Casa"))
    assert store.get_selected().id == HOME_ID
    assert store.get_selected().name == "Casa"


def test_save_without_timezone_rejected(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(time_zone=""))


def test_save_invalid_iana_rejected(store) -> None:
    for zone in ("not/a-zone", "GMT-0800", "UTC"):
        with pytest.raises(InvalidLocationError):
            store.save(home(time_zone=zone))


def test_save_catalogued_iana_accepted(store) -> None:
    los = store.save(home(time_zone="America/Los_Angeles"))
    assert los.time_zone == "America/Los_Angeles"
    calcutta = store.save(hood(time_zone="Asia/Calcutta"))
    assert calcutta.time_zone == "Asia/Calcutta"


def test_longitude_offset_not_persisted(store) -> None:
    with pytest.raises(InvalidLocationError):
        store.save(home(time_zone="Etc/GMT+8"))
    saved = store.save(home())
    assert not hasattr(saved, "fixed_offset")
    assert "fixed_offset" not in saved.__dict__


def test_catalogue_failure_is_not_invalid_timezone(store, monkeypatch, tmp_path) -> None:
    def fail_catalogue():
        raise RuntimeError("catalogue resource missing")

    monkeypatch.setattr(timezone_module, "allowed_timezone_identifiers", fail_catalogue)
    path = getattr(store, "path", None)
    before = path.read_bytes() if path is not None and path.exists() else None
    with pytest.raises(TimeZoneCatalogError):
        store.save(home())
    if path is None:
        return
    if before is None:
        assert not path.exists()
    else:
        assert path.read_bytes() == before


def test_memory_and_file_agree_on_save_select_delete(tmp_path: Path) -> None:
    memory = MemoryLocationStore()
    file_store = FileLocationStore(tmp_path / "locations.json")
    drafts = (
        home(id=HOME_ID, aliases=("house",), elevation_m=10),
        hood(id=HOOD_ID),
        bend(id=BEND_ID, aliases=("central",)),
    )
    for draft in drafts:
        assert memory.save(draft) == file_store.save(draft)
    assert memory.select(HOOD_ID) == file_store.select(HOOD_ID)
    memory.delete(BEND_ID)
    file_store.delete(BEND_ID)
    assert memory.list() == file_store.list()
    assert memory.get_selected() == file_store.get_selected()


def _swap_home_bend_names(store) -> None:
    if isinstance(store, MemoryLocationStore):
        swapped = []
        for location in store._document.locations:
            if location.id == HOME_ID:
                swapped.append(replace(location, name="Bend"))
            elif location.id == HOOD_ID:
                swapped.append(replace(location, name="Home"))
            else:
                swapped.append(location)
        store._document = replace(store._document, locations=tuple(swapped))
        return
    path = store.path
    document = json.loads(path.read_text(encoding="utf-8"))
    for row in document["locations"]:
        if row["id"] == HOME_ID:
            row["name"] = "Bend"
        elif row["id"] == HOOD_ID:
            row["name"] = "Home"
    path.write_text(json.dumps(document), encoding="utf-8")


def test_select_query_does_not_use_a_later_snapshot(store, monkeypatch) -> None:
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID, name="Bend"))
    store.clear_selection()
    real = locations_module._resolve

    def hijack(document, query):
        found = real(document, query)
        _swap_home_bend_names(store)
        return found

    monkeypatch.setattr(locations_module, "_resolve", hijack)
    selected = store.select_query("Home")
    assert selected.id == HOME_ID
    assert selected.name == "Home"
    assert store.get_selected().id == HOME_ID
    assert store.get(HOME_ID).name == "Home"


def test_delete_query_does_not_use_a_later_snapshot(store, monkeypatch) -> None:
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID, name="Bend"))
    real = locations_module._resolve

    def hijack(document, query):
        found = real(document, query)
        _swap_home_bend_names(store)
        return found

    monkeypatch.setattr(locations_module, "_resolve", hijack)
    store.delete_query("Home")
    ids = {row.id for row in store.list()}
    assert HOME_ID not in ids
    assert HOOD_ID in ids
    assert store.get(HOOD_ID).name == "Bend"


def test_file_query_mutations_do_not_reenter_public_methods(tmp_path, monkeypatch) -> None:
    store = FileLocationStore(tmp_path / "locations.json")
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID, name="Bend"))

    def boom(*_args, **_kwargs):
        raise AssertionError("query mutation must not reenter resolve/select/delete")

    monkeypatch.setattr(store, "resolve", boom)
    monkeypatch.setattr(store, "select", boom)
    monkeypatch.setattr(store, "delete", boom)
    store.select_query("Home")
    assert store.get_selected().id == HOME_ID
    store.delete_query("Bend")
    assert {row.id for row in store.list()} == {HOME_ID}


def test_one_off_location_object_does_not_touch_store(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = FileLocationStore(path)
    saved = store.save(home(id=HOME_ID))
    original = path.read_bytes()
    mtime = path.stat().st_mtime_ns
    request = ConditionsRequest(
        location=Location(44.0, -121.3, name="Sisters"),
        reference_time=NOW,
    )
    asyncio.run(ConditionsService(
        FakeProvider(), engine=FakeEngine(), atlas_path="test-atlas", clock=lambda: NOW,
    ).conditions(request))
    assert path.read_bytes() == original
    assert path.stat().st_mtime_ns == mtime
    assert store.get_selected() == saved
