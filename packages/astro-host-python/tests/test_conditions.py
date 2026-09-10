from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import date, timedelta
import json

import astro_engine.observing_night as observing_night_module

from astro_host.cache import MemoryWeatherCache, WeatherCache
from astro_host.conditions import ConditionsService
from astro_host.weather_cache_file import FileWeatherCache
from astro_host.engine import ConditionsEngine
from astro_host.errors import EngineCallError
from astro_host.models import (
    ConditionsRequest,
    ConditionsStatus,
    Location,
    PayloadDiagnostics,
    PayloadState,
    WeatherQuery,
    WeatherSnapshot,
)
import astro_host.timezones as timezone_module

from support import FakeEngine, FakeProvider, NOW, hourly_rows


LOCATION = Location(34.05, -118.24)


def run_conditions(
    provider: FakeProvider,
    *,
    engine: FakeEngine | None = None,
    request: ConditionsRequest | None = None,
    cache: WeatherCache | None = None,
    stale_age: timedelta | None = None,
    atlas_path: str | None = "test-atlas",
):
    service = ConditionsService(
        provider,
        engine=engine or FakeEngine(),
        cache=cache,
        stale_on_error_max_age=stale_age,
        atlas_path=atlas_path,
        clock=lambda: NOW,
    )
    return asyncio.run(service.conditions(
        request or ConditionsRequest(LOCATION, NOW)
    ))


def issue_codes(result) -> set[str]:
    return {issue.code for issue in result.issues}


def test_live_complete_active_night_composes_all_required_facts() -> None:
    provider = FakeProvider()
    engine = FakeEngine()
    result = run_conditions(provider, engine=engine)

    assert result.status is ConditionsStatus.COMPLETE
    assert result.selected_night is not None
    assert result.selected_night.selection == "active"
    assert result.night_conditions is not None
    assert result.night_conditions.public_score == 90
    assert result.night_conditions.best_window is not None
    assert result.night_conditions.cloud_timing == "none"
    assert result.observing_quality is not None
    assert result.observing_quality.light_pollution_available
    assert result.astronomy is not None
    assert engine.moon_times == tuple(row.time for row in result.weather.hourly)


def test_live_partial_is_degraded_and_empty_is_unavailable() -> None:
    partial = run_conditions(FakeProvider(partial=True))
    assert partial.status is ConditionsStatus.DEGRADED
    assert "partial_weather_payload" in issue_codes(partial)

    empty = run_conditions(FakeProvider(empty=True))
    assert empty.status is ConditionsStatus.UNAVAILABLE
    assert "empty_weather_payload" in issue_codes(empty)


class FlipEmptyThenFullProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.n = 0

    async def fetch(self, query):
        self.n += 1
        self.empty = self.n == 1
        return await super().fetch(query)


def test_empty_snapshot_is_not_cached_for_fresh_reuse() -> None:
    cache = MemoryWeatherCache()
    provider = FlipEmptyThenFullProvider()

    first = run_conditions(provider, cache=cache)
    second = run_conditions(provider, cache=cache)

    assert first.status is ConditionsStatus.UNAVAILABLE
    assert "empty_weather_payload" in issue_codes(first)
    assert provider.n == 2
    assert second.status is ConditionsStatus.COMPLETE
    assert second.night_conditions is not None


def test_provider_failure_without_cache_is_unavailable() -> None:
    result = run_conditions(FakeProvider(failure=True))
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert "weather_provider_failure" in issue_codes(result)
    assert result.acquisition.provider_attempt.failure is not None
    assert result.acquisition.provider_attempt.failure.attempt_count == 3


class DecodeFailureEngine(FakeEngine):
    def decode_weather(self, payload):
        raise EngineCallError(
            "weather.decode",
            "validation",
            "decoder rejected payload",
            {"field": "hourly.time"},
        )


def test_engine_failure_stays_separate_from_provider_failure() -> None:
    result = run_conditions(FakeProvider(), engine=DecodeFailureEngine())
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert result.acquisition.provider_attempt.state.value == "succeeded"
    assert result.acquisition.provider_attempt.failure is None
    issue = next(issue for issue in result.issues if issue.code == "engine_error")
    assert issue.details == {
        "capability": "weather.decode",
        "engine_code": "validation",
        "field": "hourly.time",
    }


def test_timezone_catalogue_failure_is_structured_and_distinct(
    monkeypatch,
) -> None:
    def fail_catalogue():
        raise OSError("timezone catalogue unavailable")

    monkeypatch.setattr(
        timezone_module, "allowed_timezone_identifiers", fail_catalogue
    )
    provider = FakeProvider()
    result = run_conditions(provider)
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert len(provider.calls) == 1
    assert result.timezone.authority.value == "unavailable"
    assert result.timezone.attempts[0].state.value == "failed"
    assert result.timezone.attempts[0].source.value == "weather_provider"
    assert result.acquisition.provider_attempt.state.value == "succeeded"
    assert issue_codes(result) == {"timezone_catalog_failure"}
    assert "invalid_timezone_hint" not in issue_codes(result)
    assert "authoritative_timezone_unavailable" not in issue_codes(result)


