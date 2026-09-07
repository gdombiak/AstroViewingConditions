"""Exact two-way parity and fail-closed contract checks for target metadata."""
from copy import deepcopy

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPS = {"targets.requirements", "catalog.solar_system", "targets.moon_sensitivity"}
CASES = [f for f in iter_deterministic_fixtures() if f["meta"]["capability"] in CAPS]


@pytest.mark.parametrize("fixture", CASES, ids=lambda f: f["id"])
def test_target_metadata_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope(fixture["meta"]["capability"], fixture["input"])
    for actual, expected in ((swift, fixture["expected"]), (python, fixture["expected"]),
                             (swift, python), (python, swift)):
        compare_envelope(actual, expected, policy_id=fixture["meta"]["equality"])


def test_public_catalog_and_manual_fixture_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text()
    ids = [line.split(": ", 1)[1] for line in catalog.splitlines() if line.startswith("  - id: ")]
    assert ids == list(PUBLIC_CAPABILITY_IDS)
    assert len(ids) == 29
    assert len(CASES) == 74
    for fixture in CASES:
        assert fixture['meta']['engine_semver'] == '>=1.0.0 <2.0.0'
        assert fixture['meta']['origin'] == 'manual'
        assert load_policy_fields(fixture['meta']['equality'])


@pytest.mark.parametrize('fixture', [f for f in CASES if f['expected']['ok']], ids=lambda f: f['id'])
def test_exact_equality_rejects_missing_extra_and_changed_values(fixture):
    expected = fixture['expected']
    for mutation in ('missing', 'extra', 'changed'):
        changed = deepcopy(expected)
        row = changed['result']
        key = next(iter(row))
        if mutation == 'missing':
            del row[key]
        elif mutation == 'extra':
            row['unexpected'] = 1
        elif 'requirement' in row:
            row['requirement']['practical_visual_aperture_mm'] = -1
        elif 'entries' in row:
            row['entries'].reverse()
        else:
            row['sensitivity'] += 0.001
        for left, right in ((changed, expected), (expected, changed)):
            with pytest.raises(AssertionError):
                compare_envelope(left, right, policy_id=fixture['meta']['equality'])
