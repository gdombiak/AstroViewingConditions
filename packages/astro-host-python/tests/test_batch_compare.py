from __future__ import annotations

import asyncio
from dataclasses import replace
import io
import json
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from astro_host.cache import MemoryWeatherCache
from astro_host.cli import EXIT_OK, main, parse_batch_compare_request
from astro_host.conditions import ConditionsService
from astro_host.engine import ConditionsEngine
from astro_host.errors import InvalidRequestError, WeatherProviderError
from astro_host.locations import MemoryLocationStore
from astro_host.models import (
    BatchCandidate, ConditionsRequest, Location, ProviderFailure, ProviderFailureKind,
)
from support import FakeEngine, FakeProvider, NOW, hourly_rows
from test_locations import home


CENTER = Location(34.05, -118.24, "Center", time_zone_hint="America/Los_Angeles")
CANDIDATES = (
    BatchCandidate("a", "Far Place", Location(34.35, -118.24),
                   "https://example.test/source", "https://maps.example.test/a",
                   {"access": "unknown"}),
    BatchCandidate("b", "Near Place", Location(34.15, -118.24)),
)


class RecordingEngine(FakeEngine):
    def __init__(self):
        super().__init__()
        self.zones = []
        self.atlas_loads = 0
        self.compositions = []
        self.comparisons = []

    def analyze_night(self, *, reference_time, time_zone, window, forecasts, moon_samples):
        self.zones.append(time_zone)
        return super().analyze_night(
            reference_time=reference_time, time_zone=time_zone, window=window,
            forecasts=forecasts, moon_samples=moon_samples,
        )

    def prepare_brightness_lookup(self, atlas_path):
        self.atlas_loads += 1
        return object()

    def compose_location_scores(self, candidates):
        self.compositions.append(candidates)
        return super().compose_location_scores(candidates)

    def compare_locations(self, candidates):
        self.comparisons.append(candidates)
        return super().compare_locations(candidates)


class SelectiveProvider(FakeProvider):
    def __init__(self, *, fail_latitudes=(), partial_latitudes=()):
        super().__init__()
        self.fail_latitudes = set(fail_latitudes)
        self.partial_latitudes = set(partial_latitudes)
        self.active = 0
        self.maximum_active = 0

    async def fetch(self, query):
        self.active += 1
        self.maximum_active = max(self.active, self.maximum_active)
        try:
            await asyncio.sleep(0)
            if query.location.latitude in self.fail_latitudes:
                self.calls.append(query)
                raise WeatherProviderError(ProviderFailure(
                    ProviderFailureKind.TIMEOUT, "weather timed out", 3
                ))
            self.partial = query.location.latitude in self.partial_latitudes
            return await super().fetch(query)
        finally:
            self.active -= 1


def run(candidates=CANDIDATES, *, provider=None, engine=None, cache=None,
        request=None, stale_age=None):
    provider = provider or SelectiveProvider()
    engine = engine or RecordingEngine()
    service = ConditionsService(
        provider, engine=engine, cache=cache,
        stale_on_error_max_age=stale_age,
        atlas_path="test-atlas", clock=lambda: NOW,
    )
    result = asyncio.run(service.batch_compare(
        request or ConditionsRequest(CENTER, NOW), candidates
    ))
    return result, provider, engine


