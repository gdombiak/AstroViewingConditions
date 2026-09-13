"""Cross-runtime equality for arbitrary-coordinate great-circle distance."""
from __future__ import annotations

import pytest

from compare import compare_envelope
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CASES = [item for item in iter_deterministic_fixtures()
         if item["meta"]["capability"] == "location.distance"]


@pytest.mark.parametrize("fixture", CASES, ids=lambda item: item["id"])
def test_location_distance_swift_python_parity(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope("location.distance", fixture["input"])
    for actual, expected in ((swift, fixture["expected"]),
                             (python, fixture["expected"]),
                             (swift, python)):
        compare_envelope(actual, expected, policy_id="location_distance")


def test_distance_fixture_count():
    assert len(CASES) == 5
