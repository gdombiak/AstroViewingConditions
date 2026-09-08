"""Astro Engine Python library.

Public CLI 1.0 allow-list is the catalogued contract set in cli.py.
Library surface includes scoring, LPATLAS1 lookup, weather/ISS decode,
grid, location comparison, and the curated catalog. Capability execution
is shared with the CLI through `_capability.evaluate_capability`.
"""

from astro_engine.catalog import load_deep_sky_catalog
from astro_engine.cloud_timing import classify_cloud_timing
from astro_engine.contracts import engine_semver
from astro_engine.fog import score_fog
from astro_engine.grid import generate_grid
from astro_engine.location_compare import compare_locations
from astro_engine.location_compose_scores import compose_location_scores
from astro_engine.location_filter_recommendable import filter_recommendable
from astro_engine.iss import decode_iss
from astro_engine.light_pollution import LightPollutionArtifact
from astro_engine.night_conditions import analyze_night_conditions, public_night_score
from astro_engine.night_forecast import derive_window as derive_night_forecast_window
from astro_engine.observing_quality import assess_observing_quality
from astro_engine.seeing import seeing_penalty
from astro_engine.transparency import transparency_penalty
from astro_engine.weather import decode_weather

__all__ = [
    "LightPollutionArtifact",
    "analyze_night_conditions",
    "assess_observing_quality",
    "classify_cloud_timing",
    "decode_iss",
    "decode_weather",
    "derive_night_forecast_window",
    "compare_locations",
    "compose_location_scores",
    "engine_semver",
    "filter_recommendable",
    "generate_grid",
    "load_deep_sky_catalog",
    "public_night_score",
    "score_fog",
    "seeing_penalty",
    "transparency_penalty",
]