def test_ranked_named_results_use_center_calendar_engine_order_and_one_atlas_load():
    result, provider, engine = run()
    assert result["status"] == "complete"
    assert result["time_zone"] == "America/Los_Angeles"
    assert result["observing_date"] == date(2026, 2, 19)
    assert result["center"]["selected_night"].observing_date == date(2026, 2, 19)
    assert result["center"]["public_score"] == 85
    assert result["scoring_mode"] == "observing_quality"
    assert all(row["public_score"] == result["center"]["public_score"]
               for row in result["ranked_destinations"])
    assert engine.zones == ["America/Los_Angeles"] * 3
    assert engine.atlas_loads == 1
    assert len(engine.compositions) == 1
    assert len(engine.comparisons) == 1
    assert [row["key"] for row in result["ranked_destinations"]] == ["b", "a"]
    assert [row["key"] for row in result["ranked_destinations"]] == engine.compare_locations(
        engine.comparisons[0]
    )["ranking"]
    assert result["ranked_destinations"][1]["source_url"] == "https://example.test/source"
    assert result["ranked_destinations"][1]["metadata"] == {"access": "unknown"}
    assert result["ranked_destinations"][0]["distance_miles"] == engine.distance_miles(
        CENTER, CANDIDATES[1].location
    )
    assert provider.maximum_active <= 3


def test_candidate_timezone_does_not_reinterpret_center_night():
    candidates = (BatchCandidate(
        "denver", "Denver Place",
        Location(39.7, -105.0, time_zone_hint="America/Denver"),
    ),)
    result, _, engine = run(candidates)
    assert result["evaluated_count"] == 1
    assert result["ranked_destinations"][0]["selected_night"].observing_date == result["observing_date"]
    assert engine.zones == ["America/Los_Angeles", "America/Los_Angeles"]


def test_eastern_provider_midnight_preserves_centers_following_dawn():
    center_zone = ZoneInfo("America/Los_Angeles")
    candidate_zone = ZoneInfo("America/Denver")
    reference = datetime(2026, 2, 20, 1, tzinfo=timezone.utc)
    center = Location(34.05, -118.24, time_zone_hint=center_zone.key)
    candidate = BatchCandidate(
        "denver", "Denver Place", Location(39.7, -105.0, time_zone_hint=candidate_zone.key)
    )

    class CalendarProvider(FakeProvider):
        async def fetch(self, query):
            response = await super().fetch(query)
            zone = center_zone if query.location.latitude == center.latitude else candidate_zone
            first_day = reference.astimezone(zone).date() - timedelta(days=query.past_days)
            first_hour = datetime.combine(first_day, time.min, tzinfo=zone).astimezone(timezone.utc)
            return replace(response, raw_payload={
                "days": query.forecast_days + query.past_days,
                "first_hour": first_hour.isoformat(), "timezone": zone.key,
            }, provider_timezone=zone.key)

    class CalendarEngine(RecordingEngine):
        def __init__(self):
            super().__init__()
            self.candidate_sun_days = []
            self.candidate_windows = []

        def decode_weather(self, payload):
            first_hour = datetime.fromisoformat(payload["first_hour"])
            rows = tuple(replace(row, time=first_hour + timedelta(hours=index))
                         for index, row in enumerate(hourly_rows(payload["days"])))
            return rows, payload["timezone"], None

        def sun_events(self, location, *, day, start, end):
            if location.latitude == candidate.location.latitude:
                self.candidate_sun_days.append(day)
            return super().sun_events(location, day=day, start=start, end=end)

        def analyze_night(self, *, reference_time, time_zone, window, forecasts, moon_samples):
            if time_zone == center_zone.key and window.start.date() == date(2026, 2, 20):
                self.candidate_windows.append((window, tuple(row.time for row in forecasts)))
            return super().analyze_night(
                reference_time=reference_time, time_zone=time_zone, window=window,
                forecasts=forecasts, moon_samples=moon_samples,
            )

    provider, engine = CalendarProvider(), CalendarEngine()
    service = ConditionsService(provider, engine=engine, atlas_path="test-atlas", clock=lambda: NOW)
    result = asyncio.run(service.batch_compare(ConditionsRequest(center, reference), (candidate,)))
    assert reference.astimezone(center_zone).date() == date(2026, 2, 19)
    assert reference.astimezone(candidate_zone).date() == date(2026, 2, 19)
    assert result["center"]["selected_night"].observing_date == date(2026, 2, 19)
    query = next(query for query in provider.calls
                 if query.location.latitude == candidate.location.latitude)
    assert (query.past_days, query.forecast_days) == (2, 2)
    provider_first_hour = datetime.combine(
        date(2026, 2, 17), time.min, tzinfo=candidate_zone
    ).astimezone(timezone.utc)
    assert provider_first_hour.astimezone(center_zone).date() == date(2026, 2, 16)
    assert date(2026, 2, 20) in engine.candidate_sun_days
    assert result["evaluated_count"] == 1
    assert result["observing_date"] == date(2026, 2, 19)
    selected = result["ranked_destinations"][0]["selected_night"]
    assert selected.observing_date == date(2026, 2, 19)
    assert (selected.forecast_window.start, selected.forecast_window.end) == (
        datetime(2026, 2, 20, 3, tzinfo=timezone.utc),
        datetime(2026, 2, 20, 13, tzinfo=timezone.utc),
    )
    assert engine.candidate_windows
    window, filtered_times = engine.candidate_windows[-1]
    assert (window.start, window.end) == (
        selected.forecast_window.start, selected.forecast_window.end
    )
    assert filtered_times and all(window.start <= instant < window.end for instant in filtered_times)


