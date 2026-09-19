from __future__ import annotations

import math

import pytest

from astro_engine.errors import ValidationError
from astro_engine.transparency import transparency_penalty


def test_never_returns_null() -> None:
    assert transparency_penalty({"total_cloud_cover": 0}) == {"penalty": 0.0}


def test_missing_layers_use_total_cloud() -> None:
    assert transparency_penalty(
        {
            "total_cloud_cover": 60,
            "low_cloud_cover": 0,
            "high_cloud_cover": 0,
        }
    ) == {"penalty": 1.0}


def test_clamp_total_above_100() -> None:
    assert transparency_penalty({"total_cloud_cover": 150}) == {"penalty": 2.0}


def test_layered_max_with_total() -> None:
    # layered = 0*0.5 + 0*0.3 + 100*0.2 = 20 → 0.5; total 0 → max 20
    assert transparency_penalty(
        {
            "total_cloud_cover": 0,
            "low_cloud_cover": 0,
            "mid_cloud_cover": 0,
            "high_cloud_cover": 100,
        }
    ) == {"penalty": 0.5}


def test_visibility_lower_bound_and_combine() -> None:
    # cloud 0, vis 1000 → vis component 2, combined 0.5, max(0, 0.5)=0.5
    assert transparency_penalty(
        {
            "total_cloud_cover": 0,
            "visibility_meters": 1000,
        }
    ) == {"penalty": 0.5}


def test_clear_vis_20km() -> None:
    assert transparency_penalty(
        {
            "total_cloud_cover": 0,
            "low_cloud_cover": 0,
            "mid_cloud_cover": 0,
            "high_cloud_cover": 0,
            "visibility_meters": 20000,
        }
    ) == {"penalty": 0.0}


def test_boolean_and_non_finite_rejected() -> None:
    with pytest.raises(ValidationError):
        transparency_penalty({"total_cloud_cover": False})
    with pytest.raises(ValidationError):
        transparency_penalty(
            {"total_cloud_cover": 0, "visibility_meters": math.inf}
        )
