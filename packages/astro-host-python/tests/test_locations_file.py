from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import pickle
import subprocess
import sys
import time
import pytest

from astro_host.errors import (
    LocationStoreCorruptError,
    LocationStoreError,
    LocationStoreUnsupportedSchemaError,
)
from astro_host.locations import (
    FileLocationStore,
    LOCATIONS_FILENAME,
    SCHEMA_VERSION,
    _Document,
    _encode_document,
    default_locations_path,
)
from astro_host.models import SavedLocation, SavedLocationDraft
from astro_host.weather_cache_file import CACHE_FILENAME, default_state_dir

from test_locations import BEND_ID, HOME_ID, HOOD_ID, bend, home, hood


HOST_SRC = Path(__file__).resolve().parents[1] / "src"
ENGINE_SRC = Path(__file__).resolve().parents[2] / "astro-engine-python" / "src"


def store_at(path: Path) -> FileLocationStore:
    return FileLocationStore(path)


def test_missing_file_is_empty_without_side_effects(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "locations.json"
    store = store_at(path)
    assert store.list() == ()
    assert store.get_selected() is None
    assert list(tmp_path.iterdir()) == []
    assert not path.exists()
    assert not path.with_name(path.name + ".lock").exists()


def test_constructor_does_not_io(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    FileLocationStore(path)
    assert list(tmp_path.iterdir()) == []


def test_uppercase_supplied_id_file_json_is_lowercase(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID.upper()))
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["locations"][0]["id"] == HOME_ID


def test_on_disk_uppercase_id_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["id"] = HOME_ID.upper()
    document["selected_location_id"] = HOME_ID.upper()
    original = json.dumps(document) + "\n"
    path.write_text(original, encoding="utf-8")
    store = store_at(path)
    with pytest.raises(LocationStoreCorruptError):
        store.list()
    assert path.read_text(encoding="utf-8") == original


def test_exact_coordinate_json_round_trip(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    saved = store.save(home(id=HOME_ID))
    loaded = store_at(path).get(HOME_ID)
    assert loaded.latitude == 34.05
    assert loaded == saved
    store.save(home(id=BEND_ID, name="Nearby", latitude=34.06))
    assert store.get(HOME_ID).latitude == 34.05
    assert store.get(BEND_ID).latitude == 34.06


def test_integer_json_latitude_coerces_to_float(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["latitude"] = 34
    path.write_text(json.dumps(document), encoding="utf-8")
    loaded = store_at(path).get(HOME_ID)
    assert loaded.latitude == 34.0
    assert isinstance(loaded.latitude, float)


def test_empty_after_trim_alias_on_disk_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["aliases"] = [""]
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_file_decode_rejects_duplicate_labels(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][1]["name"] = "HOME"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_truncated_json_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text('{"schema_version":1,"locations":[', encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()
    assert path.read_text(encoding="utf-8") == '{"schema_version":1,"locations":['


def test_non_utf8_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_bytes(b"\xff\xfe not utf-8 {")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()
    assert path.read_bytes() == b"\xff\xfe not utf-8 {"


def test_invalid_json_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text("{not-json", encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_schema_version_bool_is_corrupt_and_not_self_healed(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    original = '{"schema_version":true,"locations":[],"selected_location_id":null}\n'
    path.write_text(original, encoding="utf-8")
    store = store_at(path)
    with pytest.raises(LocationStoreCorruptError):
        store.list()
    with pytest.raises(LocationStoreCorruptError):
        store.save(home())
    assert path.read_text(encoding="utf-8") == original


def test_schema_version_zero_is_unsupported_schema_not_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    original = '{"schema_version":0,"locations":[],"selected_location_id":null}\n'
    path.write_text(original, encoding="utf-8")
    store = store_at(path)
    with pytest.raises(LocationStoreUnsupportedSchemaError) as exc:
        store.save(home())
    assert exc.value.schema_version == 0
    assert path.read_text(encoding="utf-8") == original


def test_foreign_schema_version_raises_and_is_never_overwritten(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    original = '{"schema_version":2,"locations":[{"keep":true}],"selected_location_id":null}\n'
    path.write_text(original, encoding="utf-8")
    store = store_at(path)
    with pytest.raises(LocationStoreUnsupportedSchemaError):
        store.list()
    with pytest.raises(LocationStoreUnsupportedSchemaError):
        store.save(home())
    assert path.read_text(encoding="utf-8") == original


def test_dangling_selected_id_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["selected_location_id"] = BEND_ID
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_duplicate_ids_on_disk_are_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][1]["id"] = HOME_ID
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_malformed_sibling_invalidates_whole_file(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["latitude"] = True
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).get(HOOD_ID)


def test_extra_keys_preserved_on_rewrite(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["future_field"] = {"keep": True}
    document["locations"][0]["future_note"] = "home-extra"
    path.write_text(json.dumps(document), encoding="utf-8")
    store_at(path).save(bend(id=BEND_ID))
    rewritten = json.loads(path.read_text(encoding="utf-8"))
    assert rewritten["future_field"] == {"keep": True}
    home_row = next(row for row in rewritten["locations"] if row["id"] == HOME_ID)
    assert home_row["future_note"] == "home-extra"


def test_extra_keys_on_replaced_row_preserved(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID, aliases=("house",)))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["future_note"] = "stay"
    path.write_text(json.dumps(document), encoding="utf-8")
    store_at(path).save(home(id=HOME_ID, name="Casa", aliases=("house",)))
    rewritten = json.loads(path.read_text(encoding="utf-8"))
    assert rewritten["locations"][0]["name"] == "Casa"
    assert rewritten["locations"][0]["future_note"] == "stay"


def test_unknown_key_merge_cannot_clobber_known_fields() -> None:
    location = SavedLocation(
        id=HOME_ID,
        name="Home",
        latitude=34.05,
        longitude=-118.24,
        time_zone="America/Los_Angeles",
    )
    payload = json.loads(_encode_document(_Document(
        locations=(location,),
        selected_location_id=HOME_ID,
        extra={
            "schema_version": 99,
            "locations": [],
            "selected_location_id": "clobber",
            "future_field": 1,
        },
        location_extras={
            HOME_ID: {
                "id": "00000000-0000-4000-8000-000000000000",
                "name": "Wrong",
                "latitude": 0,
                "longitude": 0,
                "time_zone": "Etc/UTC",
                "aliases": ["nope"],
                "elevation_m": 999,
                "future_note": "keep",
            }
        },
    )))
    assert payload["schema_version"] == SCHEMA_VERSION
    assert payload["selected_location_id"] == HOME_ID
    assert payload["future_field"] == 1
    row = payload["locations"][0]
    assert row["id"] == HOME_ID
    assert row["name"] == "Home"
    assert row["latitude"] == 34.05
    assert row["time_zone"] == "America/Los_Angeles"
    assert row["future_note"] == "keep"
    assert "elevation_m" not in row


def test_missing_required_field_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    del document["locations"][0]["name"]
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError) as exc:
        store_at(path).list()
    assert exc.value.code == "corrupt"


def test_latitude_true_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["latitude"] = True
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_aliases_string_or_null_on_disk_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    original = json.loads(path.read_text(encoding="utf-8"))
    for bad in ("house", None):
        document = json.loads(json.dumps(original))
        document["locations"][0]["aliases"] = bad
        path.write_text(json.dumps(document), encoding="utf-8")
        with pytest.raises(LocationStoreCorruptError):
            store_at(path).list()


def test_oversized_json_number_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["latitude"] = int("1" + "0" * 400)
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_nan_json_is_corrupt(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text(
        '{"schema_version":1,"locations":[],"selected_location_id":null,"noise":NaN}\n',
        encoding="utf-8",
    )
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).list()


def test_empty_document_after_delete_all_round_trips(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    saved = store.save(home())
    store.delete(saved.id)
    assert path.exists()
    document = json.loads(path.read_text(encoding="utf-8"))
    assert document["locations"] == []
    assert document["selected_location_id"] is None
    loaded = store_at(path)
    assert loaded.list() == ()
    assert loaded.get_selected() is None


def test_restart_new_instance_reuses_state(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    saved = store_at(path).save(home(id=HOME_ID, aliases=("house",)))
    loaded = store_at(path)
    assert loaded.get(HOME_ID) == saved
    assert loaded.get_selected() == saved


def test_os_replace_oserror_raises_and_leaves_previous(
    tmp_path: Path, monkeypatch,
) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    first = store.save(home(id=HOME_ID))
    original = path.read_bytes()

    def boom(*_args, **_kwargs):
        raise OSError("replace failed")

    monkeypatch.setattr("astro_host.locations.os.replace", boom)
    with pytest.raises(LocationStoreError) as exc:
        store.save(hood(id=HOOD_ID))
    assert exc.value.code == "host_failure"
    assert path.read_bytes() == original
    monkeypatch.undo()
    assert store_at(path).get(HOME_ID) == first
    assert store_at(path).get_selected() == first


def test_parent_created_only_on_first_write_no_leftover_temps(tmp_path: Path) -> None:
    path = tmp_path / "state" / "locations.json"
    store = store_at(path)
    assert not path.parent.exists()
    store.save(home())
    assert path.exists()
    assert list(path.parent.glob("*.tmp")) == []


def test_persisted_invalid_timezone_is_corrupt_not_dropped(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store_at(path).save(home(id=HOME_ID))
    document = json.loads(path.read_text(encoding="utf-8"))
    document["locations"][0]["time_zone"] = "not/a-zone"
    original = json.dumps(document)
    path.write_text(original, encoding="utf-8")
    with pytest.raises(LocationStoreCorruptError):
        store_at(path).save(hood())
    assert path.read_text(encoding="utf-8") == original


def test_two_os_processes_serialized_saves_keep_both_rows(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    go = tmp_path / "go"
    workers = [
        _start_save_process(tmp_path, path, home(id=HOME_ID), tmp_path / "ready-home", go),
        _start_save_process(tmp_path, path, hood(id=HOOD_ID), tmp_path / "ready-hood", go),
    ]
    _wait_ready((tmp_path / "ready-home", tmp_path / "ready-hood"), workers)
    go.write_text("1", encoding="utf-8")
    results = [worker.wait(timeout=15) for worker in workers]
    if results != [0, 0]:
        _fail_workers(workers, f"workers exited {results}")
    loaded = store_at(path)
    assert {row.id for row in loaded.list()} == {HOME_ID, HOOD_ID}


def test_delete_select_race_cannot_dangle(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = store_at(path)
    store.save(home(id=HOME_ID))
    store.save(hood(id=HOOD_ID))
    store.save(bend(id=BEND_ID))
    go = tmp_path / "go"
    workers = [
        _start_action_process(
            tmp_path, path, "delete", HOME_ID, tmp_path / "ready-delete", go,
        ),
        _start_action_process(
            tmp_path, path, "select", HOME_ID, tmp_path / "ready-select", go,
        ),
    ]
    _wait_ready((tmp_path / "ready-delete", tmp_path / "ready-select"), workers)
    go.write_text("1", encoding="utf-8")
    [worker.wait(timeout=15) for worker in workers]
    loaded = json.loads(path.read_text(encoding="utf-8"))
    ids = {row["id"] for row in loaded["locations"]}
    selected = loaded["selected_location_id"]
    assert selected is None or selected in ids


def test_lock_is_sync_no_await_in_locations_module() -> None:
    source = (
        Path(__file__).resolve().parents[1] / "src" / "astro_host" / "locations.py"
    ).read_text(encoding="utf-8")
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, ast.Await):
            raise AssertionError("locations.py must not await")
        if isinstance(node, ast.AsyncFunctionDef):
            raise AssertionError(f"async function {node.name} is forbidden")


def test_file_store_does_not_read_weather_cache_json(tmp_path: Path) -> None:
    weather = tmp_path / CACHE_FILENAME
    weather.write_text(
        '{"schema_version":1,"entries":[{"keep":true}]}\n', encoding="utf-8"
    )
    store = store_at(tmp_path / LOCATIONS_FILENAME)
    assert store.list() == ()
    assert weather.read_text(encoding="utf-8").startswith('{"schema_version":1')


def test_default_locations_path_uses_state_dir(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("ASTRO_HOST_STATE_DIR", str(tmp_path / "bot-state"))
    assert default_state_dir() == tmp_path / "bot-state"
    assert default_locations_path() == tmp_path / "bot-state" / LOCATIONS_FILENAME


def _pythonpath() -> str:
    existing = os.environ.get("PYTHONPATH", "")
    parts = [str(HOST_SRC), str(ENGINE_SRC)]
    if existing:
        parts.append(existing)
    return os.pathsep.join(parts)


def _start_save_process(
    tmp_path: Path,
    store_path: Path,
    draft: SavedLocationDraft,
    ready: Path,
    go: Path,
) -> subprocess.Popen[bytes]:
    payload = tmp_path / f"{draft.id}.pkl"
    payload.write_bytes(pickle.dumps(draft))
    script = """
import pickle, sys, time
from pathlib import Path
from astro_host.locations import FileLocationStore
path, payload, ready, go = sys.argv[1:]
Path(ready).write_text("1", encoding="utf-8")
deadline = time.time() + 15
while not Path(go).exists():
    if time.time() > deadline:
        raise SystemExit("timed out waiting to start")
    time.sleep(0.01)
draft = pickle.loads(Path(payload).read_bytes())
FileLocationStore(path).save(draft)
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
    location_id: str,
    ready: Path,
    go: Path,
) -> subprocess.Popen[bytes]:
    script = """
import sys, time
from pathlib import Path
from astro_host.locations import FileLocationStore
path, action, location_id, ready, go = sys.argv[1:]
Path(ready).write_text("1", encoding="utf-8")
deadline = time.time() + 15
while not Path(go).exists():
    if time.time() > deadline:
        raise SystemExit("timed out waiting to start")
    time.sleep(0.01)
store = FileLocationStore(path)
try:
    if action == "delete":
        store.delete(location_id)
    else:
        store.select(location_id)
except Exception:
    pass
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = _pythonpath()
    return subprocess.Popen(
        [
            sys.executable, "-c", script,
            str(store_path), action, location_id, str(ready), str(go),
        ],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def _wait_ready(flags: tuple[Path, ...], workers: list[subprocess.Popen[bytes]]) -> None:
    deadline = time.time() + 15
    while time.time() < deadline:
        if all(flag.exists() for flag in flags):
            return
        time.sleep(0.01)
    _fail_workers(workers, "workers did not become ready")


def _fail_workers(workers: list[subprocess.Popen[bytes]], message: str) -> None:
    details = []
    for worker in workers:
        if worker.poll() is None:
            worker.kill()
        stdout, stderr = worker.communicate(timeout=5)
        details.append(
            f"exit={worker.returncode} stdout={stdout!r} stderr={stderr!r}"
        )
    raise AssertionError(message + " " + " | ".join(details))
