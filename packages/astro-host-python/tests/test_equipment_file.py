from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import pickle
import subprocess
import sys

import pytest

from astro_host.errors import (
    EquipmentStoreCorruptError,
    EquipmentStoreError,
    EquipmentStoreUnsupportedSchemaError,
)
from astro_host.equipment import (
    EQUIPMENT_FILENAME,
    SCHEMA_VERSION,
    FileEquipmentStore,
    _Document,
    _encode_document,
    default_equipment_path,
)
from astro_host.models import (
    EquipmentApertureUnit,
    EquipmentSelection,
    EquipmentSelectionMode,
    EquipmentType,
    SavedEquipment,
    SavedEquipmentDraft,
)
from astro_host.weather_cache_file import CACHE_FILENAME, default_state_dir

from test_equipment import S30_ID, VIRTUOSO_ID, BINO_ID, binoculars, s30, virtuoso


HOST_SRC = Path(__file__).resolve().parents[1] / "src"
ENGINE_SRC = Path(__file__).resolve().parents[2] / "astro-engine-python" / "src"


def store_at(path: Path) -> FileEquipmentStore:
    return FileEquipmentStore(path)


def test_missing_file_is_empty_without_side_effects(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "equipment.json"
    store = store_at(path)
    assert store.list() == ()
    assert store.get_selected().mode is EquipmentSelectionMode.ALL_SAVED
    assert list(tmp_path.iterdir()) == []
    assert not path.exists()
    assert not path.with_name(path.name + ".lock").exists()


def test_constructor_does_not_io(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    FileEquipmentStore(path)
    assert list(tmp_path.iterdir()) == []


def test_uppercase_supplied_id_file_json_is_lowercase(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID.upper(), aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["items"][0]["id"] == S30_ID


def test_on_disk_uppercase_id_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()), select=True)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["id"] = S30_ID.upper()
    document["selection"]["id"] = S30_ID.upper()
    original = json.dumps(document) + "\n"
    path.write_text(original, encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()
    assert path.read_text(encoding="utf-8") == original


def test_integer_json_aperture_coerces_to_float(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["aperture_mm"] = 30
    path.write_text(json.dumps(document), encoding="utf-8")
    loaded = store_at(path).get(S30_ID)
    assert loaded.aperture_mm == 30.0
    assert isinstance(loaded.aperture_mm, float)


def test_empty_after_trim_alias_on_disk_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=("S30",)))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["aliases"] = [""]
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_file_decode_rejects_duplicate_labels(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][1]["name"] = "S30 PRO"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_malformed_sibling_invalidates_whole_file(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["aperture_mm"] = True
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).get(VIRTUOSO_ID)


def test_truncated_json_and_non_utf8_are_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text('{"schema_version":1,"items":[', encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()
    path.write_bytes(b"\xff\xfe not utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_nan_json_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text(
        '{"schema_version":1,"items":[],"selection":{"mode":"all_saved"},"noise":NaN}\n',
        encoding="utf-8",
    )
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_missing_required_keys_are_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    del document["items"][0]["name"]
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_schema_zero_is_unsupported_and_not_overwritten(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    original = '{"schema_version":0,"items":[],"selection":{"mode":"all_saved"}}\n'
    path.write_text(original, encoding="utf-8")
    store = store_at(path)
    with pytest.raises(EquipmentStoreUnsupportedSchemaError) as exc:
        store.list()
    assert exc.value.code == "unsupported_schema"
    with pytest.raises(EquipmentStoreUnsupportedSchemaError):
        store.save(s30())
    assert path.read_text(encoding="utf-8") == original


def test_schema_two_is_unsupported(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text(
        '{"schema_version":2,"items":[],"selection":{"mode":"all_saved"}}\n',
        encoding="utf-8",
    )
    with pytest.raises(EquipmentStoreUnsupportedSchemaError):
        store_at(path).list()


def test_bool_schema_version_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text(
        '{"schema_version":true,"items":[],"selection":{"mode":"all_saved"}}\n',
        encoding="utf-8",
    )
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_dangling_selection_id_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()), select=True)
    document = json.loads(path.read_text(encoding="utf-8"))
    document["selection"]["id"] = VIRTUOSO_ID
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_all_saved_with_id_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["selection"]["id"] = S30_ID
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_unknown_type_unit_and_mode_are_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()))
    original = json.loads(path.read_text(encoding="utf-8"))
    for field, value in (
        ("type", "camera"),
        ("aperture_unit", "feet"),
    ):
        document = json.loads(json.dumps(original))
        document["items"][0][field] = value
        path.write_text(json.dumps(document), encoding="utf-8")
        with pytest.raises(EquipmentStoreCorruptError):
            store_at(path).list()
    document = json.loads(json.dumps(original))
    document["selection"]["mode"] = "custom"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_telescope_magnification_on_disk_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=()))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["magnification"] = 50
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_binoculars_missing_magnification_on_disk_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(binoculars(id=BINO_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    del document["items"][0]["magnification"]
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        store_at(path).list()


def test_extra_keys_preserved_on_rewrite(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()))
    store.save(virtuoso(id=VIRTUOSO_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["future_field"] = {"keep": True}
    document["items"][0]["future_note"] = "s30-extra"
    document["selection"]["future_sel"] = 1
    path.write_text(json.dumps(document), encoding="utf-8")
    store_at(path).save(binoculars(id=BINO_ID))
    rewritten = json.loads(path.read_text(encoding="utf-8"))
    assert rewritten["future_field"] == {"keep": True}
    s30_row = next(row for row in rewritten["items"] if row["id"] == S30_ID)
    assert s30_row["future_note"] == "s30-extra"
    assert rewritten["selection"]["future_sel"] == 1


def test_extra_keys_on_replaced_row_preserved(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store_at(path).save(s30(id=S30_ID, aliases=("S30",)))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["items"][0]["future_note"] = "stay"
    path.write_text(json.dumps(document), encoding="utf-8")
    store_at(path).save(s30(id=S30_ID, name="Casa", aliases=("S30",)))
    rewritten = json.loads(path.read_text(encoding="utf-8"))
    assert rewritten["items"][0]["name"] == "Casa"
    assert rewritten["items"][0]["future_note"] == "stay"


def test_unknown_key_merge_cannot_clobber_known_fields() -> None:
    item = SavedEquipment(
        id=S30_ID,
        name="S30 Pro",
        type=EquipmentType.SMART_TELESCOPE,
        aperture_mm=30.0,
        aperture_unit=EquipmentApertureUnit.MILLIMETERS,
    )
    payload = json.loads(_encode_document(_Document(
        items=(item,),
        selection=EquipmentSelection(EquipmentSelectionMode.ITEM, S30_ID),
        extra={
            "schema_version": 99,
            "items": [],
            "selection": "clobber",
            "future_field": 1,
        },
        item_extras={
            S30_ID: {
                "id": "00000000-0000-4000-8000-000000000000",
                "name": "Wrong",
                "type": "binoculars",
                "aperture_mm": 0,
                "aperture_unit": "inches",
                "aliases": ["nope"],
                "magnification": 99,
                "future_note": "keep",
            }
        },
        selection_extra={"mode": "all_saved", "id": "nope", "future_sel": True},
    )))
    assert payload["schema_version"] == SCHEMA_VERSION
    assert payload["selection"]["mode"] == "item"
    assert payload["selection"]["id"] == S30_ID
    assert payload["selection"]["future_sel"] is True
    assert payload["future_field"] == 1
    row = payload["items"][0]
    assert row["id"] == S30_ID
    assert row["name"] == "S30 Pro"
    assert row["type"] == "smartTelescope"
    assert row["aperture_mm"] == 30.0
    assert "magnification" not in row
    assert row["future_note"] == "keep"


def test_delete_last_item_file_remains_all_saved(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()), select=True)
    store.delete(S30_ID)
    assert path.exists()
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["items"] == []
    assert document["selection"] == {"mode": "all_saved"}
    loaded = store_at(path)
    assert loaded.list() == ()
    assert loaded.get_selected().mode is EquipmentSelectionMode.ALL_SAVED


def test_delete_last_item_naked_eye_only_file_preserves_mode(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()))
    store.select_naked_eye()
    store.delete(S30_ID)
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["items"] == []
    assert document["selection"] == {"mode": "naked_eye_only"}
    assert store_at(path).get_selected().mode is EquipmentSelectionMode.NAKED_EYE_ONLY


def test_os_replace_oserror_raises_and_leaves_previous(
    tmp_path: Path, monkeypatch,
) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    first = store.save(s30(id=S30_ID, aliases=())).item
    original = path.read_bytes()

    def boom(*_args, **_kwargs):
        raise OSError("replace failed")

    monkeypatch.setattr("astro_host.equipment.os.replace", boom)
    with pytest.raises(EquipmentStoreError) as exc:
        store.save(virtuoso(id=VIRTUOSO_ID))
    assert exc.value.code == "host_failure"
    assert path.read_bytes() == original
    monkeypatch.undo()
    assert store_at(path).get(S30_ID) == first


def test_parent_created_only_on_first_write_no_leftover_temps(tmp_path: Path) -> None:
    path = tmp_path / "state" / "equipment.json"
    store = store_at(path)
    assert not path.parent.exists()
    store.save(s30(aliases=()))
    assert path.exists()
    assert list(path.parent.glob("*.tmp")) == []


def test_lock_is_sync_no_await_in_equipment_module() -> None:
    source = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "equipment.py"
    ).read_text(encoding="utf-8")
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, ast.Await):
            raise AssertionError("equipment.py must not await")
        if isinstance(node, ast.AsyncFunctionDef):
            raise AssertionError(f"async function {node.name} is forbidden")


