"""Parity and public-contract checks for equipment recommendation filtering."""
from __future__ import annotations

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPABILITY = "targets.filter_recommendations_by_equipment"
CASES = [
    fixture for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] == CAPABILITY
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_equipment_filter_exact_both_directions(fixture):
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
        compare_envelope(
            actual,
            expected,
            policy_id="filter_recommendations_by_equipment",
        )


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
    assert "equality: filter_recommendations_by_equipment" in block
    assert "has_saved_inventory" in block

    fields = load_policy_fields("filter_recommendations_by_equipment")
    assert fields == {
        "selected": "exact",
        "selected[].index": "exact",
        "selected[].key": "exact",
        "code": "exact",
        "message": "exact",
    }
    assert len(CASES) == 12
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_selected_capability_order_does_not_change_result(tmp_path):
    fixture = next(case for case in CASES if case["id"] == "duplicate-windows-all-pass-v1")
    document = fixture["input"]
    capabilities = document["injected"]["capabilities"]
    second = {"key": "0", "type": "nakedEye", "aperture_mm": None, "magnification": None}

    results = []
    for ordered in (capabilities + [second], [second] + capabilities):
        candidate = {
            **document,
            "injected": {**document["injected"], "capabilities": ordered},
        }
        results.append(python_envelope(CAPABILITY, candidate))
    assert results[0] == results[1]
