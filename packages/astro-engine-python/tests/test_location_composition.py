from __future__ import annotations

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.grid import CONTRACT_POINT_CAP
from astro_engine.location_compose_scores import (
    CAPABILITY_ID as COMPOSE_ID,
    Candidate,
    MAX_CANDIDATE_COUNT as COMPOSE_CAP,
    ObservingQualityInput,
    compose,
    compose_location_scores,
)
from astro_engine.location_filter_recommendable import (
    CAPABILITY_ID as FILTER_ID,
    MAX_CANDIDATE_COUNT as FILTER_CAP,
    filter_recommendable,
)
from compare import compare_envelope
from python_eval import python_envelope
from support import iter_capability_fixtures

COMPOSE_DIR = "fixtures/capabilities/location-compose-scores"
FILTER_DIR = "fixtures/capabilities/location-filter-recommendable"
COMPOSE_FIXTURES = (
    "boolean-score-v1",
    "fractional-score-v1",
    "multiple-centers-v1",
    "no-scorable-locations-v1",
    "oq-mode-unscorable-lp-ignored-v1",
    "score-above-domain-v1",
    "search-wide-fallback-v1",
    "unknown-observing-quality-field-v1",
    "unscorable-center-boundary-scores-v1",
)
FILTER_FIXTURES = ("empty-v1", "four-states-v1", "invalid-state-v1", "unknown-field-v1")


@pytest.mark.parametrize(
    ("directory", "capability", "fixture_id"),
    [
        *((COMPOSE_DIR, COMPOSE_ID, fixture_id) for fixture_id in COMPOSE_FIXTURES),
        *((FILTER_DIR, FILTER_ID, fixture_id) for fixture_id in FILTER_FIXTURES),
    ],
)
def test_named_location_composition_fixtures(directory, capability, fixture_id):
    fixtures = {item["id"]: item for item in iter_capability_fixtures(directory)}
    fixture = fixtures[fixture_id]
    actual = python_envelope(capability, fixture["input"])
    compare_envelope(actual, fixture["expected"], policy_id=fixture["meta"]["equality"])


def test_fixture_sets_are_frozen():
    assert tuple(item["id"] for item in iter_capability_fixtures(COMPOSE_DIR)) == COMPOSE_FIXTURES
    assert tuple(item["id"] for item in iter_capability_fixtures(FILTER_DIR)) == FILTER_FIXTURES


def test_transport_caps_are_shared_location_grid_size():
    assert COMPOSE_CAP == FILTER_CAP == CONTRACT_POINT_CAP


@pytest.mark.parametrize(
    ("night_score", "observing_quality_score"),
    [(-1, 50), (101, 50), (50, -1), (50, 101)],
)
def test_typed_compose_rejects_out_of_range_scores(
    night_score, observing_quality_score
):
    candidate = Candidate(
        is_center=True,
        night_conditions_score=night_score,
        has_nighttime_rows=True,
        observing_quality=ObservingQualityInput(
            score=observing_quality_score,
            has_valid_light_pollution=True,
        ),
    )

    with pytest.raises(ValidationError, match="invalid location.compose_scores input"):
        compose([candidate])


def test_filter_requires_exact_portable_states():
    assert filter_recommendable(
        {"suitability": ["suitable", "unknown", "unchecked", "unsuitable"]}
    ) == {"recommendable_input_indices": [0, 1]}


def test_compose_requires_exact_input_keys():
    with pytest.raises(ValidationError, match="invalid location.compose_scores input"):
        compose_location_scores({"candidates": [], "ranking": []})


@pytest.mark.parametrize(
    "evaluate,key",
    [
        (compose_location_scores, "candidates"),
        (filter_recommendable, "suitability"),
    ],
)
def test_transport_caps_reject_one_row_over_the_shared_grid_bound(evaluate, key):
    with pytest.raises(SampleCapError):
        evaluate({key: [None] * 886})
