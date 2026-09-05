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
    engine_semver,
    generate_grid,
    load_deep_sky_catalog,
    public_night_score,
    score_fog,
    seeing_penalty,
    transparency_penalty,
)
from astro_engine.catalog import CAPABILITY_ID as CATALOG_CAPABILITY_ID
from astro_engine.grid import CAPABILITY_ID as GRID_CAPABILITY_ID
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
    assert callable(decode_iss)
    assert callable(generate_grid)
    assert callable(load_deep_sky_catalog)
    assert LightPollutionArtifact.from_bytes is not None
    assert engine_semver() == "0.1.0"
    assert CAPABILITY_ID == "observing_quality.assess"
    assert LP_CAPABILITY_ID == "light_pollution.lookup"
    assert WEATHER_CAPABILITY_ID == "weather.decode"
    assert ISS_CAPABILITY_ID == "iss.decode"
    assert GRID_CAPABILITY_ID == "location.grid"
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
        "catalog.deep_sky",
    )


def test_pyproject_has_no_runtime_dependencies() -> None:
    path = Path(__file__).resolve().parents[1] / "pyproject.toml"
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    assert data["project"]["dependencies"] == []
    assert data["project"]["requires-python"] == ">=3.11"


def test_no_package_local_provider_fixture_copies() -> None:
    root = Path(__file__).resolve().parents[1]
    banned = {"happy-path.json", "two-passes.json", "deep-sky.json"}
    found = [path for path in root.rglob("*.json") if path.name in banned]
    assert found == []