def test_candidate_provider_calendar_uses_past_coverage_for_center_night():
    center_zone = ZoneInfo("Pacific/Pago_Pago")
    candidate_zone = ZoneInfo("Pacific/Kiritimati")
    reference = datetime(2026, 2, 20, 15, tzinfo=timezone.utc)
    center = Location(-14.28, -170.7, time_zone_hint=center_zone.key)
    candidate = BatchCandidate(
        "kiritimati", "Kiritimati Place",
        Location(1.87, -157.4, time_zone_hint=candidate_zone.key),
    )

    class CalendarProvider(FakeProvider):
        async def fetch(self, query):
            response = await super().fetch(query)
            zone = center_zone if query.location.latitude == center.latitude else candidate_zone
            provider_day = reference.astimezone(zone).date()
            first_day = provider_day - timedelta(days=query.past_days)
            first_hour = datetime.combine(first_day, time.min, tzinfo=zone).astimezone(timezone.utc)
            return replace(
                response,
                raw_payload={
                    "days": query.forecast_days + query.past_days,
                    "first_hour": first_hour.isoformat(),
                    "timezone": zone.key,
                },
                provider_timezone=zone.key,
            )

    class CalendarEngine(RecordingEngine):
        def __init__(self):
            super().__init__()
            self.windows = []

        def decode_weather(self, payload):
            first_hour = datetime.fromisoformat(payload["first_hour"])
            rows = tuple(
                replace(row, time=first_hour + timedelta(hours=index))
                for index, row in enumerate(hourly_rows(payload["days"]))
            )
            return rows, payload["timezone"], None

        def sun_events(self, location, *, day, start, end):
            facts = super().sun_events(location, day=day, start=start, end=end)
            return replace(
                facts,
                astronomical_twilight_end=datetime.combine(
                    day, time(19), tzinfo=center_zone
                ).astimezone(timezone.utc),
                astronomical_twilight_begin=datetime.combine(
                    day, time(5), tzinfo=center_zone
                ).astimezone(timezone.utc),
            )

        def resolve_active_night(self, *, reference_time, time_zone,
                                 forecast_start_time, daily_sun_events):
            return ConditionsEngine().resolve_active_night(
                reference_time=reference_time, time_zone=time_zone,
                forecast_start_time=forecast_start_time,
                daily_sun_events=daily_sun_events,
            )

        def analyze_night(self, *, reference_time, time_zone, window, forecasts,
                          moon_samples):
            self.windows.append((time_zone, window, tuple(row.time for row in forecasts)))
            return super().analyze_night(
                reference_time=reference_time, time_zone=time_zone, window=window,
                forecasts=forecasts, moon_samples=moon_samples,
            )

    provider, engine = CalendarProvider(), CalendarEngine()
    service = ConditionsService(
        provider, engine=engine, atlas_path="test-atlas", clock=lambda: NOW
    )
    result = asyncio.run(service.batch_compare(
        ConditionsRequest(center, reference), (candidate,)
    ))
    assert reference.astimezone(center_zone).date() == date(2026, 2, 20)
    assert reference.astimezone(candidate_zone).date() == date(2026, 2, 21)
    assert result["observing_date"] == date(2026, 2, 19)
    assert result["evaluated_count"] == 1
    assert result["ranked_destinations"][0]["selected_night"].observing_date == date(2026, 2, 19)
    candidate_query = next(
        query for query in provider.calls if query.location.latitude == candidate.location.latitude
    )
    assert [query.past_days for query in provider.calls
            if query.location.latitude == center.latitude] == [0, 1]
    assert candidate_query.past_days == 2
    assert candidate_query.forecast_days == 2
    expected_start = datetime(2026, 2, 20, 6, tzinfo=timezone.utc)
    expected_end = datetime(2026, 2, 20, 16, tzinfo=timezone.utc)
    candidate_zone_used, window, filtered_times = engine.windows[-1]
    assert candidate_zone_used == center_zone.key
    assert (window.start, window.end) == (expected_start, expected_end)
    assert filtered_times
    assert all(expected_start <= instant < expected_end for instant in filtered_times)
    # The candidate's current provider day begins four hours after this night
    # starts. Past-day coverage is required even though this case needs only one.
    no_past_start = datetime.combine(
        date(2026, 2, 21), time.min, tzinfo=candidate_zone
    ).astimezone(timezone.utc)
    one_past_start = no_past_start - timedelta(days=1)
    assert no_past_start > expected_start
    assert one_past_start <= expected_start


