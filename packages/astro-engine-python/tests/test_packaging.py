from __future__ import annotations

import importlib

from astro_engine import (
    analyze_night_conditions,
    assess_observing_quality,
    engine_semver,
    public_night_score,
    score_fog,
    seeing_penalty,
    transparency_penalty,
)
from astro_engine.observing_quality import CAPABILITY_ID


def test_public_imports() -> None:
    assert callable(assess_observing_quality)
    assert callable(score_fog)
    assert callable(seeing_penalty)
    assert callable(transparency_penalty)
    assert callable(analyze_night_conditions)
    assert callable(public_night_score)
    assert engine_semver() == "0.1.0"
    assert CAPABILITY_ID == "observing_quality.assess"
    module = importlib.import_module("astro_engine.cli")
    assert callable(module.main)
    assert "F2 allow-list: observing_quality.assess" in module.USAGE
