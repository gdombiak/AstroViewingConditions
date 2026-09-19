from __future__ import annotations

import asyncio
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from astro_host.conditions import ConditionsService
from astro_host.engine import RecommendationEngine
from astro_host.equipment import FileEquipmentStore, MemoryEquipmentStore
from astro_host.equipment_session import compose_active
from astro_host.errors import (
    EngineCallError,
    EquipmentStoreCorruptError,
    InvalidRequestError,
)
from astro_host.locations import FileLocationStore, MemoryLocationStore
from astro_host.places import ObservingLocationService
from astro_host.models import (
    ConditionsRequest,
    ConditionsStatus,
    EmptyReason,
    EquipmentOverride,
    EquipmentOverrideMode,
    EquipmentSelectionMode,
    Location,
    LocationSource,
    MinimumFit,
    RecommendationFamily,
    RecommendationMode,
)
from astro_host.providers.http import HttpResponse
from astro_host.providers.open_meteo import OpenMeteoPolicy, OpenMeteoWeatherProvider
from astro_host.recommendations import (
    BEST_LIMIT,
    BROWSE_DEFAULT_MINIMUM_SCORE,
    CANDIDATE_POOL_LIMIT,
    RecommendationService,
    _HostCandidate,
    _remap,
)
from astro_host.models import ScoringPath, VisibilityWindow

from support import NOW, RecordingRecommendationEngine
from test_engine_composition import LocalCalendarTransport, RawOpenMeteoProvider
from test_equipment import S30_ID, s30
from test_locations import home


LA = Location(34.05, -118.24, name="Los Angeles")

_SPECIALIZED_WINDOW = {
    "start": "2026-02-20T04:00:00Z",
    "end": "2026-02-20T08:00:00Z",
    "best_time": "2026-02-20T06:00:00Z",
    "max_altitude": 50.0,
    "direction": "S",
    "azimuth": 180.0,
}
_PLANET_SAMPLES = (
    {
        "time": "2026-02-20T05:00:00Z",
        "altitude": 40.0,
        "azimuth": 180.0,
        "solar_elongation": 90.0,
    },
)
_MOON_OBSERVATION = {
    "phase": 0.2,
    "illumination": 20,
    "rise": "2026-02-20T03:00:00Z",
    "set": "2026-02-20T12:00:00Z",
    "always_up": False,
    "always_down": False,
    "samples": [
        {"time": "2026-02-20T05:00:00Z", "altitude": 30.0, "azimuth": 180.0},
    ],
}
_STUB_REQUIREMENT = {
    "naked_eye_suitability": "preferred",
    "binocular_suitability": "practical",
    "preferred_binocular_magnification": None,
    "practical_binocular_aperture_mm": None,
    "preferred_binocular_aperture_mm": None,
    "practical_visual_aperture_mm": None,
    "preferred_visual_aperture_mm": None,
    "practical_smart_eaa_aperture_mm": None,
    "preferred_smart_eaa_aperture_mm": None,
    "framing": "medium",
    "magnification_benefit": False,
    "smart_eaa_suitability": "supported",
}


def _specialized_row(score: int = 80) -> dict[str, object]:
    return {
        "score": score,
        "visibility_window": dict(_SPECIALIZED_WINDOW),
        "reasons": ["visible"],
    }


def _service(provider=None, engine=None, clock=None):
    conditions = ConditionsService(
        provider or RawOpenMeteoProvider(),
        atlas_path=None,
        clock=clock or (lambda: NOW),
    )
    return RecommendationService(conditions, engine=engine), conditions, provider


def _empty_equipment():
    return compose_active(MemoryEquipmentStore().load())


def _recommend(**overrides):
    service, conditions, provider = _service(
        overrides.pop("provider", None),
        overrides.pop("engine", None),
        overrides.pop("clock", None),
    )
    equipment = overrides.pop("equipment", None) or _empty_equipment()
    result = asyncio.run(
        service.recommend(
            location=overrides.pop("location", LA),
            location_source=overrides.pop(
                "location_source", LocationSource.EXPLICIT_OVERRIDE
            ),
            reference_time=overrides.pop("reference_time", NOW),
            mode=overrides.pop("mode", RecommendationMode.BEST),
            observing_date=overrides.pop("observing_date", None),
            force_refresh=overrides.pop("force_refresh", False),
            equipment=equipment,
            minimum_fit=overrides.pop("minimum_fit", MinimumFit.ANY),
            target_types=overrides.pop("target_types", None),
            object_types=overrides.pop("object_types", None),
            minimum_score=overrides.pop("minimum_score", None),
            limit=overrides.pop("limit", None),
        )
    )
    return result, service, conditions, provider


