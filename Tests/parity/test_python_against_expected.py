from __future__ import annotations

from astro_engine.contracts import engine_semver
from astro_engine.semver import satisfies

from compare import compare_envelope
from fixtures import iter_scoring_fixtures
from python_eval import python_envelope


def test_python_matches_hand_authored_scoring_fixtures() -> None:
    fixtures = list(iter_scoring_fixtures())
    assert len(fixtures) >= 14
    version = engine_semver()
    for fixture in fixtures:
        meta = fixture["meta"]
        capability = meta["capability"]
        assert satisfies(version, meta["engine_semver"]), fixture["id"]
        assert "engine_semver" not in fixture["expected"], fixture["id"]
        actual = python_envelope(capability, fixture["input"])
        compare_envelope(
            actual,
            fixture["expected"],
            policy_id=meta["equality"],
        )
