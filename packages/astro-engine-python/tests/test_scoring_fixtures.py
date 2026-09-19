from __future__ import annotations

from astro_engine.contracts import engine_semver
from astro_engine.semver import satisfies

from compare import compare_envelope
from conftest import PARITY
from python_eval import python_envelope
from support import iter_capability_fixtures

_SCORING_DIRS = (
    "fixtures/capabilities/fog",
    "fixtures/capabilities/seeing",
    "fixtures/capabilities/transparency",
    "fixtures/capabilities/night-conditions",
    "fixtures/capabilities/night-conditions-score",
)

_DECODE_DIRS = (
    "fixtures/capabilities/weather-decode",
    "fixtures/capabilities/iss-decode",
)

_DETERMINISTIC_DIRS = (
    "fixtures/capabilities/location-grid",
    "fixtures/capabilities/catalog-deep-sky",
)


def test_parity_helpers_exist_at_git_recorded_path() -> None:
    assert PARITY.parts[-2:] == ("Tests", "parity"), PARITY
    assert PARITY.is_dir(), PARITY
    assert (PARITY / "compare.py").is_file()
    assert (PARITY / "python_eval.py").is_file()


def test_phase6_contract_fixtures() -> None:
    fixtures = [
        fixture
        for relative in _SCORING_DIRS
        for fixture in iter_capability_fixtures(relative)
    ]
    assert len(fixtures) >= 30
    version = engine_semver()
    for fixture in fixtures:
        meta = fixture["meta"]
        assert satisfies(version, meta["engine_semver"]), fixture["id"]
        assert "engine_semver" not in fixture["expected"], fixture["id"]
        actual = python_envelope(meta["capability"], fixture["input"])
        compare_envelope(actual, fixture["expected"], policy_id=meta["equality"])


def test_phase9_deterministic_contract_fixtures() -> None:
    fixtures = [
        fixture
        for relative in _DETERMINISTIC_DIRS
        for fixture in iter_capability_fixtures(relative)
    ]
    assert len(fixtures) == 6
    version = engine_semver()
    for fixture in fixtures:
        meta = fixture["meta"]
        assert satisfies(version, meta["engine_semver"]), fixture["id"]
        assert "engine_semver" not in fixture["expected"], fixture["id"]
        actual = python_envelope(meta["capability"], fixture["input"])
        compare_envelope(actual, fixture["expected"], policy_id=meta["equality"])


def test_phase8_decode_contract_fixtures() -> None:
    fixtures = [
        fixture
        for relative in _DECODE_DIRS
        for fixture in iter_capability_fixtures(relative)
    ]
    assert len(fixtures) == 13
    version = engine_semver()
    for fixture in fixtures:
        meta = fixture["meta"]
        assert satisfies(version, meta["engine_semver"]), fixture["id"]
        assert "engine_semver" not in fixture["expected"], fixture["id"]
        actual = python_envelope(meta["capability"], fixture["input"])
        compare_envelope(actual, fixture["expected"], policy_id=meta["equality"])
