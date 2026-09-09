from __future__ import annotations

import io
import json
import math

import pytest

from astro_host.cli import EXIT_FAILURE, EXIT_INVALID_REQUEST, EXIT_OK, main
from astro_host.conditions import ConditionsService

from support import FakeEngine, FakeProvider, NOW


def request_document() -> dict[str, object]:
    return {
        "location": {"latitude": 34.05, "longitude": -118.24},
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }


def invoke(tmp_path, provider: FakeProvider):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(request_document()), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    service = ConditionsService(
        provider,
        engine=FakeEngine(),
        atlas_path="test-atlas",
        clock=lambda: NOW,
    )
    status = main(
        ["agent.conditions", "--input", str(path)],
        service=service,
        stdout=stdout,
        stderr=stderr,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_cli_complete_success_envelope(tmp_path) -> None:
    status, payload, stderr = invoke(tmp_path, FakeProvider())
    assert status == EXIT_OK
    assert stderr == ""
    assert payload["ok"] is True
    assert payload["operation"] == "agent.conditions"
    assert payload["result"]["status"] == "complete"
    assert payload["result"]["generated_at"] == "2026-02-20T05:00:00Z"


def test_cli_degraded_and_unavailable_are_structured_successes(tmp_path) -> None:
    _, degraded, _ = invoke(tmp_path, FakeProvider(partial=True))
    assert degraded["ok"] is True
    assert degraded["result"]["status"] == "degraded"

    status, unavailable, _ = invoke(tmp_path, FakeProvider(empty=True))
    assert status == EXIT_OK
    assert unavailable["ok"] is True
    assert unavailable["result"]["status"] == "unavailable"


def test_cli_invalid_request_has_distinct_exit_status(tmp_path) -> None:
    path = tmp_path / "bad.json"
    path.write_text(json.dumps({"reference_time": "not-an-instant"}), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path)],
        stdout=stdout,
        stderr=io.StringIO(),
    )
    payload = json.loads(stdout.getvalue())
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert payload["error"]["code"] == "invalid_request"


def test_cli_rejects_boolean_coordinates(tmp_path) -> None:
    document = request_document()
    document["location"]["latitude"] = True
    path = tmp_path / "bad-coordinate.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path)],
        stdout=stdout,
        stderr=io.StringIO(),
    )
    assert status == EXIT_INVALID_REQUEST


@pytest.mark.parametrize(
    "elevation",
    [pytest.param(math.nan, id="nan"), pytest.param(math.inf, id="infinity")],
)
def test_cli_rejects_non_finite_elevation_with_one_json_envelope(
    tmp_path, elevation,
) -> None:
    document = request_document()
    document["location"]["elevation_m"] = elevation
    path = tmp_path / "non-finite-elevation.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path)],
        service=ConditionsService(
            FakeProvider(), engine=FakeEngine(), clock=lambda: NOW
        ),
        stdout=stdout,
        stderr=io.StringIO(),
    )

    payload = json.loads(stdout.getvalue())
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert payload["error"]["code"] == "invalid_request"


def test_cli_accepts_finite_elevation(tmp_path) -> None:
    document = request_document()
    document["location"]["elevation_m"] = 123.5
    path = tmp_path / "finite-elevation.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path)],
        service=ConditionsService(
            FakeProvider(), engine=FakeEngine(), atlas_path="test-atlas",
            clock=lambda: NOW,
        ),
        stdout=stdout,
        stderr=io.StringIO(),
    )

    payload = json.loads(stdout.getvalue())
    assert status == EXIT_OK
    assert payload["result"]["request"]["location"]["elevation_m"] == 123.5


class NonFiniteResultService:
    async def conditions(self, request):
        return {"non_finite": math.nan}


def test_cli_serialization_failure_emits_one_complete_envelope(tmp_path) -> None:
    path = tmp_path / "request.json"
    path.write_text(json.dumps(request_document()), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.conditions", "--input", str(path)],
        service=NonFiniteResultService(),
        stdout=stdout,
        stderr=io.StringIO(),
    )

    payload = json.loads(stdout.getvalue())
    assert status == EXIT_FAILURE
    assert payload["ok"] is False
    assert payload["error"]["code"] == "host_failure"
