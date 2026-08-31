from __future__ import annotations

import importlib

from astro_engine import assess_observing_quality, engine_semver
from astro_engine.observing_quality import CAPABILITY_ID


def test_public_imports() -> None:
    assert callable(assess_observing_quality)
    assert engine_semver() == "0.1.0"
    assert CAPABILITY_ID == "observing_quality.assess"
    module = importlib.import_module("astro_engine.cli")
    assert callable(module.main)
