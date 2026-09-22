from __future__ import annotations

import json
from pathlib import Path

import pytest

from astro_host.equipment import FileEquipmentStore
from astro_host.errors import (
    EyepieceConflictError,
    EyepieceNotFoundError,
    EyepieceStoreCorruptError,
    EyepieceStoreUnsupportedSchemaError,
    InvalidEyepieceError,
)
from astro_host.eyepieces import FileEyepieceStore, MemoryEyepieceStore
from astro_host.models import EquipmentType, SavedEyepieceDraft

from test_equipment import VIRTUOSO_ID, virtuoso


DELOS_ID = "33333333-3333-4333-8333-333333333333"
PANOPTIC_ID = "44444444-4444-4444-8444-444444444444"


def delos(**overrides) -> SavedEyepieceDraft:
    fields = dict(
        name="8 mm Delos",
        focal_length_mm=8,
        afov_degrees=72,
        aliases=("Delos 8",),
    )
    fields.update(overrides)
    return SavedEyepieceDraft(**fields)


def panoptic(**overrides) -> SavedEyepieceDraft:
    fields = dict(name="24 mm Panoptic", focal_length_mm=24, afov_degrees=68)
    fields.update(overrides)
    return SavedEyepieceDraft(**fields)


@pytest.fixture(params=["memory", "file"])
def store(request, tmp_path: Path):
    if request.param == "memory":
        return MemoryEyepieceStore()
    return FileEyepieceStore(tmp_path / "eyepieces.json")


def test_first_list_is_empty_and_does_not_create_a_file(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    assert FileEyepieceStore(path).list() == ()
    assert not path.exists()
    assert MemoryEyepieceStore().list() == ()


def test_save_list_resolve_update_and_delete(store) -> None:
    created = store.save(delos()).item
    assert created is not None
    assert created.focal_length_mm == 8
    assert created.afov_degrees == 72
    assert created.aliases == ("Delos 8",)
    assert store.resolve("delos 8").id == created.id
    updated = store.save(delos(id=created.id, name="8mm Delos", afov_degrees=None)).item
    assert updated is not None
    assert updated.id == created.id
    assert updated.name == "8mm Delos"
    assert updated.afov_degrees is None
    assert len(store.list()) == 1
    deleted = store.delete_query("8mm Delos").item
    assert deleted is not None
    assert deleted.id == created.id
    assert store.list() == ()


def test_explicit_id_and_missing_afov(store) -> None:
    saved = store.save(panoptic(id=PANOPTIC_ID, afov_degrees=None, aliases=())).item
    assert saved is not None
    assert saved.id == PANOPTIC_ID
    assert saved.afov_degrees is None
    assert store.get(PANOPTIC_ID).name == "24 mm Panoptic"


def test_duplicate_name_conflicts_and_missing_is_not_found(store) -> None:
    store.save(delos(id=DELOS_ID, aliases=()))
    with pytest.raises(EyepieceConflictError):
        store.save(delos(name="8 MM DELOS", aliases=()))
    with pytest.raises(EyepieceNotFoundError):
        store.resolve("missing eyepiece")


def test_invalid_focal_length_and_afov_are_rejected(store) -> None:
    with pytest.raises(InvalidEyepieceError):
        store.save(delos(focal_length_mm=0))
    with pytest.raises(InvalidEyepieceError):
        store.save(delos(focal_length_mm=-8))
    with pytest.raises(InvalidEyepieceError):
        store.save(delos(afov_degrees=181))
    with pytest.raises(InvalidEyepieceError):
        store.save(delos(name="  "))


def test_eyepiece_inventory_does_not_touch_equipment(tmp_path: Path) -> None:
    equipment_path = tmp_path / "equipment.json"
    eyepiece_path = tmp_path / "eyepieces.json"
    equipment = FileEquipmentStore(equipment_path)
    equipment.save(virtuoso(id=VIRTUOSO_ID, focal_length_mm=750))
    before = equipment_path.read_bytes()
    FileEyepieceStore(eyepiece_path).save(delos(id=DELOS_ID, aliases=()))
    assert equipment_path.read_bytes() == before
    loaded = FileEquipmentStore(equipment_path).get(VIRTUOSO_ID)
    assert loaded.type is EquipmentType.VISUAL_TELESCOPE
    assert loaded.focal_length_mm == 750
    assert FileEyepieceStore(eyepiece_path).get(DELOS_ID).name == "8 mm Delos"


def test_old_shape_is_not_an_equipment_document(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    path.write_text(
        '{"schema_version":1,"items":[],"selection":{"mode":"all_saved"}}\n',
        encoding="utf-8",
    )
    loaded = FileEyepieceStore(path).load()
    assert loaded.items == ()
    document = json.loads(path.read_text(encoding="utf-8"))
    assert "selection" not in document or document.get("selection") == {"mode": "all_saved"}


def test_unknown_document_field_survives_rewrite(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    store = FileEyepieceStore(path)
    store.save(delos(id=DELOS_ID, aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["future_field"] = {"keep": True}
    document["items"][0]["future_note"] = "stay"
    path.write_text(json.dumps(document), encoding="utf-8")
    store.save(panoptic(id=PANOPTIC_ID, aliases=()))
    rewritten = json.loads(path.read_text(encoding="utf-8"))
    assert rewritten["future_field"] == {"keep": True}
    row = next(item for item in rewritten["items"] if item["id"] == DELOS_ID)
    assert row["future_note"] == "stay"
    assert "type" not in row


def test_corrupt_file_is_not_replaced(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    original = '{"schema_version":1,"items":['
    path.write_text(original, encoding="utf-8")
    with pytest.raises(EyepieceStoreCorruptError):
        FileEyepieceStore(path).list()
    assert path.read_text(encoding="utf-8") == original


def test_unsupported_schema_is_not_overwritten(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    original = '{"schema_version":2,"items":[{"keep":true}]}\n'
    path.write_text(original, encoding="utf-8")
    with pytest.raises(EyepieceStoreUnsupportedSchemaError) as exc:
        FileEyepieceStore(path).save(delos())
    assert exc.value.schema_version == 2
    assert path.read_text(encoding="utf-8") == original


def test_bool_schema_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "eyepieces.json"
    original = '{"schema_version":true,"items":[]}\n'
    path.write_text(original, encoding="utf-8")
    with pytest.raises(EyepieceStoreCorruptError):
        FileEyepieceStore(path).list()
    assert path.read_text(encoding="utf-8") == original