def test_active_after_midnight_keeps_centers_previous_observing_date():
    after_midnight = datetime(2026, 2, 20, 12, tzinfo=timezone.utc)
    result, _, _ = run(request=ConditionsRequest(CENTER, after_midnight))
    assert result["observing_date"] == date(2026, 2, 19)
    assert all(row["selected_night"].observing_date == date(2026, 2, 19)
               for row in result["ranked_destinations"])


def test_acquisition_is_bounded_for_eight_candidates():
    candidates = tuple(BatchCandidate(
        str(index), f"Place {index}", Location(34.1 + index * 0.01, -118.2)
    ) for index in range(8))
    result, provider, _ = run(candidates)
    assert result["evaluated_count"] == 8
    assert provider.maximum_active == 3


def test_identity_fields_do_not_change_ranking_and_one_candidate_works():
    renamed = tuple(BatchCandidate(row.key, "Changed " + row.name, row.location,
                                   "https://other.test", None) for row in CANDIDATES)
    first, _, _ = run()
    second, _, _ = run(renamed)
    assert [row["key"] for row in first["ranked_destinations"]] == [
        row["key"] for row in second["ranked_destinations"]
    ]
    one, _, _ = run(CANDIDATES[:1])
    assert one["evaluated_count"] == 1


def test_host_uses_engine_distance_and_ranking_verbatim():
    class AuthorityEngine(RecordingEngine):
        def distance_miles(self, center, candidate):
            return 123.0 if candidate.latitude == CANDIDATES[0].location.latitude else 456.0

        def compare_locations(self, candidates):
            self.comparisons.append(candidates)
            return {"ranking": ["a", "b"]}

    result, _, engine = run(engine=AuthorityEngine())
    assert [row["key"] for row in result["ranked_destinations"]] == ["a", "b"]
    assert [row["distance_miles"] for row in result["ranked_destinations"]] == [123.0, 456.0]
    assert [row["distance_miles"] for row in engine.comparisons[0]] == [123.0, 456.0]


