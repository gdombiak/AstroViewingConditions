from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from astro_engine.catalog import load_deep_sky_catalog
from astro_engine.compose_recommendations import compose_recommendations
from astro_engine.deep_sky_observation import evaluate_deep_sky_observation
from astro_engine.equipment import match_equipment
from astro_engine.errors import ValidationError
from astro_engine.filter_recommendations_by_equipment import (
    REQUIREMENT_KEYS,
    filter_recommendations_by_equipment,
)
from astro_engine.moon_observation import evaluate_moon_observation
from astro_engine.moon_recommendation import recommend_moon
from astro_engine.planet_observation import evaluate_planet_observation
from astro_engine.planet_recommendation import recommend_planet
from astro_engine.target_metadata import OBJECT_TYPES, evaluate_metadata
from astro_engine.targets import recommend_targets

from astro_host.engine import CATALOG_OBJECT_TYPES, RecommendationEngine
from astro_host.equipment_session import compose_active
from astro_host.models import (
    ActiveEquipment,
    EquipmentSelection,
    EquipmentSelectionMode,
    EquipmentSource,
    HourlyRating,
    Location,
)
from astro_host.equipment import MemoryEquipmentStore

from support import RecordingRecommendationEngine
from test_equipment import s30


LA = Location(34.05, -118.24)
NIGHT_START = datetime(2026, 2, 20, 2, 30, tzinfo=timezone.utc)
NIGHT_END = datetime(2026, 2, 20, 14, 0, tzinfo=timezone.utc)
DAY_START = datetime(2026, 2, 19, 8, tzinfo=timezone.utc)


def _camel(snake: str) -> str:
    head, *rest = snake.split("_")
    return head + "".join(part.capitalize() for part in rest)


def _ratings() -> tuple[HourlyRating, ...]:
    return tuple(
        HourlyRating(
            time=NIGHT_START + timedelta(hours=index),
            score=70.0,
            cloud_cover=10,
            fog_score=0,
            moon_illumination=20,
            moon_altitude=10.0,
            wind_speed=2.0,
        )
        for index in range(8)
    )


def test_production_engine_has_no_call_history() -> None:
    engine = RecommendationEngine()
    assert not hasattr(engine, "recorded")
    engine.solar_system()
    assert not hasattr(engine, "recorded")


def test_catalog_object_types_match_public_engine_sets() -> None:
    catalog_types = {entry["object_type"] for entry in load_deep_sky_catalog()}
    assert set(CATALOG_OBJECT_TYPES) == catalog_types
    assert set(CATALOG_OBJECT_TYPES.values()) == OBJECT_TYPES
    for snake, mapped in CATALOG_OBJECT_TYPES.items():
        assert mapped == _camel(snake)
        evaluate_metadata(
            "targets.moon_sensitivity", {"object_type": mapped}
        )
    with pytest.raises(ValidationError):
        evaluate_metadata(
            "targets.moon_sensitivity", {"object_type": "globular_cluster"}
        )


