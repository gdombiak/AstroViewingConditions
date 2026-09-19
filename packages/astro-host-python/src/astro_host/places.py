"""Place resolution, confirmation, and selected-location composition."""

from __future__ import annotations

import math

from astro_host.errors import (
    InvalidPlaceCandidateError,
    InvalidProviderTimezoneError,
    InvalidRequestError,
    NoSelectedLocationError,
)
from astro_host.locations import LocationStore
from astro_host.models import (
    Location,
    LocationSource,
    PlaceCandidate,
    PlaceConfirmRequest,
    PlaceProviderRecord,
    PlaceResolution,
    PlaceResolutionStatus,
    SavedLocation,
    SavedLocationDraft,
    TimeZoneSource,
)
from astro_host.providers.place import PlaceResolver
from astro_host.timezones import validate_iana


PLACE_ATTRIBUTION = {
    "provider": "open_meteo",
    "license": "CC BY 4.0",
    "text": "Location data by Open-Meteo.com (GeoNames)",
}
_SUPPORTED_CONFIRM_PROVIDER = "open_meteo"


class ObservingLocationService:
    def __init__(
        self,
        store: LocationStore | None = None,
        resolver: PlaceResolver | None = None,
    ) -> None:
        self._store = store
        self._resolver = resolver

    async def resolve_place(self, query: str) -> PlaceResolution:
        if not isinstance(query, str):
            raise InvalidRequestError("query must be a non-empty string")
        trimmed = query.strip()
        if not trimmed:
            raise InvalidRequestError("query must be a non-empty string")
        if self._resolver is None:
            raise InvalidRequestError("place resolver is not configured")
        result = await self._resolver.resolve(trimmed)
        candidates = tuple(
            _candidate_from_record(record, index + 1, result.provider)
            for index, record in enumerate(result.records)
        )
        if not candidates:
            return PlaceResolution(
                status=PlaceResolutionStatus.NOT_FOUND,
                query=trimmed,
                candidates=(),
                provider=result.provider,
                attempt_count=result.attempt_count,
                attribution=dict(PLACE_ATTRIBUTION),
            )
        usable = tuple(row for row in candidates if row.usable)
        if len(candidates) == 1 and not usable:
            raise InvalidProviderTimezoneError(
                "The resolved place has no usable IANA timezone."
            )
        if len(candidates) == 1:
            status = PlaceResolutionStatus.UNIQUE
        else:
            status = PlaceResolutionStatus.AMBIGUOUS
        return PlaceResolution(
            status=status,
            query=trimmed,
            candidates=candidates,
            provider=result.provider,
            attempt_count=result.attempt_count,
            attribution=dict(PLACE_ATTRIBUTION),
        )

    def confirm_save(self, request: PlaceConfirmRequest) -> SavedLocation:
        if self._store is None:
            raise InvalidRequestError("location store is not configured")
        candidate = request.candidate
        if not isinstance(candidate, PlaceCandidate):
            raise InvalidPlaceCandidateError("candidate is required")
        if candidate.provider != _SUPPORTED_CONFIRM_PROVIDER:
            raise InvalidPlaceCandidateError("candidate.provider is not supported")
        if not isinstance(candidate.name, str) or not candidate.name.strip():
            raise InvalidPlaceCandidateError("candidate.name must be a non-empty string")
        _require_usable_place_facts(candidate)
        name = request.name if request.name is not None else candidate.name
        saved = self._store.save(
            SavedLocationDraft(
                name=name,
                latitude=candidate.latitude,
                longitude=candidate.longitude,
                time_zone=candidate.time_zone,
                aliases=request.aliases,
                elevation_m=candidate.elevation_m,
                id=None,
            ),
            select=request.select,
        )
        return saved

    def location_for_conditions(
        self,
        explicit: Location | None,
        *,
        store: LocationStore | None = None,
    ) -> tuple[Location, LocationSource]:
        if explicit is not None:
            return explicit, LocationSource.EXPLICIT_OVERRIDE
        source = store if store is not None else self._store
        if source is None:
            raise InvalidRequestError("location store is not configured")
        selected = source.get_selected()
        if selected is None:
            raise NoSelectedLocationError()
        return selected.to_conditions_location(), LocationSource.SELECTED_SAVED

    def candidate_to_location(self, candidate: PlaceCandidate) -> Location:
        _require_usable_place_facts(candidate)
        return Location(
            latitude=candidate.latitude,
            longitude=candidate.longitude,
            name=candidate.name,
            location_id=None,
            elevation_m=candidate.elevation_m,
            time_zone_hint=candidate.time_zone,
        )


def place_display_name(
    name: str, admin1: str | None, country: str | None
) -> str:
    if admin1 and country:
        return f"{name}, {admin1}, {country}"
    if country:
        return f"{name}, {country}"
    return name


def _candidate_from_record(
    record: PlaceProviderRecord, rank: int, provider: str
) -> PlaceCandidate:
    time_zone, usable, unusable_reason = _timezone_usability(record.timezone)
    return PlaceCandidate(
        provider=provider,
        provider_place_id=record.provider_place_id,
        name=record.name,
        display_name=place_display_name(record.name, record.admin1, record.country),
        latitude=record.latitude,
        longitude=record.longitude,
        time_zone=time_zone,
        usable=usable,
        unusable_reason=unusable_reason,
        elevation_m=record.elevation_m,
        country=record.country,
        admin1=record.admin1,
        admin2=record.admin2,
        country_code=record.country_code,
        feature_code=record.feature_code,
        population=record.population,
        rank=rank,
    )


def _timezone_usability(
    raw: object,
) -> tuple[str | None, bool, str | None]:
    if raw is None:
        return None, False, "missing_timezone"
    if not isinstance(raw, str):
        return None, False, "invalid_timezone"
    if not raw:
        return None, False, "missing_timezone"
    ok, reason = validate_iana(raw, TimeZoneSource.LOCATION_HINT)
    if ok:
        return raw, True, None
    if reason == "not accepted by zoneinfo":
        return None, False, "invalid_timezone"
    return None, False, "unsupported_timezone"


def _require_usable_place_facts(candidate: PlaceCandidate) -> None:
    """Facts required to use or save a candidate. Display metadata is not checked."""
    if not isinstance(candidate, PlaceCandidate):
        raise InvalidPlaceCandidateError("candidate is required")
    if not candidate.usable:
        raise InvalidPlaceCandidateError("candidate is not usable")
    _require_coordinate(candidate.latitude, "latitude", -90, 90)
    _require_coordinate(candidate.longitude, "longitude", -180, 180)
    if not isinstance(candidate.time_zone, str) or not candidate.time_zone:
        raise InvalidPlaceCandidateError("candidate.time_zone is required")
    ok, reason = validate_iana(candidate.time_zone, TimeZoneSource.LOCATION_HINT)
    if not ok:
        raise InvalidPlaceCandidateError(
            "candidate.time_zone must be an IANA identifier accepted by "
            "ZoneInfo and the shared engine catalogue"
            + (f" ({reason})" if reason else "")
        )


def _require_coordinate(value: object, name: str, minimum: float, maximum: float) -> None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidPlaceCandidateError(f"candidate.{name} must be a number")
    try:
        number = float(value)
    except OverflowError as exc:
        raise InvalidPlaceCandidateError(f"candidate.{name} must be finite") from exc
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise InvalidPlaceCandidateError(
            f"candidate.{name} must be finite and between {minimum} and {maximum}"
        )
