"""Parity and public-contract checks for active observing-night resolution."""
from __future__ import annotations

import json

import pytest

from astro_engine.cli import PUBLIC_CAPABILITY_IDS
from astro_engine.contracts import contracts_root
from compare import compare_envelope, load_policy_fields
from fixtures import iter_deterministic_fixtures
from python_eval import python_envelope
from swift_eval import run_swift_eval

CAPABILITY = "observing_night.resolve_active"
CASES = [
    fixture for fixture in iter_deterministic_fixtures()
    if fixture["meta"]["capability"] == CAPABILITY
]


@pytest.mark.parametrize("fixture", CASES, ids=lambda fixture: fixture["id"])
def test_observing_night_exact_both_directions(fixture):
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
        compare_envelope(actual, expected, policy_id="observing_night")


def test_catalog_fixture_and_equality_contract():
    catalog = (contracts_root() / "capabilities.yaml").read_text(encoding="utf-8")
    catalog_ids = [
        line.split(": ", 1)[1]
        for line in catalog.splitlines()
        if line.startswith("  - id: ")
    ]
    assert tuple(catalog_ids) == PUBLIC_CAPABILITY_IDS
    assert catalog_ids[-2] == CAPABILITY
    block = catalog.split(f"  - id: {CAPABILITY}\n", 1)[1]
    assert 'since: "1.0.0"' in block
    assert "hosts: [ios, cli]" in block
    assert "equality: observing_night" in block
    assert "daily_moon_count" in block

    fields = load_policy_fields("observing_night")
    assert fields == {
        "state": "exact",
        "time_zone": "exact",
        "day_offset": "exact",
        "day_index": "exact",
        "observing_date": "exact",
        "observing_day_start": "exact",
        "astronomical_night_start": "exact",
        "astronomical_night_end": "exact",
        "code": "exact",
        "message": "exact",
    }
    assert len(CASES) == 37
    for fixture in CASES:
        assert fixture["meta"]["engine_semver"] == ">=1.0.0 <2.0.0"
        assert fixture["meta"]["origin"] == "manual"
        assert fixture["meta"]["hosts"] == ["swift", "python"]


def test_every_state_and_both_day_offsets_are_represented():
    """The three states must never collapse; the fixture set proves each exists."""
    states = {fixture["expected"]["result"]["state"]
              for fixture in CASES if fixture["expected"]["ok"]}
    assert states == {"resolved", "requires_active_previous_payload", "unavailable"}
    offsets = {fixture["expected"]["result"]["day_offset"]
               for fixture in CASES if fixture["expected"]["ok"]}
    assert offsets == {-1, 0, None}


def test_procedure_documents_the_timezone_boundary():
    text = (contracts_root() / "procedures/observing-night.md").read_text(encoding="utf-8")
    assert "approximate(longitude:)" in text
    assert "Timezone **acquisition** is host-owned" in text


def test_public_timezone_policy_is_one_shared_catalogued_set():
    """Neither runtime's own parser may define the accepted identifier set."""
    from astro_engine.observing_night import allowed_timezone_identifiers

    allowed = allowed_timezone_identifiers()
    document = json.loads(
        (contracts_root() / "data/timezones/observing-night-zones.json")
        .read_text(encoding="utf-8")
    )
    assert document["identifier_count"] == len(allowed) == len(document["identifiers"])
    assert document["identifiers"] == sorted(document["identifiers"])
    assert all("/" in identifier for identifier in allowed)
    for catalogued in ("America/Los_Angeles", "America/Havana", "Pacific/Apia",
                       "Australia/Lord_Howe", "Asia/Kathmandu", "Atlantic/Azores",
                       "Pacific/Fakaofo", "America/Santiago", "Europe/Madrid"):
        assert catalogued in allowed, catalogued
    for rejected in ("GMT-0800", "GMT+0530", "GMT", "UTC", "Etc/GMT+8", "Etc/UTC",
                     "US/Pacific", "EST5EDT", "Zulu", "right/UTC", "posix/UTC",
                     "localtime", "Mars/Olympus_Mons"):
        assert rejected not in allowed, rejected
