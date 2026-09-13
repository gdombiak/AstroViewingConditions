"""Parity for the production cloud-advisory eligibility gate."""

from __future__ import annotations

import json
import subprocess

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root, night_quality_calibration
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import ensure_eval_binary, run_swift_eval

CAPABILITY = "night_conditions.select_cloud_advisory"
CASES = [
    fixture for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] == CAPABILITY
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_cloud_advisory_fixtures_match_both_engines(fixture):
    code, swift, stderr = run_swift_eval(fixture["path"])
    assert code == 0, stderr
    assert swift is not None
    swift.pop("engine_semver", None)
    python = python_envelope(CAPABILITY, fixture["input"])
    for actual, expected in (
        (swift, fixture["expected"]),
        (python, fixture["expected"]),
        (swift, python),
    ):
        compare_envelope(actual, expected, policy_id="cloud_advisory")


@pytest.mark.parametrize("at_floor", [False, True])
def test_calibrated_floor_boundary_matches_both_engines(at_floor, tmp_path):
    floor = night_quality_calibration()["cloud_floor"]["cloud_cover_min"]
    average = floor if at_floor else floor - 0.25
    document = {
        "capability": CAPABILITY,
        "injected": {
            "cloud_timing": "late_heavy",
            "rating": "fair",
            "average_cloud_cover": average,
        },
    }
    path = tmp_path / "input.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    completed = subprocess.run(
        [str(ensure_eval_binary()), CAPABILITY, "--input", str(path)],
        capture_output=True, text=True, check=False,
    )
    assert completed.returncode == 0, completed.stderr
    swift = json.loads(completed.stdout)
    swift.pop("engine_semver", None)
    python = python_envelope(CAPABILITY, document)
    assert swift["result"]["cloud_advisory"] == (
        None if at_floor else "late_heavy"
    )
    compare_envelope(swift, python, policy_id="cloud_advisory")


def test_contract_is_public_and_exact():
    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    catalog_ids = [
        line.split(": ", 1)[1]
        for line in catalog.splitlines()
        if line.startswith("  - id: ")
    ]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-3] == CAPABILITY
    assert load_policy_fields("cloud_advisory") == {
        "cloud_advisory": "exact", "code": "exact", "message": "exact"
    }
    assert len(CASES) == 6