def test_known_location_matches_conditions_night_and_bounds() -> None:
    result, service, conditions, _ = _recommend()
    parallel = asyncio.run(
        conditions.conditions(ConditionsRequest(LA, NOW))
    )
    assert result.status in {ConditionsStatus.COMPLETE, ConditionsStatus.DEGRADED}
    assert len(result.recommendations) <= BEST_LIMIT
    assert result.returned_count == len(result.recommendations)
    assert result.query.mode is RecommendationMode.BEST
    assert result.query.minimum_score is None
    scores = [row.score for row in result.recommendations]
    assert scores == sorted(scores, reverse=True)
    assert result.night.observing_date == parallel.selected_night.observing_date
    assert result.generated_at == parallel.generated_at
    assert result.pool_size <= CANDIDATE_POOL_LIMIT
    assert result.candidate_count >= result.pool_size
    assert result.pool_truncated is (result.candidate_count > result.pool_size)
    assert {row.target_type for row in result.recommendations} <= {
        "moon",
        "planet",
        "deepSky",
    }
    assert all(row.overall_rank >= row.rank for row in result.recommendations)


def test_selected_saved_location_is_used_and_store_is_unchanged() -> None:
    store = MemoryLocationStore()
    saved = store.save(home())
    before = store.load()
    conditions = ConditionsService(
        RawOpenMeteoProvider(), atlas_path=None, clock=lambda: NOW
    )
    location, source = ObservingLocationService(
        store=store
    ).location_for_conditions(None)
    result = asyncio.run(
        RecommendationService(conditions).recommend(
            location=location,
            location_source=source,
            reference_time=NOW,
            mode=RecommendationMode.BEST,
            equipment=_empty_equipment(),
        )
    )
    after = store.load()
    assert source is LocationSource.SELECTED_SAVED
    assert result.location.location_id == saved.id
    assert after == before


def test_explicit_location_does_not_open_location_store(tmp_path: Path) -> None:
    path = tmp_path / "locations.json"
    store = FileLocationStore(path)
    store.save(home())
    stamp = path.read_bytes()
    result, *_ = _recommend(location=Location(34.05, -118.24))
    assert result.location_source is LocationSource.EXPLICIT_OVERRIDE
    assert path.read_bytes() == stamp


def test_omitted_minimum_fit_any_keeps_membership_with_selected_equipment() -> None:
    empty = _empty_equipment()
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    store.select(S30_ID)
    selected = compose_active(store.load())
    unfiltered, *_ = _recommend(equipment=empty)
    filtered, *_ = _recommend(equipment=selected)
    assert selected.engine_has_saved_inventory is True
    assert filtered.equipment.minimum_fit is MinimumFit.ANY
    assert [row.key for row in filtered.recommendations] == [
        row.key for row in unfiltered.recommendations
    ]
    if filtered.recommendations:
        assert all(row.equipment_fit is not None for row in filtered.recommendations)
    assert all(row.equipment_fit is None for row in unfiltered.recommendations)


def test_equipment_override_does_not_mutate_store() -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    before = store.load()
    active = compose_active(
        before, EquipmentOverride(id=S30_ID)
    )
    result, *_ = _recommend(equipment=active)
    assert result.equipment.override_applied is True
    assert result.equipment.minimum_fit is MinimumFit.ANY
    assert store.load() == before


def test_empty_all_saved_vs_naked_eye_only_flags() -> None:
    empty = compose_active(MemoryEquipmentStore().load())
    store = MemoryEquipmentStore()
    store.select_naked_eye()
    naked = compose_active(store.load())
    empty_result, *_ = _recommend(equipment=empty)
    naked_result, *_ = _recommend(equipment=naked)
    assert empty.engine_has_saved_inventory is False
    assert naked.engine_has_saved_inventory is True
    assert empty_result.equipment.engine_has_saved_inventory is False
    assert naked_result.equipment.engine_has_saved_inventory is True
    assert [row.key for row in empty_result.recommendations] == [
        row.key for row in naked_result.recommendations
    ]
    assert all(row.equipment_fit is None for row in empty_result.recommendations)
    if naked_result.recommendations:
        assert all(row.equipment_fit is not None for row in naked_result.recommendations)
        assert all(
            row.equipment_fit.key == "0" for row in naked_result.recommendations
        )


