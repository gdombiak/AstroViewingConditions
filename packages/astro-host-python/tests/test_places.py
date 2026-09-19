from __future__ import annotations

import asyncio
from pathlib import Path
import uuid

import pytest

from astro_host.conditions import ConditionsService
from astro_host.errors import (
    InvalidPlaceCandidateError,
    InvalidProviderTimezoneError,
    InvalidRequestError,
    LocationConflictError,
    NoSelectedLocationError,
    PlaceProviderError,
)
from astro_host.locations import FileLocationStore, MemoryLocationStore
from astro_host.models import (
    ConditionsRequest,
    Location,
    LocationSource,
    PlaceCandidate,
    PlaceConfirmRequest,
    PlaceProviderRecord,
    PlaceProviderResult,
    PlaceResolutionStatus,
    ProviderFailure,
    ProviderFailureKind,
)
from astro_host.places import ObservingLocationService, place_display_name

from support import FakeEngine, FakeProvider, NOW
from test_locations import HOME_ID, home, hood
from test_open_meteo_geocoding import portland_me, portland_or


class FakePlaceResolver:
    name = "open_meteo"

    def __init__(self, result=None, error=None):
        self.result = result
        self.error = error
        self.calls = []

    async def resolve(self, query: str) -> PlaceProviderResult:
        self.calls.append(query)
        if self.error is not None:
            raise self.error
        return self.result


class BoomResolver:
    name = "open_meteo"

    async def resolve(self, query: str):
        raise AssertionError("confirm/save must not resolve")


def record_from(row: dict, **overrides) -> PlaceProviderRecord:
    fields = dict(
        provider_place_id=row.get("id") if isinstance(row.get("id"), int) else None,
        name=row["name"],
        latitude=row["latitude"],
        longitude=row["longitude"],
        timezone=row.get("timezone"),
        elevation_m=row.get("elevation") if isinstance(row.get("elevation"), (int, float)) else None,
        country=row.get("country") if isinstance(row.get("country"), str) else None,
        admin1=row.get("admin1") if isinstance(row.get("admin1"), str) else None,
        admin2=row.get("admin2") if isinstance(row.get("admin2"), str) else None,
        country_code=row.get("country_code") if isinstance(row.get("country_code"), str) else None,
        feature_code=row.get("feature_code") if isinstance(row.get("feature_code"), str) else None,
        population=row.get("population") if isinstance(row.get("population"), int) and not isinstance(row.get("population"), bool) else None,
    )
    fields.update(overrides)
    return PlaceProviderRecord(**fields)


def provider_result(*rows: dict, **record_overrides) -> PlaceProviderResult:
    records = tuple(record_from(row) for row in rows)
    if record_overrides:
        last = records[-1]
        records = (*records[:-1], PlaceProviderRecord(
            **{**last.__dict__, **record_overrides}
        ))
    return PlaceProviderResult("open_meteo", records, 1)


def service_for(result: PlaceProviderResult, store=None) -> ObservingLocationService:
    return ObservingLocationService(
        store=store or MemoryLocationStore(),
        resolver=FakePlaceResolver(result),
    )


def resolve(result: PlaceProviderResult, query="Portland"):
    return asyncio.run(service_for(result).resolve_place(query))


def usable_candidate(**overrides) -> PlaceCandidate:
    fields = dict(
        provider="open_meteo",
        provider_place_id=5746545,
        name="Portland",
        display_name="Portland, Oregon, United States",
        latitude=45.52345,
        longitude=-122.67621,
        time_zone="America/Los_Angeles",
        usable=True,
        unusable_reason=None,
        elevation_m=12.0,
        country="United States",
        admin1="Oregon",
        admin2="Multnomah County",
        country_code="US",
        feature_code="PPLA2",
        population=652503,
        rank=1,
    )
    fields.update(overrides)
    return PlaceCandidate(**fields)


def test_display_name_matches_ios_formula() -> None:
    assert place_display_name("Portland", "Oregon", "United States") == (
        "Portland, Oregon, United States"
    )
    assert place_display_name("Berlin", None, "Germany") == "Berlin, Germany"
    assert place_display_name("Home", None, None) == "Home"


def test_unique_stub_stewart() -> None:
    resolution = resolve(provider_result({
        "id": 1,
        "name": "Stub Stewart State Park",
        "latitude": 45.736,
        "longitude": -123.186,
        "timezone": "America/Los_Angeles",
        "country": "United States",
        "admin1": "Oregon",
    }), query="Stub Stewart")
    assert resolution.status is PlaceResolutionStatus.UNIQUE
    assert len(resolution.candidates) == 1
    assert resolution.candidates[0].usable is True
    assert resolution.candidates[0].time_zone == "America/Los_Angeles"
    assert resolution.candidates[0].rank == 1
    assert resolution.attribution["provider"] == "open_meteo"


def test_portland_two_rows_are_ambiguous() -> None:
    resolution = resolve(provider_result(portland_or(), portland_me()))
    assert resolution.status is PlaceResolutionStatus.AMBIGUOUS
    assert [row.admin1 for row in resolution.candidates] == ["Oregon", "Maine"]
    assert all(row.usable for row in resolution.candidates)


