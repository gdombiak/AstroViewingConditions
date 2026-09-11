from __future__ import annotations

import io
import json
from pathlib import Path

import pytest

from astro_host.cli import (
    EXIT_FAILURE,
    EXIT_INVALID_REQUEST,
    EXIT_OK,
    main,
    parse_recommendations_request,
)
from astro_host.conditions import ConditionsService
from astro_host.engine import RecommendationEngine
from astro_host.equipment import MemoryEquipmentStore
from astro_host.errors import EngineCallError, InvalidRequestError
from astro_host.locations import MemoryLocationStore
from astro_host.models import EquipmentSelectionMode

from support import NOW
from test_engine_composition import RawOpenMeteoProvider
from test_equipment import S30_ID, s30
from test_locations import home


def invoke(
    tmp_path: Path,
    document: dict[str, object],
    *,
    service=None,
    store=None,
    equipment_store=None,
    recommendation_engine=None,
):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    status = main(
        ["agent.recommendations", "--input", str(path)],
        service=service,
        store=store,
        equipment_store=equipment_store,
        recommendation_engine=recommendation_engine,
        stdout=stdout,
        stderr=stderr,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def _service():
    return ConditionsService(
        RawOpenMeteoProvider(), atlas_path=None, clock=lambda: NOW
    )


def _document(**overrides) -> dict[str, object]:
    body = {
        "location": {"latitude": 34.05, "longitude": -118.24},
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }
    body.update(overrides)
    return body


def test_cli_success_envelope(tmp_path: Path) -> None:
    status, payload, stderr = invoke(
        tmp_path, _document(), service=_service(), equipment_store=MemoryEquipmentStore()
    )
    assert status == EXIT_OK
    assert stderr == ""
    assert payload["ok"] is True
    assert payload["operation"] == "agent.recommendations"
    assert payload["result"]["status"] in {"complete", "degraded"}
    assert payload["result"]["equipment"]["minimum_fit"] == "any"
    assert len(payload["result"]["recommendations"]) <= 5


def test_cli_unavailable_is_ok_true(tmp_path: Path) -> None:
    from support import FakeEngine, FakeProvider

    service = ConditionsService(
        FakeProvider(empty=True),
        engine=FakeEngine(),
        atlas_path="test-atlas",
        clock=lambda: NOW,
    )
    status, payload, _ = invoke(
        tmp_path, _document(), service=service, equipment_store=MemoryEquipmentStore()
    )
    assert status == EXIT_OK
    assert payload["ok"] is True
    assert payload["result"]["status"] == "unavailable"
    assert payload["result"]["recommendations"] == []


def test_cli_engine_failure_is_ok_false(tmp_path: Path) -> None:
    class Boom(RecommendationEngine):
        def solar_system(self):
            raise EngineCallError(
                "catalog.solar_system", "validation", "injected catalog failure"
            )

    status, payload, _ = invoke(
        tmp_path,
        _document(),
        service=_service(),
        equipment_store=MemoryEquipmentStore(),
        recommendation_engine=Boom(),
    )
    assert status == EXIT_FAILURE
    assert payload["ok"] is False
    assert payload["error"]["code"] == "engine_failure"
    assert payload["error"]["details"]["capability"] == "catalog.solar_system"
    assert payload["error"]["details"]["engine_code"] == "validation"


def test_cli_unknown_key_invalid_request(tmp_path: Path) -> None:
    status, payload, _ = invoke(tmp_path, {**_document(), "top_n": 5})
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


@pytest.mark.parametrize("value", [[], {}, 1, True, None, "prettyGood"])
def test_parse_minimum_fit_rejects_non_enum(value) -> None:
    with pytest.raises(InvalidRequestError, match="minimum_fit"):
        parse_recommendations_request({
            "reference_time": NOW.isoformat().replace("+00:00", "Z"),
            "minimum_fit": value,
        })


@pytest.mark.parametrize("value", [[], {}, 1, True, None, "prettyGood"])
def test_cli_invalid_minimum_fit_is_invalid_request(tmp_path: Path, value) -> None:
    status, payload, _ = invoke(tmp_path, {**_document(), "minimum_fit": value})
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert payload["error"]["code"] == "invalid_request"


def test_cli_equipment_mode_item_invalid_request(tmp_path: Path) -> None:
    status, payload, _ = invoke(
        tmp_path, {**_document(), "equipment": {"mode": "item"}}
    )
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"


def test_cli_omitted_location_uses_selected(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    saved = store.save(home())
    status, payload, _ = invoke(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        service=_service(),
        store=store,
        equipment_store=MemoryEquipmentStore(),
    )
    assert status == EXIT_OK
    assert payload["result"]["location_source"] == "selected_saved"
    assert payload["result"]["location"]["location_id"] == saved.id
    assert store.get_selected().id == saved.id


def test_cli_does_not_write_equipment_store(tmp_path: Path) -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    before = store.load()
    status, payload, _ = invoke(
        tmp_path,
        {**_document(), "equipment": {"id": S30_ID}},
        service=_service(),
        equipment_store=store,
    )
    assert status == EXIT_OK
    assert payload["result"]["equipment"]["override_applied"] is True
    assert store.load() == before
    assert store.load().selection.mode is EquipmentSelectionMode.ALL_SAVED