class SixCandidateEngine(RecommendationEngine):
    """Six catalog planets; filter keeps the sixth only when threshold is not any."""

    def solar_system(self):
        return [{"id": f"t{index}", "type": "planet"} for index in range(6)]

    def deep_sky(self):
        return []

    def moon_info(self, location, instant):
        return {"altitude": 0.0, "illumination": 0}

    def planet_observation(self, target_id, location, night_start, night_end):
        return {"samples": list(_PLANET_SAMPLES)}

    def planet_recommendation(self, target_id, samples, **kwargs):
        return _specialized_row(90 - int(str(target_id)[1:]))

    def filter_recommendations(self, rows, equipment, minimum_fit):
        assert len(rows) >= 6
        if minimum_fit == MinimumFit.ANY.value:
            return list(range(len(rows)))
        return [5]

    def requirements(self, target_id):
        return {"requirement": dict(_STUB_REQUIREMENT), "is_planet": True}

    def match_equipment(self, requirement, is_planet, equipment):
        return None


def test_explicit_challenging_or_better_changes_visible_membership() -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    store.select(S30_ID)
    selected = compose_active(store.load())
    any_result, *_ = _recommend(
        engine=SixCandidateEngine(),
        equipment=selected,
        minimum_fit=MinimumFit.ANY,
    )
    gated, *_ = _recommend(
        engine=SixCandidateEngine(),
        equipment=selected,
        minimum_fit=MinimumFit.CHALLENGING_OR_BETTER,
    )
    assert [row.key for row in any_result.recommendations] == [
        "t0", "t1", "t2", "t3", "t4",
    ]
    assert [row.key for row in gated.recommendations] == ["t5"]
    assert gated.pool_size == 6
    assert gated.equipment_matched_count == 1
    assert any_result.equipment_matched_count == 6
    assert any_result.query_matched_count == 6
    assert any_result.returned_count == 5
    assert any_result.truncated is True
    assert [row.overall_rank for row in any_result.recommendations] == [1, 2, 3, 4, 5]
    assert gated.recommendations[0].rank == 1
    assert gated.recommendations[0].overall_rank == 6
    assert gated.truncated is False


def test_service_sixth_row_survives_when_filter_drops_first_five() -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    selected = compose_active(store.load())
    result, *_ = _recommend(
        engine=SixCandidateEngine(),
        equipment=selected,
        minimum_fit=MinimumFit.CHALLENGING_OR_BETTER,
    )
    assert [row.key for row in result.recommendations] == ["t5"]
    assert result.pool_size == 6
    assert result.equipment_matched_count == 1
    assert result.recommendations[0].overall_rank == 6
    assert result.recommendations[0].rank == 1


def test_explicit_threshold_on_empty_inventory_is_echoed_not_rewritten() -> None:
    empty = _empty_equipment()
    result, *_ = _recommend(
        equipment=empty, minimum_fit=MinimumFit.CHALLENGING_OR_BETTER
    )
    assert empty.engine_has_saved_inventory is False
    assert result.equipment.minimum_fit is MinimumFit.CHALLENGING_OR_BETTER
    unfiltered, *_ = _recommend(equipment=empty, minimum_fit=MinimumFit.ANY)
    assert [row.key for row in result.recommendations] == [
        row.key for row in unfiltered.recommendations
    ]


def test_solar_catalog_order_and_membership_drive_specialized_calls() -> None:
    class CatalogWalk(RecordingRecommendationEngine):
        def __init__(self) -> None:
            super().__init__()
            self.specialized_walk: list[str] = []

        def solar_system(self):
            return [
                {"id": "saturn", "type": "planet"},
                {"id": "moon", "type": "moon"},
                {"id": "venus", "type": "planet"},
            ]

        def deep_sky(self):
            return []

        def moon_info(self, location, instant):
            return {"altitude": 0.0, "illumination": 0}

        def moon_observation(self, location, night_start, night_end):
            self.specialized_walk.append("moon")
            return dict(_MOON_OBSERVATION)

        def moon_recommendation(self, observation, **kwargs):
            return _specialized_row(70)

        def planet_observation(self, target_id, location, night_start, night_end):
            self.specialized_walk.append(target_id)
            return {"samples": list(_PLANET_SAMPLES)}

        def planet_recommendation(self, target_id, samples, **kwargs):
            return _specialized_row(80)

        def requirements(self, target_id):
            return {
                "requirement": dict(_STUB_REQUIREMENT),
                "is_planet": target_id != "moon",
            }

        def match_equipment(self, requirement, is_planet, equipment):
            return None

    engine = CatalogWalk()
    result, service, *_ = _recommend(engine=engine)
    assert engine.specialized_walk == ["saturn", "moon", "venus"]
    compose = [
        payload for name, payload in service._engine.recorded
        if name == "targets.compose_recommendations"
    ]
    assert compose
    assert [row["key"] for row in compose[0]["candidates"]] == [
        "saturn", "moon", "venus",
    ]
    assert {row.target_id for row in result.recommendations} <= {
        "saturn", "moon", "venus",
    }
    assert "mars" not in engine.specialized_walk
    assert "jupiter" not in engine.specialized_walk