def test_file_store_query_methods_do_not_call_public_resolve_select_delete() -> None:
    source = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "equipment.py"
    ).read_text(encoding="utf-8")
    tree = ast.parse(source)
    class_node = next(
        node for node in tree.body
        if isinstance(node, ast.ClassDef) and node.name == "FileEquipmentStore"
    )
    for method in class_node.body:
        if not isinstance(method, ast.FunctionDef):
            continue
        if method.name not in {"select_query", "delete_query"}:
            continue
        called = {
            node.attr
            for node in ast.walk(method)
            if isinstance(node, ast.Attribute)
        }
        assert "resolve" not in called
        assert "select" not in called or method.name == "select_query"
        assert "delete" not in called or method.name == "delete_query"
        for node in ast.walk(method):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                assert node.func.attr not in {"resolve", "select", "delete"}


def test_file_store_does_not_read_weather_or_locations(tmp_path: Path) -> None:
    weather = tmp_path / CACHE_FILENAME
    weather.write_text('{"schema_version":1,"entries":[]}\n', encoding="utf-8")
    locations = tmp_path / "locations.json"
    locations.write_text(
        '{"schema_version":1,"locations":[],"selected_location_id":null}\n',
        encoding="utf-8",
    )
    store = store_at(tmp_path / EQUIPMENT_FILENAME)
    assert store.list() == ()
    assert weather.read_text(encoding="utf-8").startswith('{"schema_version":1')
    assert "locations" in locations.read_text(encoding="utf-8")


