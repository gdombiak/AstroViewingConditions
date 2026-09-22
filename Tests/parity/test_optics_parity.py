"""Cross-runtime equality for telescope and eyepiece optical ratios."""
from __future__ import annotations

import pytest

from compare import compare_envelope
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CASES = [item for item in iter_deterministic_fixtures()
         if item["meta"]["capability"] == "optics.calculate"]


@pytest.mark.parametrize("fixture", CASES, ids=lambda item: item["id"])
def test_optics_swift_python_parity(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope("optics.calculate", fixture["input"])
    for actual, expected in ((swift, fixture["expected"]),
                             (python, fixture["expected"]),
                             (swift, python)):
        compare_envelope(actual, expected, policy_id="optics_calculate")


def test_optics_fixture_count():
    assert len(CASES) == 8


def test_optics_is_the_last_public_capability():
    from astro_engine.cli import PUBLIC_CAPABILITY_IDS
    from astro_engine.contracts import contracts_root

    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    catalog_ids = [
        line.split(": ", 1)[1]
        for line in catalog.splitlines()
        if line.startswith("  - id: ")
    ]
    assert catalog_ids[-1] == "optics.calculate"
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
