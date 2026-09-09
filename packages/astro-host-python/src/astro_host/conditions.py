"""The first host composition: ``agent.conditions``."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import date, datetime, time, timedelta, timezone
import math
from pathlib import Path
from typing import Callable, Sequence
from zoneinfo import ZoneInfo

from astro_host.cache import (
    FRESH_WEATHER_TTL,
    MemoryWeatherCache,
    WeatherCache,
    covers_window,
    is_fresh,
    snapshot_age,
    stale_allowed,
)
from astro_host.engine import ConditionsEngine
from astro_host.errors import (
    EngineCallError,
    InvalidRequestError,
    TimeZoneCatalogError,
    WeatherProviderError,
)
from astro_host.models import (
    AcquisitionReport,
    AstronomyFacts,
    ConditionsRequest,
    ConditionsResult,
    ConditionsStatus,
    DataOrigin,
    FreshnessState,
    HostIssue,
    IssueSeverity,
    Location,
    NightConditionsFacts,
    PayloadDiagnostics,
    PayloadState,
    ProviderAttempt,
    ProviderAttemptState,
    ProviderFailure,
    SelectedNight,
    SnapshotProvenance,
    SunEventsFacts,
    TimeZoneAttempt,
    TimeZoneAttemptState,
    TimeZoneAuthority,
    TimeZoneResolution,
    TimeZoneSource,
    WeatherFacts,
    WeatherQuery,
    WeatherSnapshot,
)
from astro_host.providers.open_meteo import OpenMeteoWeatherProvider
from astro_host.providers.weather import WeatherProvider
from astro_host.timezones import approximate_offset_seconds, resolve_timezone


@dataclass(frozen=True)
class _Acquired:
    snapshot: WeatherSnapshot | None
    report: AcquisitionReport
    engine_error: EngineCallError | None = None


class _RequiredTwilightError(Exception):
    def __init__(self, days: Sequence[str]) -> None:
        super().__init__("required astronomical twilight boundaries are unavailable")
        self.days = tuple(days)


class ConditionsService:
    def __init__(
        self,
        weather_provider: WeatherProvider | None = None,
        *,
        cache: WeatherCache | None = None,
        engine: ConditionsEngine | None = None,
        stale_on_error_max_age: timedelta | None = None,
        atlas_path: Path | str | None = None,
        clock: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        if stale_on_error_max_age is not None and stale_on_error_max_age <= timedelta(0):
            raise ValueError("stale_on_error_max_age must be positive")
        self._weather = weather_provider or OpenMeteoWeatherProvider(clock=clock)
        self._cache = cache or MemoryWeatherCache()
        self._engine = engine or ConditionsEngine()
        self._stale_max_age = stale_on_error_max_age
        self._atlas_path = None if atlas_path is None else Path(atlas_path)
        self._clock = clock

    async def conditions(self, request: ConditionsRequest) -> ConditionsResult:
        request = _validate_request(request)
        now = _as_utc(self._clock())

        try:
            initial_timezone, _ = resolve_timezone(
                request.location, provider_identifier=None, resolved_at=now
            )
        except TimeZoneCatalogError as exc:
            return self._timezone_catalog_unavailable(
                request, now, _empty_report(self._weather.name), exc
            )
        if initial_timezone.authority is TimeZoneAuthority.AUTHORITATIVE:
            assert initial_timezone.iana_identifier is not None
            initial_days = _forecast_days(request, ZoneInfo(initial_timezone.iana_identifier))
        else:
            # One current-night request supplies both weather and the provider's
            # rostered IANA timezone. A larger explicit-date request is replanned
            # after that authoritative zone is known.
            initial_days = 2

        try:
            acquired = await self._acquire(request, initial_days, now)
        except TimeZoneCatalogError as exc:
            return self._timezone_catalog_unavailable(
                request, now, _empty_report(self._weather.name), exc
            )
        provider_identifier = (
            acquired.snapshot.provider_timezone if acquired.snapshot is not None else None
        )
        try:
            tz, timezone_issues = resolve_timezone(
                request.location,
                provider_identifier=provider_identifier,
                resolved_at=now,
            )
        except TimeZoneCatalogError as exc:
            return self._timezone_catalog_unavailable(
                request, now, acquired.report, exc,
                provider_identifier=provider_identifier,
            )
        issues = list(timezone_issues)

        if acquired.engine_error is not None:
            issues.append(_engine_issue(acquired.engine_error))
            return self._unavailable(request, now, tz, acquired.report, issues)

        snapshot = acquired.snapshot
        if snapshot is None:
            failure = acquired.report.provider_attempt.failure
            if failure is not None:
                issues.append(HostIssue(
                    code="weather_provider_failure",
                    message=failure.message,
                    severity=IssueSeverity.ERROR,
                    component="weather",
                    details={
                        "kind": failure.kind.value,
                        "attempt_count": failure.attempt_count,
                        "status_code": failure.status_code,
                    },
                ))
            return self._unavailable(request, now, tz, acquired.report, issues)

        if tz.authority is not TimeZoneAuthority.AUTHORITATIVE:
            issues.append(HostIssue(
                code="authoritative_timezone_unavailable",
                message="No authoritative IANA timezone is available for this location.",
                severity=IssueSeverity.ERROR,
                component="timezone",
                details={"fixed_offset_seconds": tz.fixed_offset_seconds},
            ))
            return self._unavailable(request, now, tz, acquired.report, issues)

        assert tz.iana_identifier is not None
        zone = ZoneInfo(tz.iana_identifier)
        required_days = _forecast_days(request, zone)
        if snapshot.query.forecast_days < required_days:
            earlier = acquired
            try:
                acquired = _merge_acquired(
                    earlier,
                    await self._acquire(request, required_days, now),
                )
            except TimeZoneCatalogError as exc:
                return self._timezone_catalog_unavailable(
                    request, now, earlier.report, exc,
                    provider_identifier=provider_identifier,
                )
            snapshot = acquired.snapshot
            if acquired.engine_error is not None:
                issues.append(_engine_issue(acquired.engine_error))
                return self._unavailable(request, now, tz, acquired.report, issues)
            if snapshot is None:
                failure = acquired.report.provider_attempt.failure
                if failure is not None:
                    issues.append(HostIssue(
                        code="weather_provider_failure",
                        message=failure.message,
                        severity=IssueSeverity.ERROR,
                        component="weather",
                        details={"kind": failure.kind.value},
                    ))
                return self._unavailable(request, now, tz, acquired.report, issues)
            try:
                acquired_tz, acquired_tz_issues = resolve_timezone(
                    request.location,
                    provider_identifier=snapshot.provider_timezone,
                    resolved_at=now,
                )
            except TimeZoneCatalogError as exc:
                return self._timezone_catalog_unavailable(
                    request, now, acquired.report, exc,
                    provider_identifier=snapshot.provider_timezone,
                )
            issues = list(acquired_tz_issues)
            if acquired_tz.authority is not TimeZoneAuthority.AUTHORITATIVE:
                issues.append(HostIssue(
                    code="authoritative_timezone_unavailable",
                    message="No authoritative IANA timezone is available for this location.",
                    severity=IssueSeverity.ERROR,
                    component="timezone",
                ))
                return self._unavailable(request, now, acquired_tz, acquired.report, issues)
            tz = acquired_tz
            assert tz.iana_identifier is not None
            zone = ZoneInfo(tz.iana_identifier)

        if snapshot.diagnostics.state is PayloadState.EMPTY or not snapshot.hourly:
            issues.append(HostIssue(
                code="empty_weather_payload",
                message="The weather provider returned no usable hourly weather rows.",
                severity=IssueSeverity.ERROR,
                component="weather",
            ))
            return self._unavailable(request, now, tz, acquired.report, issues)

        issues.extend(_weather_degradation_issues(snapshot, acquired.report))

        try:
            sun_rows = self._sun_rows(snapshot, zone)
            selected, sun_today, sun_tomorrow = self._select_night(
                request, snapshot, zone, sun_rows
            )
            if (
                request.observing_date is None
                and selected.state == "requires_active_previous_payload"
                and snapshot.query.past_days == 0
            ):
                earlier = acquired
                try:
                    acquired = _merge_acquired(
                        earlier,
                        await self._acquire(
                            request, required_days, now, past_days=1
                        ),
                    )
                except TimeZoneCatalogError as exc:
                    return self._timezone_catalog_unavailable(
                        request, now, earlier.report, exc,
                        provider_identifier=snapshot.provider_timezone,
                    )
                snapshot = acquired.snapshot
                if acquired.engine_error is not None:
                    issues.append(_engine_issue(acquired.engine_error))
                    return self._unavailable(
                        request, now, tz, acquired.report, issues
                    )
                if snapshot is None:
                    failure = acquired.report.provider_attempt.failure
                    if failure is not None:
                        issues.append(_provider_failure_issue(failure))
                    return self._unavailable(
                        request, now, tz, acquired.report, issues,
                        selected_night=selected,
                    )
                try:
                    tz, timezone_issues = resolve_timezone(
                        request.location,
                        provider_identifier=snapshot.provider_timezone,
                        resolved_at=now,
                    )
                except TimeZoneCatalogError as exc:
                    return self._timezone_catalog_unavailable(
                        request, now, acquired.report, exc,
                        provider_identifier=snapshot.provider_timezone,
                    )
                issues = list(timezone_issues)
                if tz.authority is not TimeZoneAuthority.AUTHORITATIVE:
                    issues.append(_authoritative_timezone_issue(tz))
                    return self._unavailable(
                        request, now, tz, acquired.report, issues
                    )
                assert tz.iana_identifier is not None
                zone = ZoneInfo(tz.iana_identifier)
                if (
                    snapshot.diagnostics.state is PayloadState.EMPTY
                    or not snapshot.hourly
                ):
                    issues.append(_empty_payload_issue())
                    return self._unavailable(
                        request, now, tz, acquired.report, issues
                    )
                issues.extend(
                    _weather_degradation_issues(snapshot, acquired.report)
                )
                sun_rows = self._sun_rows(snapshot, zone)
                selected, sun_today, sun_tomorrow = self._select_night(
                    request, snapshot, zone, sun_rows
                )
            if selected.forecast_window is None:
                issues.append(HostIssue(
                    code="observing_night_unavailable",
                    message=(
                        "The requested observing night could not be resolved "
                        f"({selected.state})."
                    ),
                    severity=IssueSeverity.ERROR,
                    component="observing_night",
                    details={"state": selected.state},
                ))
                return self._unavailable(
                    request, now, tz, acquired.report, issues, selected_night=selected
                )

            window = selected.forecast_window
            night_rows = tuple(
                row for row in snapshot.hourly if window.start <= row.time < window.end
            )
            if not night_rows:
                issues.append(HostIssue(
                    code="required_weather_unavailable",
                    message="No hourly weather rows fall inside the selected night window.",
                    severity=IssueSeverity.ERROR,
                    component="weather",
                ))
                return self._unavailable(
                    request, now, tz, acquired.report, issues, selected_night=selected
                )

            full_coverage = covers_window(snapshot, window.start, window.end)
            if acquired.report.snapshot is not None and (
                acquired.report.snapshot.freshness is FreshnessState.STALE
            ) and not full_coverage:
                issues.append(HostIssue(
                    code="stale_weather_does_not_cover_night",
                    message="The stale cache does not continuously cover the requested night.",
                    severity=IssueSeverity.ERROR,
                    component="weather",
                ))
                return self._unavailable(
                    request, now, tz, acquired.report, issues, selected_night=selected
                )
            if not full_coverage:
                issues.append(HostIssue(
                    code="incomplete_night_coverage",
                    message="Hourly weather does not continuously cover the full night.",
                    severity=IssueSeverity.WARNING,
                    component="weather",
                ))

            moon_times = sorted({row.time for row in night_rows})
            moon_samples = self._engine.moon_series(request.location, moon_times)
            analysis = self._engine.analyze_night(
                reference_time=request.reference_time,
                time_zone=tz.iana_identifier,
                window=window,
                forecasts=night_rows,
                moon_samples=moon_samples,
            )
            best_window = self._engine.select_best_window(analysis.hourly_ratings)
            cloud_timing = self._engine.classify_cloud_timing(analysis.hourly_ratings)
            night_conditions = NightConditionsFacts(
                rating=analysis.rating,
                public_score=analysis.public_score,
                details=analysis.details,
                hourly_ratings=analysis.hourly_ratings,
                night_start=analysis.night_start,
                night_end=analysis.night_end,
                trend=analysis.trend,
                first_half_score=analysis.first_half_score,
                second_half_score=analysis.second_half_score,
                best_window=best_window,
                cloud_timing=cloud_timing,
            )
            astronomy = AstronomyFacts(
                sun_today=sun_today,
                sun_tomorrow=sun_tomorrow,
                moon_samples=moon_samples,
            )
        except _RequiredTwilightError as exc:
            issues.append(_twilight_issue(exc.days))
            return self._unavailable(request, now, tz, acquired.report, issues)
        except EngineCallError as exc:
            issues.append(_engine_issue(exc))
            return self._unavailable(request, now, tz, acquired.report, issues)

        brightness: float | None = None
        if self._atlas_path is None:
            issues.append(HostIssue(
                code="light_pollution_unavailable",
                message=(
                    "No light-pollution atlas is configured; Observing Quality "
                    "uses the Night Conditions fallback."
                ),
                severity=IssueSeverity.WARNING,
                component="light_pollution",
            ))
        else:
            try:
                brightness = self._engine.lookup_brightness(
                    self._atlas_path, request.location
                )
                if brightness is None:
                    issues.append(HostIssue(
                        code="light_pollution_no_data",
                        message="The light-pollution atlas has no value for this coordinate.",
                        severity=IssueSeverity.WARNING,
                        component="light_pollution",
                    ))
            except EngineCallError as exc:
                issues.append(HostIssue(
                    code="light_pollution_resource_failure",
                    message=exc.message,
                    severity=IssueSeverity.WARNING,
                    component="light_pollution",
                    details={
                        "engine_code": exc.code,
                        "capability": exc.capability,
                        **exc.details,
                    },
                ))
                brightness = None

        try:
            observing_quality = self._engine.assess_observing_quality(
                night_conditions.public_score, brightness
            )
        except EngineCallError as exc:
            issues.append(_engine_issue(exc))
            return self._unavailable(request, now, tz, acquired.report, issues)

        status = (
            ConditionsStatus.DEGRADED
            if any(issue.degrades_result for issue in issues)
            else ConditionsStatus.COMPLETE
        )
        return ConditionsResult(
            status=status,
            generated_at=now,
            request=request,
            timezone=tz,
            acquisition=acquired.report,
            selected_night=selected,
            weather=WeatherFacts(
                hourly=night_rows,
                provider_timezone=snapshot.provider_timezone,
                utc_offset_seconds=snapshot.utc_offset_seconds,
            ),
            astronomy=astronomy,
            night_conditions=night_conditions,
            observing_quality=observing_quality,
            issues=tuple(issues),
            engine_semver=self._engine.semver,
        )

    async def _acquire(
        self,
        request: ConditionsRequest,
        forecast_days: int,
        now: datetime,
        *,
        past_days: int = 0,
    ) -> _Acquired:
        query = WeatherQuery(request.location, forecast_days, past_days)
        cached = await self._cache.get(query)
        if cached is not None and not request.force_refresh:
            cached_tz, _ = resolve_timezone(
                request.location,
                provider_identifier=cached.provider_timezone,
                resolved_at=now,
            )
            if cached_tz.iana_identifier is not None and is_fresh(
                cached,
                query,
                now=now,
                zone=ZoneInfo(cached_tz.iana_identifier),
                ttl=FRESH_WEATHER_TTL,
            ):
                return _Acquired(
                    snapshot=cached,
                    report=_report(
                        cached,
                        now,
                        origin=DataOrigin.CACHE,
                        freshness=FreshnessState.FRESH,
                        attempt=ProviderAttempt(
                            ProviderAttemptState.NOT_ATTEMPTED,
                            cached.provider,
                            0,
                        ),
                    ),
                )

        try:
            response = await self._weather.fetch(query)
        except WeatherProviderError as exc:
            attempt = ProviderAttempt(
                ProviderAttemptState.FAILED,
                self._weather.name,
                exc.failure.attempt_count,
                exc.failure,
            )
            if cached is not None and stale_allowed(
                cached, now=now, maximum_age=self._stale_max_age
            ):
                return _Acquired(
                    snapshot=cached,
                    report=_report(
                        cached,
                        now,
                        origin=DataOrigin.CACHE,
                        freshness=FreshnessState.STALE,
                        attempt=attempt,
                    ),
                )
            return _Acquired(
                snapshot=None,
                report=AcquisitionReport(
                    attempt, None, None, provider_attempts=(attempt,)
                ),
            )

        attempt = ProviderAttempt(
            ProviderAttemptState.SUCCEEDED,
            response.provider,
            response.attempt_count,
        )
        try:
            rows, decoded_timezone, decoded_offset = self._engine.decode_weather(
                response.raw_payload
            )
        except EngineCallError as exc:
            return _Acquired(
                snapshot=None,
                report=AcquisitionReport(
                    attempt,
                    None,
                    response.diagnostics,
                    provider_attempts=(attempt,),
                ),
                engine_error=exc,
            )

        diagnostics = response.diagnostics
        if len(rows) < diagnostics.provider_time_count:
            diagnostics = PayloadDiagnostics(
                state=PayloadState.PARTIAL,
                messages=diagnostics.messages + (
                    "weather.decode skipped "
                    f"{diagnostics.provider_time_count - len(rows)} timestamp row(s)",
                ),
                provider_time_count=diagnostics.provider_time_count,
            )
        if not rows:
            diagnostics = replace(diagnostics, state=PayloadState.EMPTY)
        snapshot = WeatherSnapshot(
            query=query,
            provider=response.provider,
            fetched_at=response.fetched_at,
            provider_timezone=decoded_timezone or response.provider_timezone,
            utc_offset_seconds=decoded_offset,
            hourly=rows,
            diagnostics=diagnostics,
        )
        if snapshot.hourly:
            await self._cache.put(snapshot)
        return _Acquired(
            snapshot=snapshot,
            report=_report(
                snapshot,
                now,
                origin=DataOrigin.LIVE,
                freshness=FreshnessState.FRESH,
                attempt=attempt,
            ),
        )

    def _sun_rows(
        self, snapshot: WeatherSnapshot, zone: ZoneInfo
    ) -> tuple[SunEventsFacts, ...]:
        first_day = snapshot.hourly[0].time.astimezone(zone).date()
        rows = []
        for offset in range(
            snapshot.query.past_days + snapshot.query.forecast_days
        ):
            day = first_day + timedelta(days=offset)
            start = datetime.combine(day, time.min, tzinfo=zone).astimezone(timezone.utc)
            end = datetime.combine(
                day + timedelta(days=1), time.min, tzinfo=zone
            ).astimezone(timezone.utc)
            rows.append(self._engine.sun_events(
                snapshot.query.location, day=day, start=start, end=end
            ))
        return tuple(rows)

    def _select_night(
        self,
        request: ConditionsRequest,
        snapshot: WeatherSnapshot,
        zone: ZoneInfo,
        sun_rows: Sequence[SunEventsFacts],
    ) -> tuple[SelectedNight, SunEventsFacts, SunEventsFacts]:
        if request.observing_date is None:
            complete_rows = _complete_twilight_prefix(sun_rows)
            if not complete_rows:
                _require_twilight(sun_rows)
            active = self._engine.resolve_active_night(
                reference_time=request.reference_time,
                time_zone=zone.key,
                forecast_start_time=snapshot.hourly[0].time,
                daily_sun_events=complete_rows,
            )
            if active.state != "resolved":
                if active.state == "unavailable":
                    _require_twilight(sun_rows)
                selected = SelectedNight(
                    selection="active",
                    state=active.state,
                    observing_date=active.observing_date,
                    observing_day_start=active.observing_day_start,
                    astronomical_night_start=active.astronomical_night_start,
                    astronomical_night_end=active.astronomical_night_end,
                    forecast_window=None,
                    day_index=active.day_index,
                    day_offset=active.day_offset,
                )
                return selected, sun_rows[0], sun_rows[min(1, len(sun_rows) - 1)]
            assert active.day_index is not None and active.observing_day_start is not None
            index = active.day_index
            if index + 1 >= len(sun_rows):
                selected = SelectedNight(
                    selection="active", state="unavailable",
                    observing_date=active.observing_date,
                    observing_day_start=active.observing_day_start,
                    astronomical_night_start=active.astronomical_night_start,
                    astronomical_night_end=active.astronomical_night_end,
                    forecast_window=None, day_index=index, day_offset=active.day_offset,
                )
                return selected, sun_rows[index], sun_rows[index]
            today, tomorrow = sun_rows[index], sun_rows[index + 1]
            _require_twilight((today, tomorrow))
            window = self._engine.derive_window(
                observing_time=active.observing_day_start,
                time_zone=zone.key,
                sun_today=today,
                sun_tomorrow=tomorrow,
            )
            return SelectedNight(
                selection="active", state=active.state,
                observing_date=active.observing_date,
                observing_day_start=active.observing_day_start,
                astronomical_night_start=active.astronomical_night_start,
                astronomical_night_end=active.astronomical_night_end,
                forecast_window=window, day_index=index, day_offset=active.day_offset,
            ), today, tomorrow

        first_day = snapshot.hourly[0].time.astimezone(zone).date()
        index = (request.observing_date - first_day).days
        if index < 0 or index + 1 >= len(sun_rows):
            selected = SelectedNight(
                selection="explicit_date", state="unavailable",
                observing_date=request.observing_date, observing_day_start=None,
                astronomical_night_start=None, astronomical_night_end=None,
                forecast_window=None, day_index=index,
            )
            return selected, sun_rows[0], sun_rows[min(1, len(sun_rows) - 1)]
        today, tomorrow = sun_rows[index], sun_rows[index + 1]
        _require_twilight((today, tomorrow))
        day_start = datetime.combine(
            request.observing_date, time.min, tzinfo=zone
        ).astimezone(timezone.utc)
        window = self._engine.derive_window(
            observing_time=day_start,
            time_zone=zone.key,
            sun_today=today,
            sun_tomorrow=tomorrow,
        )
        return SelectedNight(
            selection="explicit_date", state="resolved",
            observing_date=request.observing_date,
            observing_day_start=day_start,
            astronomical_night_start=today.astronomical_twilight_end,
            astronomical_night_end=tomorrow.astronomical_twilight_begin,
            forecast_window=window, day_index=index, day_offset=None,
        ), today, tomorrow

    def _unavailable(
        self,
        request: ConditionsRequest,
        now: datetime,
        timezone_result: TimeZoneResolution,
        acquisition: AcquisitionReport,
        issues: list[HostIssue],
        *,
        selected_night: SelectedNight | None = None,
    ) -> ConditionsResult:
        return ConditionsResult(
            status=ConditionsStatus.UNAVAILABLE,
            generated_at=now,
            request=request,
            timezone=timezone_result,
            acquisition=acquisition,
            selected_night=selected_night,
            weather=None,
            astronomy=None,
            night_conditions=None,
            observing_quality=None,
            issues=tuple(issues),
            engine_semver=self._engine.semver,
        )

    def _timezone_catalog_unavailable(
        self,
        request: ConditionsRequest,
        now: datetime,
        acquisition: AcquisitionReport,
        error: TimeZoneCatalogError,
        *,
        provider_identifier: str | None = None,
    ) -> ConditionsResult:
        timezone_result = TimeZoneResolution(
            authority=TimeZoneAuthority.UNAVAILABLE,
            source=TimeZoneSource.NONE,
            iana_identifier=None,
            fixed_offset_seconds=approximate_offset_seconds(
                request.location.longitude
            ),
            resolved_at=now,
            attempts=(TimeZoneAttempt(
                source=error.source,
                candidate=error.candidate,
                state=TimeZoneAttemptState.FAILED,
                detail=str(error),
            ),),
            provider_identifier=provider_identifier,
        )
        issue = HostIssue(
            code="timezone_catalog_failure",
            message="The shared engine timezone catalogue could not be queried.",
            severity=IssueSeverity.ERROR,
            component="engine",
            details={
                "candidate": error.candidate,
                "source": error.source.value,
                "error_type": type(error.cause).__name__,
                "error": str(error.cause),
            },
        )
        return self._unavailable(
            request, now, timezone_result, acquisition, [issue]
        )


def _validate_request(request: ConditionsRequest) -> ConditionsRequest:
    if not isinstance(request, ConditionsRequest):
        raise InvalidRequestError("request must be a ConditionsRequest")
    location = request.location
    if not isinstance(location, Location):
        raise InvalidRequestError("request.location must be a Location")
    if (
        isinstance(location.latitude, bool)
        or not isinstance(location.latitude, (int, float))
    ):
        raise InvalidRequestError("latitude must be a number")
    if (
        isinstance(location.longitude, bool)
        or not isinstance(location.longitude, (int, float))
    ):
        raise InvalidRequestError("longitude must be a number")
    if not _is_finite_number(location.latitude) or not -90 <= location.latitude <= 90:
        raise InvalidRequestError("latitude must be finite and between -90 and 90")
    if not _is_finite_number(location.longitude) or not -180 <= location.longitude <= 180:
        raise InvalidRequestError("longitude must be finite and between -180 and 180")
    if location.elevation_m is not None and (
        not _is_finite_number(location.elevation_m)
    ):
        raise InvalidRequestError("elevation_m must be a finite number or null")
    if location.time_zone_hint is not None and not isinstance(
        location.time_zone_hint, str
    ):
        raise InvalidRequestError("time_zone_hint must be a string or null")
    if not isinstance(request.reference_time, datetime):
        raise InvalidRequestError("reference_time must be a datetime")
    if request.reference_time.tzinfo is None or request.reference_time.utcoffset() is None:
        raise InvalidRequestError("reference_time must include a timezone offset")
    if request.reference_time.microsecond != 0:
        raise InvalidRequestError("reference_time must use whole-second precision")
    normalized = replace(request, reference_time=_as_utc(request.reference_time))
    if not 2000 <= normalized.reference_time.year < 2050:
        raise InvalidRequestError("reference_time must be within 2000...2049")
    if request.observing_date is not None and (
        not isinstance(request.observing_date, date)
        or isinstance(request.observing_date, datetime)
    ):
        raise InvalidRequestError("observing_date must be a date or null")
    if not isinstance(request.force_refresh, bool):
        raise InvalidRequestError("force_refresh must be a boolean")
    return normalized


def _is_finite_number(value: object) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _forecast_days(request: ConditionsRequest, zone: ZoneInfo) -> int:
    local_reference_day = request.reference_time.astimezone(zone).date()
    selected = request.observing_date or local_reference_day
    offset = (selected - local_reference_day).days
    if offset < 0:
        raise InvalidRequestError("observing_date must not precede the reference local date")
    # Selected evening plus the following morning.
    return max(2, offset + 2)


def _complete_twilight_prefix(
    sun_rows: Sequence[SunEventsFacts],
) -> tuple[SunEventsFacts, ...]:
    """Rows safe to pass to active-night resolution without fabricating events."""
    complete: list[SunEventsFacts] = []
    for row in sun_rows:
        if (
            row.astronomical_twilight_begin is None
            or row.astronomical_twilight_end is None
        ):
            break
        complete.append(row)
    return tuple(complete)


def _require_twilight(sun_rows: Sequence[SunEventsFacts]) -> None:
    missing = [
        row.day.isoformat()
        for row in sun_rows
        if row.astronomical_twilight_begin is None
        or row.astronomical_twilight_end is None
    ]
    if missing:
        raise _RequiredTwilightError(missing)


def _report(
    snapshot: WeatherSnapshot,
    now: datetime,
    *,
    origin: DataOrigin,
    freshness: FreshnessState,
    attempt: ProviderAttempt,
) -> AcquisitionReport:
    age = snapshot_age(snapshot, now)
    return AcquisitionReport(
        provider_attempt=attempt,
        snapshot=SnapshotProvenance(
            origin=origin,
            freshness=freshness,
            fetched_at=snapshot.fetched_at,
            age_seconds=0.0 if age is None else age.total_seconds(),
            query=snapshot.query,
        ),
        payload=snapshot.diagnostics,
        provider_attempts=(attempt,),
    )


def _empty_report(provider: str) -> AcquisitionReport:
    attempt = ProviderAttempt(
        state=ProviderAttemptState.NOT_ATTEMPTED,
        provider=provider,
        attempt_count=0,
    )
    return AcquisitionReport(
        provider_attempt=attempt,
        snapshot=None,
        payload=None,
        provider_attempts=(attempt,),
    )


def _merge_acquired(earlier: _Acquired, later: _Acquired) -> _Acquired:
    prior_attempts = (
        earlier.report.provider_attempts
        or (earlier.report.provider_attempt,)
    )
    later_attempts = (
        later.report.provider_attempts
        or (later.report.provider_attempt,)
    )
    return replace(
        later,
        report=replace(
            later.report,
            provider_attempts=prior_attempts + later_attempts,
        ),
    )


def _weather_degradation_issues(
    snapshot: WeatherSnapshot, report: AcquisitionReport
) -> list[HostIssue]:
    issues: list[HostIssue] = []
    if snapshot.diagnostics.state is PayloadState.PARTIAL:
        issues.append(HostIssue(
            code="partial_weather_payload",
            message="The weather payload is usable but incomplete.",
            severity=IssueSeverity.WARNING,
            component="weather",
            details={"diagnostics": list(snapshot.diagnostics.messages)},
        ))
    if report.snapshot is not None and (
        report.snapshot.freshness is FreshnessState.STALE
    ):
        issues.append(HostIssue(
            code="stale_weather_fallback",
            message=(
                "Live weather refresh failed; a configured stale cache "
                "fallback was used."
            ),
            severity=IssueSeverity.WARNING,
            component="weather",
            details={"age_seconds": report.snapshot.age_seconds},
        ))
    return issues


def _provider_failure_issue(failure: ProviderFailure) -> HostIssue:
    return HostIssue(
        code="weather_provider_failure",
        message=failure.message,
        severity=IssueSeverity.ERROR,
        component="weather",
        details={
            "kind": failure.kind.value,
            "attempt_count": failure.attempt_count,
            "status_code": failure.status_code,
        },
    )


def _authoritative_timezone_issue(tz: TimeZoneResolution) -> HostIssue:
    return HostIssue(
        code="authoritative_timezone_unavailable",
        message="No authoritative IANA timezone is available for this location.",
        severity=IssueSeverity.ERROR,
        component="timezone",
        details={"fixed_offset_seconds": tz.fixed_offset_seconds},
    )


def _empty_payload_issue() -> HostIssue:
    return HostIssue(
        code="empty_weather_payload",
        message="The weather provider returned no usable hourly weather rows.",
        severity=IssueSeverity.ERROR,
        component="weather",
    )


def _twilight_issue(missing: Sequence[str]) -> HostIssue:
    return HostIssue(
        code="required_twilight_unavailable",
        message="Required astronomical twilight boundaries are unavailable.",
        severity=IssueSeverity.ERROR,
        component="astronomy",
        details={"days": list(missing)},
    )


def _engine_issue(error: EngineCallError) -> HostIssue:
    return HostIssue(
        code="engine_error",
        message=error.message,
        severity=IssueSeverity.ERROR,
        component="engine",
        details={
            "capability": error.capability,
            "engine_code": error.code,
            **error.details,
        },
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise InvalidRequestError("clock must return an aware datetime")
    return value.astimezone(timezone.utc)
