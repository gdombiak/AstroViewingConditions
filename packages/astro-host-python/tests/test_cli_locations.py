from __future__ import annotations

import io
import json
from pathlib import Path

from argparse import Namespace

import pytest

from astro_host.cli import (
    EXIT_FAILURE,
    EXIT_INVALID_REQUEST,
    EXIT_OK,
    build_default_location_store,
    main,
)
from astro_host.locations import FileLocationStore, MemoryLocationStore

from test_locations import HOME_ID, HOOD_ID, home


def invoke_locations(
    tmp_path: Path,
    document: dict[str, object],
    *,
    store=None,
    extra_args: list[str] | None = None,
):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    argv = ["agent.locations", "--input", str(path), *(extra_args or [])]
    status = main(argv, store=store, stdout=stdout, stderr=stderr)
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_cli_list_empty_ok(tmp_path: Path) -> None:
    status, payload, stderr = invoke_locations(
        tmp_path, {"action": "list"}, store=MemoryLocationStore(),
    )
    assert status == EXIT_OK
    assert stderr == ""
    assert payload == {
        "ok": True,
        "operation": "agent.locations",
        "result": {
            "action": "list",
            "locations": [],
            "selected_location_id": None,
        },
    }


def test_cli_save_get_select_delete_round_trip(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    status, saved, _ = invoke_locations(tmp_path, {
        "action": "save",
        "location": {
            "name": "Home",
            "latitude": 34.05,
            "longitude": -118.24,
            "time_zone": "America/Los_Angeles",
            "aliases": ["house"],
        },
    }, store=store)
    assert status == EXIT_OK
    location_id = saved["result"]["location"]["id"]
    assert saved["result"]["selected_location_id"] == location_id
    _, listed, _ = invoke_locations(tmp_path, {"action": "list"}, store=store)
    assert len(listed["result"]["locations"]) == 1
    _, got, _ = invoke_locations(
        tmp_path, {"action": "get", "id": location_id}, store=store,
    )
    assert got["result"]["location"]["name"] == "Home"
    _, resolved, _ = invoke_locations(
        tmp_path, {"action": "resolve", "query": "house"}, store=store,
    )
    assert resolved["result"]["location"]["id"] == location_id
    invoke_locations(tmp_path, {
        "action": "save",
        "location": {
            "name": "Hood",
            "latitude": 45.37,
            "longitude": -121.70,
            "time_zone": "America/Los_Angeles",
            "id": HOOD_ID,
        },
    }, store=store)
    _, selected, _ = invoke_locations(
        tmp_path, {"action": "select", "query": "Hood"}, store=store,
    )
    assert selected["result"]["selected_location_id"] == HOOD_ID
    _, deleted, _ = invoke_locations(
        tmp_path, {"action": "delete", "id": HOOD_ID}, store=store,
    )
    assert deleted["result"]["selected_location_id"] == location_id


def test_cli_save_empty_name_is_exit_2(tmp_path: Path) -> None:
    status, payload, _ = invoke_locations(tmp_path, {
        "action": "save",
        "location": {
            "name": "  ",
            "latitude": 34.05,
            "longitude": -118.24,
            "time_zone": "America/Los_Angeles",
        },
    }, store=MemoryLocationStore())
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert payload["error"]["code"] == "invalid_request"


def test_cli_corrupt_is_not_empty_ok(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text('{"schema_version":1,"locations":[', encoding="utf-8")
    status, payload, _ = invoke_locations(
        tmp_path,
        {"action": "list"},
        extra_args=["--locations-path", str(path)],
    )
    assert status == EXIT_FAILURE
    assert payload["ok"] is False
    assert payload["error"]["code"] == "corrupt"
    assert "result" not in payload


def test_cli_unsupported_schema(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text(
        '{"schema_version":0,"locations":[],"selected_location_id":null}\n',
        encoding="utf-8",
    )
    status, payload, _ = invoke_locations(
        tmp_path,
        {"action": "list"},
        extra_args=["--locations-path", str(path)],
    )
    assert status == EXIT_FAILURE
    assert payload["error"]["code"] == "unsupported_schema"


def test_cli_conflict_and_not_found_codes(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    status, conflict, _ = invoke_locations(tmp_path, {
        "action": "save",
        "location": {
            "name": "HOME",
            "latitude": 10.0,
            "longitude": 10.0,
            "time_zone": "America/Los_Angeles",
        },
    }, store=store)
    assert status == EXIT_FAILURE
    assert conflict["error"]["code"] == "conflict"
    status, missing, _ = invoke_locations(
        tmp_path, {"action": "get", "id": HOOD_ID}, store=store,
    )
    assert status == EXIT_FAILURE
    assert missing["error"]["code"] == "not_found"


def test_cli_invalid_action_invalid_request_exit_2(tmp_path: Path) -> None:
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "explode"}, store=MemoryLocationStore(),
    )
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_cli_missing_input_file_is_invalid_request_exit_2(tmp_path: Path) -> None:
    stdout = io.StringIO()
    status = main(
        ["agent.locations", "--input", str(tmp_path / "missing.json")],
        store=MemoryLocationStore(),
        stdout=stdout,
        stderr=io.StringIO(),
    )
    payload = json.loads(stdout.getvalue())
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_cli_path_flag_and_state_dir_env(tmp_path: Path, monkeypatch) -> None:
    custom = tmp_path / "custom" / "locations.json"
    store = build_default_location_store(Namespace(locations_path=str(custom)))
    assert isinstance(store, FileLocationStore)
    assert store.path == custom.expanduser().resolve()
    assert not custom.exists()
    monkeypatch.setenv("ASTRO_HOST_STATE_DIR", str(tmp_path / "state"))
    env_store = build_default_location_store(Namespace(locations_path=None))
    assert env_store.path == (tmp_path / "state" / "locations.json").resolve()


def test_injected_store_creates_no_files(tmp_path: Path) -> None:
    before = {path.resolve() for path in tmp_path.rglob("*")}
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "list"}, store=MemoryLocationStore(),
    )
    assert status == EXIT_OK
    assert payload["ok"] is True
    after = {path.resolve() for path in tmp_path.rglob("*")}
    created = after - before
    assert all(path.name == "request.json" or path.is_dir() for path in created)
    assert not any(path.name == "locations.json" for path in created)
    assert not any(path.name == "weather-cache.json" for path in created)


