from __future__ import annotations

import io
import json
from pathlib import Path

from astro_host.cli import EXIT_FAILURE, EXIT_INVALID_REQUEST, EXIT_OK, main
from astro_host.errors import PlaceProviderError
from astro_host.models import (
    PlaceProviderResult,
    ProviderFailure,
    ProviderFailureKind,
)

from test_open_meteo_geocoding import portland_me, portland_or
from test_places import FakePlaceResolver, record_from, usable_candidate


def invoke_places(tmp_path: Path, document: dict[str, object], *, resolver=None):
    path = tmp_path / "request.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    status = main(
        ["agent.places", "--input", str(path)],
        resolver=resolver,
        stdout=stdout,
        stderr=stderr,
    )
    return status, json.loads(stdout.getvalue()), stderr.getvalue()


def test_cli_places_unique_success(tmp_path: Path) -> None:
    resolver = FakePlaceResolver(PlaceProviderResult(
        "open_meteo", (record_from(portland_or()),), 1
    ))
    status, payload, stderr = invoke_places(
        tmp_path, {"action": "resolve", "query": "Portland"}, resolver=resolver
    )
    assert status == EXIT_OK
    assert stderr == ""
    assert payload["ok"] is True
    assert payload["operation"] == "agent.places"
    assert payload["result"]["action"] == "resolve"
    assert payload["result"]["status"] == "unique"
    assert payload["result"]["candidates"][0]["admin1"] == "Oregon"
    assert payload["result"]["attribution"]["provider"] == "open_meteo"
    assert resolver.calls == ["Portland"]


def test_cli_places_ambiguous_and_not_found_are_success(tmp_path: Path) -> None:
    status, ambiguous, _ = invoke_places(
        tmp_path,
        {"action": "resolve", "query": "Portland"},
        resolver=FakePlaceResolver(PlaceProviderResult(
            "open_meteo",
            (record_from(portland_or()), record_from(portland_me())),
            1,
        )),
    )
    assert status == EXIT_OK
    assert ambiguous["result"]["status"] == "ambiguous"
    assert len(ambiguous["result"]["candidates"]) == 2

    status, missing, _ = invoke_places(
        tmp_path,
        {"action": "resolve", "query": "Narnia"},
        resolver=FakePlaceResolver(PlaceProviderResult("open_meteo", (), 1)),
    )
    assert status == EXIT_OK
    assert missing["result"]["status"] == "not_found"
    assert missing["result"]["candidates"] == []


def test_cli_places_provider_failure(tmp_path: Path) -> None:
    status, payload, _ = invoke_places(
        tmp_path,
        {"action": "resolve", "query": "Portland"},
        resolver=FakePlaceResolver(error=PlaceProviderError(ProviderFailure(
            ProviderFailureKind.HTTP, "Open-Meteo returned HTTP 503", 3, 503
        ))),
    )
    assert status == EXIT_FAILURE
    assert payload["ok"] is False
    assert payload["error"]["code"] == "provider_failure"


def test_cli_places_unique_unusable_timezone(tmp_path: Path) -> None:
    status, payload, _ = invoke_places(
        tmp_path,
        {"action": "resolve", "query": "Portland"},
        resolver=FakePlaceResolver(PlaceProviderResult(
            "open_meteo", (record_from(portland_or(), timezone=None),), 1
        )),
    )
    assert status == EXIT_FAILURE
    assert payload["error"]["code"] == "invalid_provider_timezone"


def test_cli_places_invalid_action_and_empty_query(tmp_path: Path) -> None:
    status, payload, _ = invoke_places(tmp_path, {"action": "save", "query": "Portland"})
    assert status == EXIT_INVALID_REQUEST
    assert payload["error"]["code"] == "invalid_request"
    status, payload, _ = invoke_places(tmp_path, {"action": "resolve", "query": "  "})
    assert status == EXIT_INVALID_REQUEST


def test_cli_places_does_not_construct_location_store(tmp_path: Path, monkeypatch) -> None:
    def boom(*_args, **_kwargs):
        raise AssertionError("FileLocationStore constructed")

    monkeypatch.setattr("astro_host.cli.FileLocationStore", boom)
    status, payload, _ = invoke_places(
        tmp_path,
        {"action": "resolve", "query": "Portland"},
        resolver=FakePlaceResolver(PlaceProviderResult(
            "open_meteo", (record_from(portland_or()),), 1
        )),
    )
    assert status == EXIT_OK
    assert payload["ok"] is True


def test_save_from_candidate_does_not_construct_resolver(tmp_path: Path, monkeypatch) -> None:
    def boom(*_args, **_kwargs):
        raise AssertionError("OpenMeteoPlaceResolver constructed")

    monkeypatch.setattr("astro_host.cli.OpenMeteoPlaceResolver", boom)
    from astro_host.locations import MemoryLocationStore
    from test_cli_locations import invoke_locations

    candidate = usable_candidate()
    document = {
        "action": "save_from_candidate",
        "candidate": {
            "provider": candidate.provider,
            "provider_place_id": candidate.provider_place_id,
            "name": candidate.name,
            "display_name": candidate.display_name,
            "latitude": candidate.latitude,
            "longitude": candidate.longitude,
            "time_zone": candidate.time_zone,
            "usable": True,
            "unusable_reason": None,
            "elevation_m": candidate.elevation_m,
            "country": candidate.country,
            "admin1": candidate.admin1,
            "admin2": candidate.admin2,
            "country_code": candidate.country_code,
            "feature_code": candidate.feature_code,
            "population": candidate.population,
            "rank": 1,
        },
        "select": True,
    }
    status, payload, _ = invoke_locations(
        tmp_path, document, store=MemoryLocationStore()
    )
    assert status == EXIT_OK
    assert payload["result"]["action"] == "save_from_candidate"
    assert payload["result"]["location"]["name"] == "Portland"
    assert payload["result"]["selected_location_id"] == payload["result"]["location"]["id"]
