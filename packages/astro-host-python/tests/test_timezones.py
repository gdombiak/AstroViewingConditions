from __future__ import annotations

from datetime import datetime, timezone

import pytest

from astro_host.errors import TimeZoneCatalogError
from astro_host.models import Location, TimeZoneAuthority, TimeZoneSource
from astro_host.timezones import approximate_offset_seconds, resolve_timezone
import astro_host.timezones as timezone_module


NOW = datetime(2026, 2, 19, 12, tzinfo=timezone.utc)


def test_explicit_iana_wins_and_mismatch_is_retained() -> None:
    result, issues = resolve_timezone(
        Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
        provider_identifier="America/New_York",
        resolved_at=NOW,
    )
    assert result.iana_identifier == "America/Los_Angeles"
    assert result.source is TimeZoneSource.LOCATION_HINT
    assert result.provider_identifier == "America/New_York"
    assert [issue.code for issue in issues] == ["timezone_mismatch"]
    assert not issues[0].degrades_result


def test_provider_iana_is_automatic_fallback() -> None:
    result, issues = resolve_timezone(
        Location(34.05, -118.24),
        provider_identifier="America/Los_Angeles",
        resolved_at=NOW,
    )
    assert result.authority is TimeZoneAuthority.AUTHORITATIVE
    assert result.source is TimeZoneSource.WEATHER_PROVIDER
    assert result.iana_identifier == "America/Los_Angeles"
    assert issues == ()


def test_invalid_candidates_leave_non_authoritative_offset() -> None:
    result, issues = resolve_timezone(
        Location(0, 30, time_zone_hint="not/a-zone"),
        provider_identifier="also/not-a-zone",
        resolved_at=NOW,
    )
    assert result.authority is TimeZoneAuthority.APPROXIMATE
    assert result.iana_identifier is None
    assert result.fixed_offset_seconds == 7200
    assert {issue.code for issue in issues} == {
        "invalid_timezone_hint", "invalid_provider_timezone"
    }


def test_valid_but_unsupported_iana_is_a_normal_rejection(monkeypatch) -> None:
    monkeypatch.setattr(timezone_module, "allowed_timezone_identifiers", lambda: set())
    result, issues = resolve_timezone(
        Location(0, 0, time_zone_hint="UTC"),
        provider_identifier=None,
        resolved_at=NOW,
    )
    assert result.authority is TimeZoneAuthority.APPROXIMATE
    assert [issue.code for issue in issues] == ["unsupported_timezone_hint"]
    assert result.attempts[0].detail == (
        "not present in the shared engine timezone catalogue"
    )


def test_catalogue_failure_is_not_a_candidate_rejection(monkeypatch) -> None:
    def fail_catalogue():
        raise RuntimeError("catalogue resource missing")

    monkeypatch.setattr(
        timezone_module, "allowed_timezone_identifiers", fail_catalogue
    )
    with pytest.raises(TimeZoneCatalogError) as exc:
        resolve_timezone(
            Location(34.05, -118.24, time_zone_hint="America/Los_Angeles"),
            provider_identifier=None,
            resolved_at=NOW,
        )
    assert exc.value.source is TimeZoneSource.LOCATION_HINT
    assert exc.value.candidate == "America/Los_Angeles"


def test_fixed_offset_rounds_half_away_and_is_never_iana() -> None:
    assert approximate_offset_seconds(7.5) == 3600
    assert approximate_offset_seconds(-7.5) == -3600


def test_dst_zone_is_retained_as_iana_identity() -> None:
    result, _ = resolve_timezone(
        Location(34.05, -118.24),
        provider_identifier="America/Los_Angeles",
        resolved_at=NOW,
    )
    assert result.iana_identifier == "America/Los_Angeles"
