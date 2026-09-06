from __future__ import annotations

import json
from pathlib import Path

import pytest

from astro_engine.errors import ValidationError
from astro_engine.location_compare import (
    CAPABILITY_ID,
    LocationCompareCandidate,
    SUITABILITY_RANK,
    compare_locations,
    is_higher_ranked,
    key_is_less,
)

from compare import compare_envelope
from python_eval import python_envelope
from support import iter_capability_fixtures

COMPARE_DIR = "fixtures/capabilities/location-compare"
FROZEN_FIXTURE_IDS = (
    "default-unchecked-v1",
    "duplicate-key-v1",
    "invalid-suitability-v1",
    "missing-night-conditions-score-v1",
    "public-score-wins-v1",
    "successive-tie-breaks-v1",
    "suitability-injected-v1",
    "unknown-suitability-key-v1",
    "utf8-key-order-v1",
    "utf8-suitability-overlay-v1",
)


def test_named_compare_fixtures_are_contract_owned() -> None:
    fixtures = list(iter_capability_fixtures(COMPARE_DIR))
    assert [item["id"] for item in fixtures] == sorted(FROZEN_FIXTURE_IDS)
    for fixture in fixtures:
        path: Path = fixture["path"]
        assert "packages" not in path.parts
        assert path.parts[-3:] == ("capabilities", "location-compare", fixture["id"])


@pytest.mark.parametrize("fixture_id", FROZEN_FIXTURE_IDS)
def test_named_compare_fixtures(fixture_id: str) -> None:
    fixture = next(item for item in iter_capability_fixtures(COMPARE_DIR) if item["id"] == fixture_id)
    actual = python_envelope(CAPABILITY_ID, fixture["input"])
    compare_envelope(actual, fixture["expected"], policy_id=fixture["meta"]["equality"])


def test_suitability_ranks_match_production_order() -> None:
    assert SUITABILITY_RANK == {
        "suitable": 0,
        "unknown": 1,
        "unchecked": 2,
        "unsuitable": 3,
    }


def test_contract_key_breaks_production_ties() -> None:
    left = _candidate(key="b")
    right = _candidate(key="a")
    assert is_higher_ranked(right, left) is True
    assert is_higher_ranked(left, right) is False
    assert is_higher_ranked(left, right, use_key=False) is False
    assert is_higher_ranked(right, left, use_key=False) is False


def test_utf8_byte_key_order_not_collation_or_canonical_equivalence() -> None:
    combining = "A\u030a"
    precomposed = "\u00c5"
    assert combining.encode("utf-8") < precomposed.encode("utf-8")
    assert key_is_less(combining, precomposed) is True
    assert key_is_less(precomposed, combining) is False
    assert key_is_less("ss", "\u00df") is True
    assert key_is_less("z", "\u00e4") is True
    ranked = compare_locations(
        {
            "candidates": [
                _row("\u00e4"),
                _row("\u00c5"),
                _row(combining),
                _row("z"),
            ]
        }
    )
    assert ranked["ranking"] == [combining, "z", "\u00c5", "\u00e4"]


def _row(key: str) -> dict:
    return {
        "key": key,
        "public_score": 70,
        "night_conditions_score": 70,
        "avg_cloud_cover": 5,
        "fog_score": 5,
        "avg_wind_speed": 5,
        "distance_miles": 8,
        "latitude": 40,
        "longitude": -74,
    }


def test_night_conditions_score_is_not_a_ranking_key() -> None:
    better = _candidate(key="better", public_score=90, night_conditions_score=10)
    worse = _candidate(key="worse", public_score=80, night_conditions_score=100)
    assert is_higher_ranked(better, worse) is True
    assert is_higher_ranked(worse, better) is False


def test_bool_public_score_is_rejected() -> None:
    with pytest.raises(ValidationError, match="public_score must be a finite JSON number"):
        compare_locations(
            {
                "candidates": [
                    {
                        "key": "here",
                        "public_score": True,
                        "night_conditions_score": 80,
                        "avg_cloud_cover": 1,
                        "fog_score": 1,
                        "avg_wind_speed": 1,
                        "distance_miles": 1,
                        "latitude": 1,
                        "longitude": 1,
                    }
                ]
            }
        )


def test_missing_candidates_is_validation() -> None:
    with pytest.raises(ValidationError, match="injected.candidates must be an array"):
        compare_locations({})


def test_object_shaped_suitability_overlay_is_rejected() -> None:
    with pytest.raises(ValidationError, match="suitability must be an array"):
        compare_locations(
            {
                "candidates": [_row("here")],
                "suitability": {"here": "suitable"},
            }
        )


def test_json_eval_path_applies_distinct_suitability_to_canonical_equivalents() -> None:
    document = json.loads(
        r"""
        {
          "candidates": [
            {
              "key": "A\u030A",
              "public_score": 70,
              "night_conditions_score": 70,
              "avg_cloud_cover": 5,
              "fog_score": 5,
              "avg_wind_speed": 5,
              "distance_miles": 8,
              "latitude": 40,
              "longitude": -74
            },
            {
              "key": "\u00C5",
              "public_score": 70,
              "night_conditions_score": 70,
              "avg_cloud_cover": 5,
              "fog_score": 5,
              "avg_wind_speed": 5,
              "distance_miles": 8,
              "latitude": 40,
              "longitude": -74
            }
          ],
          "suitability": [
            {"key": "A\u030A", "suitability": "unsuitable"},
            {"key": "\u00C5", "suitability": "suitable"}
          ]
        }
        """
    )
    result = compare_locations(document)
    combining = "A\u030a"
    precomposed = "\u00c5"
    assert result["ranking"] == [precomposed, combining]
    assert result["locations"][0]["suitability"] == "suitable"
    assert result["locations"][1]["suitability"] == "unsuitable"


def test_omitted_night_conditions_score_is_not_inferred() -> None:
    with pytest.raises(ValidationError, match="night_conditions_score must be a finite JSON number"):
        compare_locations(
            {
                "candidates": [
                    {
                        "key": "here",
                        "public_score": 80,
                        "avg_cloud_cover": 1,
                        "fog_score": 1,
                        "avg_wind_speed": 1,
                        "distance_miles": 1,
                        "latitude": 1,
                        "longitude": 1,
                    }
                ]
            }
        )


def _candidate(
    *,
    key: str,
    public_score: int = 70,
    night_conditions_score: int | None = None,
    cloud: float = 5,
    fog: int = 5,
    wind: float = 5,
    distance: float = 8,
    latitude: float = 40,
    longitude: float = -74,
    suitability: str = "unchecked",
) -> LocationCompareCandidate:
    return LocationCompareCandidate(
        key=key,
        public_score=public_score,
        night_conditions_score=public_score if night_conditions_score is None else night_conditions_score,
        avg_cloud_cover=cloud,
        fog_score=fog,
        avg_wind_speed=wind,
        distance_miles=distance,
        latitude=latitude,
        longitude=longitude,
        suitability=suitability,
    )