def test_moon_null_omits_only_moon() -> None:
    class MoonNull(RecommendationEngine):
        def moon_recommendation(self, *args, **kwargs):
            return None

    result, *_ = _recommend(engine=MoonNull())
    assert all(row.target_type != "moon" for row in result.recommendations)
    assert result.status is not ConditionsStatus.UNAVAILABLE


def test_one_planet_null_omits_only_that_planet() -> None:
    class VenusNull(RecordingRecommendationEngine):
        def planet_observation(self, target_id, location, night_start, night_end):
            if target_id == "venus":
                return None
            return super().planet_observation(
                target_id, location, night_start, night_end
            )

    result, service, *_ = _recommend(engine=VenusNull())
    assert all(row.target_id != "venus" for row in result.recommendations)
    recorded = service._engine.recorded
    assert any(name == "astronomy.planet_observation" for name, _ in recorded)


def test_engine_exception_fails_operation_not_partial_family() -> None:
    class VenusBoom(RecommendationEngine):
        def planet_recommendation(self, target_id, samples, **kwargs):
            if target_id == "venus":
                raise EngineCallError(
                    "targets.planet_recommendation",
                    "validation",
                    "injected",
                )
            return super().planet_recommendation(target_id, samples, **kwargs)

    with pytest.raises(EngineCallError) as caught:
        _recommend(engine=VenusBoom())
    assert caught.value.capability == "targets.planet_recommendation"
    assert caught.value.code == "validation"


def test_compose_and_filter_remap_by_index_not_key() -> None:
    window = VisibilityWindow(
        start=NOW,
        end=NOW + timedelta(hours=2),
        best_time=NOW + timedelta(hours=1),
        max_altitude=50,
        direction="S",
        azimuth=180,
    )
    mixed = [
        _HostCandidate(
            key=f"dup@{index}",
            target_id="m31",
            name="Andromeda",
            family=RecommendationFamily.DEEP_SKY,
            type="deepSky",
            object_type="galaxy",
            score=80 - index,
            scoring_path=ScoringPath.TARGETS_RECOMMEND,
            visibility_window=window,
            reasons=(),
        )
        for index in range(6)
    ]
    pool = _remap(mixed, [5, 4, 3, 2, 1, 0][:CANDIDATE_POOL_LIMIT])
    assert pool[0] is mixed[5]
    filtered = _remap(pool, [0])
    visible = filtered[:BEST_LIMIT]
    assert [row.key for row in visible] == [mixed[5].key]


def test_sixth_row_can_enter_final_five_when_filter_drops_first_five() -> None:
    window = VisibilityWindow(
        start=NOW,
        end=NOW + timedelta(hours=1),
        best_time=NOW,
        max_altitude=40,
        direction="S",
        azimuth=180,
    )
    mixed = [
        _HostCandidate(
            key=f"row{index}",
            target_id=f"t{index}",
            name=f"T{index}",
            family=RecommendationFamily.DEEP_SKY,
            type="deepSky",
            object_type="galaxy",
            score=90 - index,
            scoring_path=ScoringPath.TARGETS_RECOMMEND,
            visibility_window=window,
            reasons=(),
        )
        for index in range(6)
    ]
    pool = _remap(mixed, list(range(6)))
    filtered = _remap(pool, [5])
    visible = filtered[:BEST_LIMIT]
    assert [row.key for row in visible] == ["row5"]