def test_valid_or_plus_missing_timezone_me_is_ambiguous() -> None:
    me = portland_me()
    del me["timezone"]
    resolution = resolve(provider_result(portland_or(), me))
    assert resolution.status is PlaceResolutionStatus.AMBIGUOUS
    assert resolution.candidates[0].usable is True
    assert resolution.candidates[1].usable is False
    assert resolution.candidates[1].unusable_reason == "missing_timezone"
    assert resolution.candidates[1].time_zone is None


def test_valid_or_plus_non_string_timezone_me_is_ambiguous() -> None:
    resolution = resolve(PlaceProviderResult("open_meteo", (
        record_from(portland_or()),
        record_from(portland_me(), timezone=8),
    ), 1))
    assert resolution.status is PlaceResolutionStatus.AMBIGUOUS
    assert resolution.candidates[1].usable is False
    assert resolution.candidates[1].unusable_reason == "invalid_timezone"
    assert resolution.candidates[0].usable is True


def test_valid_or_plus_bad_optional_metadata_me_is_ambiguous() -> None:
    resolution = resolve(PlaceProviderResult("open_meteo", (
        record_from(portland_or()),
        record_from(portland_me(), elevation_m=None, population=None, provider_place_id=None),
    ), 1))
    assert resolution.status is PlaceResolutionStatus.AMBIGUOUS
    assert len(resolution.candidates) == 2
    assert resolution.candidates[1].elevation_m is None
    assert resolution.candidates[1].usable is True


def test_unique_row_malformed_optional_fields_stay_none() -> None:
    resolution = resolve(PlaceProviderResult("open_meteo", (
        record_from(portland_or(), elevation_m=None, population=None),
    ), 1))
    assert resolution.status is PlaceResolutionStatus.UNIQUE
    assert resolution.candidates[0].elevation_m is None
    assert resolution.candidates[0].population is None
    assert resolution.candidates[0].usable is True


def test_zero_results_are_not_found() -> None:
    resolution = resolve(PlaceProviderResult("open_meteo", (), 1), query="Narnia")
    assert resolution.status is PlaceResolutionStatus.NOT_FOUND
    assert resolution.candidates == ()
    assert resolution.query == "Narnia"


def test_unique_unusable_timezone_is_dedicated_error() -> None:
    with pytest.raises(InvalidProviderTimezoneError):
        resolve(PlaceProviderResult("open_meteo", (
            record_from(portland_or(), timezone=None),
        ), 1))
    with pytest.raises(InvalidProviderTimezoneError):
        resolve(PlaceProviderResult("open_meteo", (
            record_from(portland_or(), timezone="Etc/Unknown"),
        ), 1))


def test_empty_query_does_not_call_resolver() -> None:
    fake = FakePlaceResolver(provider_result(portland_or()))
    with pytest.raises(InvalidRequestError):
        asyncio.run(ObservingLocationService(resolver=fake).resolve_place("  "))
    assert fake.calls == []


def test_provider_failure_propagates() -> None:
    error = PlaceProviderError(ProviderFailure(
        ProviderFailureKind.TIMEOUT, "geocoding timed out", 3
    ))
    with pytest.raises(PlaceProviderError):
        asyncio.run(ObservingLocationService(
            resolver=FakePlaceResolver(error=error)
        ).resolve_place("Portland"))


def test_confirm_saves_exact_candidate_facts() -> None:
    store = MemoryLocationStore()
    service = ObservingLocationService(store=store, resolver=BoomResolver())
    candidate = usable_candidate()
    saved = service.confirm_save(PlaceConfirmRequest(candidate=candidate))
    assert saved.latitude == candidate.latitude
    assert saved.longitude == candidate.longitude
    assert saved.time_zone == candidate.time_zone
    assert saved.elevation_m == candidate.elevation_m
    assert saved.name == candidate.name
    assert saved.id == str(uuid.UUID(saved.id))
    assert uuid.UUID(saved.id).version == 4
    assert saved.id != str(candidate.provider_place_id)


def test_confirm_does_not_call_resolver() -> None:
    store = MemoryLocationStore()
    ObservingLocationService(store=store, resolver=BoomResolver()).confirm_save(
        PlaceConfirmRequest(candidate=usable_candidate())
    )


def test_confirm_unusable_does_not_save() -> None:
    store = MemoryLocationStore()
    with pytest.raises(InvalidPlaceCandidateError):
        ObservingLocationService(store=store).confirm_save(PlaceConfirmRequest(
            candidate=usable_candidate(usable=False, time_zone=None, unusable_reason="missing_timezone")
        ))
    assert store.list() == ()


def test_confirm_after_provider_result_changes_keeps_shown_facts() -> None:
    store = MemoryLocationStore()
    shown = usable_candidate(latitude=45.52345, longitude=-122.67621)
    fake = FakePlaceResolver(provider_result(portland_me()))
    service = ObservingLocationService(store=store, resolver=fake)
    saved = service.confirm_save(PlaceConfirmRequest(candidate=shown))
    assert saved.latitude == 45.52345
    assert saved.longitude == -122.67621
    assert fake.calls == []


