"""Timezone authority and provenance for location-derived conditions."""

from __future__ import annotations

from datetime import datetime
import math
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.observing_night import allowed_timezone_identifiers

from astro_host.errors import TimeZoneCatalogError
from astro_host.models import (
    HostIssue,
    IssueSeverity,
    Location,
    TimeZoneAttempt,
    TimeZoneAttemptState,
    TimeZoneAuthority,
    TimeZoneResolution,
    TimeZoneSource,
)


def resolve_timezone(
    location: Location,
    *,
    provider_identifier: str | None,
    resolved_at: datetime,
) -> tuple[TimeZoneResolution, tuple[HostIssue, ...]]:
    attempts: list[TimeZoneAttempt] = []
    issues: list[HostIssue] = []
    hint = location.time_zone_hint
    valid_hint, hint_reason = _validate_iana(hint, TimeZoneSource.LOCATION_HINT)
    if hint is None:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.LOCATION_HINT, None, TimeZoneAttemptState.NOT_AVAILABLE
        ))
    elif valid_hint:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.LOCATION_HINT, hint, TimeZoneAttemptState.ACCEPTED
        ))
    else:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.LOCATION_HINT,
            hint,
            TimeZoneAttemptState.REJECTED,
            hint_reason,
        ))
        issues.append(HostIssue(
            code=(
                "invalid_timezone_hint"
                if hint_reason == "not accepted by zoneinfo"
                else "unsupported_timezone_hint"
            ),
            message=(
                "The saved location timezone hint is not a valid IANA identifier."
                if hint_reason == "not accepted by zoneinfo"
                else "The saved location timezone is not supported by the shared engine catalogue."
            ),
            severity=IssueSeverity.WARNING,
            component="timezone",
            degrades_result=False,
            details={"candidate": hint},
        ))

    valid_provider, provider_reason = _validate_iana(
        provider_identifier, TimeZoneSource.WEATHER_PROVIDER
    )
    if provider_identifier is None:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.WEATHER_PROVIDER,
            None,
            TimeZoneAttemptState.NOT_AVAILABLE,
        ))
    elif valid_provider:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.WEATHER_PROVIDER,
            provider_identifier,
            TimeZoneAttemptState.ACCEPTED,
        ))
    else:
        attempts.append(TimeZoneAttempt(
            TimeZoneSource.WEATHER_PROVIDER,
            provider_identifier,
            TimeZoneAttemptState.REJECTED,
            provider_reason,
        ))
        issues.append(HostIssue(
            code=(
                "invalid_provider_timezone"
                if provider_reason == "not accepted by zoneinfo"
                else "unsupported_provider_timezone"
            ),
            message=(
                "The weather provider timezone is not a valid IANA identifier."
                if provider_reason == "not accepted by zoneinfo"
                else (
                    "The weather provider timezone is not supported by the "
                    "shared engine catalogue."
                )
            ),
            severity=IssueSeverity.WARNING,
            component="timezone",
            degrades_result=not valid_hint,
            details={"candidate": provider_identifier},
        ))

    if valid_hint:
        assert hint is not None
        if valid_provider and provider_identifier != hint:
            issues.append(HostIssue(
                code="timezone_mismatch",
                message=(
                    "The saved location timezone differs from the weather provider; "
                    "the saved timezone was retained."
                ),
                severity=IssueSeverity.WARNING,
                component="timezone",
                degrades_result=False,
                details={"selected": hint, "provider": provider_identifier},
            ))
        return TimeZoneResolution(
            authority=TimeZoneAuthority.AUTHORITATIVE,
            source=TimeZoneSource.LOCATION_HINT,
            iana_identifier=hint,
            fixed_offset_seconds=None,
            resolved_at=resolved_at,
            attempts=tuple(attempts),
            provider_identifier=provider_identifier,
        ), tuple(issues)

    if valid_provider:
        assert provider_identifier is not None
        return TimeZoneResolution(
            authority=TimeZoneAuthority.AUTHORITATIVE,
            source=TimeZoneSource.WEATHER_PROVIDER,
            iana_identifier=provider_identifier,
            fixed_offset_seconds=None,
            resolved_at=resolved_at,
            attempts=tuple(attempts),
            provider_identifier=provider_identifier,
        ), tuple(issues)

    offset = approximate_offset_seconds(location.longitude)
    attempts.append(TimeZoneAttempt(
        TimeZoneSource.LONGITUDE_APPROXIMATION,
        None,
        TimeZoneAttemptState.ACCEPTED,
        f"fixed UTC offset {offset} seconds; diagnostic only",
    ))
    return TimeZoneResolution(
        authority=TimeZoneAuthority.APPROXIMATE,
        source=TimeZoneSource.LONGITUDE_APPROXIMATION,
        iana_identifier=None,
        fixed_offset_seconds=offset,
        resolved_at=resolved_at,
        attempts=tuple(attempts),
        provider_identifier=provider_identifier,
    ), tuple(issues)


def approximate_offset_seconds(longitude: float) -> int:
    hours = _round_half_away_from_zero(longitude / 15.0)
    return hours * 3600


def _round_half_away_from_zero(value: float) -> int:
    return int(math.copysign(math.floor(abs(value) + 0.5), value))


def _validate_iana(
    candidate: str | None, source: TimeZoneSource
) -> tuple[bool, str | None]:
    if not candidate:
        return False, None
    try:
        ZoneInfo(candidate)
    except (ZoneInfoNotFoundError, ValueError, KeyError, TypeError):
        return False, "not accepted by zoneinfo"
    try:
        accepted = candidate in allowed_timezone_identifiers()
    except Exception as exc:
        raise TimeZoneCatalogError(source, candidate, exc) from exc
    if not accepted:
        return False, "not present in the shared engine timezone catalogue"
    return True, None