class ScoreThirty(RecommendationEngine):
    def moon_recommendation(self, observation, **kwargs):
        raw = super().moon_recommendation(observation, **kwargs)
        if raw is None:
            return {
                "score": 30,
                "visibility_window": {
                    "start": "2026-02-20T04:00:00Z",
                    "end": "2026-02-20T08:00:00Z",
                    "best_time": "2026-02-20T06:00:00Z",
                    "max_altitude": 40.0,
                    "direction": "S",
                    "azimuth": 180.0,
                },
                "reasons": ["moonVisibleUsefulWindow"],
            }
        return {**raw, "score": 30}

    def planet_observation(self, target_id, location, night_start, night_end):
        return None

    def deep_sky(self):
        return []


def test_score_30_is_eligible() -> None:
    result, *_ = _recommend(engine=ScoreThirty())
    assert result.recommendations
    assert result.recommendations[0].score == 30
    assert all(row.score >= 0 for row in result.recommendations)
    assert result.query.mode is RecommendationMode.BEST
    assert result.query.minimum_score is None


def test_degraded_conditions_still_rank() -> None:
    result, *_ = _recommend()
    assert result.status is ConditionsStatus.DEGRADED
    assert result.issues
    assert "light_pollution_unavailable" in {issue.code for issue in result.issues}


def test_provider_fetch_count_is_one_before_midnight() -> None:
    class Counting(RawOpenMeteoProvider):
        def __init__(self):
            self.calls = []

        async def fetch(self, query):
            self.calls.append(query)
            return await RawOpenMeteoProvider.fetch(self, query)

    provider = Counting()
    result, *_ = _recommend(provider=provider)
    assert result.status is ConditionsStatus.DEGRADED
    assert len(provider.calls) == 1


