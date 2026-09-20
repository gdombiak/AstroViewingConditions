from __future__ import annotations

import io
import json
from dataclasses import replace
from datetime import date, datetime, timezone

from astro_host.cli import (
    EXIT_INVALID_REQUEST,
    EXIT_OK,
    AGENT_OPERATIONS,
    main,
    parse_sky_facts_request,
)
from astro_host.conditions import ConditionsService
from astro_host.engine import ConditionsEngine
from astro_host.errors import EngineCallError, InvalidRequestError
from astro_host.locations import MemoryLocationStore
from astro_host.models import (
    ActiveNightResolution,
    ConditionsStatus,
    Location,
    SkyFactsRequest,
    TimeZoneAuthority,
)

from support import FakeEngine, FakeProvider, NOW
from test_locations import home
import pytest


LA = Location(
    34.05, -118.24, "Los Angeles", time_zone_hint="America/Los_Angeles"
)
AFTER_MIDNIGHT = datetime(2026, 2, 20, 8, 30, tzinfo=timezone.utc)
SVALBARD = Location(
    78.22, 15.65, "Longyearbyen", time_zone_hint="Europe/Oslo"
)
POLAR_SUMMER = datetime(2026, 6, 21, 12, 0, tzinfo=timezone.utc)


class RecordingProvider(FakeProvider):
    pass


def service(
    *,
    provider=None,
    engine=None,
    atlas_path: str | None = "test-atlas",
    clock=None,
) -> ConditionsService:
    return ConditionsService(
        provider or RecordingProvider(failure=True),
        engine=engine or FakeEngine(),
        atlas_path=atlas_path,
        clock=clock or (lambda: NOW),
    )


def run_sky_facts(
    request: SkyFactsRequest | None = None,
    **kwargs,
):
    return service(**kwargs).sky_facts(request or SkyFactsRequest(LA, NOW))


def issue_codes(result) -> set[str]:
    return {issue.code for issue in result.issues}


def test_selected_saved_location_via_cli(tmp_path) -> None:
    store = MemoryLocationStore()
    saved = store.save(home())
    path = tmp_path / "request.json"
    path.write_text(json.dumps({
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
    }), encoding="utf-8")
    provider = RecordingProvider(failure=True)
    stdout = io.StringIO()
    status = main(
        ["agent.sky_facts", "--input", str(path)],
        service=service(provider=provider),
        store=store,
        stdout=stdout,
        stderr=io.StringIO(),
    )
    payload = json.loads(stdout.getvalue())
    assert status == EXIT_OK
    assert payload["ok"] is True
    assert payload["operation"] == "agent.sky_facts"
    assert payload["result"]["location_source"] == "selected_saved"
    assert payload["result"]["request"]["location"]["location_id"] == saved.id
    assert payload["result"]["request"]["location"]["latitude"] == saved.latitude
    assert provider.calls == []


def test_explicit_location_is_one_use(tmp_path) -> None:
    store = MemoryLocationStore()
    store.save(home())
    path = tmp_path / "request.json"
    path.write_text(json.dumps({
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
        "location": {
            "latitude": 44.0582,
            "longitude": -121.3153,
            "name": "Bend",
            "time_zone_hint": "America/Los_Angeles",
        },
    }), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.sky_facts", "--input", str(path)],
        service=service(),
        store=store,
        stdout=stdout,
        stderr=io.StringIO(),
    )
    payload = json.loads(stdout.getvalue())
    assert status == EXIT_OK
    assert payload["result"]["location_source"] == "explicit_override"
    assert payload["result"]["request"]["location"]["latitude"] == 44.0582
    assert store.get_selected().name == "Home"


def test_explicit_observing_date_selects_that_night() -> None:
    result = run_sky_facts(SkyFactsRequest(
        LA, NOW, observing_date=date(2026, 2, 21)
    ))
    assert result.status is ConditionsStatus.COMPLETE
    assert result.selected_night is not None
    assert result.selected_night.selection == "explicit_date"
    assert result.selected_night.observing_date == date(2026, 2, 21)
    assert result.sun_today is not None
    assert result.sun_today.day == date(2026, 2, 21)
    assert result.sun_tomorrow is not None
    assert result.sun_tomorrow.day == date(2026, 2, 22)


def test_after_midnight_keeps_preceding_observing_night() -> None:
    engine = ConditionsEngine()
    provider = RecordingProvider(failure=True)
    result = service(provider=provider, engine=engine, atlas_path=None).sky_facts(
        SkyFactsRequest(LA, AFTER_MIDNIGHT)
    )
    assert provider.calls == []
    assert result.selected_night is not None
    assert result.selected_night.observing_date == date(2026, 2, 19)
    assert result.selected_night.selection == "active"
    assert result.selected_night.state == "resolved"