def test_real_contracts_root_failure_cannot_break_unavailable_result(
    monkeypatch, tmp_path,
) -> None:
    monkeypatch.setenv("CONTRACTS_ROOT", str(tmp_path / "missing-contracts"))
    monkeypatch.setattr(observing_night_module, "_ALLOWED_TIMEZONES", None)
    service = ConditionsService(
        FakeProvider(),
        engine=ConditionsEngine(),
        clock=lambda: NOW,
    )
    request = ConditionsRequest(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        NOW,
    )

    result = asyncio.run(service.conditions(request))

    assert result.status is ConditionsStatus.UNAVAILABLE
    assert result.engine_semver == "unknown"
    assert issue_codes(result) == {"timezone_catalog_failure"}
    issue = result.issues[0]
    assert issue.details["error_type"] == "ContractsRootError"


def test_available_contracts_report_real_engine_semver() -> None:
    service = ConditionsService(
        FakeProvider(failure=True),
        engine=ConditionsEngine(),
        clock=lambda: NOW,
    )
    request = ConditionsRequest(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        NOW,
    )

    result = asyncio.run(service.conditions(request))

    assert result.status is ConditionsStatus.UNAVAILABLE
    assert result.engine_semver == "1.0.0"
    assert issue_codes(result) == {"weather_provider_failure"}


def test_stale_fallback_is_disabled_by_default_and_degraded_when_enabled() -> None:
    cache = MemoryWeatherCache()
    stale = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2),
        provider="open_meteo",
        fetched_at=NOW - timedelta(hours=2),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 48),
    )
    asyncio.run(cache.put(stale))

    disabled = run_conditions(FakeProvider(failure=True), cache=cache)
    assert disabled.status is ConditionsStatus.UNAVAILABLE

    enabled = run_conditions(
        FakeProvider(failure=True),
        cache=cache,
        stale_age=timedelta(hours=3),
    )
    assert enabled.status is ConditionsStatus.DEGRADED
    assert "stale_weather_fallback" in issue_codes(enabled)
    assert enabled.acquisition.snapshot is not None
    assert enabled.acquisition.snapshot.freshness.value == "stale"


def test_force_refresh_bypasses_a_fresh_cache_entry() -> None:
    cache = MemoryWeatherCache()
    fresh = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2),
        provider="open_meteo",
        fetched_at=NOW - timedelta(minutes=5),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 48),
    )
    asyncio.run(cache.put(fresh))
    provider = FakeProvider()
    result = run_conditions(
        provider,
        cache=cache,
        request=ConditionsRequest(LOCATION, NOW, force_refresh=True),
    )
    assert result.status is ConditionsStatus.COMPLETE
    assert len(provider.calls) == 1
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.origin.value == "live"


def test_explicit_observing_date_plans_through_following_morning() -> None:
    provider = FakeProvider()
    request = ConditionsRequest(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        NOW,
        observing_date=date(2026, 2, 20),
    )
    result = run_conditions(provider, request=request)
    assert result.status is ConditionsStatus.COMPLETE
    assert provider.calls[0].forecast_days == 3
    assert result.selected_night is not None
    assert result.selected_night.selection == "explicit_date"
    assert result.selected_night.observing_date == date(2026, 2, 20)


def test_generic_service_does_not_impose_open_meteo_horizon() -> None:
    provider = FakeProvider()
    request = ConditionsRequest(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        NOW,
        observing_date=date(2026, 3, 7),
    )
    result = run_conditions(provider, request=request)
    assert provider.calls[0].forecast_days == 18
    assert result.status is ConditionsStatus.COMPLETE


def test_generic_empty_payload_issue_does_not_name_open_meteo() -> None:
    result = run_conditions(FakeProvider(empty=True))
    issue = next(
        issue for issue in result.issues if issue.code == "empty_weather_payload"
    )
    assert "Open-Meteo" not in issue.message


def test_provider_timezone_is_required_when_hint_is_absent() -> None:
    result = run_conditions(FakeProvider(timezone_name=None))
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert result.timezone.iana_identifier is None
    assert "authoritative_timezone_unavailable" in issue_codes(result)


def test_no_rows_in_exact_night_window_is_unavailable() -> None:
    result = run_conditions(
        FakeProvider(), engine=FakeEngine(window_shift_days=10)
    )
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert "required_weather_unavailable" in issue_codes(result)