def test_recorded_payloads_inject_into_real_engine_functions() -> None:
    engine = RecordingRecommendationEngine()
    ratings = _ratings()
    observation = engine.moon_observation(LA, NIGHT_START, NIGHT_END)
    recommendation = engine.moon_recommendation(
        observation,
        night_start=NIGHT_START,
        night_end=NIGHT_END,
        cloud_cover_score=10,
        hourly_ratings=ratings,
        best_window=None,
    )
    assert recommendation is None or "score" in recommendation

    moon_obs_payload = _payload(engine, "astronomy.moon_observation")
    assert set(moon_obs_payload) == {
        "latitude", "longitude", "night_start", "night_end",
    }
    evaluate_moon_observation(moon_obs_payload)

    moon_rec_payload = _payload(engine, "targets.moon_recommendation")
    assert set(moon_rec_payload) == {
        "night_start",
        "night_end",
        "best_window",
        "moon",
        "cloud_cover_score",
        "hourly_ratings",
    }
    assert set(moon_rec_payload["moon"]) == {
        "phase",
        "illumination",
        "rise",
        "set",
        "always_up",
        "always_down",
        "samples",
    }
    assert "night_start" not in moon_rec_payload["moon"]
    assert all(
        set(row) == {"time", "score"} for row in moon_rec_payload["hourly_ratings"]
    )
    recommend_moon(moon_rec_payload)

    planet_observation = engine.planet_observation(
        "jupiter", LA, NIGHT_START, NIGHT_END
    )
    assert planet_observation is not None
    engine.planet_recommendation(
        "jupiter",
        planet_observation["samples"],
        night_start=NIGHT_START,
        night_end=NIGHT_END,
        cloud_cover_score=10,
        hourly_ratings=ratings,
    )
    planet_obs_payload = _payload(engine, "astronomy.planet_observation")
    evaluate_planet_observation(planet_obs_payload)
    planet_rec_payload = _payload(engine, "targets.planet_recommendation")
    assert set(planet_rec_payload) == {
        "target_id",
        "night_start",
        "night_end",
        "samples",
        "cloud_cover_score",
        "hourly_ratings",
    }
    assert "sample_start" not in planet_rec_payload
    assert all(
        set(row) == {"time", "altitude", "azimuth", "solar_elongation"}
        for row in planet_rec_payload["samples"]
    )
    recommend_planet(planet_rec_payload)

    windows = engine.deep_sky_windows("m31", LA, NIGHT_START, NIGHT_END)
    window_payload = _payload(engine, "targets.deep_sky_windows")
    assert set(window_payload) == {
        "target_id", "latitude", "longitude", "night_start", "night_end",
    }
    evaluate_deep_sky_observation("targets.deep_sky_windows", window_payload)

    moon = engine.moon_info(LA, DAY_START)
    moon_info_payload = _payload(engine, "astronomy.moon_info")
    assert set(moon_info_payload) == {"latitude", "longitude", "time"}
    assert "time" not in moon

    if windows:
        parsed = engine.parse_visibility_window(windows[0])
        engine.recommend_deep_sky(
            darkness_start=NIGHT_START,
            darkness_end=NIGHT_END,
            moon=moon,
            cloud_cover_score=10,
            hourly_ratings=ratings,
            rows=[
                (
                    "m31@start@end",
                    "galaxy",
                    0.4,
                    1.0,
                    parsed.start,
                    parsed.end,
                    parsed.best_time,
                    parsed.max_altitude,
                )
            ],
        )
        recommend_payload = _payload(engine, "targets.recommend")
        assert {row["type"] for row in recommend_payload["candidates"]} == {"deepSky"}
        assert set(recommend_payload["moon"]) == {"altitude", "illumination"}
        recommend_targets(recommend_payload)

    engine.compose_recommendations(
        [("moon", 80, NIGHT_START), ("m31@a@b", 70, NIGHT_START)],
        limit=100,
    )
    compose_payload = _payload(engine, "targets.compose_recommendations")
    assert set(compose_payload) == {"candidates", "limit"}
    assert compose_payload["limit"] == 100
    assert all(
        set(row) == {"key", "score", "best_time"}
        for row in compose_payload["candidates"]
    )
    compose_recommendations(compose_payload)

    resolved = engine.requirements("m77")
    requirements_payload = _payload(engine, "targets.requirements")
    assert requirements_payload == {"id": "m77"}
    evaluate_metadata("targets.requirements", requirements_payload)
    assert set(resolved["requirement"]) == REQUIREMENT_KEYS
    assert resolved["requirement"]["preferred_binocular_magnification"] is None
    assert resolved["requirement"]["practical_binocular_aperture_mm"] is None

    store = MemoryEquipmentStore()
    store.save(s30(id="3fa85f64-5717-4562-b3fc-2c963f66afa6"))
    active = compose_active(store.load())
    engine.filter_recommendations(
        [("m77", False, resolved["requirement"])],
        active,
        "any",
    )
    filter_payload = _payload(engine, "targets.filter_recommendations_by_equipment")
    assert set(filter_payload) == {
        "candidates", "capabilities", "has_saved_inventory", "minimum_fit",
    }
    assert filter_payload["has_saved_inventory"] is True
    assert filter_payload["has_saved_inventory"] == active.engine_has_saved_inventory
    assert all(
        set(row) == {"key", "type", "aperture_mm", "magnification"}
        for row in filter_payload["capabilities"]
    )
    for row in filter_payload["capabilities"]:
        assert "id" not in row
        assert "name" not in row
    requirement = filter_payload["candidates"][0]["requirement"]
    assert set(requirement) == REQUIREMENT_KEYS
    assert "preferred_binocular_magnification" in requirement
    assert requirement["preferred_binocular_magnification"] is None
    filter_recommendations_by_equipment(filter_payload)

    engine.match_equipment(resolved["requirement"], False, active)
    match_payload = _payload(engine, "equipment.match")
    assert set(match_payload) == {"requirement", "is_planet", "capabilities"}
    match_equipment(match_payload)


def test_filter_uses_engine_has_saved_inventory_not_item_count() -> None:
    engine = RecordingRecommendationEngine()
    resolved = engine.requirements("moon")
    empty = ActiveEquipment(
        source=EquipmentSource.NO_EQUIPMENT,
        has_saved_inventory=False,
        engine_has_saved_inventory=False,
        selection=EquipmentSelection(EquipmentSelectionMode.ALL_SAVED),
        capabilities=(),
        identities=(),
        override_applied=False,
    )
    engine.filter_recommendations(
        [("moon", False, resolved["requirement"])],
        empty,
        "challengingOrBetter",
    )
    payload = _payload(engine, "targets.filter_recommendations_by_equipment")
    assert payload["has_saved_inventory"] is False
    assert payload["minimum_fit"] == "challengingOrBetter"
    filter_recommendations_by_equipment(payload)


def _payload(
    engine: RecordingRecommendationEngine, capability: str
) -> dict[str, object]:
    matches = [body for name, body in engine.recorded if name == capability]
    assert matches, capability
    return matches[-1]
