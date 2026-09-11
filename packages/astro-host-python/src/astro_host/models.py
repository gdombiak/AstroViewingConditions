"""Typed host models for the first ``agent.conditions`` vertical slice."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime
from enum import Enum
from typing import Mapping


class TimeZoneAuthority(str, Enum):
    AUTHORITATIVE = "authoritative"
    APPROXIMATE = "approximate"
    UNAVAILABLE = "unavailable"


class TimeZoneSource(str, Enum):
    LOCATION_HINT = "location_hint"
    WEATHER_PROVIDER = "weather_provider"
    LONGITUDE_APPROXIMATION = "longitude_approximation"
    NONE = "none"


class TimeZoneAttemptState(str, Enum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    FAILED = "failed"
    NOT_AVAILABLE = "not_available"


class ProviderAttemptState(str, Enum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    NOT_ATTEMPTED = "not_attempted"


class ProviderFailureKind(str, Enum):
    TIMEOUT = "timeout"
    NETWORK = "network"
    RATE_LIMITED = "rate_limited"
    HTTP = "http"
    INVALID_JSON = "invalid_json"
    INVALID_PAYLOAD = "invalid_payload"


class PayloadState(str, Enum):
    COMPLETE = "complete"
    PARTIAL = "partial"
    EMPTY = "empty"


class DataOrigin(str, Enum):
    LIVE = "live"
    CACHE = "cache"


class FreshnessState(str, Enum):
    FRESH = "fresh"
    STALE = "stale"


class ConditionsStatus(str, Enum):
    COMPLETE = "complete"
    DEGRADED = "degraded"
    UNAVAILABLE = "unavailable"


class IssueSeverity(str, Enum):
    WARNING = "warning"
    ERROR = "error"


@dataclass(frozen=True)
class Location:
    latitude: float
    longitude: float
    name: str | None = None
    location_id: str | None = None
    elevation_m: float | None = None
    time_zone_hint: str | None = None


@dataclass(frozen=True)
class SavedLocation:
    id: str
    name: str
    latitude: float
    longitude: float
    time_zone: str
    aliases: tuple[str, ...] = ()
    elevation_m: float | None = None

    def to_conditions_location(self) -> Location:
        return Location(
            latitude=self.latitude,
            longitude=self.longitude,
            name=self.name,
            location_id=self.id,
            elevation_m=self.elevation_m,
            time_zone_hint=self.time_zone,
        )


@dataclass(frozen=True)
class SavedLocationDraft:
    name: str
    latitude: float
    longitude: float
    time_zone: str
    aliases: tuple[str, ...] = ()
    elevation_m: float | None = None
    id: str | None = None


@dataclass(frozen=True)
class LocationState:
    locations: tuple[SavedLocation, ...]
    selected_location_id: str | None


class PlaceResolutionStatus(str, Enum):
    UNIQUE = "unique"
    AMBIGUOUS = "ambiguous"
    NOT_FOUND = "not_found"


class LocationSource(str, Enum):
    EXPLICIT_OVERRIDE = "explicit_override"
    SELECTED_SAVED = "selected_saved"


@dataclass(frozen=True)
class PlaceProviderRecord:
    """Wire-shaped row. Timezone is raw and unvalidated."""
    provider_place_id: int | None
    name: str
    latitude: float
    longitude: float
    timezone: object = None
    elevation_m: float | None = None
    country: str | None = None
    admin1: str | None = None
    admin2: str | None = None
    country_code: str | None = None
    feature_code: str | None = None
    population: int | None = None


@dataclass(frozen=True)
class PlaceProviderResult:
    provider: str
    records: tuple[PlaceProviderRecord, ...]
    attempt_count: int


@dataclass(frozen=True)
class PlaceCandidate:
    """Facts shown to the user. Confirm persists these, not a re-query."""
    provider: str
    provider_place_id: int | None
    name: str
    display_name: str
    latitude: float
    longitude: float
    time_zone: str | None
    usable: bool
    unusable_reason: str | None
    elevation_m: float | None
    country: str | None
    admin1: str | None
    admin2: str | None
    country_code: str | None
    feature_code: str | None
    population: int | None
    rank: int


@dataclass(frozen=True)
class PlaceResolution:
    status: PlaceResolutionStatus
    query: str
    candidates: tuple[PlaceCandidate, ...]
    provider: str
    attempt_count: int
    attribution: Mapping[str, str]


@dataclass(frozen=True)
class PlaceConfirmRequest:
    candidate: PlaceCandidate
    name: str | None = None
    aliases: tuple[str, ...] = ()
    select: bool = False


@dataclass(frozen=True)
class HostConditionsRequest:
    """CLI/library input. location=None means 'use selected'."""
    location: Location | None
    reference_time: datetime
    observing_date: date | None = None
    force_refresh: bool = False


@dataclass(frozen=True)
class ConditionsRequest:
    location: Location
    reference_time: datetime
    observing_date: date | None = None
    force_refresh: bool = False


@dataclass(frozen=True)
class TimeZoneAttempt:
    source: TimeZoneSource
    candidate: str | None
    state: TimeZoneAttemptState
    detail: str | None = None


@dataclass(frozen=True)
class TimeZoneResolution:
    authority: TimeZoneAuthority
    source: TimeZoneSource
    iana_identifier: str | None
    fixed_offset_seconds: int | None
    resolved_at: datetime
    attempts: tuple[TimeZoneAttempt, ...]
    provider_identifier: str | None = None


@dataclass(frozen=True)
class WeatherQuery:
    location: Location
    forecast_days: int
    past_days: int = 0


@dataclass(frozen=True)
class PayloadDiagnostics:
    state: PayloadState
    messages: tuple[str, ...] = ()
    provider_time_count: int = 0


@dataclass(frozen=True)
class WeatherProviderResponse:
    provider: str
    fetched_at: datetime
    raw_payload: Mapping[str, object]
    provider_timezone: str | None
    utc_offset_seconds: int | None
    attempt_count: int
    diagnostics: PayloadDiagnostics


@dataclass(frozen=True)
class ProviderFailure:
    kind: ProviderFailureKind
    message: str
    attempt_count: int
    status_code: int | None = None


@dataclass(frozen=True)
class ProviderAttempt:
    state: ProviderAttemptState
    provider: str
    attempt_count: int
    failure: ProviderFailure | None = None


@dataclass(frozen=True)
class HourlyWeather:
    time: datetime
    cloud_cover: int
    humidity: int
    wind_speed: float
    wind_direction: int
    temperature: float
    dew_point: float | None = None
    visibility: float | None = None
    low_cloud_cover: int | None = None
    mid_cloud_cover: int | None = None
    high_cloud_cover: int | None = None
    wind_speed_200hpa: float | None = None


@dataclass(frozen=True)
class WeatherSnapshot:
    query: WeatherQuery
    provider: str
    fetched_at: datetime
    provider_timezone: str | None
    utc_offset_seconds: int | None
    hourly: tuple[HourlyWeather, ...]
    diagnostics: PayloadDiagnostics


@dataclass(frozen=True)
class SnapshotProvenance:
    origin: DataOrigin
    freshness: FreshnessState
    fetched_at: datetime
    age_seconds: float
    query: WeatherQuery


@dataclass(frozen=True)
class AcquisitionReport:
    provider_attempt: ProviderAttempt
    snapshot: SnapshotProvenance | None
    payload: PayloadDiagnostics | None
    provider_attempts: tuple[ProviderAttempt, ...] = ()


@dataclass(frozen=True)
class TimeWindow:
    start: datetime
    end: datetime


@dataclass(frozen=True)
class SelectedNight:
    selection: str
    state: str
    observing_date: date | None
    observing_day_start: datetime | None
    astronomical_night_start: datetime | None
    astronomical_night_end: datetime | None
    forecast_window: TimeWindow | None
    day_index: int | None = None
    day_offset: int | None = None


@dataclass(frozen=True)
class SunEventsFacts:
    day: date
    sunrise: datetime | None
    sunset: datetime | None
    civil_twilight_begin: datetime | None
    civil_twilight_end: datetime | None
    nautical_twilight_begin: datetime | None
    nautical_twilight_end: datetime | None
    astronomical_twilight_begin: datetime | None
    astronomical_twilight_end: datetime | None


@dataclass(frozen=True)
class MoonSample:
    time: datetime
    altitude_deg: float
    illumination_pct: int


@dataclass(frozen=True)
class AstronomyFacts:
    sun_today: SunEventsFacts
    sun_tomorrow: SunEventsFacts
    moon_samples: tuple[MoonSample, ...]


@dataclass(frozen=True)
class HourlyRating:
    time: datetime
    score: float
    cloud_cover: int
    fog_score: int
    moon_illumination: int
    moon_altitude: float
    wind_speed: float
    seeing_score: float | None = None
    transparency_score: float | None = None


@dataclass(frozen=True)
class ActiveNightResolution:
    state: str
    observing_date: date | None
    observing_day_start: datetime | None
    astronomical_night_start: datetime | None
    astronomical_night_end: datetime | None
    day_index: int | None
    day_offset: int | None


@dataclass(frozen=True)
class NightAnalysis:
    rating: str
    public_score: int
    details: Mapping[str, object]
    hourly_ratings: tuple[HourlyRating, ...]
    night_start: datetime
    night_end: datetime
    trend: str
    first_half_score: float | None
    second_half_score: float | None


@dataclass(frozen=True)
class NightConditionsFacts:
    rating: str
    public_score: int
    details: Mapping[str, object]
    hourly_ratings: tuple[HourlyRating, ...]
    night_start: datetime
    night_end: datetime
    trend: str
    first_half_score: float | None
    second_half_score: float | None
    best_window: TimeWindow | None
    cloud_timing: str


@dataclass(frozen=True)
class ObservingQualityFacts:
    score: int
    night_conditions_score: int
    modeled_zenith_sky_brightness: float | None
    base_penalty: float | None
    applied_penalty: float | None
    light_pollution_available: bool


@dataclass(frozen=True)
class WeatherFacts:
    hourly: tuple[HourlyWeather, ...]
    provider_timezone: str | None
    utc_offset_seconds: int | None


@dataclass(frozen=True)
class HostIssue:
    code: str
    message: str
    severity: IssueSeverity
    component: str
    degrades_result: bool = True
    details: Mapping[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class ConditionsResult:
    status: ConditionsStatus
    generated_at: datetime
    request: ConditionsRequest
    timezone: TimeZoneResolution
    acquisition: AcquisitionReport
    selected_night: SelectedNight | None
    weather: WeatherFacts | None
    astronomy: AstronomyFacts | None
    night_conditions: NightConditionsFacts | None
    observing_quality: ObservingQualityFacts | None
    issues: tuple[HostIssue, ...]
    engine_semver: str


class EquipmentType(str, Enum):
    BINOCULARS = "binoculars"
    VISUAL_TELESCOPE = "visualTelescope"
    SMART_TELESCOPE = "smartTelescope"


class EquipmentApertureUnit(str, Enum):
    MILLIMETERS = "millimeters"
    INCHES = "inches"


class EquipmentSelectionMode(str, Enum):
    ALL_SAVED = "all_saved"
    ITEM = "item"
    NAKED_EYE_ONLY = "naked_eye_only"


class EquipmentOverrideMode(str, Enum):
    """Override ``mode`` only. ``item`` is not valid here; use id or query."""

    ALL_SAVED = "all_saved"
    NAKED_EYE_ONLY = "naked_eye_only"


class EquipmentSource(str, Enum):
    EXPLICIT_OVERRIDE = "explicit_override"
    SELECTED_ITEM = "selected_item"
    ALL_SAVED = "all_saved"
    NAKED_EYE_ONLY = "naked_eye_only"
    NO_EQUIPMENT = "no_equipment"


@dataclass(frozen=True)
class EquipmentCapabilityFact:
    """Engine-legal capability row: exactly the four match/filter fields."""

    key: str
    type: str
    aperture_mm: float | None
    magnification: float | None

    def as_engine_row(self) -> dict[str, object]:
        return {
            "key": self.key,
            "type": self.type,
            "aperture_mm": self.aperture_mm,
            "magnification": self.magnification,
        }


@dataclass(frozen=True)
class EquipmentCapabilityIdentity:
    """Display identity for a capability row. Not engine input."""

    key: str
    id: str | None
    name: str | None


@dataclass(frozen=True)
class SavedEquipment:
    id: str
    name: str
    type: EquipmentType
    aperture_mm: float
    aperture_unit: EquipmentApertureUnit
    aliases: tuple[str, ...] = ()
    magnification: float | None = None

    def to_capability_fact(self) -> EquipmentCapabilityFact:
        return EquipmentCapabilityFact(
            key="1" + self.id,
            type=self.type.value,
            aperture_mm=self.aperture_mm,
            magnification=self.magnification,
        )

    def to_capability_identity(self) -> EquipmentCapabilityIdentity:
        return EquipmentCapabilityIdentity(
            key="1" + self.id,
            id=self.id,
            name=self.name,
        )


@dataclass(frozen=True)
class SavedEquipmentDraft:
    name: str
    type: EquipmentType
    aperture: float
    aperture_unit: EquipmentApertureUnit
    aliases: tuple[str, ...] = ()
    magnification: float | None = None
    id: str | None = None


@dataclass(frozen=True)
class InlineEquipmentDraft:
    """One-off capability facts. No identity, name, or aliases."""

    type: EquipmentType
    aperture: float
    aperture_unit: EquipmentApertureUnit
    magnification: float | None = None


@dataclass(frozen=True)
class EquipmentSelection:
    mode: EquipmentSelectionMode
    id: str | None = None


@dataclass(frozen=True)
class EquipmentState:
    items: tuple[SavedEquipment, ...]
    selection: EquipmentSelection


@dataclass(frozen=True)
class EquipmentWriteResult:
    state: EquipmentState
    item: SavedEquipment | None = None


@dataclass(frozen=True)
class ActiveEquipment:
    source: EquipmentSource
    has_saved_inventory: bool
    engine_has_saved_inventory: bool
    selection: EquipmentSelection
    capabilities: tuple[EquipmentCapabilityFact, ...]
    identities: tuple[EquipmentCapabilityIdentity, ...]
    override_applied: bool

    def engine_capabilities(self) -> tuple[dict[str, object], ...]:
        """Authoritative rows for equipment.match / filter_recommendations."""
        return tuple(row.as_engine_row() for row in self.capabilities)


@dataclass(frozen=True)
class EquipmentOverride:
    """Exactly one of id, query, mode, inline. ``mode`` cannot be item."""

    id: str | None = None
    query: str | None = None
    mode: EquipmentOverrideMode | None = None
    inline: InlineEquipmentDraft | None = None
