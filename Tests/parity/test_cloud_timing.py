"""Parity and public-contract checks for semantic cloud-timing classification."""
from __future__ import annotations

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPABILITY = "night_conditions.classify_cloud_timing"
CASES = [
    fixture for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] == CAPABILITY
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_cloud_timing_exact_both_directions(fixture):
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
        compare_envelope(actual, expected, policy_id="cloud_timing")


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
    assert "equality: cloud_timing" in block

    assert load_policy_fields("cloud_timing") == {
        "cloud_timing": "exact",
        "code": "exact",
        "message": "exact",
    }
    assert len(CASES) == 35
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_every_semantic_class_and_edge_class_is_represented():
    verdicts = {
        fixture["expected"]["result"]["cloud_timing"]
        for fixture in CASES if fixture["expected"]["ok"]
    }
    assert verdicts == {"none", "early_heavy", "late_heavy", "intermittent_heavy"}

    fixture_ids = {fixture["id"] for fixture in CASES}
    assert {
        "empty-v1",
        "single-row-v1",
        "single-heavy-row-between-clear-v1",
        "two-row-run-v1",
        "whole-night-heavy-v1",
        "heavy-threshold-equal-v1",
        "heavy-threshold-below-v1",
        "usable-threshold-equal-v1",
        "usable-threshold-below-v1",
        "spacing-3599-v1",
        "spacing-3601-v1",
        "duplicate-timestamp-v1",
        "backwards-timestamp-v1",
        "two-hour-gap-v1",
        "distant-usable-hour-v1",
        "ineligible-run-loses-to-eligible-v1",
        "longest-run-wins-v1",
        "average-cloud-tie-break-v1",
        "earliest-start-tie-break-v1",
        "row-cap-v1",
    } <= fixture_ids
