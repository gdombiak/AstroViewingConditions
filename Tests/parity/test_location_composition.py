"""Cross-language parity for the deterministic Best Nearby composition slice."""
from __future__ import annotations

import pytest

from compare import compare_envelope
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPABILITIES = {"location.compose_scores", "location.filter_recommendable"}
CASES = [
    fixture
    for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] in CAPABILITIES
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_location_composition_exact_both_directions(fixture):
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
        compare_envelope(actual, expected, policy_id=fixture["meta"]["equality"])


def test_fixture_count_and_metadata():
    assert len(CASES) == 13
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]
