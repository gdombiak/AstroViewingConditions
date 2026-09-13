"""Focused library contract checks for cloud-advisory selection."""

from __future__ import annotations

import pytest

from astro_engine.cloud_advisory import select_cloud_advisory
from astro_engine.contracts import night_quality_calibration
from astro_engine.errors import ValidationError


def document(**changes):
    return {
        "cloud_timing": "early_heavy",
        "rating": "good",
        "average_cloud_cover": 10,
        **changes,
    }


@pytest.mark.parametrize("timing", ["early_heavy", "late_heavy", "intermittent_heavy"])
def test_eligible_codes_pass_through(timing):
    assert select_cloud_advisory(document(cloud_timing=timing)) == {
        "cloud_advisory": timing
    }


def test_none_poor_and_calibrated_floor_suppress_advice():
    floor = night_quality_calibration()["cloud_floor"]["cloud_cover_min"]
    for input in (
        document(cloud_timing="none"),
        document(rating="poor"),
        document(average_cloud_cover=floor),
    ):
        assert select_cloud_advisory(input) == {"cloud_advisory": None}
    assert select_cloud_advisory(document(average_cloud_cover=floor - 0.25)) == {
        "cloud_advisory": "early_heavy"
    }


@pytest.mark.parametrize("changes", [
    {"cloud_timing": "unknown"},
    {"rating": "unknown"},
    {"average_cloud_cover": True},
    {"average_cloud_cover": float("nan")},
    {"average_cloud_cover": -1},
])
def test_invalid_values_fail_closed(changes):
    with pytest.raises(ValidationError, match="invalid night_conditions.select_cloud_advisory input"):
        select_cloud_advisory(document(**changes))
