from __future__ import annotations

import io
import json
from pathlib import Path

from astro_host.cli import EXIT_FAILURE, EXIT_INVALID_REQUEST, EXIT_OK, main
from astro_host.conditions import ConditionsService
from astro_host.locations import FileLocationStore, MemoryLocationStore
from astro_host.places import ObservingLocationService

from support import FakeEngine, FakeProvider, NOW
from test_cli import request_document
from test_locations import home, hood
from test_places import BoomResolver


def invoke_conditions(tmp_path: Path, document: dict[str, object], *, store=None, extra_args=None):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path), *(extra_args or [])],
        service=ConditionsService(
            FakeProvider(), engine=FakeEngine(), atlas_path="test-atlas",
            clock=lambda: NOW,
        ),
        store=store,
        stdout=stdout,
        stderr=stderr,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_explicit_override_beats_selected(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    document = request_document()
    document["location"] = {
        "latitude": 44.0582,
        "longitude": -121.3153,
        "name": "Bend",
        "time_zone_hint": "America/Los_Angeles",
    }
    status, payload, _ = invoke_conditions(tmp_path, document, store=store)
    assert status == EXIT_OK
    assert payload["result"]["location_source"] == "explicit_override"
    assert payload["result"]["request"]["location"]["latitude"] == 44.0582
    assert store.get_selected().name == "Home"


def test_omitted_location_uses_selected(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    saved = store.save(home())
    document = {
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }
    status, payload, _ = invoke_conditions(tmp_path, document, store=store)
    assert status == EXIT_OK
    assert payload["result"]["location_source"] == "selected_saved"
    assert payload["result"]["request"]["location"]["location_id"] == saved.id
    assert payload["result"]["request"]["location"]["latitude"] == saved.latitude


def test_omitted_no_selected_is_typed_error(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    status, payload, _ = invoke_conditions(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        store=store,
    )
    assert status == EXIT_FAILURE
    assert payload["error"]["code"] == "no_selected_location"


def test_omitted_several_none_selected(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    store.save(hood())
    store.clear_selection()
    status, payload, _ = invoke_conditions(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        store=store,
    )
    assert payload["error"]["code"] == "no_selected_location"


def test_omitted_corrupt_is_not_no_selected(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text('{"schema_version":1,"locations":[', encoding="utf-8")
    status, payload, _ = invoke_conditions(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        extra_args=["--locations-path", str(path)],
    )
    assert status == EXIT_FAILURE
    assert payload["error"]["code"] == "corrupt"
    assert payload["error"]["code"] != "no_selected_location"


def test_explicit_invalid_does_not_fall_back(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    document = request_document()
    document["location"]["latitude"] = True
    status, payload, _ = invoke_conditions(tmp_path, document, store=store)
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_location_null_is_invalid_request(tmp_path: Path) -> None:
    document = {
        "location": None,
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }
    status, payload, _ = invoke_conditions(
        tmp_path, document, store=MemoryLocationStore()
    )
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_omitted_location_constructs_store(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    FileLocationStore(path).save(home())
    status, payload, _ = invoke_conditions(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        extra_args=["--locations-path", str(path)],
    )
    assert status == EXIT_OK
    assert payload["result"]["location_source"] == "selected_saved"


def test_selected_path_does_not_use_resolver() -> None:
    store = MemoryLocationStore()
    store.save(home())
    location, source = ObservingLocationService(
        store=store, resolver=BoomResolver()
    ).location_for_conditions(None)
    assert source.value == "selected_saved"
    assert location.time_zone_hint == "America/Los_Angeles"