def test_default_equipment_path_uses_state_dir(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ASTRO_HOST_STATE_DIR", str(tmp_path / "bot-state"))
    assert default_state_dir() == tmp_path / "bot-state"
    assert default_equipment_path() == tmp_path / "bot-state" / EQUIPMENT_FILENAME


def test_restart_new_instance_reuses_state(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    saved = store_at(path).save(s30(id=S30_ID)).item
    loaded = store_at(path)
    assert loaded.get(S30_ID) == saved
    assert loaded.get_selected().mode is EquipmentSelectionMode.ALL_SAVED


def test_two_os_processes_serialized_saves_keep_both_rows(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    go = tmp_path / "go"
    workers = [
        _start_save_process(tmp_path, path, s30(id=S30_ID, aliases=()), tmp_path / "ready-s30", go),
        _start_save_process(
            tmp_path, path, virtuoso(id=VIRTUOSO_ID), tmp_path / "ready-virt", go,
        ),
    ]
    _wait_ready((tmp_path / "ready-s30", tmp_path / "ready-virt"), workers)
    go.write_text("1", encoding="utf-8")
    results = [worker.wait(timeout=15) for worker in workers]
    if results != [0, 0]:
        _fail_workers(workers, f"workers exited {results}")
    loaded = store_at(path)
    assert {row.id for row in loaded.list()} == {S30_ID, VIRTUOSO_ID}
    selection = json.loads(path.read_text(encoding="utf-8"))["selection"]
    if selection["mode"] == "item":
        assert selection["id"] in {S30_ID, VIRTUOSO_ID}


def test_delete_select_race_cannot_dangle(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    store = store_at(path)
    store.save(s30(id=S30_ID, aliases=()), select=True)
    store.save(virtuoso(id=VIRTUOSO_ID))
    go = tmp_path / "go"
    workers = [
        _start_action_process(
            tmp_path, path, "delete", S30_ID, tmp_path / "ready-delete", go,
        ),
        _start_action_process(
            tmp_path, path, "select", S30_ID, tmp_path / "ready-select", go,
        ),
    ]
    _wait_ready((tmp_path / "ready-delete", tmp_path / "ready-select"), workers)
    go.write_text("1", encoding="utf-8")
    [worker.wait(timeout=15) for worker in workers]
    loaded = json.loads(path.read_text(encoding="utf-8"))
    ids = {row["id"] for row in loaded["items"]}
    selection = loaded["selection"]
    if selection["mode"] == "item":
        assert selection["id"] in ids
    else:
        assert "id" not in selection


def _pythonpath() -> str:
    existing = os.environ.get("PYTHONPATH", "")
    parts = [str(HOST_SRC), str(ENGINE_SRC)]
    if existing:
        parts.append(existing)
    return os.pathsep.join(parts)


def _start_save_process(
    tmp_path: Path,
    store_path: Path,
    draft: SavedEquipmentDraft,
    ready: Path,
    go: Path,
) -> subprocess.Popen[bytes]:
    payload = tmp_path / f"{draft.id}.pkl"
    payload.write_bytes(pickle.dumps(draft))
    script = """
import pickle, sys, time
from pathlib import Path
from astro_host.equipment import FileEquipmentStore
path, payload, ready, go = sys.argv[1:]
Path(ready).write_text("1", encoding="utf-8")
deadline = time.time() + 15
while not Path(go).exists():
    if time.time() > deadline:
        raise SystemExit("timed out waiting to start")
    time.sleep(0.01)
draft = pickle.loads(Path(payload).read_bytes())
FileEquipmentStore(path).save(draft)
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = _pythonpath()
    return subprocess.Popen(
        [sys.executable, "-c", script, str(store_path), str(payload), str(ready), str(go)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _start_action_process(
    tmp_path: Path,
    store_path: Path,
    action: str,
    equipment_id: str,
    ready: Path,
    go: Path,
) -> subprocess.Popen[bytes]:
    script = """
import sys, time
from pathlib import Path
from astro_host.equipment import FileEquipmentStore
path, action, equipment_id, ready, go = sys.argv[1:]
Path(ready).write_text("1", encoding="utf-8")
deadline = time.time() + 15
while not Path(go).exists():
    if time.time() > deadline:
        raise SystemExit("timed out waiting to start")
    time.sleep(0.01)
store = FileEquipmentStore(path)
try:
    if action == "delete":
        store.delete(equipment_id)
    else:
        store.select(equipment_id)
except Exception:
    pass
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = _pythonpath()
    return subprocess.Popen(
        [
            sys.executable, "-c", script,
            str(store_path), action, equipment_id, str(ready), str(go),
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _wait_ready(paths, workers) -> None:
    import time
    deadline = time.time() + 15
    while time.time() < deadline:
        if all(path.exists() for path in paths):
            return
        if any(worker.poll() is not None for worker in workers):
            _fail_workers(workers, "worker exited before ready")
        time.sleep(0.01)
    _fail_workers(workers, "timed out waiting for workers")


def _fail_workers(workers, message: str) -> None:
    details = []
    for worker in workers:
        stdout, stderr = worker.communicate(timeout=1)
        details.append(f"exit={worker.returncode} stderr={stderr!r} stdout={stdout!r}")
    raise AssertionError(message + " " + " | ".join(details))