def test_after_midnight_shares_observing_date_and_moon_info_instant() -> None:
    reference = datetime(2026, 3, 8, 9, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Los_Angeles")
    transport = LocalCalendarTransport(date(2026, 3, 8), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    engine = RecordingRecommendationEngine()
    conditions = ConditionsService(
        provider, atlas_path=None, clock=lambda: reference
    )
    result = asyncio.run(
        RecommendationService(conditions, engine=engine).recommend(
            location=LA,
            location_source=LocationSource.EXPLICIT_OVERRIDE,
            reference_time=reference,
            mode=RecommendationMode.BEST,
            equipment=_empty_equipment(),
        )
    )
    parallel = asyncio.run(
        conditions.conditions(ConditionsRequest(LA, reference))
    )
    assert result.night.observing_date == date(2026, 3, 7)
    assert result.night.observing_date == parallel.selected_night.observing_date
    moon_info = [body for name, body in engine.recorded if name == "astronomy.moon_info"]
    assert moon_info
    assert moon_info[0]["time"] == result.night.observing_day_start.strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    assert len(transport.calls) == 2
    assert "past_days" not in transport.calls[0]
    assert transport.calls[1]["past_days"] == "1"


def test_explicit_observing_date_vs_active_night() -> None:
    reference = datetime(2026, 3, 8, 9, 30, tzinfo=timezone.utc)
    local_zone = ZoneInfo("America/Los_Angeles")
    transport = LocalCalendarTransport(date(2026, 3, 8), local_zone)
    provider = OpenMeteoWeatherProvider(
        transport,
        policy=OpenMeteoPolicy(max_attempts=1),
        clock=lambda: reference,
    )
    conditions = ConditionsService(
        provider, atlas_path=None, clock=lambda: reference
    )
    service = RecommendationService(conditions)
    omitted = asyncio.run(
        service.recommend(
            location=LA,
            location_source=LocationSource.EXPLICIT_OVERRIDE,
            reference_time=reference,
            mode=RecommendationMode.BEST,
            equipment=_empty_equipment(),
        )
    )
    explicit = asyncio.run(
        service.recommend(
            location=LA,
            location_source=LocationSource.EXPLICIT_OVERRIDE,
            reference_time=reference,
            mode=RecommendationMode.BEST,
            observing_date=date(2026, 3, 8),
            equipment=_empty_equipment(),
        )
    )
    omitted_conditions = asyncio.run(
        conditions.conditions(ConditionsRequest(LA, reference))
    )
    explicit_conditions = asyncio.run(
        conditions.conditions(
            ConditionsRequest(LA, reference, observing_date=date(2026, 3, 8))
        )
    )
    assert omitted.night.observing_date == omitted_conditions.selected_night.observing_date
    assert explicit.night.observing_date == explicit_conditions.selected_night.observing_date
    assert omitted.night.observing_date == date(2026, 3, 7)
    assert explicit.night.observing_date == date(2026, 3, 8)


def test_two_dso_windows_remain_distinct() -> None:
    class TwoWindows(RecommendationEngine):
        def deep_sky_windows(self, target_id, location, night_start, night_end):
            if target_id != "m31":
                return super().deep_sky_windows(
                    target_id, location, night_start, night_end
                )
            start = night_start
            mid = night_start + timedelta(hours=2)
            end = night_end
            return [
                {
                    "start": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "end": mid.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "best_time": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "max_altitude": 70.0,
                    "azimuth": 180.0,
                    "direction": "S",
                },
                {
                    "start": mid.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "end": end.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "best_time": mid.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "max_altitude": 55.0,
                    "azimuth": 200.0,
                    "direction": "SW",
                },
            ]

        def planet_observation(self, target_id, location, night_start, night_end):
            return None

        def moon_recommendation(self, observation, **kwargs):
            return None

        def deep_sky(self):
            return [
                entry
                for entry in super().deep_sky()
                if entry["id"] == "m31"
            ]

    result, *_ = _recommend(engine=TwoWindows())
    m31 = [row for row in result.recommendations if row.target_id == "m31"]
    keys = [row.key for row in m31]
    assert len(keys) == len(set(keys))
    assert all("@" in key for key in keys)


def test_targets_recommend_is_deep_sky_only() -> None:
    result, service, *_ = _recommend(engine=RecordingRecommendationEngine())
    payloads = [
        body for name, body in service._engine.recorded if name == "targets.recommend"
    ]
    if payloads:
        assert {row["type"] for row in payloads[0]["candidates"]} == {"deepSky"}
        assert all(
            row.scoring_path is ScoringPath.TARGETS_RECOMMEND
            for row in result.recommendations
            if row.target_type == "deepSky"
        )
        assert all(
            row.scoring_path is not ScoringPath.TARGETS_RECOMMEND
            for row in result.recommendations
            if row.target_type != "deepSky"
        )


def test_corrupt_equipment_store_fails_closed(tmp_path: Path) -> None:
    path = tmp_path / "equipment.json"
    path.write_text("{not-json", encoding="utf-8")
    with pytest.raises(EquipmentStoreCorruptError):
        FileEquipmentStore(path).load()


def test_excellent_only_can_empty_with_reason() -> None:
    store = MemoryEquipmentStore()
    store.save(s30(id=S30_ID))
    selected = compose_active(store.load())
    result, *_ = _recommend(
        equipment=selected, minimum_fit=MinimumFit.EXCELLENT_ONLY
    )
    if result.pool_size and not result.recommendations:
        assert result.empty_reason is EmptyReason.NONE_MEET_EQUIPMENT_FIT
        assert result.equipment_matched_count == 0


class MixedCatalogEngine(RecommendationEngine):
    """Six planets scoring 90-85, then Albireo 80 and M31 40."""

    def solar_system(self):
        return [{"id": f"p{index}", "type": "planet"} for index in range(6)]

    def deep_sky(self):
        return [
            {
                "id": "m31",
                "common_name": "Andromeda",
                "object_type": "galaxy",
                "difficulty": 0.4,
                "surface_brightness": 13.5,
            },
            {
                "id": "albireo",
                "common_name": "Albireo",
                "object_type": "double_star",
                "difficulty": 0.2,
                "surface_brightness": None,
            },
        ]

    def moon_info(self, location, instant):
        return {"altitude": 0.0, "illumination": 0}

    def moon_recommendation(self, observation, **kwargs):
        return None

    def planet_observation(self, target_id, location, night_start, night_end):
        return {"samples": list(_PLANET_SAMPLES)}

    def planet_recommendation(self, target_id, samples, **kwargs):
        return _specialized_row(90 - int(str(target_id)[1:]))

    def deep_sky_windows(self, target_id, location, night_start, night_end):
        return [dict(_SPECIALIZED_WINDOW)]

    def recommend_deep_sky(self, *, rows, **kwargs):
        scores = {"m31": 40, "albireo": 80}
        return {key: scores[key.split("@")[0]] for key, *_rest in rows}

    def filter_recommendations(self, rows, equipment, minimum_fit):
        return list(range(len(rows)))

    def requirements(self, target_id):
        return {
            "requirement": dict(_STUB_REQUIREMENT),
            "is_planet": str(target_id).startswith("p"),
        }

    def match_equipment(self, requirement, is_planet, equipment):
        return None


def test_best_rejects_browse_fields() -> None:
    with pytest.raises(InvalidRequestError, match="best mode"):
        _recommend(
            engine=MixedCatalogEngine(),
            mode=RecommendationMode.BEST,
            object_types=("galaxy",),
        )


def test_best_does_not_apply_score_floor() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(), mode=RecommendationMode.BEST
    )
    assert [row.target_id for row in result.recommendations] == [
        "p0", "p1", "p2", "p3", "p4",
    ]
    assert result.query.mode is RecommendationMode.BEST
    assert result.query.minimum_score is None
    assert result.query.limit is None
    assert result.truncated is True
    assert result.equipment_matched_count == 8
    assert result.query_matched_count == 8
    assert result.returned_count == 5
    assert "family" not in result.recommendations[0].__dataclass_fields__
    assert "is_planet" not in result.recommendations[0].__dataclass_fields__


def test_browse_default_score_floor_and_query_echo() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(), mode=RecommendationMode.BROWSE
    )
    assert result.query.mode is RecommendationMode.BROWSE
    assert result.query.minimum_score == BROWSE_DEFAULT_MINIMUM_SCORE
    assert result.query.limit is None
    assert all(row.score >= 45 for row in result.recommendations)
    assert [row.target_id for row in result.recommendations] == [
        "p0", "p1", "p2", "p3", "p4", "p5", "albireo",
    ]
    assert "m31" not in {row.target_id for row in result.recommendations}
    assert result.equipment_matched_count == 8
    assert result.query_matched_count == 7
    assert result.returned_count == 7
    assert result.truncated is False