def test_half_open_window_and_moon_timestamps_match_retained_rows() -> None:
    engine = FakeEngine()
    result = run_conditions(FakeProvider(), engine=engine)
    assert result.weather is not None
    assert result.selected_night is not None
    window = result.selected_night.forecast_window
    assert window is not None
    times = tuple(row.time for row in result.weather.hourly)
    assert times[0] == window.start
    assert times[-1] < window.end
    assert window.end not in times
    assert engine.moon_times == times


class FailingLightPollutionEngine(FakeEngine):
    def lookup_brightness(self, atlas_path, location):
        raise EngineCallError("light_pollution.lookup", "atlas_invalid", "bad atlas")


def test_optional_light_pollution_failure_retains_night_conditions() -> None:
    result = run_conditions(FakeProvider(), engine=FailingLightPollutionEngine())
    assert result.status is ConditionsStatus.DEGRADED
    assert result.night_conditions is not None
    assert result.observing_quality is not None
    assert not result.observing_quality.light_pollution_available
    assert "light_pollution_resource_failure" in issue_codes(result)


def test_absent_optional_atlas_uses_observing_quality_fallback() -> None:
    result = run_conditions(FakeProvider(), atlas_path=None)
    assert result.status is ConditionsStatus.DEGRADED
    assert result.night_conditions is not None
    assert result.observing_quality is not None
    assert result.observing_quality.score == result.night_conditions.public_score
    assert "light_pollution_unavailable" in issue_codes(result)


class MissingTwilightEngine(FakeEngine):
    def sun_events(self, location, *, day, start, end):
        return replace(
            super().sun_events(location, day=day, start=start, end=end),
            astronomical_twilight_end=None,
        )


def test_missing_required_twilight_is_unavailable_without_approximation() -> None:
    result = run_conditions(FakeProvider(), engine=MissingTwilightEngine())
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert "required_twilight_unavailable" in issue_codes(result)


class MissingUnrelatedExplicitSunEngine(FakeEngine):
    def sun_events(self, location, *, day, start, end):
        result = super().sun_events(location, day=day, start=start, end=end)
        if day == date(2026, 2, 19):
            return replace(result, astronomical_twilight_end=None)
        return result


def test_explicit_date_ignores_unrelated_missing_sun_row() -> None:
    request = ConditionsRequest(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        NOW,
        observing_date=date(2026, 2, 20),
    )
    result = run_conditions(
        FakeProvider(), engine=MissingUnrelatedExplicitSunEngine(), request=request
    )
    assert result.status is ConditionsStatus.COMPLETE
    assert result.selected_night is not None
    assert result.selected_night.observing_date == date(2026, 2, 20)
    assert "required_twilight_unavailable" not in issue_codes(result)


def test_file_cache_reuses_home_across_services_and_keeps_other_locations(
    tmp_path,
) -> None:
    path = tmp_path / "weather-cache.json"
    cache = FileWeatherCache(path)
    home_provider = FakeProvider()
    first = run_conditions(home_provider, cache=cache)
    assert first.status is ConditionsStatus.COMPLETE
    assert home_provider.calls
    assert first.acquisition.snapshot is not None
    assert first.acquisition.snapshot.origin.value == "live"

    hood = Location(45.37, -121.70, time_zone_hint="America/Los_Angeles")
    hood_provider = FakeProvider()
    hood_result = run_conditions(
        hood_provider,
        cache=cache,
        request=ConditionsRequest(hood, NOW),
    )
    assert hood_result.status is ConditionsStatus.COMPLETE
    assert hood_provider.calls

    reuse_provider = FakeProvider()
    reused = run_conditions(reuse_provider, cache=cache)
    assert reused.status is ConditionsStatus.COMPLETE
    assert reuse_provider.calls == []
    assert reused.acquisition.snapshot is not None
    assert reused.acquisition.snapshot.origin.value == "cache"

    hood_again = FakeProvider()
    hood_reused = run_conditions(
        hood_again,
        cache=cache,
        request=ConditionsRequest(hood, NOW),
    )
    assert hood_again.calls == []
    assert hood_reused.acquisition.snapshot is not None
    assert hood_reused.acquisition.snapshot.origin.value == "cache"


def test_file_cache_does_not_persist_empty_snapshots(tmp_path) -> None:
    path = tmp_path / "weather-cache.json"
    result = run_conditions(FakeProvider(empty=True), cache=FileWeatherCache(path))
    assert result.status is ConditionsStatus.UNAVAILABLE
    assert not path.exists()


def test_file_cache_persists_partial_with_rows(tmp_path) -> None:
    path = tmp_path / "weather-cache.json"
    result = run_conditions(FakeProvider(partial=True), cache=FileWeatherCache(path))
    assert result.status is ConditionsStatus.DEGRADED
    loaded = asyncio.run(FileWeatherCache(path).get(
        WeatherQuery(LOCATION, 1), provider="open_meteo",
    ))
    assert loaded is not None
    assert loaded.hourly
    assert loaded.diagnostics.state is PayloadState.PARTIAL