def test_build_default_location_store_does_not_create_file(tmp_path: Path) -> None:
    path = tmp_path / "custom" / "locations.json"
    store = build_default_location_store(Namespace(locations_path=str(path)))
    assert isinstance(store, FileLocationStore)
    assert not path.exists()
    assert list(tmp_path.iterdir()) == []


def test_locations_cli_does_not_create_weather_cache(tmp_path: Path, monkeypatch) -> None:
    def boom(*_args, **_kwargs):
        raise AssertionError("FileWeatherCache constructed")

    monkeypatch.setattr("astro_host.cli.FileWeatherCache", boom)
    monkeypatch.setattr("astro_host.cli.build_default_service", boom)
    status, payload, _ = invoke_locations(
        tmp_path,
        {"action": "list"},
        extra_args=["--locations-path", str(tmp_path / "locations.json")],
    )
    assert status == EXIT_OK
    assert payload["result"]["locations"] == []
    assert not (tmp_path / "weather-cache.json").exists()


class _RecordingStore(MemoryLocationStore):
    def __init__(self) -> None:
        super().__init__()
        self.calls: list[tuple[str, str]] = []

    def resolve(self, query: str):
        self.calls.append(("resolve", query))
        return super().resolve(query)

    def get(self, id: str):
        self.calls.append(("get", id))
        return super().get(id)

    def select(self, id: str):
        self.calls.append(("select", id))
        return super().select(id)

    def select_query(self, query: str):
        self.calls.append(("select_query", query))
        return super().select_query(query)

    def delete(self, id: str):
        self.calls.append(("delete", id))
        return super().delete(id)

    def delete_query(self, query: str):
        self.calls.append(("delete_query", query))
        return super().delete_query(query)


def test_cli_get_query_uses_single_resolve(tmp_path: Path) -> None:
    store = _RecordingStore()
    store.save(home(id=HOME_ID))
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "get", "query": "Home"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["location"]["id"] == HOME_ID
    assert store.calls == [("resolve", "Home")]


def test_cli_select_query_is_one_atomic_call(tmp_path: Path) -> None:
    store = _RecordingStore()
    store.save(home(id=HOME_ID))
    store.save(home(id=HOOD_ID, name="Bend", latitude=45.37, longitude=-121.70))
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "select", "query": "Bend"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["selected_location_id"] == HOOD_ID
    assert store.calls == [("select_query", "Bend")]


def test_cli_delete_query_is_one_atomic_call(tmp_path: Path) -> None:
    store = _RecordingStore()
    store.save(home(id=HOME_ID))
    store.save(home(id=HOOD_ID, name="Bend", latitude=45.37, longitude=-121.70))
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "delete", "query": "Bend"}, store=store,
    )
    assert status == EXIT_OK
    assert {row["id"] for row in invoke_locations(
        tmp_path, {"action": "list"}, store=store,
    )[1]["result"]["locations"]} == {HOME_ID}
    assert store.calls == [("delete_query", "Bend")]


def test_cli_query_select_does_not_follow_a_later_rename(
    tmp_path: Path, monkeypatch,
) -> None:
    store = MemoryLocationStore()
    store.save(home(id=HOME_ID))
    store.save(home(id=HOOD_ID, name="Bend", latitude=45.37, longitude=-121.70))
    import astro_host.locations as locations_module
    from dataclasses import replace as dc_replace

    real = locations_module._resolve

    def hijack(document, query):
        found = real(document, query)
        swapped = []
        for location in store._document.locations:
            if location.id == HOME_ID:
                swapped.append(dc_replace(location, name="Bend"))
            elif location.id == HOOD_ID:
                swapped.append(dc_replace(location, name="Home"))
            else:
                swapped.append(location)
        store._document = dc_replace(store._document, locations=tuple(swapped))
        return found

    monkeypatch.setattr(locations_module, "_resolve", hijack)
    status, payload, _ = invoke_locations(
        tmp_path, {"action": "select", "query": "Home"}, store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["selected_location_id"] == HOME_ID
    assert payload["result"]["location"]["name"] == "Home"


def test_cli_aliases_null_is_invalid_request(tmp_path: Path) -> None:
    status, payload, _ = invoke_locations(tmp_path, {
        "action": "save",
        "location": {
            "name": "Home",
            "latitude": 34.05,
            "longitude": -118.24,
            "time_zone": "America/Los_Angeles",
            "aliases": None,
        },
    }, store=MemoryLocationStore())
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"