def test_confirm_duplicate_name_conflicts() -> None:
    store = MemoryLocationStore()
    store.save(home(name="Portland"))
    with pytest.raises(LocationConflictError):
        ObservingLocationService(store=store).confirm_save(
            PlaceConfirmRequest(candidate=usable_candidate())
        )


def test_confirm_user_name_home() -> None:
    store = MemoryLocationStore()
    saved = ObservingLocationService(store=store).confirm_save(PlaceConfirmRequest(
        candidate=usable_candidate(),
        name="Home",
        aliases=("house",),
    ))
    assert saved.name == "Home"
    assert saved.aliases == ("house",)
    assert saved.latitude == 45.52345


def test_confirm_select_false_does_not_change_existing_selection() -> None:
    store = MemoryLocationStore()
    first = store.save(home())
    ObservingLocationService(store=store).confirm_save(PlaceConfirmRequest(
        candidate=usable_candidate(name="Bend"),
        select=False,
    ))
    assert store.get_selected().id == first.id


def test_confirm_select_true_sets_selected_in_one_write(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = FileLocationStore(path)
    store.save(home(id=HOME_ID))
    service = ObservingLocationService(store=store)
    saved = service.confirm_save(PlaceConfirmRequest(
        candidate=usable_candidate(name="Bend"),
        select=True,
    ))
    assert store.get_selected().id == saved.id
    loaded = FileLocationStore(path)
    assert loaded.get_selected().id == saved.id


@pytest.mark.parametrize("time_zone", ["UTC", "Etc/Unknown"])
def test_candidate_to_location_rejects_usable_flag_with_invalid_timezone(
    tmp_path: Path, time_zone: str
) -> None:
    path = tmp_path / "locations.json"
    store = FileLocationStore(path)
    selected = store.save(home(id=HOME_ID))
    original = path.read_bytes()
    provider = FakeProvider()
    service = ObservingLocationService(store=store, resolver=BoomResolver())
    bogus = usable_candidate(usable=True, time_zone=time_zone)
    with pytest.raises(InvalidPlaceCandidateError):
        location = service.candidate_to_location(bogus)
        asyncio.run(ConditionsService(
            provider, engine=FakeEngine(), atlas_path="test-atlas", clock=lambda: NOW,
        ).conditions(ConditionsRequest(location=location, reference_time=NOW)))
    assert path.read_bytes() == original
    assert store.get_selected() == selected
    assert provider.calls == []
    with pytest.raises(InvalidPlaceCandidateError):
        service.confirm_save(PlaceConfirmRequest(candidate=bogus))
    assert path.read_bytes() == original
    assert store.get_selected() == selected
    assert provider.calls == []


def test_candidate_to_location_does_not_touch_store(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = FileLocationStore(path)
    selected = store.save(home(id=HOME_ID))
    original = path.read_bytes()
    service = ObservingLocationService(store=store)
    location = service.candidate_to_location(usable_candidate())
    asyncio.run(ConditionsService(
        FakeProvider(), engine=FakeEngine(), atlas_path="test-atlas", clock=lambda: NOW,
    ).conditions(ConditionsRequest(location=location, reference_time=NOW)))
    assert path.read_bytes() == original
    assert store.get_selected() == selected
    assert location.location_id is None
    assert location.time_zone_hint == "America/Los_Angeles"


def test_explicit_override_beats_selected_without_geocode() -> None:
    store = MemoryLocationStore()
    store.save(home())
    explicit = Location(44.0, -121.3, name="Sisters", time_zone_hint="America/Los_Angeles")
    location, source = ObservingLocationService(
        store=store, resolver=BoomResolver()
    ).location_for_conditions(explicit)
    assert location == explicit
    assert source is LocationSource.EXPLICIT_OVERRIDE
    assert store.get_selected().name == "Home"


def test_omitted_location_uses_selected() -> None:
    store = MemoryLocationStore()
    saved = store.save(home())
    location, source = ObservingLocationService(store=store).location_for_conditions(None)
    assert source is LocationSource.SELECTED_SAVED
    assert location.location_id == saved.id
    assert location.time_zone_hint == "America/Los_Angeles"
    assert location.latitude == saved.latitude


def test_no_selected_location_errors() -> None:
    store = MemoryLocationStore()
    with pytest.raises(NoSelectedLocationError):
        ObservingLocationService(store=store).location_for_conditions(None)
    store.save(home())
    store.save(hood())
    store.clear_selection()
    with pytest.raises(NoSelectedLocationError):
        ObservingLocationService(store=store).location_for_conditions(None)


def test_explicit_does_not_read_corrupt_store(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    path.write_text('{"schema_version":1,"locations":[', encoding="utf-8")
    explicit = Location(34.05, -118.24)
    location, source = ObservingLocationService(
        store=FileLocationStore(path)
    ).location_for_conditions(explicit)
    assert location == explicit
    assert source is LocationSource.EXPLICIT_OVERRIDE
