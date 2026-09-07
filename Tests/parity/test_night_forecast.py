"""Parity and public-contract checks for night forecast-window derivation."""
from __future__ import annotations

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPABILITY = "night_forecast.derive_window"
CASES = [
    fixture for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] == CAPABILITY
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_night_forecast_window_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope(CAPABILITY, fixture["input"])
    for actual, expected in (
        (swift, fixture["expected"]),
        (python, fixture["expected"]),
        (swift, python),
        (python, swift),
    ):
        compare_envelope(actual, expected, policy_id="night_forecast_window")


def test_catalog_fixture_and_equality_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    catalog_ids = [
        line.split(": ", 1)[1]
        for line in catalog.splitlines()
        if line.startswith("  - id: ")
    ]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-1] == CAPABILITY
    block = catalog.split(f"  - id: {CAPABILITY}\n", 1)[1]
    assert 'since: "1.0.0"' in block
    assert "hosts: [ios, cli]" in block
    assert "equality: night_forecast_window" in block

    assert load_policy_fields("night_forecast_window") == {
        "time_zone": "exact",
        "start": "exact",
        "end": "exact",
        "code": "exact",
        "message": "exact",
    }
    assert len(CASES) == 17
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_required_calendar_edges_are_represented():
    fixture_ids = {fixture["id"] for fixture in CASES}
    assert {
        "ordinary-night-v1",
        "spring-forward-gap-v1",
        "fall-back-repeat-v1",
        "midnight-transition-v1",
        "non-hour-offset-v1",
        "missing-tomorrow-v1",
        "dropped-civil-date-v1",
        "lord-howe-half-hour-gap-v1",
        "chatham-quarter-boundary-gap-v1",
        "bahia-banderas-two-hour-gap-v1",
        "godthab-late-day-gap-v1",
        "caracas-post-transition-v1",
        "casey-multi-hour-midnight-gap-v1",
    } <= fixture_ids
