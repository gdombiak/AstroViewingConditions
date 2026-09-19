from __future__ import annotations

import io
import json
from pathlib import Path

from astro_host.cli import (
    EXIT_INVALID_REQUEST,
    EXIT_OK,
    main,
    parse_outlook_request,
)
from astro_host.conditions import ConditionsService
from astro_host.errors import InvalidRequestError
from astro_host.locations import MemoryLocationStore

from support import FakeEngine, FakeProvider, NOW
from test_locations import home
import pytest


def invoke(
    tmp_path: Path,
    document: dict[str, object],
    *,
    service=None,
    store=None,
):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    status = main(
        ["agent.outlook", "--input", str(path)],
        service=service or ConditionsService(
            FakeProvider(),
            engine=FakeEngine(),
            atlas_path="test-atlas",
            clock=lambda: NOW,
        ),
        store=store,
        stdout=stdout,
        stderr=stderr,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def _document(**overrides) -> dict[str, object]:
    body = {
        "location": {"latitude": 34.05, "longitude": -118.24},
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }
    body.update(overrides)
    return body


def test_cli_success_envelope(tmp_path: Path) -> None:
    status, payload, stderr = invoke(tmp_path, _document())
    assert status == EXIT_OK
    assert stderr == ""
    assert payload["ok"] is True
    assert payload["operation"] == "agent.outlook"
    assert payload["result"]["status"] == "complete"
    assert payload["result"]["location_source"] == "explicit_override"
    assert payload["result"]["composition_state"] == "resolved"
    assert len(payload["result"]["nights"]) == 3
    assert payload["result"]["best_index"] == 0


def test_cli_selected_location_when_omitted(tmp_path: Path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    status, payload, stderr = invoke(
        tmp_path,
        {"reference_time": NOW.isoformat().replace("+00:00", "Z")},
        store=store,
    )
    assert status == EXIT_OK
    assert stderr == ""
    assert payload["result"]["location_source"] == "selected_saved"


def test_cli_rejects_observing_date(tmp_path: Path) -> None:
    status, payload, _ = invoke(
        tmp_path, _document(observing_date="2026-02-21")
    )
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert payload["error"]["code"] == "invalid_request"
    assert "observing_date" in payload["error"]["message"]


def test_parse_outlook_request_rejects_unknown_fields() -> None:
    with pytest.raises(InvalidRequestError):
        parse_outlook_request({
            "reference_time": "2026-02-20T05:00:00Z",
            "horizon": 5,
        })