def test_light_pollution_makes_zero_provider_calls() -> None:
    provider = RecordingProvider(failure=True)
    result = run_sky_facts(provider=provider)
    assert provider.calls == []
    assert result.light_pollution.available is True
    assert result.light_pollution.modeled_zenith_sky_brightness == 21.0
    assert "observing_quality" not in result.__dataclass_fields__
    assert "night_conditions" not in result.__dataclass_fields__


def test_sun_and_moon_facts_make_zero_provider_calls() -> None:
    provider = RecordingProvider(failure=True)
    result = run_sky_facts(provider=provider)
    assert provider.calls == []
    assert result.sun_today is not None
    assert result.sun_today.sunset is not None
    assert result.sun_today.astronomical_twilight_end is not None
    assert result.moon is not None
    assert result.moon.phase == 0.25
    assert result.moon.illumination == 50
    assert result.moon.rise is not None
    assert result.moon.set is not None
    assert result.selected_night is not None
    assert result.selected_night.night_status == "available"
    assert result.selected_night.astronomical_night_duration_seconds is not None


def test_real_engine_sun_and_moon_without_weather() -> None:
    provider = RecordingProvider(failure=True)
    result = service(
        provider=provider, engine=ConditionsEngine(), atlas_path=None
    ).sky_facts(SkyFactsRequest(LA, NOW))
    assert provider.calls == []
    assert result.sun_today is not None
    assert result.sun_today.sunset is not None
    assert result.moon is not None
    assert 0.0 <= result.moon.phase <= 1.0
    assert 0 <= result.moon.illumination <= 100
    assert result.moon.samples
    assert result.selected_night is not None
    assert result.selected_night.night_status == "available"


def test_no_timezone_does_not_invent_iana_and_still_returns_light_pollution() -> None:
    location = Location(34.05, -118.24, "Nameless")
    provider = RecordingProvider(failure=True)
    result = run_sky_facts(SkyFactsRequest(location, NOW), provider=provider)
    assert provider.calls == []
    assert result.timezone.authority is TimeZoneAuthority.APPROXIMATE
    assert result.timezone.iana_identifier is None
    assert "authoritative_timezone_unavailable" in issue_codes(result)
    assert result.selected_night is None
    assert result.sun_today is None
    assert result.moon is None
    assert result.light_pollution.available is True
    assert result.status is ConditionsStatus.DEGRADED


def test_no_usable_sky_facts_is_unavailable() -> None:
    location = Location(34.05, -118.24, "Nameless")
    result = run_sky_facts(SkyFactsRequest(location, NOW), atlas_path=None)
    assert result.selected_night is None
    assert result.sun_today is None
    assert result.moon is None
    assert result.light_pollution.available is False
    assert result.status is ConditionsStatus.UNAVAILABLE


def test_resolved_valid_window_is_available() -> None:
    result = run_sky_facts()
    assert result.selected_night is not None
    assert result.selected_night.state == "resolved"
    assert result.selected_night.night_status == "available"
    assert result.selected_night.astronomical_night_start is not None
    assert result.selected_night.astronomical_night_end is not None
    assert (
        result.selected_night.astronomical_night_start
        < result.selected_night.astronomical_night_end
    )
    assert result.status is ConditionsStatus.COMPLETE


def test_resolved_inverted_window_is_structural_no_astronomical_night() -> None:
    class InvertedNightEngine(FakeEngine):
        def resolve_active_night(self, **kwargs):
            active = super().resolve_active_night(**kwargs)
            return replace(
                active,
                astronomical_night_start=active.astronomical_night_end,
                astronomical_night_end=active.astronomical_night_start,
            )

    result = run_sky_facts(engine=InvertedNightEngine())
    assert result.selected_night is not None
    assert result.selected_night.state == "resolved"
    assert result.selected_night.night_status == "no_astronomical_night"
    assert result.selected_night.astronomical_night_duration_seconds is None
    assert result.status is ConditionsStatus.COMPLETE
    assert result.light_pollution.available is True


def test_unresolved_active_night_is_unavailable_not_no_astronomical_night() -> None:
    class UnresolvedNightEngine(FakeEngine):
        def resolve_active_night(self, **kwargs):
            return ActiveNightResolution(
                state="unavailable",
                observing_date=None,
                observing_day_start=None,
                astronomical_night_start=None,
                astronomical_night_end=None,
                day_index=None,
                day_offset=None,
            )

    result = run_sky_facts(engine=UnresolvedNightEngine())
    assert result.selected_night is not None
    assert result.selected_night.state == "unavailable"
    assert result.selected_night.night_status == "unavailable"
    assert result.selected_night.astronomical_night_start is None
    assert result.selected_night.astronomical_night_end is None
    assert result.light_pollution.available is True
    assert result.status is ConditionsStatus.DEGRADED


