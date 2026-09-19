"""Parity and public-contract checks for three-night outlook composition."""
from __future__ import annotations

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

COMPOSE = "observing_night.compose_outlook"
BEST = "observing_night.select_best"

ALL = list(iter_deterministic_fixtures())
COMPOSE_CASES = [f for f in ALL if f["meta"]["capability"] == COMPOSE]
BEST_CASES = [f for f in ALL if f["meta"]["capability"] == BEST]


def _both_directions(fixture, policy_id):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope(fixture["meta"]["capability"], fixture["input"])
    for actual, expected in (
        (swift, fixture["expected"]),
        (python, fixture["expected"]),
        (swift, python),
        (python, swift),
    ):
        compare_envelope(actual, expected, policy_id=policy_id)


@pytest.mark.parametrize("fixture", COMPOSE_CASES, ids=lambda fixture: fixture["id"])
def test_compose_outlook_exact_both_directions(fixture):
    _both_directions(fixture, "night_outlook")


@pytest.mark.parametrize("fixture", BEST_CASES, ids=lambda fixture: fixture["id"])
def test_select_best_exact_both_directions(fixture):
    _both_directions(fixture, "night_outlook_best")


def test_catalog_fixture_and_equality_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    catalog_ids = [
        line.split(": ", 1)[1]
        for line in catalog.splitlines()
        if line.startswith("  - id: ")
    ]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-2:] == [COMPOSE, BEST]

    compose_block = catalog.split(f"  - id: {COMPOSE}\n", 1)[1]
    assert 'since: "1.0.0"' in compose_block
    assert "hosts: [ios, cli]" in compose_block
    assert "equality: night_outlook" in compose_block
    assert "hourly_times" in compose_block

    best_block = catalog.split(f"  - id: {BEST}\n", 1)[1]
    assert 'since: "1.0.0"' in best_block
    assert "equality: night_outlook_best" in best_block

    assert load_policy_fields("night_outlook") == {
        "state": "exact",
        "time_zone": "exact",
        "nights": "exact",
        "nights[].slot_index": "exact",
        "nights[].day_offset": "exact",
        "nights[].day_index": "exact",
        "nights[].observing_date": "exact",
        "nights[].observing_day_start": "exact",
        "nights[].astronomical_night_start": "exact",
        "nights[].astronomical_night_end": "exact",
        "nights[].status": "exact",
        "code": "exact",
        "message": "exact",
    }
    assert load_policy_fields("night_outlook_best") == {
        "best_index": "exact",
        "code": "exact",
        "message": "exact",
    }

    assert len(COMPOSE_CASES) == 28
    assert len(BEST_CASES) == 16
    for fixture in COMPOSE_CASES + BEST_CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_every_composition_state_and_night_status_is_represented():
    """The states and the three per-night statuses must never collapse."""
    results = [f["expected"]["result"] for f in COMPOSE_CASES if f["expected"]["ok"]]
    assert {result["state"] for result in results} == {
        "resolved", "requires_active_previous_payload", "unavailable"
    }
    statuses = {night["status"] for result in results for night in result["nights"]}
    assert statuses == {"available", "no_astronomical_night", "unavailable"}
    offsets = {
        night["day_offset"] for result in results for night in result["nights"]
    }
    assert offsets == {-1, 0, 1, 2}
    # Every composed outlook is exactly three rows, in slot order.
    for result in results:
        assert [night["slot_index"] for night in result["nights"]] == [0, 1, 2]


def test_best_night_tie_and_eligibility_edges_are_pinned():
    """The tie rule and the eligibility rule each need a fixture that proves them."""
    by_id = {f["id"]: f for f in BEST_CASES}
    assert by_id["tie-selects-earliest-v1"]["expected"]["result"]["best_index"] == 0
    assert by_id["later-tie-after-lower-first-v1"]["expected"]["result"]["best_index"] == 1
    assert by_id["first-row-ineligible-v1"]["expected"]["result"]["best_index"] == 1
    assert by_id["scored-but-not-available-v1"]["expected"]["result"]["best_index"] == 1
    assert by_id["available-without-score-v1"]["expected"]["result"]["best_index"] is None
    assert by_id["no-eligible-rows-v1"]["expected"]["result"]["best_index"] is None
    assert by_id["empty-v1"]["expected"]["result"]["best_index"] is None


def test_presentation_is_absent_from_both_transports():
    """No label, verdict, tone, status text, score or best window crosses here."""
    forbidden = {
        "display_label", "label", "verdict", "score_tone", "tone", "status_text",
        "best_window", "is_best_night", "night_conditions_score",
        "observing_quality_score", "generated_at", "location_name",
    }
    for fixture in COMPOSE_CASES:
        assert not forbidden & set(fixture["input"]["injected"])
        if not fixture["expected"]["ok"]:
            continue
        for night in fixture["expected"]["result"]["nights"]:
            assert not forbidden & set(night)
    for fixture in BEST_CASES:
        rows = fixture["input"]["injected"]["nights"]
        for row in rows:
            if isinstance(row, dict) and set(row) == {"status", "score"}:
                continue
            # Only the deliberately malformed fixture carries anything else.
            assert fixture["id"] == "unexpected-row-key-v1"
