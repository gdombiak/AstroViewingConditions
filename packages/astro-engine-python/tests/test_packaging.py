from __future__ import annotations

import importlib
import tomllib
from pathlib import Path

from astro_engine import (
    LightPollutionArtifact,
    analyze_night_conditions,
    assess_observing_quality,
    decode_iss,
    decode_weather,
    derive_night_forecast_window,
    engine_semver,
    compare_locations,
    compose_location_scores,
    filter_recommendable,
    generate_grid,
    load_deep_sky_catalog,
    public_night_score,
    score_fog,
    seeing_penalty,
    transparency_penalty,
)
from astro_engine.contracts import contracts_root
from astro_engine.catalog import CAPABILITY_ID as CATALOG_CAPABILITY_ID
from astro_engine.grid import CAPABILITY_ID as GRID_CAPABILITY_ID
from astro_engine.location_compare import CAPABILITY_ID as COMPARE_CAPABILITY_ID
from astro_engine.location_compose_scores import CAPABILITY_ID as COMPOSE_LOCATION_SCORES_ID
from astro_engine.location_filter_recommendable import CAPABILITY_ID as FILTER_RECOMMENDABLE_ID
from astro_engine.iss import CAPABILITY_ID as ISS_CAPABILITY_ID
from astro_engine.light_pollution import CAPABILITY_ID as LP_CAPABILITY_ID
from astro_engine.observing_quality import CAPABILITY_ID
from astro_engine.weather import CAPABILITY_ID as WEATHER_CAPABILITY_ID


def test_public_imports() -> None:
    assert callable(assess_observing_quality)
    assert callable(score_fog)
    assert callable(seeing_penalty)
    assert callable(transparency_penalty)
    assert callable(analyze_night_conditions)
    assert callable(public_night_score)
    assert callable(decode_weather)
    assert callable(derive_night_forecast_window)
    assert callable(decode_iss)
    assert callable(generate_grid)
    assert callable(compare_locations)
    assert callable(compose_location_scores)
    assert callable(filter_recommendable)
    assert callable(load_deep_sky_catalog)
    assert LightPollutionArtifact.from_bytes is not None
    assert engine_semver() == "1.0.0"
    assert CAPABILITY_ID == "observing_quality.assess"
    assert LP_CAPABILITY_ID == "light_pollution.lookup"
    assert WEATHER_CAPABILITY_ID == "weather.decode"
    assert ISS_CAPABILITY_ID == "iss.decode"
    assert GRID_CAPABILITY_ID == "location.grid"
    assert COMPARE_CAPABILITY_ID == "location.compare"
    assert COMPOSE_LOCATION_SCORES_ID == "location.compose_scores"
    assert FILTER_RECOMMENDABLE_ID == "location.filter_recommendable"
    assert CATALOG_CAPABILITY_ID == "catalog.deep_sky"
    module = importlib.import_module("astro_engine.cli")
    assert callable(module.main)
    assert "1.0 allow-list:" in module.USAGE
    assert "F2 allow-list" not in module.USAGE
    assert "--atlas-path FILE" in module.USAGE
    for capability in module.PUBLIC_CAPABILITY_IDS:
        assert capability in module.USAGE
    assert module.PUBLIC_CAPABILITY_IDS == (
        "observing_quality.assess",
        "night_conditions.analyze",
        "night_conditions.score",
        "fog.score",
        "seeing.penalty",
        "transparency.penalty",
        "light_pollution.lookup",
        "weather.decode",
        "iss.decode",
        "location.grid",
        "location.compare",
        "location.compose_scores",
        "location.filter_recommendable",
        "catalog.deep_sky",
        "targets.recommend",
        "equipment.match",
        "observing_window.select",
        "targets.requirements",
        "catalog.solar_system",
        "targets.moon_sensitivity",
        "astronomy.horizontal_position",
        "targets.deep_sky_windows",
        "astronomy.sun_events",
        "astronomy.moon_info",
        "astronomy.moon_series",
        "astronomy.moon_observation",
        "targets.moon_recommendation",
        "astronomy.planet_observation",
        "targets.planet_recommendation",
        "targets.compose_recommendations",
        "targets.filter_recommendations_by_equipment",
        "observing_night.resolve_active",
        "night_forecast.derive_window",
        "night_conditions.classify_cloud_timing",
        "observing_night.compose_outlook",
        "observing_night.select_best",
    )


def test_pyproject_pins_offline_astronomy_dependencies() -> None:
    path = Path(__file__).resolve().parents[1] / "pyproject.toml"
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    assert data["project"]["dependencies"] == ["skyfield==1.55", "skyfield-data==7.0.0"]
    assert data["project"]["requires-python"] == ">=3.11"
    assert data["project"]["version"] == "1.0.0"
    assert data["project"]["version"] == engine_semver()


def test_catalog_current_release_matches_engine_version() -> None:
    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    assert 'engine_semver: "1.0.0"' in catalog
    since_lines = [
        line for line in catalog.splitlines() if line.startswith("    since: ")
    ]
    assert since_lines == (
        ['    since: "0.1.0"'] * 10
        + ['    since: "1.0.0"'] * 3
        + ['    since: "0.1.0"']
        + ['    since: "1.0.0"'] * 22
    )


def test_no_package_local_provider_fixture_copies() -> None:
    root = Path(__file__).resolve().parents[1]
    banned = {"happy-path.json", "two-passes.json", "deep-sky.json", "solar-system.json", "target-requirements.json"}
    found = [
        path for path in root.rglob("*.json")
        if path.name in banned and "build" not in path.parts
    ]
    assert found == []


def test_release_build_sources_runtime_resources_from_canonical_locations() -> None:
    root = Path(__file__).resolve().parents[1]
    hook = (root / "setup.py").read_text(encoding="utf-8")
    assert 'repository / "contracts"' in hook
    assert 'contracts / "data"' in hook
    assert '"light_pollution_global_v1.bin"' in hook
    assert 'Path(self.build_lib) / "astro_engine" / "resources"' in hook
