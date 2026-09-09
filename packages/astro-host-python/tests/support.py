from __future__ import annotations

from datetime import datetime, time, timedelta, timezone

from astro_host.errors import WeatherProviderError
from astro_host.models import (
    ActiveNightResolution,
    HourlyRating,
    HourlyWeather,
    MoonSample,
    NightAnalysis,
    ObservingQualityFacts,
    PayloadDiagnostics,
    PayloadState,
    ProviderFailure,
    ProviderFailureKind,
    SunEventsFacts,
    TimeWindow,
    WeatherProviderResponse,
)

NOW = datetime(2026, 2, 20, 5, tzinfo=timezone.utc)


def hourly_rows(days: int = 2) -> tuple[HourlyWeather, ...]:
    start = datetime(2026, 2, 19, 8, tzinfo=timezone.utc)
    return tuple(
        HourlyWeather(
            time=start + timedelta(hours=index),
            cloud_cover=10,
            humidity=40,
            wind_speed=2,
            wind_direction=180,
            temperature=10,
            dew_point=4,
            visibility=10_000,
            low_cloud_cover=5,
            mid_cloud_cover=3,
            high_cloud_cover=2,
            wind_speed_200hpa=30,
        )
        for index in range(days * 24)
    )


class FakeProvider:
    name = "open_meteo"

    def __init__(
        self,
        *,
        timezone_name: str | None = "America/Los_Angeles",
        partial: bool = False,
        empty: bool = False,
        failure: bool = False,
    ) -> None:
        self.timezone_name = timezone_name
        self.partial = partial
        self.empty = empty
        self.failure = failure
        self.calls = []

    async def fetch(self, query):
        self.calls.append(query)
        if self.failure:
            raise WeatherProviderError(ProviderFailure(
                ProviderFailureKind.TIMEOUT, "weather timed out", 3
            ))
        messages = ("missing_optional_series:visibility",) if self.partial else ()
        state = PayloadState.EMPTY if self.empty else (
            PayloadState.PARTIAL if self.partial else PayloadState.COMPLETE
        )
        return WeatherProviderResponse(
            provider=self.name,
            fetched_at=NOW,
            raw_payload={
                "days": query.forecast_days,
                "empty": self.empty,
                "timezone": self.timezone_name,
            },
            provider_timezone=self.timezone_name,
            utc_offset_seconds=-28_800,
            attempt_count=1,
            diagnostics=PayloadDiagnostics(
                state, messages, 0 if self.empty else query.forecast_days * 24
            ),
        )


class FakeEngine:
    def __init__(self, *, window_shift_days: int = 0) -> None:
        self.window_shift_days = window_shift_days
        self.moon_times: tuple[datetime, ...] = ()

    @property
    def semver(self) -> str:
        return "1.0.0"

    def decode_weather(self, payload):
        if payload.get("empty"):
            return (), payload.get("timezone"), -28_800
        return hourly_rows(int(payload["days"])), payload.get("timezone"), -28_800

    def sun_events(self, location, *, day, start, end):
        midnight = datetime.combine(day, time.min, tzinfo=timezone.utc)
        return SunEventsFacts(
            day=day,
            sunrise=midnight + timedelta(hours=14),
            sunset=midnight + timedelta(days=1, hours=2),
            civil_twilight_begin=midnight + timedelta(hours=13, minutes=30),
            civil_twilight_end=midnight + timedelta(days=1, hours=2, minutes=30),
            nautical_twilight_begin=midnight + timedelta(hours=13),
            nautical_twilight_end=midnight + timedelta(days=1, hours=3),
            astronomical_twilight_begin=midnight + timedelta(hours=13),
            astronomical_twilight_end=midnight + timedelta(days=1, hours=3),
        )

    def resolve_active_night(
        self, *, reference_time, time_zone, forecast_start_time, daily_sun_events
    ):
        today, tomorrow = daily_sun_events[:2]
        return ActiveNightResolution(
            state="resolved",
            observing_date=today.day,
            observing_day_start=forecast_start_time,
            astronomical_night_start=today.astronomical_twilight_end,
            astronomical_night_end=tomorrow.astronomical_twilight_begin,
            day_index=0,
            day_offset=0,
        )

    def derive_window(self, *, observing_time, time_zone, sun_today, sun_tomorrow):
        shift = timedelta(days=self.window_shift_days)
        return TimeWindow(
            sun_today.astronomical_twilight_end + shift,
            sun_tomorrow.astronomical_twilight_begin + shift,
        )

    def moon_series(self, location, times):
        self.moon_times = tuple(times)
        return tuple(MoonSample(value, 20.0, 25) for value in times)

    def analyze_night(
        self, *, reference_time, time_zone, window, forecasts, moon_samples
    ):
        ratings = tuple(
            HourlyRating(
                time=row.time,
                score=0.2,
                cloud_cover=row.cloud_cover,
                fog_score=0,
                moon_illumination=25,
                moon_altitude=20,
                wind_speed=row.wind_speed,
                seeing_score=0.1,
                transparency_score=0.1,
            )
            for row in forecasts
        )
        return NightAnalysis(
            rating="excellent",
            public_score=90,
            details={"cloud_cover_score": 10.0},
            hourly_ratings=ratings,
            night_start=ratings[0].time,
            night_end=ratings[-1].time,
            trend="stable",
            first_half_score=0.2,
            second_half_score=0.2,
        )

    def select_best_window(self, ratings):
        return TimeWindow(ratings[0].time, ratings[-1].time)

    def classify_cloud_timing(self, ratings):
        return "none"

    def lookup_brightness(self, atlas_path, location):
        return 21.0

    def assess_observing_quality(self, night_conditions_score, brightness):
        return ObservingQualityFacts(
            score=85 if brightness is not None else night_conditions_score,
            night_conditions_score=night_conditions_score,
            modeled_zenith_sky_brightness=brightness,
            base_penalty=5.0 if brightness is not None else None,
            applied_penalty=5.0 if brightness is not None else None,
            light_pollution_available=brightness is not None,
        )