def test_one_light_pollution_miss_forces_coherent_fallback():
    class MissingLP(RecordingEngine):
        def lookup_prepared_brightness(self, artifact, location):
            return None if location.latitude == CANDIDATES[0].location.latitude else 21.0

    result, _, engine = run(engine=MissingLP())
    assert result["scoring_mode"] == "night_conditions_fallback"
    assert result["center"]["public_score"] == 90
    assert result["center"]["public_score"] == result["center"]["night_conditions"]["public_score"]
    assert all(row["public_score"] == row["night_conditions"]["public_score"]
               for row in result["ranked_destinations"])
    assert all(row["public_score"] == result["center"]["public_score"]
               for row in result["ranked_destinations"])
    assert all(row["improvement_over_center"] == 0
               for row in result["ranked_destinations"])
    assert engine.compositions[0][1]["observing_quality"]["has_valid_light_pollution"] is False


def test_all_light_pollution_missing_still_ranks_in_night_conditions_mode():
    class NoLP(RecordingEngine):
        def lookup_prepared_brightness(self, artifact, location):
            return None

    result, _, _ = run(engine=NoLP())
    assert result["evaluated_count"] == 2
    assert result["scoring_mode"] == "night_conditions_fallback"
    assert result["status"] == "degraded"


def test_all_poor_scores_remain_visible_without_host_recommendation_threshold():
    class PoorEngine(RecordingEngine):
        def analyze_night(self, *, reference_time, time_zone, window, forecasts, moon_samples):
            facts = super().analyze_night(
                reference_time=reference_time, time_zone=time_zone, window=window,
                forecasts=forecasts, moon_samples=moon_samples,
            )
            return replace(facts, rating="poor", public_score=5)

        def assess_observing_quality(self, night_conditions_score, brightness):
            return replace(super().assess_observing_quality(night_conditions_score, brightness),
                           score=5, night_conditions_score=5)

    result, _, _ = run(engine=PoorEngine())
    assert result["evaluated_count"] == 2
    assert all(row["public_score"] == 5 for row in result["ranked_destinations"])
    assert all(row["night_conditions"]["rating"] == "poor"
               for row in result["ranked_destinations"])


def test_partial_weather_failure_and_all_destinations_unavailable():
    partial, _, _ = run(provider=SelectiveProvider(
        fail_latitudes={CANDIDATES[0].location.latitude}
    ))
    assert partial["status"] == "degraded"
    assert [row["key"] for row in partial["ranked_destinations"]] == ["b"]
    assert partial["omitted_candidates"][0]["key"] == "a"
    all_failed, _, _ = run(provider=SelectiveProvider(
        fail_latitudes={row.location.latitude for row in CANDIDATES}
    ))
    assert all_failed["status"] == "unavailable"
    assert all_failed["evaluated_count"] == 0
    assert all_failed["center"]["public_score"] == 85
    provider_wide, _, _ = run(
        provider=SelectiveProvider(fail_latitudes={
            CENTER.latitude, *(row.location.latitude for row in CANDIDATES)
        }),
        request=ConditionsRequest(CENTER, NOW, observing_date=date(2026, 2, 19)),
    )
    assert provider_wide["status"] == "unavailable"


def test_unscorable_center_still_ranks_destinations_without_deltas():
    result, _, _ = run(
        provider=SelectiveProvider(fail_latitudes={CENTER.latitude}),
        request=ConditionsRequest(CENTER, NOW, observing_date=date(2026, 2, 19)),
    )
    assert result["status"] == "degraded"
    assert result["evaluated_count"] == 2
    assert result["center"]["public_score"] is None
    assert all(row["improvement_over_center"] is None
               for row in result["ranked_destinations"])


def test_center_weather_failure_still_resolves_active_night_from_sun_events():
    class ActiveFallbackEngine(RecordingEngine):
        def resolve_active_night(self, *, reference_time, time_zone,
                                 forecast_start_time, daily_sun_events):
            active = super().resolve_active_night(
                reference_time=reference_time, time_zone=time_zone,
                forecast_start_time=forecast_start_time,
                daily_sun_events=daily_sun_events,
            )
            return replace(active, observing_date=date(2026, 2, 19))

    result, _, _ = run(
        provider=SelectiveProvider(fail_latitudes={CENTER.latitude}),
        engine=ActiveFallbackEngine(),
    )
    assert result["observing_date"] == date(2026, 2, 19)
    assert result["selected_night"].observing_date == date(2026, 2, 19)
    assert result["evaluated_count"] == 2
    assert all(row["improvement_over_center"] is None
               for row in result["ranked_destinations"])


