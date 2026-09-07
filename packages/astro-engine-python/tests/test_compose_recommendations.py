"""Unit semantics for targets.compose_recommendations."""
from __future__ import annotations

import pytest

from astro_engine.compose_recommendations import (
    CAPABILITY_ID,
    EARLIEST_EPOCH_SECONDS,
    INTEGER_MAGNITUDE_LIMIT,
    LATEST_EPOCH_SECONDS,
    MAX_ROW_COUNT,
    MAX_SCORE,
    MIN_SCORE,
    Candidate,
    compose_recommendations,
    selected,
)
from astro_engine.errors import SampleCapError, ValidationError


def row(key: str, score: int, best_time: str) -> dict:
    return {"key": key, "score": score, "best_time": best_time}


def compose(candidates: list, limit) -> list:
    return compose_recommendations({"candidates": candidates, "limit": limit})["selected"]


def keys(result: list) -> list[str]:
    return [item["key"] for item in result]


def indices(result: list) -> list[int]:
    return [item["index"] for item in result]


# --- ordering -------------------------------------------------------------


def test_score_descending_is_the_primary_key():
    result = compose([
        row("m31", 61, "2026-03-01T22:00:00Z"),
        row("moon", 84, "2026-03-01T21:00:00Z"),
        row("jupiter", 73, "2026-03-01T23:00:00Z"),
    ], 5)
    assert keys(result) == ["moon", "jupiter", "m31"]
    assert indices(result) == [1, 2, 0]


def test_equal_scores_break_on_earlier_best_time():
    result = compose([
        row("saturn", 70, "2026-03-01T23:45:00Z"),
        row("m42", 70, "2026-03-01T20:15:00Z"),
        row("moon", 70, "2026-03-01T22:00:00Z"),
    ], 5)
    assert keys(result) == ["m42", "moon", "saturn"]


def test_complete_tie_preserves_input_order():
    result = compose([row(key, 66, "2026-03-01T21:00:00Z")
                      for key in ("venus", "m45", "moon", "mars")], 10)
    assert indices(result) == [0, 1, 2, 3]


def test_no_target_type_has_priority_independent_of_score_and_best_time():
    result = compose([
        row("m31", 61, "2026-03-01T20:00:00Z"),
        row("jupiter", 61, "2026-03-01T21:00:00Z"),
        row("moon", 60, "2026-03-01T23:00:00Z"),
    ], 5)
    assert keys(result) == ["m31", "jupiter", "moon"]


def test_duplicate_keys_are_preserved_and_disambiguated_by_index():
    result = compose([
        row("m31", 50, "2026-03-01T22:00:00Z"),
        row("m31", 70, "2026-03-01T22:00:00Z"),
        row("m31", 50, "2026-03-01T21:00:00Z"),
    ], 5)
    assert keys(result) == ["m31"] * 3
    assert indices(result) == [1, 2, 0]


def test_selected_helper_returns_original_indices():
    rows = [Candidate("a", 40, 10.0), Candidate("b", 91, 5.0), Candidate("c", 40, 5.0)]
    assert [item.index for item in selected(rows, 3)] == [1, 2, 0]


# --- limit ----------------------------------------------------------------


def test_limit_truncates_after_ordering():
    result = compose([
        row("m13", 55, "2026-03-01T20:30:00Z"),
        row("moon", 84, "2026-03-01T21:00:00Z"),
        row("jupiter", 73, "2026-03-01T23:00:00Z"),
    ], 2)
    assert keys(result) == ["moon", "jupiter"]


@pytest.mark.parametrize(
    "limit", [0, -1, -3, -1441, -100_000, -INTEGER_MAGNITUDE_LIMIT])
def test_zero_and_negative_limits_select_nothing(limit):
    """`limit` has no semantic lower bound: production is max(0, limit)."""
    assert compose([row("moon", 84, "2026-03-01T21:00:00Z")], limit) == []