def test_browse_minimum_score_zero_includes_poor_targets() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(),
        mode=RecommendationMode.BROWSE,
        minimum_score=0,
    )
    assert result.query.minimum_score == 0
    assert [row.target_id for row in result.recommendations][-1] == "m31"
    assert result.recommendations[-1].score == 40
    assert result.returned_count == 8
    assert result.truncated is False


def test_browse_object_type_searches_beyond_best_five() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(),
        mode=RecommendationMode.BROWSE,
        object_types=("galaxy",),
        minimum_score=0,
    )
    assert [row.target_id for row in result.recommendations] == ["m31"]
    assert result.recommendations[0].rank == 1
    assert result.recommendations[0].overall_rank == 8
    assert result.recommendations[0].target_type == "deepSky"
    assert result.recommendations[0].object_type == "galaxy"
    assert result.query.object_types == ("galaxy",)
    assert result.query_matched_count == 1
    assert result.truncated is False


def test_browse_filters_before_limit() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(),
        mode=RecommendationMode.BROWSE,
        target_types=("deepSky",),
        minimum_score=0,
        limit=1,
    )
    assert [row.target_id for row in result.recommendations] == ["albireo"]
    assert result.query_matched_count == 2
    assert result.returned_count == 1
    assert result.truncated is True
    assert result.query.limit == 1
    assert result.recommendations[0].overall_rank == 7


def test_browse_deep_sky_includes_double_stars() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(),
        mode=RecommendationMode.BROWSE,
        target_types=("deepSky",),
        minimum_score=0,
    )
    assert [row.target_id for row in result.recommendations] == ["albireo", "m31"]
    assert {row.object_type for row in result.recommendations} == {
        "doubleStar",
        "galaxy",
    }


def test_browse_planet_and_galaxy_filters_are_valid_empty() -> None:
    result, *_ = _recommend(
        engine=MixedCatalogEngine(),
        mode=RecommendationMode.BROWSE,
        target_types=("planet",),
        object_types=("galaxy",),
        minimum_score=0,
    )
    assert result.recommendations == ()
    assert result.equipment_matched_count == 8
    assert result.query_matched_count == 0
    assert result.empty_reason is EmptyReason.NONE_MATCH_QUERY


def test_browse_default_floor_can_empty_low_scores() -> None:
    result, *_ = _recommend(
        engine=ScoreThirty(), mode=RecommendationMode.BROWSE
    )
    assert result.query.minimum_score == 45
    assert result.equipment_matched_count >= 1
    assert result.recommendations == ()
    assert result.query_matched_count == 0
    assert result.empty_reason is EmptyReason.NONE_MATCH_QUERY