def test_file_cache_oversized_number_does_not_host_fail(tmp_path) -> None:
    path = tmp_path / "weather-cache.json"
    first = run_conditions(FakeProvider(), cache=FileWeatherCache(path))
    assert first.status is ConditionsStatus.COMPLETE
    document = json.loads(path.read_text(encoding="utf-8"))
    document["entries"][0]["hourly"][0]["wind_speed"] = 10 ** 400
    path.write_text(json.dumps(document), encoding="utf-8")
    provider = FakeProvider()
    result = run_conditions(provider, cache=FileWeatherCache(path))
    assert result.status is ConditionsStatus.COMPLETE
    assert provider.calls


def test_file_cache_stale_fallback_survives_new_instance(tmp_path) -> None:
    path = tmp_path / "weather-cache.json"
    stale = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2),
        provider="open_meteo",
        fetched_at=NOW - timedelta(hours=2),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 48),
    )
    asyncio.run(FileWeatherCache(path).put(stale))
    result = run_conditions(
        FakeProvider(failure=True),
        cache=FileWeatherCache(path),
        stale_age=timedelta(hours=3),
    )
    assert result.status is ConditionsStatus.DEGRADED
    assert "stale_weather_fallback" in issue_codes(result)
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.freshness.value == "stale"


def test_file_cache_stale_fallback_ignores_future_richer_snapshot(tmp_path) -> None:
    path = tmp_path / "weather-cache.json"
    older = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2),
        provider="open_meteo",
        fetched_at=NOW - timedelta(hours=2),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 48),
    )
    richer = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2, past_days=1),
        provider="open_meteo",
        fetched_at=NOW + timedelta(minutes=30),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(3),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 72),
    )
    asyncio.run(FileWeatherCache(path, clock=lambda: NOW).put(older))
    asyncio.run(FileWeatherCache(
        path, clock=lambda: NOW + timedelta(hours=1),
    ).put(richer))
    result = run_conditions(
        FakeProvider(failure=True),
        cache=FileWeatherCache(path, clock=lambda: NOW),
        stale_age=timedelta(hours=3),
    )
    assert result.status is ConditionsStatus.DEGRADED
    assert "stale_weather_fallback" in issue_codes(result)
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.freshness.value == "stale"
    assert result.acquisition.snapshot.query.past_days == 0


class _ClockedProvider(FakeProvider):
    def __init__(self, clock, **kwargs) -> None:
        super().__init__(**kwargs)
        self._clock = clock

    async def fetch(self, query):
        response = await super().fetch(query)
        return replace(response, fetched_at=self._clock())


def test_default_cache_uses_service_clock_for_fresh_reuse(monkeypatch) -> None:
    class _Wall:
        @staticmethod
        def now(tz=None):
            return NOW

    monkeypatch.setattr("astro_host.cache.datetime", _Wall)
    shifted = NOW + timedelta(hours=2)
    provider = _ClockedProvider(lambda: shifted)
    service = ConditionsService(
        provider,
        engine=FakeEngine(),
        atlas_path="test-atlas",
        clock=lambda: shifted,
    )
    request = ConditionsRequest(LOCATION, shifted)
    first = asyncio.run(service.conditions(request))
    calls = len(provider.calls)
    second = asyncio.run(service.conditions(request))
    assert first.status is ConditionsStatus.COMPLETE
    assert second.status is ConditionsStatus.COMPLETE
    assert second.acquisition.snapshot is not None
    assert second.acquisition.snapshot.origin.value == "cache"
    assert len(provider.calls) == calls


def test_default_cache_inverse_skew_does_not_mask_stale_entry(monkeypatch) -> None:
    class _Wall:
        @staticmethod
        def now(tz=None):
            return NOW + timedelta(hours=3)

    monkeypatch.setattr("astro_host.cache.datetime", _Wall)
    service = ConditionsService(
        FakeProvider(failure=True),
        engine=FakeEngine(),
        atlas_path="test-atlas",
        clock=lambda: NOW,
        stale_on_error_max_age=timedelta(hours=3),
    )
    older = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2),
        provider="open_meteo",
        fetched_at=NOW - timedelta(hours=2),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 48),
    )
    richer = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 2, past_days=1),
        provider="open_meteo",
        fetched_at=NOW + timedelta(minutes=30),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(3),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 72),
    )
    asyncio.run(service._cache.put(older))
    asyncio.run(service._cache.put(richer))
    result = asyncio.run(service.conditions(ConditionsRequest(LOCATION, NOW)))
    assert result.status is ConditionsStatus.DEGRADED
    assert "stale_weather_fallback" in issue_codes(result)
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.freshness.value == "stale"
    assert result.acquisition.snapshot.query.past_days == 0