@pytest.mark.parametrize("limit", [3, 1441, 100_000, INTEGER_MAGNITUDE_LIMIT])
def test_limit_above_candidate_count_returns_everything(limit):
    """A limit far above the 1440 row cap cannot add work or output."""
    rows = [row("moon", 84, "2026-03-01T21:00:00Z"), row("m31", 61, "2026-03-01T22:00:00Z")]
    assert keys(compose(rows, limit)) == ["moon", "m31"]


@pytest.mark.parametrize(
    "limit", [5, 0, -1, -INTEGER_MAGNITUDE_LIMIT, INTEGER_MAGNITUDE_LIMIT])
def test_empty_candidates_compose_to_nothing(limit):
    assert compose([], limit) == []


# --- transport ------------------------------------------------------------


def test_integral_floats_are_accepted():
    assert keys(compose([row("moon", 84.0, "2026-03-01T21:00:00Z")], 1.0)) == ["moon"]


@pytest.mark.parametrize("document", [
    {"candidates": [], "limit": 5, "tie_breaker": "type"},
    {"candidates": []},
    {"limit": 5},
    {"candidates": [{"key": "moon", "score": 84,
                     "best_time": "2026-03-01T21:00:00Z", "type": "moon"}], "limit": 5},
    {"candidates": [{"key": "moon", "score": 84}], "limit": 5},
    {"candidates": {"key": "moon"}, "limit": 5},
    {"candidates": ["moon"], "limit": 5},
    {"candidates": [row("", 84, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [row("moon", True, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [], "limit": True},
    {"candidates": [row("moon", "84", "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [row("moon", 84.5, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [], "limit": 2.5},
    {"candidates": [row("moon", MIN_SCORE - 1, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [row("moon", MAX_SCORE + 1, "2026-03-01T21:00:00Z")], "limit": 5},
    {"candidates": [], "limit": -INTEGER_MAGNITUDE_LIMIT - 1},
    {"candidates": [], "limit": INTEGER_MAGNITUDE_LIMIT + 1},
    {"candidates": [], "limit": float("inf")},
    {"candidates": [], "limit": float("nan")},
    {"candidates": [], "limit": "5"},
    {"candidates": [row("moon", 84, "2026-03-01T21:00:00+00:00")], "limit": 5},
    {"candidates": [row("moon", 84, "2026-03-01 21:00:00")], "limit": 5},
    {"candidates": [row("moon", 84, "1999-12-31T21:59:59Z")], "limit": 5},
    {"candidates": [row("moon", 84, "2500-01-01T01:15:00Z")], "limit": 5},
])
def test_invalid_documents_fail_closed(document):
    with pytest.raises(ValidationError) as excinfo:
        compose_recommendations(document)
    assert str(excinfo.value) == f"invalid {CAPABILITY_ID} input"


def test_boundary_scores_and_instants_are_accepted():
    assert len(compose([
        row("floor", MIN_SCORE, "1999-12-31T22:00:00Z"),
        row("ceiling", MAX_SCORE, "2500-01-01T01:14:59Z"),
    ], 5)) == 2


def test_limit_uses_the_shared_engine_integer_magnitude():
    """The same bound targets.moon_recommendation applies to its integers."""
    from astro_engine.moon_recommendation import _integer as moon_integer

    assert INTEGER_MAGNITUDE_LIMIT == 1_000_000_000
    assert moon_integer(INTEGER_MAGNITUDE_LIMIT) == INTEGER_MAGNITUDE_LIMIT
    with pytest.raises(ValidationError):
        moon_integer(INTEGER_MAGNITUDE_LIMIT + 1)


def test_accepted_instant_range_is_the_planet_window_spill():
    assert EARLIEST_EPOCH_SECONDS == 946_684_800.0 - 7200.0
    assert LATEST_EPOCH_SECONDS == 16_725_225_599.0 + 4500.0


def test_row_cap_is_checked_before_iteration():
    rows = [row(f"t{index}", 50, "2026-03-01T21:00:00Z") for index in range(MAX_ROW_COUNT + 1)]
    with pytest.raises(SampleCapError) as excinfo:
        compose(rows, 5)
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)")
    assert len(compose(rows[:MAX_ROW_COUNT], INTEGER_MAGNITUDE_LIMIT)) == MAX_ROW_COUNT
