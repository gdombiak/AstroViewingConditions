"""Exact two-way parity and fail-closed contract checks for observing windows."""
from copy import deepcopy

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CASES = [f for f in iter_deterministic_fixtures() if f["meta"]["capability"] == "observing_window.select"]


@pytest.mark.parametrize("fixture", CASES, ids=lambda f: f["id"])
def test_observing_window_exact_both_directions(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == (0 if fixture["expected"]["ok"] else 2), stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope("observing_window.select", fixture["input"])
    for actual, expected in ((swift, fixture["expected"]), (python, fixture["expected"]),
                             (swift, python), (python, swift)):
        compare_envelope(actual, expected, policy_id="observing_window")


def test_observing_window_catalog_and_fixture_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text()
    catalog_ids = [line.split(": ", 1)[1] for line in catalog.splitlines() if line.startswith("  - id: ")]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    block = catalog.split("  - id: observing_window.select\n", 1)[1].split("  - id:", 1)[0]
    assert 'since: "1.0.0"' in block
    assert 'hosts: [ios, cli]' in block
    assert 'equality: observing_window' in block
    procedure = (contracts_root() / "procedures/observing-window.md").read_text()
    assert "observing_window.select" in procedure
    assert load_policy_fields("observing_window") == {
        "best_window": "null_or_object", "best_window.start": "exact",
        "best_window.end": "exact", "code": "exact", "message": "exact"}
    assert len(CASES) == 40
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["equality"] == "observing_window"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


@pytest.mark.parametrize("mutation", ["missing-window", "null-window", "missing-end", "extra-field", "shift-end", "wrong-type"])
def test_observing_window_equality_fails_closed(mutation):
    expected = next(f["expected"] for f in CASES if f["id"] == "single-qualifying-v1")
    actual = deepcopy(expected)
    result = actual["result"]
    if mutation == "missing-window":
        del result["best_window"]
    elif mutation == "null-window":
        result["best_window"] = None
    elif mutation == "missing-end":
        del result["best_window"]["end"]
    elif mutation == "extra-field":
        result["best_window"]["duration"] = 0
    elif mutation == "shift-end":
        result["best_window"]["end"] = "2026-09-06T02:00:01Z"
    else:
        result["best_window"] = []
    for left, right in ((actual, expected), (expected, actual)):
        with pytest.raises(AssertionError):
            compare_envelope(left, right, policy_id="observing_window")