def test_batch_reuses_cache_and_stale_on_error():
    cache = MemoryWeatherCache(clock=lambda: NOW)
    first, provider, _ = run(cache=cache)
    assert first["evaluated_count"] == 2
    calls = len(provider.calls)
    second, _, _ = run(cache=cache, provider=provider)
    assert second["evaluated_count"] == 2
    assert len(provider.calls) == calls
    provider.fail_latitudes = {row.location.latitude for row in CANDIDATES}
    stale, _, _ = run(cache=cache, provider=provider,
                      request=ConditionsRequest(CENTER, NOW, force_refresh=True),
                      stale_age=timedelta(hours=1))
    assert stale["evaluated_count"] == 2
    assert stale["status"] == "degraded"
    assert all(row["acquisition"].snapshot.freshness.value == "stale"
               for row in stale["ranked_destinations"])


def test_validation_rejects_duplicate_keys_and_coordinates():
    with pytest.raises(InvalidRequestError, match="duplicate candidate key"):
        run((CANDIDATES[0], BatchCandidate("a", "Another", CANDIDATES[1].location)))
    with pytest.raises(InvalidRequestError, match="coordinates must differ"):
        run((CANDIDATES[0], BatchCandidate("c", "Same", CANDIDATES[0].location)))
    with pytest.raises(InvalidRequestError, match="coordinates must differ"):
        run((BatchCandidate("c", "Center", CENTER),))


def test_transport_accepts_optional_center_and_preserves_metadata():
    request, candidates = parse_batch_compare_request({
        "reference_time": "2026-02-20T05:00:00Z",
        "candidates": [{"key": "a", "name": "Place", "latitude": 34.35,
                        "longitude": -118.24, "metadata": {"access": "unknown"}}],
    })
    assert request.location is None
    assert candidates[0].metadata == {"access": "unknown"}
    with pytest.raises(InvalidRequestError, match="coordinates"):
        parse_batch_compare_request({
            "reference_time": "2026-02-20T05:00:00Z",
            "candidates": [{"key": "a", "name": "Place", "latitude": True,
                            "longitude": 0}],
        })


def test_cli_selected_default_and_explicit_center_is_one_time(tmp_path):
    store = MemoryLocationStore()
    saved = store.save(home())
    service = ConditionsService(
        FakeProvider(), engine=RecordingEngine(), atlas_path="test-atlas", clock=lambda: NOW
    )
    body = {
        "reference_time": NOW.isoformat().replace("+00:00", "Z"),
        "candidates": [{"key": "a", "name": "Place", "latitude": 34.35,
                        "longitude": -118.24}],
    }

    def invoke(document):
        path = tmp_path / "batch.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        stdout, stderr = io.StringIO(), io.StringIO()
        status = main(["agent.batch_compare", "--input", str(path)],
                      service=service, store=store, stdout=stdout, stderr=stderr)
        return status, json.loads(stdout.getvalue()), stderr.getvalue()

    status, payload, stderr = invoke(body)
    assert status == EXIT_OK, stderr
    assert payload["result"]["center_source"] == "selected_saved"
    assert payload["result"]["evaluated_count"] == 1
    explicit = dict(body, center={"latitude": 34.1, "longitude": -118.24,
                                  "time_zone_hint": "America/Los_Angeles"})
    status, payload, stderr = invoke(explicit)
    assert status == EXIT_OK, stderr
    assert payload["result"]["center_source"] == "explicit_override"
    assert store.get_selected().id == saved.id
