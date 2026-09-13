from __future__ import annotations

import asyncio
from dataclasses import replace
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from astro_host.cache import MemoryWeatherCache
from astro_engine.night_outlook import compose_night_outlook

from astro_host.conditions import OUTLOOK_FORECAST_DAYS, ConditionsService
from astro_host.engine import ConditionsEngine
from astro_host.models import (
    ConditionsRequest,
    ConditionsStatus,
    Location,
    PayloadDiagnostics,
    PayloadState,
    WeatherQuery,
    WeatherSnapshot,
)

from support import FakeEngine, FakeProvider, NOW, hourly_rows
from test_engine_composition import LocalCalendarTransport, RawOpenMeteoProvider
from astro_host.providers.open_meteo import OpenMeteoPolicy, OpenMeteoWeatherProvider


LOCATION = Location(34.05, -118.24)


def run_outlook(
    provider=None,
    *,
    engine=None,
    request=None,
    cache=None,
    stale_age=None,
    atlas_path="test-atlas",
    clock=None,
):
    service = ConditionsService(
        provider or FakeProvider(),
        engine=engine or FakeEngine(),
        cache=cache,
        stale_on_error_max_age=stale_age,
        atlas_path=atlas_path,
        clock=clock or (lambda: NOW),
    )
    return asyncio.run(service.outlook(
        request or ConditionsRequest(LOCATION, NOW)
    ))


def issue_codes(result) -> set[str]:
    return {issue.code for issue in result.issues}


class VariableScoreEngine(FakeEngine):
    """Distinct headline scores from the window start, not from slot arithmetic."""

    def __init__(self, scores_by_date: dict[date, int], **kwargs):
        super().__init__(**kwargs)
        self.scores_by_date = scores_by_date

    def analyze_night(self, *, reference_time, time_zone, window, forecasts, moon_samples):
        analysis = super().analyze_night(
            reference_time=reference_time,
            time_zone=time_zone,
            window=window,
            forecasts=forecasts,
            moon_samples=moon_samples,
        )
        score = self.scores_by_date.get(window.start.date(), analysis.public_score)
        return replace(analysis, public_score=score)


class MixedStatusEngine(FakeEngine):
    def compose_outlook(
        self, *, reference_time, time_zone, forecast_start_time, daily_sun_events,
        hourly_times,
    ):
        composed = super().compose_outlook(
            reference_time=reference_time,
            time_zone=time_zone,
            forecast_start_time=forecast_start_time,
            daily_sun_events=daily_sun_events,
            hourly_times=hourly_times,
        )
        nights = list(composed.nights)
        nights[1] = replace(nights[1], status="no_astronomical_night")
        nights[2] = replace(nights[2], status="unavailable")
        return replace(composed, nights=tuple(nights))


class TruncatedHourlyProvider(RawOpenMeteoProvider):
    """Drops the last two local days so the third night cannot be covered."""

    async def fetch(self, query):
        response = await super().fetch(query)
        payload = dict(response.raw_payload)
        hourly = dict(payload["hourly"])
        keep = 36
        hourly = {key: values[:keep] for key, values in hourly.items()}
        payload["hourly"] = hourly
        return replace(
            response,
            raw_payload=payload,
            diagnostics=PayloadDiagnostics(
                PayloadState.PARTIAL, ("truncated_hourly",), keep
            ),
        )


def test_outlook_returns_exactly_three_slots() -> None:
    result = run_outlook()
    assert result.status is ConditionsStatus.COMPLETE
    assert result.composition_state == "resolved"
    assert len(result.nights) == 3
    assert [night.slot_index for night in result.nights] == [0, 1, 2]
    assert all(night.status == "available" for night in result.nights)
    assert result.best_index == 0
    assert result.nights[0].is_best is True
    assert [night.is_best for night in result.nights] == [True, False, False]


def test_outlook_does_not_request_conditions_only_cloud_advice() -> None:
    class NoAdvisoryEngine(FakeEngine):
        def select_cloud_advisory(self, cloud_timing, rating, average_cloud_cover):
            raise AssertionError("outlook must not select Bot cloud advice")

    result = run_outlook(engine=NoAdvisoryEngine())
    assert result.status is ConditionsStatus.COMPLETE


def test_outlook_plans_four_forecast_days() -> None:
    provider = FakeProvider()
    run_outlook(provider)
    assert provider.calls[0].forecast_days == OUTLOOK_FORECAST_DAYS == 4
    assert provider.calls[0].past_days == 0


def test_outlook_rejects_observing_date() -> None:
    from astro_host.errors import InvalidRequestError
    import pytest

    with pytest.raises(InvalidRequestError, match="observing_date"):
        run_outlook(request=ConditionsRequest(
            LOCATION, NOW, observing_date=date(2026, 2, 21)
        ))


def test_fake_engine_equal_scores_are_host_plumbing_only() -> None:
    result = run_outlook(atlas_path="test-atlas")
    scores = [night.observing_quality.score for night in result.nights]
    assert scores == [85, 85, 85]
    assert result.best_index == 0