def test_missing_twilight_does_not_count_as_structural_no_night() -> None:
    class MissingTwilightEngine(FakeEngine):
        def sun_events(self, location, *, day, start, end):
            return replace(
                super().sun_events(location, day=day, start=start, end=end),
                astronomical_twilight_begin=None,
                astronomical_twilight_end=None,
            )

    result = run_sky_facts(engine=MissingTwilightEngine())
    assert result.selected_night is not None
    assert result.selected_night.state == "unavailable"
    assert result.selected_night.night_status == "unavailable"
    assert result.sun_today is not None
    assert result.light_pollution.available is True
    assert result.status is ConditionsStatus.DEGRADED


def test_polar_summer_preserves_structural_or_unresolved_night() -> None:
    provider = RecordingProvider(failure=True)
    result = service(
        provider=provider, engine=ConditionsEngine(), atlas_path=None
    ).sky_facts(SkyFactsRequest(SVALBARD, POLAR_SUMMER))
    assert provider.calls == []
    assert result.selected_night is not None
    assert result.sun_today is not None
    assert result.status is not ConditionsStatus.UNAVAILABLE
    if result.selected_night.state == "resolved":
        assert result.selected_night.night_status == "no_astronomical_night"
    else:
        assert result.selected_night.night_status == "unavailable"


def test_polar_summer_explicit_date_is_structural_no_astronomical_night() -> None:
    provider = RecordingProvider(failure=True)
    result = service(
        provider=provider, engine=ConditionsEngine(), atlas_path=None
    ).sky_facts(SkyFactsRequest(
        SVALBARD, POLAR_SUMMER, observing_date=date(2026, 6, 21)
    ))
    assert provider.calls == []
    assert result.selected_night is not None
    assert result.selected_night.selection == "explicit_date"
    assert result.selected_night.state == "resolved"
    assert result.selected_night.night_status == "no_astronomical_night"


def test_atlas_no_data_is_represented() -> None:
    class EmptyAtlas(FakeEngine):
        def lookup_brightness(self, atlas_path, location):
            return None

    result = run_sky_facts(engine=EmptyAtlas())
    assert result.light_pollution.available is False
    assert result.light_pollution.modeled_zenith_sky_brightness is None
    assert "light_pollution_no_data" in issue_codes(result)
    assert result.status is ConditionsStatus.DEGRADED
    assert result.sun_today is not None


def test_atlas_resource_failure_is_represented() -> None:
    class BrokenAtlas(FakeEngine):
        def lookup_brightness(self, atlas_path, location):
            raise EngineCallError(
                "light_pollution.lookup", "atlas_invalid", "bad atlas"
            )

    result = run_sky_facts(engine=BrokenAtlas())
    assert result.light_pollution.available is False
    assert "light_pollution_resource_failure" in issue_codes(result)
    assert result.status is ConditionsStatus.DEGRADED
    assert result.moon is not None


def test_force_refresh_is_rejected() -> None:
    with pytest.raises(InvalidRequestError, match="force_refresh"):
        parse_sky_facts_request({
            "reference_time": "2026-02-20T05:00:00Z",
            "force_refresh": True,
        })


def test_cli_rejects_force_refresh(tmp_path) -> None:
    path = tmp_path / "request.json"
    path.write_text(json.dumps({
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
        "location": {"latitude": 34.05, "longitude": -118.24},
        "force_refresh": True,
    }), encoding="utf-8")
    stdout = io.StringIO()
    status = main(
        ["agent.sky_facts", "--input", str(path)],
        service=service(),
        stdout=stdout,
        stderr=io.StringIO(),
    )
    payload = json.loads(stdout.getvalue())
    assert status == EXIT_INVALID_REQUEST
    assert payload["ok"] is False
    assert "force_refresh" in payload["error"]["message"]


def test_result_omits_scores_and_weather() -> None:
    result = run_sky_facts()
    payload = json.loads(json.dumps({
        "status": result.status.value,
        "light_pollution": {
            "modeled_zenith_sky_brightness": (
                result.light_pollution.modeled_zenith_sky_brightness
            ),
            "available": result.light_pollution.available,
        },
    }))
    assert "score" not in payload
    assert result.moon is not None
    assert not hasattr(result, "weather")
    assert "night_conditions" not in result.__dataclass_fields__
    assert "observing_quality" not in result.__dataclass_fields__
    assert "force_refresh" not in result.request.__dataclass_fields__


def test_existing_operations_remain_listed() -> None:
    assert AGENT_OPERATIONS[:7] == (
        "agent.batch_compare",
        "agent.conditions",
        "agent.locations",
        "agent.places",
        "agent.equipment",
        "agent.recommendations",
        "agent.outlook",
    )
    assert "agent.sky_facts" in AGENT_OPERATIONS