def test_highest_score_wins_and_does_not_sort_slots() -> None:
    engine = VariableScoreEngine({
        date(2026, 2, 20): 60,
        date(2026, 2, 21): 90,
        date(2026, 2, 22): 80,
    })
    result = run_outlook(engine=engine, atlas_path=None)
    assert [night.slot_index for night in result.nights] == [0, 1, 2]
    scores = [night.observing_quality.score for night in result.nights]
    assert scores[1] > scores[0]
    assert scores[1] > scores[2]
    assert result.best_index == 1
    assert [night.is_best for night in result.nights] == [False, True, False]


def test_unavailable_and_no_astronomical_night_have_nil_scores() -> None:
    result = run_outlook(engine=MixedStatusEngine(), atlas_path=None)
    assert result.nights[0].status == "available"
    assert result.nights[0].observing_quality is not None
    assert result.nights[1].status == "no_astronomical_night"
    assert result.nights[1].observing_quality is None
    assert result.nights[1].night_conditions is None
    assert result.nights[2].status == "unavailable"
    assert result.nights[2].observing_quality is None
    assert result.best_index == 0


def test_nil_scores_are_ineligible_even_when_available_status_is_forced() -> None:
    class AvailableWithoutRows(FakeEngine):
        def derive_window(self, *, observing_time, time_zone, sun_today, sun_tomorrow):
            return super().derive_window(
                observing_time=observing_time,
                time_zone=time_zone,
                sun_today=sun_today,
                sun_tomorrow=sun_tomorrow,
            ).__class__(
                start=datetime(2030, 1, 1, tzinfo=timezone.utc),
                end=datetime(2030, 1, 1, 1, tzinfo=timezone.utc),
            )

    result = run_outlook(engine=AvailableWithoutRows(), atlas_path=None)
    assert all(night.status == "available" for night in result.nights)
    assert all(night.observing_quality is None for night in result.nights)
    assert result.best_index is None
    assert "required_weather_unavailable" in issue_codes(result)


def test_stale_four_day_snapshot_is_visibly_degraded() -> None:
    cache = MemoryWeatherCache(clock=lambda: NOW)
    stale = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 4),
        provider="open_meteo",
        fetched_at=NOW - timedelta(hours=2),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(4),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 96),
    )
    asyncio.run(cache.put(stale))
    result = run_outlook(
        FakeProvider(failure=True),
        cache=cache,
        stale_age=timedelta(hours=3),
    )
    assert result.status is ConditionsStatus.DEGRADED
    assert "stale_weather_fallback" in issue_codes(result)
    assert result.acquisition.snapshot is not None
    assert result.acquisition.snapshot.freshness.value == "stale"
    assert result.composition_state == "resolved"


def test_fresh_cache_is_not_stale() -> None:
    cache = MemoryWeatherCache(clock=lambda: NOW)
    fresh = WeatherSnapshot(
        query=WeatherQuery(LOCATION, 4),
        provider="open_meteo",
        fetched_at=NOW - timedelta(minutes=10),
        provider_timezone="America/Los_Angeles",
        utc_offset_seconds=-28_800,
        hourly=hourly_rows(4),
        diagnostics=PayloadDiagnostics(PayloadState.COMPLETE, (), 96),
    )
    asyncio.run(cache.put(fresh))
    provider = FakeProvider()
    result = run_outlook(provider, cache=cache)
    assert not provider.calls
    assert result.acquisition.snapshot.origin.value == "cache"
    assert result.acquisition.snapshot.freshness.value == "fresh"


def test_real_engine_outlook_has_three_observing_dates() -> None:
    service = ConditionsService(
        RawOpenMeteoProvider(),
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert result.status is ConditionsStatus.DEGRADED
    assert result.composition_state == "resolved"
    assert len(result.nights) == 3
    dates = [night.observing_date for night in result.nights]
    assert dates == [date(2026, 2, 19), date(2026, 2, 20), date(2026, 2, 21)]
    assert all(night.status == "available" for night in result.nights)
    assert result.best_index is not None
    assert result.nights[result.best_index].is_best is True
    assert sum(night.is_best for night in result.nights) == 1


def test_real_engine_after_midnight_keeps_preceding_night_in_slot_zero() -> None:
    reference = datetime(2026, 3, 8, 9, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Los_Angeles")
    transport = LocalCalendarTransport(date(2026, 3, 8), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    service = ConditionsService(
        provider,
        atlas_path=None,
        clock=lambda: reference,
    )
    result = asyncio.run(service.outlook(
        ConditionsRequest(Location(34.05, -118.24), reference)
    ))

    assert result.composition_state == "resolved"
    assert result.nights[0].observing_date == date(2026, 3, 7)
    assert result.nights[1].observing_date == date(2026, 3, 8)
    assert result.nights[2].observing_date == date(2026, 3, 9)
    assert len(transport.calls) == 2
    assert "past_days" not in transport.calls[0]
    assert transport.calls[1]["past_days"] == "1"
    assert transport.calls[0]["forecast_days"] == "4"
    assert result.acquisition.snapshot.query.past_days == 1
    assert result.acquisition.snapshot.query.forecast_days == 4
    window_start = result.nights[0].astronomical_night_start
    window_end = result.nights[0].astronomical_night_end
    assert window_start is not None and window_end is not None
    assert window_start.astimezone(local_zone).utcoffset() == timedelta(hours=-8)
    assert window_end.astimezone(local_zone).utcoffset() == timedelta(hours=-7)


def test_real_engine_truncated_hourly_marks_later_nights_unavailable() -> None:
    service = ConditionsService(
        TruncatedHourlyProvider(),
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert result.composition_state == "resolved"
    assert len(result.nights) == 3
    assert result.nights[0].status in {"available", "unavailable"}
    assert result.nights[2].status == "unavailable"
    assert result.nights[2].observing_quality is None
    if result.best_index is not None:
        assert result.nights[result.best_index].status == "available"


class ForcedHeadlineEngine(ConditionsEngine):
    """Real engine composition/selection; only the headline scores are injected."""

    def __init__(self, scores: list[int]) -> None:
        self._scores = list(scores)
        self.select_calls: list[list[tuple[str, int | None]]] = []

    def assess_observing_quality(self, night_conditions_score, brightness):
        facts = super().assess_observing_quality(night_conditions_score, brightness)
        return replace(facts, score=self._scores.pop(0))

    def select_best_night(self, nights):
        captured = list(nights)
        self.select_calls.append(captured)
        return super().select_best_night(captured)


class InvertMiddleNightEngine(ConditionsEngine):
    """Invert the Feb 20 astronomical night via real sun-event bounds."""

    def sun_events(self, location, *, day, start, end):
        result = super().sun_events(location, day=day, start=start, end=end)
        if day == date(2026, 2, 20):
            return replace(result, astronomical_twilight_end=end)
        if day == date(2026, 2, 21):
            return replace(result, astronomical_twilight_begin=start)
        return result


def test_outlook_sends_moon_count_equal_to_sun_row_count(monkeypatch) -> None:
    captured: dict[str, int] = {}
    real = compose_night_outlook

    def wrapper(payload):
        captured["daily_moon_count"] = payload["daily_moon_count"]
        captured["sun_count"] = len(payload["daily_sun_events"])
        return real(payload)

    monkeypatch.setattr("astro_host.engine.compose_night_outlook", wrapper)
    service = ConditionsService(
        RawOpenMeteoProvider(),
        engine=ConditionsEngine(),
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert result.composition_state == "resolved"
    assert captured["sun_count"] >= 3
    assert captured["daily_moon_count"] == captured["sun_count"]


def test_real_engine_equal_scores_keep_the_earliest_night() -> None:
    engine = ForcedHeadlineEngine([80, 80, 80])
    service = ConditionsService(
        RawOpenMeteoProvider(),
        engine=engine,
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert [night.slot_index for night in result.nights] == [0, 1, 2]
    assert all(night.status == "available" for night in result.nights)
    assert [night.observing_quality.score for night in result.nights] == [80, 80, 80]
    assert engine.select_calls == [[
        ("available", 80), ("available", 80), ("available", 80),
    ]]
    assert result.best_index == 0
    assert [night.is_best for night in result.nights] == [True, False, False]


def test_real_engine_later_higher_score_does_not_reorder_slots() -> None:
    engine = ForcedHeadlineEngine([60, 90, 70])
    service = ConditionsService(
        RawOpenMeteoProvider(),
        engine=engine,
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert [night.slot_index for night in result.nights] == [0, 1, 2]
    scores = [night.observing_quality.score for night in result.nights]
    assert scores == [60, 90, 70]
    assert engine.select_calls == [[
        ("available", 60), ("available", 90), ("available", 70),
    ]]
    assert result.best_index == 1
    assert [night.is_best for night in result.nights] == [False, True, False]


def test_real_engine_inverted_window_is_no_astronomical_night() -> None:
    service = ConditionsService(
        RawOpenMeteoProvider(),
        engine=InvertMiddleNightEngine(),
        atlas_path=None,
        clock=lambda: NOW,
    )
    result = asyncio.run(service.outlook(ConditionsRequest(LOCATION, NOW)))
    assert result.composition_state == "resolved"
    assert [night.slot_index for night in result.nights] == [0, 1, 2]
    assert result.nights[1].status == "no_astronomical_night"
    assert result.nights[1].observing_quality is None
    assert result.nights[1].night_conditions is None
    assert result.nights[1].is_best is False
    if result.best_index is not None:
        assert result.best_index != 1
        assert result.nights[result.best_index].status == "available"
        assert result.nights[result.best_index].observing_quality is not None


def test_havana_dst_repeat_midnight_keeps_three_civil_slots() -> None:
    # 2026-11-01 Havana falls back; 01:30 local is after the repeated midnight.
    reference = datetime(2026, 11, 1, 6, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Havana")
    transport = LocalCalendarTransport(date(2026, 11, 1), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    service = ConditionsService(
        provider,
        atlas_path=None,
        clock=lambda: reference,
    )
    result = asyncio.run(service.outlook(
        ConditionsRequest(Location(23.11, -82.36), reference)
    ))
    assert result.composition_state == "resolved"
    assert len(result.nights) == 3
    assert len({night.observing_date for night in result.nights}) == 3
